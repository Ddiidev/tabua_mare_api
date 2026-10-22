module main

import veb
import json2
import db.pg
import net.http
import shareds.types
import shareds.web_ctx
import shareds.conf_env
import shareds.instance
import domain.auth_user
import shareds.infradb_pg
import repository.auth as repo_auth
import shareds.email.resend

// AuthController trata das rotas de autenticacao (login Google, logout, /me, avatar).
pub struct AuthController {
	veb.Controller
	veb.Middleware[web_ctx.WsCtx]
pub mut:
	env          conf_env.EnvConfig
	pg_holder    &infradb_pg.PgHolder
	avatar_cache &auth_user.AvatarCache = unsafe { nil }
}

// db_conn retorna o pool PostgreSQL compartilhado da aplicacao.
// O holder e inicializado uma vez no startup e permanece vivo ate o shutdown.
fn (ac &AuthController) db_conn() !&pg.DB {
	if !ac.pg_holder.available() {
		return error('PostgreSQL indisponivel')
	}
	return ac.pg_holder.db()
}

// init_instance_header marca toda resposta de /auth com X-Tabuamare-Slot
// (slot=A|B do env TABUAMARE_SLOT); o Nginx de borda grava no access log.
fn (mut ac AuthController) init_instance_header() {
	ac.use(instance.middleware(ac.env.tabuamare_slot))
}

// safe_redirect_path permite apenas destinos locais do proprio aplicativo.
// Isso deixa o callback OAuth legivel e impede que `next` vire um redirect externo.
fn safe_redirect_path(next string) string {
	if next == '' || !next.starts_with('/') || next.starts_with('//') {
		return '/'
	}
	return next
}

// require_user_id e a pre-condicao comum das rotas privadas do painel.
fn (mut ac AuthController) require_user_id(mut ctx web_ctx.WsCtx) !int {
	uid := ac.current_user_id(mut ctx)
	if uid == 0 {
		return error('nao autenticado')
	}
	return uid
}

// session_claims e a unica leitura/validacao do cookie JWT dentro do controller.
fn (ac &AuthController) session_claims(mut ctx web_ctx.WsCtx) !auth_user.JwtClaims {
	if ac.env.session_secret == '' {
		return error('sessao nao configurada')
	}
	token := ctx.get_cookie(ac.env.session_cookie_name) or { return error('nao autenticado') }
	if !auth_user.verify(ac.env.session_secret, token) {
		return error('token invalido ou expirado')
	}
	return auth_user.decode(token) or { error('token invalido') }
}

fn (mut ac AuthController) current_user_id(mut ctx web_ctx.WsCtx) int {
	claims := ac.session_claims(mut ctx) or { return 0 }
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

	raw_json := json2.encode(user_info)

	eprintln('[oauth] connecting postgres')
	mut db := ac.db_conn() or {
		eprintln('[oauth] postgres connection failed: ${err}')
		ctx.res.set_status(.internal_server_error)
		return ctx.text('banco de dados indisponivel: ${err}')
	}

	eprintln('[oauth] upserting user')
	upsert := repo_auth.upsert_by_provider(mut db, 'google', user_info.sub, user_info.email,
		user_info.name, user_info.picture, raw_json) or {
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

	// O envio nao aguarda o provedor e nao pode impedir a sessao ou o redirect.
	if upsert.is_new_user && ac.env.email_resend != '' {
		if content := resend.welcome_email(upsert.email, ac.env.resend_from,
			ac.env.resend_reply_to, ac.env.url_env)
		{
			client := resend.Client{
				api_key: ac.env.email_resend
			}
			spawn send_welcome_email(client, content, upsert.user_id)
		} else {
			eprintln('[email] boas-vindas nao preparado user_id=${upsert.user_id}: ${err}')
		}
	}

	eprintln('[oauth] callback completed')
	next := safe_redirect_path(ctx.query['next'] or { '/dashboard' })
	return ctx.redirect(next, veb.RedirectParams{ typ: .found })
}

fn send_welcome_email(client resend.Client, content resend.ContentEmail, user_id int) {
	id := client.send(content, 'welcome-user/${user_id}') or {
		eprintln('[email] boas-vindas falhou user_id=${user_id}: ${err}')
		return
	}
	eprintln('[email] boas-vindas aceito user_id=${user_id} resend_id=${id}')
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
	claims := ac.session_claims(mut ctx) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, err.msg()))
	}

	// busca o plano atual do banco (pode ter mudado via webhooks/cancelamento)
	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
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
