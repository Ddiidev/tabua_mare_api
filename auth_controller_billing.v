module main

import json2
import db.pg
import veb
import v_stripe.stripe
import shareds.conf_env
import shareds.types
import shareds.web_ctx
import repository.auth as repo_auth

// stripe_price_id concentra a tabela de planos em um unico ponto do checkout.
fn stripe_price_id(env conf_env.EnvConfig, plan string) !string {
	price_id := match plan {
		'plan15' { env.stripe_price_plan15 }
		'plan70' { env.stripe_price_plan70 }
		'plan30' { env.stripe_price_plan30 }
		'plan150' { env.stripe_price_plan150 }
		else { return error('plano invalido') }
	}

	if price_id == '' {
		return error('price_id nao configurado')
	}
	return price_id
}

// new_stripe_client evita repetir a validacao e a construcao do cliente em cada rota.
// Usa timeout/retries do EnvConfig (defaults: 8000ms / 1 retry) para manter as
// chamadas Stripe abaixo do limite do Cloudflare (~100s) e evitar 524 no checkout.
fn (ac &AuthController) new_stripe_client() !stripe.Client {
	if ac.env.stripe_secret_key == '' {
		return error('Stripe nao configurado')
	}
	return stripe.new_client(stripe.ClientConfig{
		secret_key:  ac.env.stripe_secret_key
		timeout_ms:  ac.env.stripe_timeout_ms
		max_retries: ac.env.stripe_max_retries
	})
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
	uid := ac.require_user_id(mut ctx) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}

	parsed := json2.decode[CheckoutPayload](ctx.req.data) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'JSON invalido: ${err}'))
	}

	price_id := stripe_price_id(ac.env, parsed.plan) or {
		if err.msg() == 'plano invalido' {
			ctx.res.set_status(.bad_request)
			return ctx.json(types.failure[string](400, 'plano invalido: ${parsed.plan}'))
		}
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500,
			'price_id nao configurado para o plano ${parsed.plan}'))
	}

	// busca o usuario no DB para ter email
	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}

	user := repo_auth.find_by_id(mut db, uid) or {
		ctx.res.set_status(.not_found)
		return ctx.json(types.failure[string](404, 'usuario nao encontrado'))
	}

	// Cria o Stripe client
	mut stripe_client := ac.new_stripe_client() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'stripe client init failed: ${err}'))
	}

	// Resolve o stripe_customer_id para este app.
	//
	// Principio arquitetural: nunca fazer lookup de customer por email. O
	// email do usuario pode estar cadastrado em OUTROS produtos dentro da
	// mesma conta Stripe (multiplos SaaS compartilham o dashboard), e reusar
	// o customer por email misturaria billing de produtos distintos. O
	// customer deste app e' identificado unicamente pelo
	// stripe_customer_id salvo no DB deste app.
	//
	// Logica:
	//   1. Se o DB tem stripe_customer_id, valida com get_customer. Se for
	//      valido (existe em live e pertence a esta conta), usa.
	//   2. Se o DB esta vazio OU o ID salvo foi removido pelo Stripe, cria um
	//      NOVO customer exclusivo deste app e atualiza o DB.
	customer_id := resolve_app_customer(mut stripe_client, user.stripe_customer_id, uid,
		user.email, mut db) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'falha ao resolver customer: ${err}'))
	}

	// Cria a Checkout Session de assinatura
	mut metadata := {
		'user_id':   uid.str()
		'plan_code': parsed.plan
	}
	// idempotency_key evita sessoes duplicadas quando o usuario reenvia o
	// checkout apos um 524/timeout: o Stripe reutiliza a sessao para a mesma
	// combinacao (user_id + plano) em vez de criar uma nova.
	idempotency_key := 'checkout_${uid}_${parsed.plan}'
	session := stripe_client.create_checkout_session_with_options(stripe.CheckoutSessionCreateParams{
		mode:              stripe.checkout_mode_subscription
		line_items:        [
			stripe.CheckoutLineItem{
				price:    price_id
				quantity: 1
			},
		]
		customer:          customer_id
		success_url:       parsed.success_url
		cancel_url:        parsed.cancel_url
		metadata:          metadata
		subscription_data: stripe.CheckoutSubscriptionData{
			metadata: metadata
		}
	}, stripe.RequestOptions{
		idempotency_key: idempotency_key
	}) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'falha ao criar checkout: ${err}'))
	}

	return ctx.json(types.success([
		{
			'checkout_url': session.url
			'session_id':   session.id
		},
	]))
}

// billing_portal cria uma sessao do Stripe Customer Portal e retorna a URL
// para o frontend redirecionar o usuario a gerenciar/cancelar a assinatura.
@['/billing-portal'; post]
pub fn (mut ac AuthController) billing_portal(mut ctx web_ctx.WsCtx) veb.Result {
	uid := ac.require_user_id(mut ctx) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}

	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}

	user := repo_auth.find_by_id(mut db, uid) or {
		ctx.res.set_status(.not_found)
		return ctx.json(types.failure[string](404, 'usuario nao encontrado'))
	}

	if user.stripe_customer_id == '' {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'usuario sem customer Stripe'))
	}

	mut stripe_client := ac.new_stripe_client() or {
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

	return ctx.json(types.success([{
		'url': portal.url
	}]))
}

// cancel_subscription cancela a assinatura ativa do usuario no Stripe e
// downgrade o plano para free no banco.
@['/cancel-subscription'; post]
pub fn (mut ac AuthController) cancel_subscription(mut ctx web_ctx.WsCtx) veb.Result {
	uid := ac.require_user_id(mut ctx) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}

	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
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
		return ctx.json(types.success([{
			'portal_required': true
		}]))
	}

	mut stripe_client := ac.new_stripe_client() or {
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

	return ctx.json(types.success([{
		'cancelled': true
	}]))
}

// resolve_app_customer devolve o stripe_customer_id valido para este app.
//
// Principio arquitetural: nunca buscar customer por email. O email pode
// existir em OUTROS produtos da mesma conta Stripe (multi-SaaS) e reusar
// o customer por email misturaria billing entre produtos. O customer
// deste app e' identificado pelo stripe_customer_id salvo no DB.
//
// Logica:
//   1. Se existing_customer_id != '', valida com get_customer. Se existir,
//      retorna o mesmo ID.
//   2. Se o ID salvo foi removido pelo Stripe (404) OU se o DB esta vazio,
//      cria um NOVO customer deste app e atualiza o DB.
//   3. Falhas de rede, autenticacao ou configuracao nao criam customers
//      adicionais: o checkout falha e pode ser repetido com seguranca.
fn is_missing_stripe_customer(err IError) bool {
	if err is stripe.StripeError {
		return err.status == 404
	}
	return false
}

fn resolve_app_customer(mut stripe_client stripe.Client, existing_customer_id string, user_id int, email string, mut db pg.DB) !string {
	if existing_customer_id != '' {
		if _ := stripe_client.get_customer(existing_customer_id) {
			// Customer valido: reusa.
			return existing_customer_id
		} else {
			if !is_missing_stripe_customer(err) {
				return error('falha ao validar customer Stripe: ${err}')
			}
		}
	}
	if email == '' {
		return error('email do usuario vazio')
	}
	// Cria um novo customer exclusivo deste app. Nao reusamos por email.
	// A descricao identifica no dashboard Stripe qual produto/app o
	// originou, para nao confundir com customers de outros SaaS na
	// mesma conta Stripe que compartilham o mesmo email.
	new_customer := stripe_client.create_customer_with_options(stripe.CustomerCreateParams{
		email:       email
		description: 'Tabua Mare API'
		metadata:    {
			'user_id': user_id.str()
		}
	}, stripe.RequestOptions{
		idempotency_key: 'customer_${user_id}'
	}) or { return err }
	// Sem persistir o ID, o webhook nao consegue associar com seguranca o
	// customer ao usuario; falhamos em vez de criar um customer orfao logico.
	repo_auth.set_stripe_customer_id(mut db, user_id, new_customer.id) or {
		return error('falha ao salvar stripe_customer_id: ${err}')
	}
	return new_customer.id
}
