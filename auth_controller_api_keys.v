module main

import json2
import veb
import shareds.types
import shareds.web_ctx
import repository.auth as repo_auth

// api_keys_list lista as api_keys do usuario corrente.
@['/api-keys'; get]
pub fn (mut ac AuthController) api_keys_list(mut ctx web_ctx.WsCtx) veb.Result {
	uid := ac.require_user_id(mut ctx) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}
	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}

	keys := repo_auth.list_by_user(mut db, uid) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'erro: ${err}'))
	}
	return ctx.json(types.success(keys))
}

// api_keys_create cria uma nova api_key para o usuario corrente.
// Body JSON: {"label": "..."} — a chave nao tem plano proprio; os limites
// seguem o plano do usuario dono da chave.
@['/api-keys'; post]
pub fn (mut ac AuthController) api_keys_create(mut ctx web_ctx.WsCtx) veb.Result {
	uid := ac.require_user_id(mut ctx) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}

	parsed := json2.decode[ApiKeyCreatePayload](ctx.req.data) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'JSON invalido: ${err}'))
	}

	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}

	user_plan := repo_auth.find_plan_by_id(mut db, uid) or { 'free' }

	key_value := repo_auth.issue(mut db, uid, parsed.label, user_plan) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'erro ao criar api_key: ${err}'))
	}

	return ctx.json(types.success([
		{
			'key_value': key_value
			'label':     parsed.label
			'plan':      user_plan
		},
	]))
}

struct ApiKeyCreatePayload {
	label string
	plan  string
}

// api_keys_revoke revoga uma api_key do usuario corrente.
@['/api-keys/:id'; delete]
pub fn (mut ac AuthController) api_keys_revoke(mut ctx web_ctx.WsCtx, id string) veb.Result {
	uid := ac.require_user_id(mut ctx) or {
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

	repo_auth.revoke(mut db, uid, key_id) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'erro ao revogar: ${err}'))
	}
	return ctx.json(types.success([{
		'revoked': true
	}]))
}
