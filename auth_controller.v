module main

import veb
import db.pg
import net.http
import json
import shareds.web_ctx
import shareds.conf_env
import shareds.infradb_pg
import shareds.types
import shareds.rate_limit
import repository.rate_limit as rl
import domain.auth_user
import repository.auth as repo_auth
import repository.auth.dto
import v_stripe.stripe

// AuthController trata das rotas de autenticacao (login Google, logout, /me, avatar).
pub struct AuthController {
	veb.Controller
	veb.Middleware[web_ctx.WsCtx]
	pub mut:
	env          conf_env.EnvConfig
	pg_holder    ?&infradb_pg.PgHolder
	avatar_cache &auth_user.AvatarCache = unsafe { nil }
}

// db_conn retorna o pool PostgreSQL compartilhado da aplicacao.
// O fallback mantem testes isolados que instanciam o controller sem holder.
fn (ac &AuthController) db_conn() !&pg.DB {
	if ac.env.postgresql_conn_str == '' {
		return error('POSTGRESQL_CONN_STR nao configurado')
	}
	if holder := ac.pg_holder {
		if !holder.available() {
			return error('PostgreSQL indisponivel')
		}
		return holder.db()
	}
	return pg.connect_with_conninfo(ac.env.postgresql_conn_str)
}

// close_db fecha apenas conexoes criadas pelo fallback de testes.
// O holder de producao permanece vivo durante todo o processo.
fn (ac &AuthController) close_db(mut db &pg.DB) {
	if ac.pg_holder == none {
		db.close() or {}
	}
}

// google_login inicia o fluxo OAuth do Google: gera state, seta cookie efemero e
// redireciona para a URL de consentimento.
@['/google'; get]
pub fn (mut ac AuthController) google_login(mut ctx web_ctx.WsCtx) veb.Result {
	state := auth_user.random_state() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.text('erro ao gerar state')
	}

	// state efemero em cookie (HttpOnly, curta duracao) para validar no callback
	ctx.set_cookie(http.Cookie{
		name:      'tm_oauth_state'
		value:     state
		path:      '/'
		max_age:   600
		http_only: true
		same_site: .same_site_lax_mode
	})

	cfg := ac.google_config()
	url := auth_user.build_auth_url(cfg, state)
	return ctx.redirect(url, veb.RedirectParams{ typ: .found })
}

// google_callback recebe ?code=&state=, valida state, troca code por tokens,
// busca userinfo, faz upsert do usuario no PostgreSQL, emite JWT e seta cookie
// de sessao HttpOnly. Redireciona para / (ou ?next=).
@['/google/callback'; get]
pub fn (mut ac AuthController) google_callback(mut ctx web_ctx.WsCtx) veb.Result {
	eprintln('[oauth] callback started')
	code := ctx.query['code'] or {
		ctx.res.set_status(.bad_request)
		return ctx.text('code ausente')
	}
	state := ctx.query['state'] or {
		ctx.res.set_status(.bad_request)
		return ctx.text('state ausente')
	}

	// valida state contra o cookie efemero
	expected_state := ctx.get_cookie('tm_oauth_state') or {
		ctx.res.set_status(.bad_request)
		return ctx.text('state cookie ausente')
	}
	if state != expected_state {
		ctx.res.set_status(.bad_request)
		return ctx.text('state invalido')
	}

	cfg := ac.google_config()

	eprintln('[oauth] exchanging authorization code')
	access_token := auth_user.exchange_code(cfg, code) or {
		eprintln('[oauth] token exchange failed: ${err}')
		ctx.res.set_status(.unauthorized)
		return ctx.text('falha ao trocar code: ${err}')
	}

	eprintln('[oauth] fetching userinfo')
	user_info := auth_user.fetch_userinfo(cfg, access_token) or {
		eprintln('[oauth] userinfo failed: ${err}')
		ctx.res.set_status(.unauthorized)
		return ctx.text('falha ao obter userinfo: ${err}')
	}

	raw_json := json.encode(user_info)

	eprintln('[oauth] connecting postgres')
	mut db := ac.db_conn() or {
		eprintln('[oauth] postgres connection failed: ${err}')
		ctx.res.set_status(.internal_server_error)
		return ctx.text('banco de dados indisponivel: ${err}')
	}
	defer {
		ac.close_db(mut db)
	}

	eprintln('[oauth] upserting user')
	upsert := repo_auth.upsert_by_provider(mut db, 'google', user_info.sub,
		user_info.email, user_info.name, user_info.picture, raw_json) or {
		ctx.res.set_status(.internal_server_error)
		eprintln('[oauth] user upsert failed: ${err}')
		return ctx.text('falha ao criar/atualizar usuario: ${err}')
	}

	plan := repo_auth.find_plan_by_id(mut db, upsert.user_id) or { upsert.plan }

	token := auth_user.issue(ac.env.session_secret, upsert.user_id, upsert.email, upsert.name,
		plan, ac.env.session_ttl_hours)

	// cookie de sessao HttpOnly (frontend nao le o JWT; usa /auth/me)
	secure := ac.env.url_env.starts_with('https')
	ctx.set_cookie(http.Cookie{
		name:      ac.env.session_cookie_name
		value:     token
		path:      '/'
		max_age:   ac.env.session_ttl_hours * 3600
		secure:    secure
		http_only: true
		same_site: .same_site_lax_mode
	})

	// limpa o cookie efemero de state
	ctx.set_cookie(http.Cookie{
		name:    'tm_oauth_state'
		value:   ''
		path:    '/'
		max_age: -1
	})

	eprintln('[oauth] callback completed')
	next := ctx.query['next'] or { '/' }
	return ctx.redirect(next, veb.RedirectParams{ typ: .found })
}

// logout invalida a sessao limpando o cookie. (JWT e stateless; nao ha tabela
// de sessao para invalidar — basta o cliente descartar o cookie.)
@['/logout'; get; post]
pub fn (mut ac AuthController) logout(mut ctx web_ctx.WsCtx) veb.Result {
	ctx.set_cookie(http.Cookie{
		name:    ac.env.session_cookie_name
		value:   ''
		path:    '/'
		max_age: -1
	})
	return ctx.redirect('/', veb.RedirectParams{ typ: .found })
}

// me retorna o usuario corrente (lendo o cookie de sessao JWT) como ResultAPI.
@['/me'; get]
pub fn (mut ac AuthController) me(mut ctx web_ctx.WsCtx) veb.Result {
	token := ctx.get_cookie(ac.env.session_cookie_name) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}

	if !auth_user.verify(ac.env.session_secret, token) {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'token invalido ou expirado'))
	}

	claims := auth_user.decode(token) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'token invalido'))
	}

	// busca o plano atual do banco (pode ter mudado via webhooks/cancelamento)
	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}
	defer {
		ac.close_db(mut db)
	}
	plan := repo_auth.find_plan_by_id(mut db, claims.sub) or { claims.plan }

	user := auth_user.UserData{
		id:       claims.sub
		email:    claims.email
		name:     claims.name
		plan:     plan
		provider: 'google'
	}
	return ctx.json(types.success([user]))
}

// avatar serve a foto de perfil do usuario via cache (TTL configuravel).
// Se o cache estiver frio, busca a imagem na avatar_url (do DB/Google) e cacheia.
// Se algo falhar, redireciona 302 para a URL original do Google.
@['/avatar/:user_id'; get]
pub fn (mut ac AuthController) avatar(mut ctx web_ctx.WsCtx, user_id string) veb.Result {
	uid := user_id.int()
	if uid <= 0 {
		ctx.res.set_status(.bad_request)
		return ctx.text('user_id invalido')
	}

	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.text('banco indisponivel: ${err}')
	}
	defer {
		ac.close_db(mut db)
	}

	user := repo_auth.find_by_id(mut db, uid) or {
		ctx.res.set_status(.not_found)
		return ctx.text('usuario nao encontrado')
	}

	if user.avatar_url == '' {
		ctx.res.set_status(.not_found)
		return ctx.text('sem avatar')
	}

	// tenta o cache
	if unsafe { ac.avatar_cache != nil } {
		if cached := ac.avatar_cache.get(user_id) {
			ctx.res.header.set(.content_type, cached.content_type)
			return ctx.send_response_to_client(cached.content_type, cached.bytes.bytestr())
		}
	}

	// miss: busca a imagem na URL original
	resp := http.fetch(http.FetchConfig{
		method: .get
		url:    user.avatar_url
	}) or {
		// fallback: redireciona para a URL do Google
		return ctx.redirect(user.avatar_url, veb.RedirectParams{ typ: .found })
	}

	content_type := resp.header.get(.content_type) or { 'image/jpeg' }
	body_bytes := resp.body.bytes()
	if unsafe { ac.avatar_cache != nil } {
		ac.avatar_cache.set(user_id, body_bytes, content_type)
	}
	ctx.res.header.set(.content_type, content_type)
	return ctx.send_response_to_client(content_type, body_bytes.bytestr())
}

// api_keys_list lista as api_keys do usuario corrente.
@['/api-keys'; get]
pub fn (mut ac AuthController) api_keys_list(mut ctx web_ctx.WsCtx) veb.Result {
	uid := ac.current_user_id(mut ctx)
	if uid == 0 {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}
	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}
	defer {
		ac.close_db(mut db)
	}

	keys := repo_auth.list_by_user(mut db, uid) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'erro: ${err}'))
	}
	return ctx.json(types.success(keys))
}

// api_keys_create cria uma nova api_key para o usuario corrente.
// Body JSON: {"label": "...", "plan": "free|plan5|plan10"}
@['/api-keys'; post]
pub fn (mut ac AuthController) api_keys_create(mut ctx web_ctx.WsCtx) veb.Result {
	uid := ac.current_user_id(mut ctx)
	if uid == 0 {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}

	parsed := json.decode(ApiKeyCreatePayload, ctx.req.data) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'JSON invalido: ${err}'))
	}

	// valida plano
	match parsed.plan {
		'free', 'plan5', 'plan10', 'planannual' {}
		else {
			ctx.res.set_status(.bad_request)
			return ctx.json(types.failure[string](400, 'plano invalido: ${parsed.plan}'))
		}
	}

	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}
	defer {
		ac.close_db(mut db)
	}

	user_plan := repo_auth.find_plan_by_id(mut db, uid) or { 'free' }
	if !rate_limit.is_plan_allowed(parsed.plan, user_plan) {
		ctx.res.set_status(.forbidden)
		return ctx.json(types.failure[string](403, 'plano nao permitido para o usuario'))
	}

	key_value := repo_auth.issue(mut db, uid, parsed.label, parsed.plan) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'erro ao criar api_key: ${err}'))
	}

	return ctx.json(types.success([{'key_value': key_value, 'label': parsed.label, 'plan': parsed.plan}]))
}

struct ApiKeyCreatePayload {
	label string
	plan  string
}

// CheckoutPayload e' o body do POST /auth/checkout.
struct CheckoutPayload {
	plan        string
	success_url string
	cancel_url  string
}

// checkout cria uma Stripe Checkout Session de assinatura para o plano escolhido.
// O usuario deve estar autenticado (cookie JWT). Retorna a checkout_url para redirecionamento.
@['/checkout'; post]
pub fn (mut ac AuthController) checkout(mut ctx web_ctx.WsCtx) veb.Result {
	uid := ac.current_user_id(mut ctx)
	if uid == 0 {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}

	parsed := json.decode(CheckoutPayload, ctx.req.data) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'JSON invalido: ${err}'))
	}

	// resolve o price_id do plano
	price_id := match parsed.plan {
		'plan5' { ac.env.stripe_price_plan5 }
		'plan10' { ac.env.stripe_price_plan10 }
		'planannual' { ac.env.stripe_price_planannual }
		else {
			ctx.res.set_status(.bad_request)
			return ctx.json(types.failure[string](400, 'plano invalido: ${parsed.plan}'))
		}
	}

	if price_id == '' {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'price_id nao configurado para o plano ${parsed.plan}'))
	}

	if ac.env.stripe_secret_key == '' {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'Stripe nao configurado'))
	}

	// busca o usuario no DB para ter email
	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}
	defer {
		ac.close_db(mut db)
	}
	user := repo_auth.find_by_id(mut db, uid) or {
		ctx.res.set_status(.not_found)
		return ctx.json(types.failure[string](404, 'usuario nao encontrado'))
	}

	// cria o Stripe client
	mut stripe_client := stripe.new_client(stripe.ClientConfig{
		secret_key: ac.env.stripe_secret_key
	}) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'stripe client init failed: ${err}'))
	}

	// busca ou cria o Stripe Customer pelo email
	stripe_customer_id := resolve_stripe_customer(mut stripe_client, uid, user.email) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'falha ao resolver customer: ${err}'))
	}

	// salva o stripe_customer_id no DB se ainda nao estiver salvo
	if user.stripe_customer_id == '' || user.stripe_customer_id != stripe_customer_id {
		repo_auth.set_stripe_customer_id(mut db, uid, stripe_customer_id) or {
			eprintln('falha ao salvar stripe_customer_id: ${err}')
		}
	}

	// cria a Checkout Session de assinatura
	mut metadata := {
		'user_id':   uid.str()
		'plan_code': parsed.plan
	}
	session := stripe_client.create_checkout_session(stripe.CheckoutSessionCreateParams{
		mode:        stripe.checkout_mode_subscription
		line_items:  [
			stripe.CheckoutLineItem{
				price:    price_id
				quantity: 1
			},
		]
		customer:    stripe_customer_id
		success_url: parsed.success_url
		cancel_url:  parsed.cancel_url
		metadata:    metadata
		subscription_data: stripe.CheckoutSubscriptionData{
			metadata: metadata
		}
	}) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'falha ao criar checkout: ${err}'))
	}

	return ctx.json(types.success([{'checkout_url': session.url, 'session_id': session.id}]))
}

// billing_portal cria uma sessao do Stripe Customer Portal e retorna a URL
// para o frontend redirecionar o usuario a gerenciar/cancelar a assinatura.
@['/billing-portal'; post]
pub fn (mut ac AuthController) billing_portal(mut ctx web_ctx.WsCtx) veb.Result {
	uid := ac.current_user_id(mut ctx)
	if uid == 0 {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}

	if ac.env.stripe_secret_key == '' {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'Stripe nao configurado'))
	}

	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}
	defer {
		ac.close_db(mut db)
	}

	user := repo_auth.find_by_id(mut db, uid) or {
		ctx.res.set_status(.not_found)
		return ctx.json(types.failure[string](404, 'usuario nao encontrado'))
	}

	if user.stripe_customer_id == '' {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'usuario sem customer Stripe'))
	}

	mut stripe_client := stripe.new_client(stripe.ClientConfig{
		secret_key: ac.env.stripe_secret_key
	}) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'stripe client init failed: ${err}'))
	}

	portal := stripe_client.create_billing_portal_session(stripe.BillingPortalSessionCreateParams{
		customer:   user.stripe_customer_id
		return_url: '${ac.env.url_env}/dashboard'
	}) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'falha ao criar portal: ${err}'))
	}

	return ctx.json(types.success([{'url': portal.url}]))
}

// cancel_subscription cancela a assinatura ativa do usuario no Stripe e
// downgrade o plano para free no banco.
@['/cancel-subscription'; post]
pub fn (mut ac AuthController) cancel_subscription(mut ctx web_ctx.WsCtx) veb.Result {
	uid := ac.current_user_id(mut ctx)
	if uid == 0 {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}

	if ac.env.stripe_secret_key == '' {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'Stripe nao configurado'))
	}

	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}
	defer {
		ac.close_db(mut db)
	}

	user := repo_auth.find_by_id(mut db, uid) or {
		ctx.res.set_status(.not_found)
		return ctx.json(types.failure[string](404, 'usuario nao encontrado'))
	}

	// se nao tiver subscription_id, redireciona para o billing portal
	if user.stripe_subscription_id == '' {
		if user.stripe_customer_id == '' {
			ctx.res.set_status(.bad_request)
			return ctx.json(types.failure[string](400, 'sem assinatura ativa'))
		}
		return ctx.json(types.success([{'portal_required': true}]))
	}

	mut stripe_client := stripe.new_client(stripe.ClientConfig{
		secret_key: ac.env.stripe_secret_key
	}) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'stripe client init failed: ${err}'))
	}

	stripe_client.cancel_subscription(user.stripe_subscription_id) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'falha ao cancelar assinatura: ${err}'))
	}

	repo_auth.update_plan(mut db, uid, 'free') or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'falha ao atualizar plano: ${err}'))
	}

	return ctx.json(types.success([{'cancelled': true}]))
}

// resolve_stripe_customer busca um customer existente pelo email ou cria um novo.
fn resolve_stripe_customer(mut stripe_client stripe.Client, user_id int, email string) !string {
	if email == '' {
		return error('email do usuario vazio')
	}
	customers := stripe_client.list_customers(stripe.CustomerListParams{
		email: email
		limit: 1
	}) or { return err }
	if customers.data.len > 0 {
		return customers.data[0].id
	}
	new_customer := stripe_client.create_customer(stripe.CustomerCreateParams{
		email:    email
		metadata: {
			'user_id': user_id.str()
		}
	}) or { return err }
	return new_customer.id
}

// stripe_webhook recebe eventos do Stripe e atualiza o plano/creditos do usuario.
@['/webhook'; post]
pub fn (mut ac AuthController) stripe_webhook(mut ctx web_ctx.WsCtx) veb.Result {
	signature := ctx.req.header.get_custom('Stripe-Signature') or {
		ctx.res.set_status(.bad_request)
		return ctx.text('Missing Stripe-Signature header')
	}
	raw_body := ctx.req.data

	if ac.env.stripe_webhook_secret == '' {
		ctx.res.set_status(.internal_server_error)
		return ctx.text('webhook secret nao configurado')
	}

	event := stripe.verify_webhook_event(raw_body, signature, ac.env.stripe_webhook_secret, 300) or {
		ctx.res.set_status(.bad_request)
		return ctx.text('assinatura invalida: ${err}')
	}

	match event.type_ {
		'checkout.session.completed' {
			handle_stripe_checkout_completed(mut ac, event) or {
				eprintln('stripe webhook checkout.session.completed failed: ${err}')
			}
		}
		'customer.subscription.created', 'customer.subscription.updated' {
			handle_stripe_subscription_updated(mut ac, event) or {
				eprintln('stripe webhook ${event.type_} failed: ${err}')
			}
		}
		'customer.subscription.deleted' {
			handle_stripe_subscription_deleted(mut ac, event) or {
				eprintln('stripe webhook customer.subscription.deleted failed: ${err}')
			}
		}
		'invoice.payment_failed' {
			handle_stripe_invoice_payment_failed(mut ac, event) or {
				eprintln('stripe webhook invoice.payment_failed failed: ${err}')
			}
		}
		else {}
	}

	return ctx.json({'received': 'true'})
}

// handle_stripe_checkout_completed processa o evento checkout.session.completed:
// le o user_id dos metadados, atualiza o plano e salva subscription_id.
fn handle_stripe_checkout_completed(mut ac AuthController, event stripe.Event) ! {
	if ac.env.stripe_secret_key == '' {
		return error('stripe secret key nao configurado')
	}
	mut stripe_client := stripe.new_client(stripe.ClientConfig{
		secret_key: ac.env.stripe_secret_key
	})!

	session := stripe_client.get_checkout_session(event.data_object_id)!

	user_id_str := session.metadata['user_id'] or { '' }
	if user_id_str == '' {
		return error('user_id ausente nos metadados da session')
	}
	uid := user_id_str.int()
	if uid <= 0 {
		return error('user_id invalido: ${user_id_str}')
	}

	plan_code := session.metadata['plan_code'] or { '' }
	if plan_code == '' {
		return error('plan_code ausente nos metadados da session')
	}

	mut db := ac.db_conn() or { return err }
	defer {
		ac.close_db(mut db)
	}

	repo_auth.update_plan(mut db, uid, plan_code)!

	// salva customer_id e subscription_id se presentes
	if session.customer != '' {
		repo_auth.set_stripe_customer_id(mut db, uid, session.customer)!
	}
	if session.subscription != '' {
		repo_auth.set_stripe_subscription_id(mut db, uid, session.subscription)!
	}
}

// handle_stripe_subscription_updated processa customer.subscription.created/updated.
// Como a lib v_stripe nao expoe get_subscription nem subscription.items, este handler
// extrai customer_id e metadata (plan_code) do raw_body do evento.
fn handle_stripe_subscription_updated(mut ac AuthController, event stripe.Event) ! {
	mut db := ac.db_conn() or { return err }
	defer {
		ac.close_db(mut db)
	}

	// extrai customer_id, status e plan_code do raw_body
	parsed := json.decode(StripeWebhookEvent, event.raw_body) or {
		return error('falha ao parse raw_body: ${err}')
	}
	customer_id := parsed.data.object.customer
	if customer_id == '' {
		return error('customer_id ausente no evento')
	}
	status := parsed.data.object.status
	plan_code := parsed.data.object.metadata['plan_code'] or { '' }

	uid := repo_auth.find_id_by_stripe_customer(mut db, customer_id)!

	// status ativo/trialing -> mantem plano; senao -> free
	mut plan := 'free'
	if status in ['active', 'trialing'] {
		if plan_code != '' {
			plan = plan_code
		}
	}

	repo_auth.update_plan(mut db, uid, plan)!
	sub_id := parsed.data.object.id
	if sub_id != '' {
		repo_auth.set_stripe_subscription_id(mut db, uid, sub_id)!
	}
}

// StripeWebhookEvent decodifica o raw_body de eventos do Stripe.
// json.decode ignora campos ausentes, entao uma unica struct serve para
// todos os eventos (subscription.*, invoice.*).
struct StripeWebhookEvent {
	data StripeWebhookEventData
}

struct StripeWebhookEventData {
	object StripeWebhookEventObject
}

struct StripeWebhookEventObject {
	id       string
	customer string
	status   string
	metadata map[string]string
}

// handle_stripe_subscription_deleted processa customer.subscription.deleted (cancelamento).
fn handle_stripe_subscription_deleted(mut ac AuthController, event stripe.Event) ! {
	mut db := ac.db_conn() or { return err }
	defer {
		ac.close_db(mut db)
	}

	// extrai customer_id do raw_body para evitar chamar a API Stripe
	wrapper := json.decode(StripeWebhookEvent, event.raw_body) or {
		return error('falha ao parse raw_body: ${err}')
	}
	customer_id := wrapper.data.object.customer
	if customer_id == '' {
		return error('customer_id ausente no evento')
	}

	uid := repo_auth.find_id_by_stripe_customer(mut db, customer_id)!

	repo_auth.update_plan(mut db, uid, 'free')!
}

// handle_stripe_invoice_payment_failed processa invoice.payment_failed.
// Se o usuario tiver outra subscription ativa, nao faz nada; senao, downgrade para free.
fn handle_stripe_invoice_payment_failed(mut ac AuthController, event stripe.Event) ! {
	if ac.env.stripe_secret_key == '' {
		return error('stripe secret key nao configurado')
	}
	mut stripe_client := stripe.new_client(stripe.ClientConfig{
		secret_key: ac.env.stripe_secret_key
	})!

	invoice := json.decode(StripeWebhookEvent, event.raw_body) or {
		return error('falha ao parse raw_body: ${err}')
	}
	customer_id := invoice.data.object.customer
	if customer_id == '' {
		return error('customer_id ausente no evento')
	}

	mut db := ac.db_conn() or { return err }
	defer {
		ac.close_db(mut db)
	}

	uid := repo_auth.find_id_by_stripe_customer(mut db, customer_id)!

	// verifica se ainda ha alguma subscription ativa para o customer
	active_subs := stripe_client.list_subscriptions(stripe.SubscriptionListParams{
		customer: customer_id
		status:   'active'
		limit:    1
	}) or { return err }

	if active_subs.data.len == 0 {
		repo_auth.update_plan(mut db, uid, 'free')!
	}
}

// rate_limit_status retorna o uso atual de rate-limit do usuario/ip/chave.
// Como este endpoint nao passa pelo middleware de rate-limit (só /api/v2/* passa),
// extraimos a api_key e determinamos o plano manualmente.
@['/rate-limit-status'; get]
pub fn (mut ac AuthController) rate_limit_status(mut ctx web_ctx.WsCtx) veb.Result {
	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}
	defer {
		ac.close_db(mut db)
	}

	// Defaults: anon por IP
	ip := ctx.ip()
	mut bucket := 'ip:${ip}'
	mut plan := 'anon'

	// JWT de login nao identifica chamadas da API. Sem api_key, permanece anonimo por IP.
	// Se tem api_key valida, ela define plano e bucket isolado.
	api_key := rate_limit.extract_api_key(mut ctx)
	if api_key != '' {
		mut key_found := true
		key := repo_auth.find_by_key(mut db, api_key) or { key_found = false; dto.ApiKey{} }
		if key_found && !key.revoked {
			mut effective_plan := key.plan
			user_plan := repo_auth.find_plan_by_id(mut db, key.user_id) or { '' }
			if !rate_limit.is_plan_allowed(key.plan, user_plan) {
				effective_plan = user_plan
			}
			bucket = 'key:${key.key_value}'
			plan = effective_plan
		}
	}

	limit_rpm, limit_monthly := rate_limit.plan_limits(ac.env, plan)

	minute_key := rl.window_key_minute()
	used_rpm := rl.get_count(mut db, bucket, 'minute', minute_key) or { 0 }
	monthly := rl.get_current_month_usage(mut db, bucket) or {
		rl.CreditCheck{used: 0, remaining: limit_monthly, lim: limit_monthly}
	}

	return ctx.json(types.success([{
		'plan':              plan
		'limit_rpm':         limit_rpm.str()
		'used_rpm':          used_rpm.str()
		'remaining_rpm':     if limit_rpm == 0 { '-1' } else { (limit_rpm - used_rpm).str() }
		'limit_monthly':     limit_monthly.str()
		'used_monthly':      monthly.used.str()
		'remaining_monthly': if limit_monthly == 0 { '-1' } else { monthly.remaining.str() }
	}]))
}

// api_keys_revoke revoga uma api_key do usuario corrente.
@['/api-keys/:id'; delete]
pub fn (mut ac AuthController) api_keys_revoke(mut ctx web_ctx.WsCtx, id string) veb.Result {
	uid := ac.current_user_id(mut ctx)
	if uid == 0 {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}
	key_id := id.int()
	if key_id <= 0 {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'id invalido'))
	}

	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}
	defer {
		ac.close_db(mut db)
	}

	repo_auth.revoke(mut db, uid, key_id) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'erro ao revogar: ${err}'))
	}
	return ctx.json(types.success([{'revoked': true}]))
}

// current_user_id extrai o user_id do cookie JWT, ou 0 se nao autenticado.
fn (mut ac AuthController) current_user_id(mut ctx web_ctx.WsCtx) int {
	if ac.env.session_secret == '' {
		return 0
	}
	token := ctx.get_cookie(ac.env.session_cookie_name) or { return 0 }
	if !auth_user.verify(ac.env.session_secret, token) {
		return 0
	}
	claims := auth_user.decode(token) or { return 0 }
	return claims.sub
}

fn (ac &AuthController) google_config() auth_user.GoogleConfig {
	return auth_user.GoogleConfig{
		client_id:     ac.env.google_client_id
		client_secret: ac.env.google_client_secret
		redirect_uri:  ac.env.google_redirect_uri
		auth_url:      ac.env.google_auth_url
		token_url:     ac.env.google_token_url
		userinfo_url:  ac.env.google_userinfo_url
		scope:         ac.env.google_scope
	}
}
