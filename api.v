module main

import veb
import pool
import shareds.types
import shareds.web_ctx
import shareds.conf_env

// APIController Controller da API endpoint base: /api/v1
//
// DEPRECIADA: todos os handlers respondem 410 Gone com mensagem indicando para
// usar a v2. A V1 nao serve dados de mare (evita bypass do rate-limit free).
pub struct APIController {
	veb.Middleware[web_ctx.WsCtx]
	env conf_env.EnvConfig
mut:
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

// gone_v1 responde 410 Gone com a mensagem padrao de depreciação da V1.
fn gone_v1(mut ctx web_ctx.WsCtx) veb.Result {
	ctx.res.set_status(.gone)
	return ctx.json(types.failure[string](410, 'API v1 depreciada; use a v2. Docs: /docs'))
}

// list_states Lista todos os estados brasileiros
@['/states']
pub fn (mut api APIController) list_states(mut ctx web_ctx.WsCtx) veb.Result {
	return gone_v1(mut ctx)
}

// list_harbor_name_by_states Lista todos os nomes de portos de um estado específico
//'
@['/harbor_names/:state']
pub fn (mut api APIController) list_harbor_name_by_states(mut ctx web_ctx.WsCtx, state string) veb.Result {
	return gone_v1(mut ctx)
}

// get_harbors_by_ids Retorna informações de um/mais portos específico pelo seu ID
//'
@['/harbors/:ids']
pub fn (mut api APIController) get_harbors_by_ids(mut ctx web_ctx.WsCtx, ids string) veb.Result {
	return gone_v1(mut ctx)
}

// get_tabua_mare Retorna o tábua (tabela) da mare de um porto específico para um mês e dias específicos.
@['/tabua-mare/:harbor/:month/:days']
pub fn (mut api APIController) get_tabua_mare(mut ctx web_ctx.WsCtx, harbor_id int, month int, days string) veb.Result {
	return gone_v1(mut ctx)
}

// get_tabua_mare Retorna o tábua (tabela) da mare do porto mais próximo dentro do mesmo estado baseado em sua localização. Em um mês e dias específicos.
@['/geo-tabua-mare/:lat_lng/:state/:month/:days']
pub fn (mut api APIController) get_nearested_tabua_mare(mut ctx web_ctx.WsCtx, lat_lng string, state string, month int, days string) veb.Result {
	return gone_v1(mut ctx)
}

// get_nearest_harbor retorna os dados do porto mais próximo com base nas coordenadas geográficas.
@['/nearested-harbor/:state/:lat_lng']
pub fn (mut api APIController) get_nearest_harbor_by_state(mut ctx web_ctx.WsCtx, state string, lat_lng string) veb.Result {
	return gone_v1(mut ctx)
}

// get_nearest_harbor retorna os dados do porto mais próximo com base nas coordenadas geográficas.
@['/nearest-harbor-independent-state/:lat_lng']
pub fn (mut api APIController) get_nearest_harbor(mut ctx web_ctx.WsCtx, lat_lng string) veb.Result {
	return gone_v1(mut ctx)
}
