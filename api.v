module main

import veb
import pool
import cache
import shareds.types
import shareds.logger
import shareds.web_ctx
import shareds.conf_env
import repository.habor_mare as repo_habor_mare
import repository.tabua_mare as repo_tabua_mare

// APIController Controller da API endpoint base: /api/v1
pub struct APIController {
	veb.Middleware[web_ctx.WsCtx]
	env   conf_env.EnvConfig
	cache shared cache.Cache
mut:
	log       logger.Logger
	pool_conn &pool.ConnectionPool
}

// init_cors inicializa o middleware CORS para o APIController
fn (mut api APIController) init_cors() {
	api.use(veb.cors[web_ctx.WsCtx](veb.CorsOptions{
		origins:           ['*']
		allowed_methods:   [.get]
		allowed_headers:   ['Content-Type', 'Authorization', 'Host', 'Accept', 'Origin',
			'X-Requested-With', 'Connection', 'Content-Length', 'Cache-Control', 'sec-ch-ua-platform',
			'User-Agent', 'sec-ch-ua', 'sec-ch-ua-mobile', 'Sec-GPC', 'Accept-Language',
			'Sec-Fetch-Site', 'Sec-Fetch-Mode', 'Sec-Fetch-Dest', 'Referer', 'Accept-Encoding',
			'Cdn-Loop', 'Cf-Connecting-Ip', 'Cf-Ipcountry', 'Cf-Ray', 'Cf-Visitor', 'Cf-Warp-Tag-Id',
			'Priority', 'Sec-Ch-Ua', 'Sec-Ch-Ua-Mobile', 'Sec-Ch-Ua-Platform', 'Sec-Gpc',
			'X-Forwarded-For', 'X-Forwarded-Host', 'X-Forwarded-Proto']
		allow_credentials: true
	}))
}

// list_states Lista todos os estados brasileiros
@['/states']
pub fn (mut api APIController) list_states(mut ctx web_ctx.WsCtx) veb.Result {
	shared ctx_cache := api.cache

	api.log.async_save(
		id:    ctx.request_id
		level: 'info'
		msg:   'Listando estados'
	)

	res := repo_habor_mare.list_states(shared ctx_cache, mut api.pool_conn) or {
		api.log.async_save(
			id:    ctx.request_id
			error: err
			level: 'error'
			msg:   'Erro ao listar estados'
		)
		return ctx.ok('error: ${err}')
	}

	api.log.async_save(
		id:    ctx.request_id
		error: res.error
		level: 'error'
		msg:   'Listando estados'
	)

	return ctx.json(res)
}

// list_harbor_name_by_states Lista todos os nomes de portos de um estado específico
//'
@['/harbor_names/:state']
pub fn (mut api APIController) list_harbor_name_by_states(mut ctx web_ctx.WsCtx, state string) veb.Result {
	shared ctx_cache := api.cache

	api.log.async_save(
		id:    ctx.request_id
		level: 'info'
		msg:   'Listando nomes de portos por estado: ${state}'
	)

	res := repo_habor_mare.list_harbor_name_by_states(shared ctx_cache, mut api.pool_conn,
		state) or {
		api.log.async_save(
			id:    ctx.request_id
			error: err
			level: 'error'
			msg:   'Erro ao listar nomes de portos por estado: ${state}'
		)
		return ctx.ok('error: ${err}')
	}

	api.log.async_save(
		id:    ctx.request_id
		level: 'info'
		msg:   'Nomes de portos listados com sucesso para estado: ${state}'
	)

	return ctx.json(res)
}

// get_harbors_by_ids Retorna informações de um/mais portos específico pelo seu ID
//'
@['/harbors/:ids']
pub fn (mut api APIController) get_harbors_by_ids(mut ctx web_ctx.WsCtx, ids types.IntArr) veb.Result {
	shared ctx_cache := api.cache

	api.log.async_save(
		id:    ctx.request_id
		level: 'info'
		msg:   'Obtendo portos pelos IDs: ${ids.ints()}'
	)

	res := repo_habor_mare.get_harbor_by_ids(shared ctx_cache, mut api.pool_conn, ids.ints()) or {
		api.log.async_save(
			id:    ctx.request_id
			error: err
			level: 'error'
			msg:   'Erro ao obter portos pelos IDs: ${ids.ints()}'
		)
		return ctx.ok('error: ${err}')
	}

	api.log.async_save(
		id:    ctx.request_id
		level: 'info'
		msg:   'Po6rtos obtidos com sucesso pelos IDs: ${ids.ints()}'
	)

	return ctx.json(res)
}

// get_tabua_mare Retorna o tábua (tabela) da mare de um porto específico para um mês e dias específicos.
@['/tabua-mare/:harbor/:month/:days']
pub fn (mut api APIController) get_tabua_mare(mut ctx web_ctx.WsCtx, harbor_id int, month int, days types.IntArr) veb.Result {
	shared ctx_cache := api.cache

	api.log.async_save(
		id:    ctx.request_id
		level: 'info'
		msg:   'Obtendo tábua da maré para porto ${harbor_id} (m:${month}, d:${days})'
	)

	result := repo_tabua_mare.get_tabua_mare_by_month_days(shared ctx_cache, mut api.pool_conn,
		harbor_id, month, days.ints()) or {
		api.log.async_save(
			id:    ctx.request_id
			error: err
			level: 'error'
			msg:   'Erro ao obter tábua da maré para porto ${harbor_id}, (m:${month}, d:${days})'
		)
		return ctx.ok('error: ${err}')
	}

	api.log.async_save(
		id:    ctx.request_id
		level: 'info'
		msg:   'Tábua da maré obtida com sucesso para porto ${harbor_id}, (m:${month}, d:${days})'
	)

	return ctx.json(result)
}
