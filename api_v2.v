module main

import veb
import pool
import shareds.types
import shareds.web_ctx
import shareds.conf_env
import shareds.rate_limit
import repository.habor_mare as repo_habor_mare
import repository.tabua_mare as repo_tabua_mare
import repository.auth as repo_auth
import repository.auth.dto
import repository.rate_limit as rl
import shareds.infradb_pg

// APIController Controller da API endpoint base: /api/v2
pub struct APIControllerV2 {
	veb.Middleware[web_ctx.WsCtx]
	env conf_env.EnvConfig
mut:
	pool_conn &pool.ConnectionPool
	pg_holder &infradb_pg.PgHolder
}

// init_cors inicializa o middleware CORS para o APIController
fn (mut api APIControllerV2) init_cors() {
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

// init_rate_limit aplica o middleware de rate-limit (por IP/api_key, minuto + mes)
// usando a conexao PostgreSQL (contadores e creditos persistidos).
fn (mut api APIControllerV2) init_rate_limit(env conf_env.EnvConfig, pg_holder &infradb_pg.PgHolder) {
	api.use(rate_limit.rate_limit_middleware(rate_limit.RateLimitOpts{
		env: env
		pg_holder: pg_holder
	}))
}

// list_states Lista todos os estados brasileiros
@['/states']
pub fn (mut api APIControllerV2) list_states(mut ctx web_ctx.WsCtx) veb.Result {
	res := repo_habor_mare.list_states(mut api.pool_conn) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'error: ${err}'))
	}

	return ctx.json(types.success(res.data))
}

// list_harbor_name_by_states Lista todos os nomes de portos de um estado específico
//'
@['/harbor_names/:state']
pub fn (mut api APIControllerV2) list_harbor_name_by_states(mut ctx web_ctx.WsCtx, state string) veb.Result {
	res := repo_habor_mare.list_harbor_name_by_states(mut api.pool_conn, state) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'error: ${err}'))
	}

	return ctx.json(types.success(res.data))
}

// get_harbors_by_ids Retorna informações de um/mais portos específico pelo seu ID
//'
@['/harbors/:ids']
pub fn (mut api APIControllerV2) get_harbors_by_ids(mut ctx web_ctx.WsCtx, harbor_ids string) veb.Result {
	ids := types.StringRange(harbor_ids).list_string() or {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'error: ${err}'))
	}
	res := repo_habor_mare.get_harbor_by_ids(mut api.pool_conn, ids) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'error: ${err}'))
	}

	return ctx.json(types.success(res.data))
}

// get_tabua_mare Retorna o tábua (tabela) da mare de um porto específico para um mês e dias específicos.
@['/tabua-mare/:harbor/:month/:days']
pub fn (mut api APIControllerV2) get_tabua_mare(mut ctx web_ctx.WsCtx, harbor_id string, month int, days string) veb.Result {
	result := repo_tabua_mare.get_tabua_mare_by_month_days(mut api.pool_conn, harbor_id,
		month, types.IntRangeArr(days).ints()) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'error: ${err}'))
	}

	return ctx.json(types.success(result.data))
}

// get_tabua_mare Retorna o tábua (tabela) da mare do porto mais próximo dentro do mesmo estado baseado em sua localização. Em um mês e dias específicos.
@['/geo-tabua-mare/:lat_lng/:state/:month/:days']
pub fn (mut api APIControllerV2) get_nearested_tabua_mare(mut ctx web_ctx.WsCtx, lat_lng string, state string, month int, days string) veb.Result {
	geo_latlng := types.FloatArr(lat_lng).list_float()
	lat := geo_latlng[0] or { 0.0 }
	lng := geo_latlng[1] or { 0.0 }

	// TODO: Depois mover isso para dentro do método de get_tabua_mare_by_month_days
	nearest_harbor := repo_habor_mare.find_nearest_harbor_within_same_state_v2(mut api.pool_conn,
		lat, lng, state) or {
		ctx.res.set_status(.not_found)
		return ctx.json(types.failure[string](404, 'Nenhum porto encontrado perto das coordenadas fornecidas.'))
	}

	// TODO: CORRIGIR
	result := repo_tabua_mare.get_tabua_mare_by_month_days(mut api.pool_conn, nearest_harbor.id,
		month, types.IntRangeArr(days).ints()) or {
		ctx.res.set_status(.bad_request)
		return ctx.json(types.failure[string](400, 'error: ${err}'))
	}

	return ctx.json(types.success(result.data))
}

// get_nearest_harbor retorna os dados do porto mais próximo com base nas coordenadas geográficas.
@['/nearested-harbor/:state/:lat_lng']
pub fn (mut api APIControllerV2) get_nearest_harbor_by_state(mut ctx web_ctx.WsCtx, state string, lat_lng string) veb.Result {
	geo_latlng := types.FloatArr(lat_lng).list_float()
	lat := geo_latlng[0] or { 0.0 }
	lng := geo_latlng[1] or { 0.0 }

	nearest_harbor := repo_habor_mare.find_nearest_harbor_within_same_state_v2(mut api.pool_conn,
		lat, lng, state) or {
		ctx.res.set_status(.not_found)
		return ctx.json(types.failure[string](404, 'Nenhum porto encontrado perto das coordenadas fornecidas.'))
	}

	return ctx.json(types.success([nearest_harbor]))
}

// get_nearest_harbor retorna os dados do porto mais próximo com base nas coordenadas geográficas.
@['/nearest-harbor-independent-state/:lat_lng']
pub fn (mut api APIControllerV2) get_nearest_harbor(mut ctx web_ctx.WsCtx, lat_lng string) veb.Result {
	geo_latlng := types.FloatArr(lat_lng).list_float()
	lat := geo_latlng[0] or { 0.0 }
	lng := geo_latlng[1] or { 0.0 }

	nearest_harbor := repo_habor_mare.find_nearest_harbor_v2(mut api.pool_conn, lat, lng) or {
		ctx.res.set_status(.not_found)
		return ctx.json(types.failure[string](404, 'Nenhum porto encontrado perto das coordenadas fornecidas.'))
	}

	return ctx.json(types.success([nearest_harbor]))
}

// usage retorna a cota mensal restante para a api_key informada.
// Autenticacao via header Authorization: Bearer <key> ou X-Api-Key.
@['/usage'; get]
pub fn (mut api APIControllerV2) usage(mut ctx web_ctx.WsCtx) veb.Result {
	api_key := rate_limit.extract_api_key(mut ctx)
	if api_key == '' {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'api_key ausente'))
	}

	mut db := api.pg_holder.db()

	mut key_found := true
	key := repo_auth.find_by_key(mut db, api_key) or { key_found = false; dto.ApiKey{} }
	if !key_found || key.revoked {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'api_key invalida ou revogada'))
	}

	user_plan := repo_auth.find_plan_by_id(mut db, key.user_id) or { 'free' }
	mut effective_plan := key.plan
	if !rate_limit.is_plan_allowed(key.plan, user_plan) {
		effective_plan = user_plan
	}

	bucket := 'key:${key.key_value}'
	limit_rpm, limit_monthly := rate_limit.plan_limits(api.env, effective_plan)

	used_rpm := rl.get_count(mut db, bucket, 'minute', rl.window_key_minute()) or { 0 }
	monthly := rl.get_current_month_usage(mut db, bucket) or {
		rl.CreditCheck{used: 0, remaining: limit_monthly, lim: limit_monthly}
	}

	return ctx.json(types.success([{
		'plan':              effective_plan
		'limit_rpm':         limit_rpm.str()
		'used_rpm':          used_rpm.str()
		'remaining_rpm':     if limit_rpm == 0 { '-1' } else { (limit_rpm - used_rpm).str() }
		'limit_monthly':     limit_monthly.str()
		'used_monthly':      monthly.used.str()
		'remaining_monthly': if limit_monthly == 0 { '-1' } else { monthly.remaining.str() }
	}]))
}
