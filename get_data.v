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
pub mut:
	pool_conn &pool.ConnectionPool
	env       conf_env.EnvConfig
}

// list_states Lista todos os estados brasileiros
@['/states']
pub fn (app &APIController) list_states(mut ctx web_ctx.WsCtx) veb.Result {
	mut pool_conn := app.pool_conn
	return ctx.json(repo_data_mare.list_states(mut pool_conn) or { return ctx.ok('error: ${err}') })
}

// list_harbor_name_by_states Lista todos os nomes de portos de um estado específico
@['/harbor_names/:state']
pub fn (app &APIController) list_harbor_name_by_states(mut ctx web_ctx.WsCtx, state string) veb.Result {
	mut pool_conn := app.pool_conn
	return ctx.json(repo_data_mare.list_harbor_name_by_states(mut pool_conn, state) or {
		return ctx.ok('error: ${err}')
	})
}

// get_harbors_by_ids Retorna informações de um/mais portos específico pelo seu ID
@['/harbors/:ids']
pub fn (app &APIController) get_harbors_by_ids(mut ctx web_ctx.WsCtx, ids types.IntArr) veb.Result {
	mut pool_conn := app.pool_conn

	return ctx.json(repo_data_mare.get_harbor_by_ids(mut pool_conn, ids.ints()) or {
		return ctx.ok('error: ${err}')
	})
}

// get_tabua_mare Retorna o tábua (tabela) da mare de um porto específico para um mês e dias específicos.
@['/tabua-mare/:harbor/:month/:days']
pub fn (api &APIController) get_tabua_mare(mut ctx web_ctx.WsCtx, harbor_id int, month int, days types.IntArr) veb.Result {
	mut pool_conn := api.pool_conn

	result := repo_tabua_mare.get_tabua_mare_by_month_days(mut pool_conn, harbor_id,
		month, days.ints()) or { return ctx.ok('error: ${err}') }

	return ctx.json(result)
}
