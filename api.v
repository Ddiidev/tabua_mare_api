module main

import veb
import pool
import shareds.types
import shareds.web_ctx
import shareds.conf_env
import repository.data_mare as repo_data_mare
import repository.tabua_mare as repo_tabua_mare

// APIController Controlador da API endpoint base: /api/v1
pub struct APIController {
	veb.Middleware[web_ctx.WsCtx]
	env conf_env.EnvConfig
mut:
	pool_conn &pool.ConnectionPool
}

// list_states Lista todos os estados brasileiros
@['/states']
pub fn (mut api APIController) list_states(mut ctx web_ctx.WsCtx) veb.Result {
	return ctx.json(repo_data_mare.list_states(mut api.pool_conn) or {
		return ctx.ok('error: ${err}')
	})
}

// list_harbor_name_by_states Lista todos os nomes de portos de um estado específico
@['/harbor_names/:state']
pub fn (mut api APIController) list_harbor_name_by_states(mut ctx web_ctx.WsCtx, state string) veb.Result {
	return ctx.json(repo_data_mare.list_harbor_name_by_states(mut api.pool_conn, state) or {
		return ctx.ok('error: ${err}')
	})
}

// get_harbors_by_ids Retorna informações de um/mais portos específico pelo seu ID
@['/harbors/:ids']
pub fn (mut api APIController) get_harbors_by_ids(mut ctx web_ctx.WsCtx, ids types.IntArr) veb.Result {
	return ctx.json(repo_data_mare.get_harbor_by_ids(mut api.pool_conn, ids.ints()) or {
		return ctx.ok('error: ${err}')
	})
}

// get_tabua_mare Retorna o tábua (tabela) da mare de um porto específico para um mês e dias específicos.
@['/tabua-mare/:harbor/:month/:days']
pub fn (mut api APIController) get_tabua_mare(mut ctx web_ctx.WsCtx, harbor_id int, month int, days types.IntArr) veb.Result {
	// mut pool_conn := api.pool_conn

	result := repo_tabua_mare.get_tabua_mare_by_month_days(mut api.pool_conn, harbor_id,
		month, days.ints()) or { return ctx.ok('error: ${err}') }

	return ctx.json(result)
}
