module main

import json2
import veb
import v_stripe.stripe
import shareds.web_ctx
import repository.auth as repo_auth

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

	ac.process_stripe_event(event) or {
		eprintln('stripe webhook ${event.type_} failed: ${err}')
		ctx.res.set_status(.internal_server_error)
		return ctx.text('falha ao processar webhook')
	}

	return ctx.json({
		'received': 'true'
	})
}

// process_stripe_event concentra o despacho dos eventos aceitos pelo produto.
// O endpoint so confirma recebimento depois que o handler termina sem erro.
fn (mut ac AuthController) process_stripe_event(event stripe.Event) ! {
	match event.type_ {
		'checkout.session.completed' {
			handle_stripe_checkout_completed(mut ac, event)!
		}
		'customer.subscription.created', 'customer.subscription.updated' {
			handle_stripe_subscription_updated(mut ac, event)!
		}
		'customer.subscription.deleted' {
			handle_stripe_subscription_deleted(mut ac, event)!
		}
		'invoice.payment_failed' {
			handle_stripe_invoice_payment_failed(mut ac, event)!
		}
		else {}
	}
}

// handle_stripe_checkout_completed processa o evento checkout.session.completed:
// le o user_id dos metadados, atualiza o plano e salva subscription_id.
fn handle_stripe_checkout_completed(mut ac AuthController, event stripe.Event) ! {
	mut stripe_client := ac.new_stripe_client()!

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

	// extrai customer_id, status e plan_code do raw_body
	parsed := decode_stripe_event(event)!
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

fn decode_stripe_event(event stripe.Event) !StripeWebhookEvent {
	return json2.decode[StripeWebhookEvent](event.raw_body) or {
		error('falha ao parse raw_body: ${err}')
	}
}

// handle_stripe_subscription_deleted processa customer.subscription.deleted (cancelamento).
fn handle_stripe_subscription_deleted(mut ac AuthController, event stripe.Event) ! {
	mut db := ac.db_conn() or { return err }

	// extrai customer_id do raw_body para evitar chamar a API Stripe
	wrapper := decode_stripe_event(event)!
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
	mut stripe_client := ac.new_stripe_client()!

	invoice := decode_stripe_event(event)!
	customer_id := invoice.data.object.customer
	if customer_id == '' {
		return error('customer_id ausente no evento')
	}

	mut db := ac.db_conn() or { return err }

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
