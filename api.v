module main

import veb
import pool
import shareds.types
import shareds.web_ctx
import shareds.conf_env
import repository.habor_mare as repo_habor_mare
import repository.tabua_mare as repo_tabua_mare

// APIController Controller da API endpoint base: /api/v1
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

// list_states Lista todos os estados brasileiros
@['/states']
pub fn (mut api APIController) list_states(mut ctx web_ctx.WsCtx) veb.Result {
	res := repo_habor_mare.list_states(mut api.pool_conn) or {
		ctx.request_error('error: ${err}')
		return ctx.server_error_with_status(.bad_request)
	}

	return ctx.json(res)
}

// list_harbor_name_by_states Lista todos os nomes de portos de um estado específico
//'
@['/harbor_names/:state']
pub fn (mut api APIController) list_harbor_name_by_states(mut ctx web_ctx.WsCtx, state string) veb.Result {
	res := repo_habor_mare.list_harbor_name_by_states(mut api.pool_conn, state) or {
		ctx.request_error('error: ${err}')
		return ctx.server_error_with_status(.bad_request)
	}

	return ctx.json(res)
}

// get_harbors_by_ids Retorna informações de um/mais portos específico pelo seu ID
//'
@['/harbors/:ids']
pub fn (mut api APIController) get_harbors_by_ids(mut ctx web_ctx.WsCtx, ids types.IntRangeArr) veb.Result {
	res := repo_habor_mare.get_harbor_by_ids(mut api.pool_conn, ids.ints()) or {
		ctx.request_error('error: ${err}')
		return ctx.server_error_with_status(.bad_request)
	}

	return ctx.json(res)
}

// get_tabua_mare Retorna o tábua (tabela) da mare de um porto específico para um mês e dias específicos.
@['/tabua-mare/:harbor/:month/:days']
pub fn (mut api APIController) get_tabua_mare(mut ctx web_ctx.WsCtx, harbor_id int, month int, days types.IntRangeArr) veb.Result {
	result := repo_tabua_mare.get_tabua_mare_by_month_days(mut api.pool_conn, harbor_id,
		month, days.ints()) or {
		ctx.request_error('error: ${err}')
		return ctx.server_error_with_status(.bad_request)
	}

	return ctx.json(result)
}

// get_tabua_mare Retorna o tábua (tabela) da mare do porto mais próximo dentro do mesmo estado baseado em sua localização. Em um mês e dias específicos.
@['/geo-tabua-mare/:lat_lng/:state/:month/:days']
pub fn (mut api APIController) get_nearested_tabua_mare(mut ctx web_ctx.WsCtx, lat_lng types.FloatArr, state string, month int, days types.IntRangeArr) veb.Result {
	geo_latlng := lat_lng.list_float()
	lat := geo_latlng[0]
	lng := geo_latlng[1]

	// TODO: Depois deixar isso dentro do método de get_tabua_mare_by_month_days
	nearest_harbor := repo_habor_mare.find_nearest_harbor_within_same_state(mut api.pool_conn,
		lat, lng, state) or {
		ctx.request_error('Nenhum porto encontrado perto das coordenadas fornecidas.')
		return ctx.server_error_with_status(.not_found)
	}

	result := repo_tabua_mare.get_tabua_mare_by_month_days(mut api.pool_conn, nearest_harbor.id,
		month, days.ints()) or {
		ctx.request_error('error: ${err}')
		return ctx.server_error_with_status(.bad_request)
	}

	return ctx.json(result)
}

// get_nearest_harbor retorna os dados do porto mais próximo com base nas coordenadas geográficas.
@['/nearested-harbor/:state/:lat_lng']
pub fn (mut api APIController) get_nearest_harbor_by_state(mut ctx web_ctx.WsCtx, state string, lat_lng types.FloatArr) veb.Result {
	geo_latlng := lat_lng.list_float()
	lat := geo_latlng[0]
	lng := geo_latlng[1]

	nearest_harbor := repo_habor_mare.find_nearest_harbor_within_same_state(mut api.pool_conn,
		lat, lng, state) or {
		ctx.request_error('Nenhum porto encontrado perto das coordenadas fornecidas.')
		return ctx.server_error_with_status(.not_found)
	}

	return ctx.json(nearest_harbor)
}

// get_nearest_harbor retorna os dados do porto mais próximo com base nas coordenadas geográficas.
@['/nearest-harbor-independent-state/:lat_lng']
pub fn (mut api APIController) get_nearest_harbor(mut ctx web_ctx.WsCtx, lat_lng types.FloatArr) veb.Result {
	geo_latlng := lat_lng.list_float()
	lat := geo_latlng[0]
	lng := geo_latlng[1]

	nearest_harbor := repo_habor_mare.find_nearest_harbor(mut api.pool_conn, lat, lng) or {
		ctx.request_error('Nenhum porto encontrado perto das coordenadas fornecidas.')
		return ctx.server_error_with_status(.not_found)
	}

	return ctx.json(nearest_harbor)
}
