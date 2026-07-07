module rate_limit

import veb
import db.pg
import shareds.web_ctx
import shareds.conf_env
import shareds.types
import domain.auth_user
import repository.auth as repo_auth
import repository.auth.dto
import repository.rate_limit as rl

pub struct RateLimitOpts {
pub mut:
	env conf_env.EnvConfig
}

// rate_limit_middleware retorna um MiddlewareOptions para o veb que aplica rate-limit por IP/api_key.
// Nota: cria uma conexao PG nova por request porque capturar &pg.DB em closure do veb
// triga um bug no V 0.5.1 (handler trava no primeiro acesso). Para rate-limit
// (1-2 queries por request) o custo de open/close e' aceitavel.
pub fn rate_limit_middleware(opts RateLimitOpts) veb.MiddlewareOptions[web_ctx.WsCtx] {
	env := opts.env
	connstr := env.postgresql_conn_str
	return veb.MiddlewareOptions[web_ctx.WsCtx]{
		handler: fn [env, connstr] (mut ctx web_ctx.WsCtx) bool {
			return do_rate_limit(mut ctx, env, connstr)
		}
	}
}

// do_rate_limit executa a logica de rate-limit fora da closure para evitar
// o limite de niveis de expressao do checker do V.
fn do_rate_limit(mut ctx web_ctx.WsCtx, env conf_env.EnvConfig, connstr string) bool {
	ip := ctx.ip()
	ctx.ip = ip
	ctx.plan = 'free'

	if connstr == '' {
		return true
	}

	mut db_pg := pg.connect_with_conninfo(connstr) or {
		eprintln('rate_limit: pg connect failed: ${err}')
		return true
	}
	defer {
		db_pg.close() or {}
	}

	mut bucket := 'ip:${ip}'
	mut plan := 'anon'
	mut limit_rpm := env.rate_limit_anon_rpm
	mut limit_monthly := env.rate_limit_anon_monthly

	// se o usuario esta logado (cookie JWT valido), aplica o limite free (ou superior conforme o plano)
	uid := logged_user_id(mut ctx, env)
	if uid > 0 {
		user_plan := repo_auth.find_plan_by_id(mut db_pg, uid) or { 'free' }
		plan = user_plan
		ctx.plan = user_plan
		match user_plan {
			'plan5' {
				limit_rpm = env.rate_limit_plan5_rpm
				limit_monthly = env.rate_limit_plan5_monthly
			}
			'plan10', 'planannual' {
				limit_rpm = env.rate_limit_plan10_rpm
				limit_monthly = env.rate_limit_plan10_monthly
			}
			else {
				limit_rpm = env.rate_limit_free_rpm
				limit_monthly = env.rate_limit_free_monthly
			}
		}
	}

	api_key := extract_api_key(mut ctx)
	if api_key != '' {
		mut key_found := true
		key := repo_auth.find_by_key(mut db_pg, api_key) or { key_found = false; dto.ApiKey{} }
		if key_found && !key.revoked {
			// valida se o plano do usuario ainda permite o plano da key
			// evita furo: usuario cancelou, mas a key antiga continua paga
			mut effective_plan := key.plan
			user_plan := repo_auth.find_plan_by_id(mut db_pg, key.user_id) or { '' }
			if !is_plan_allowed(key.plan, user_plan) {
				effective_plan = user_plan
			}

			bucket = 'key:${key.key_value}'
			ctx.api_key = key.key_value
			plan = effective_plan
			ctx.plan = effective_plan
			match effective_plan {
				'plan5' {
					limit_rpm = env.rate_limit_plan5_rpm
					limit_monthly = env.rate_limit_plan5_monthly
				}
				'plan10', 'planannual' {
					limit_rpm = env.rate_limit_plan10_rpm
					limit_monthly = env.rate_limit_plan10_monthly
				}
				else {
					limit_rpm = env.rate_limit_free_rpm
					limit_monthly = env.rate_limit_free_monthly
				}
			}
		}
	}

	return apply_limits(mut ctx, mut db_pg, bucket, plan, limit_rpm, limit_monthly)
}

// is_plan_allowed retorna true se o plano da api_key ainda e valido para o usuario.
// Regras: plan10/planannual requerem usuario plan10/planannual; plan5 requer plan5 ou superior;
// free e sempre valido.
pub fn is_plan_allowed(key_plan string, user_plan string) bool {
	if key_plan == 'free' {
		return true
	}
	if key_plan == 'plan5' {
		return user_plan in ['plan5', 'plan10', 'planannual']
	}
	if key_plan in ['plan10', 'planannual'] {
		return user_plan in ['plan10', 'planannual']
	}
	return false
}

fn apply_limits(mut ctx web_ctx.WsCtx, mut db pg.DB, bucket string, plan string, limit_rpm int, limit_monthly int) bool {
	minute_key := rl.window_key_minute()
	exceeded_minute := rl.inc_and_check(mut db, bucket, 'minute', minute_key, limit_rpm) or {
		eprintln('rate_limit minute check failed: ${err}')
		false
	}
	if exceeded_minute {
		ctx.res.set_status(.too_many_requests)
		ctx.res.header.add(.retry_after, '60')
		ctx.json(types.failure[string](429, 'Limite por minuto excedido'))
		return false
	}

	if limit_monthly != 0 {
		// garante que a linha de creditos existe antes de decrementar
		rl.ensure_credit_row(mut db, bucket, plan, limit_monthly) or {
			eprintln('rate_limit ensure_credit_row failed: ${err}')
		}
		exceeded_month := rl.decrement(mut db, bucket) or {
			eprintln('rate_limit monthly check failed: ${err}')
			false
		}
		if exceeded_month {
			ctx.res.set_status(.too_many_requests)
			ctx.res.header.add(.retry_after, '3600')
			ctx.json(types.failure[string](429, 'Cota mensal excedida'))
			return false
		}
	} else {
		// plano ilimitado: cria a linha apenas para contar used
		rl.ensure_credit_row(mut db, bucket, plan, limit_monthly) or {
			eprintln('rate_limit ensure_credit_row failed: ${err}')
		}
		rl.inc(mut db, bucket, 'month', rl.window_key_month()) or {
			eprintln('rate_limit month count failed: ${err}')
		}
	}

	return true
}

fn extract_api_key(mut ctx web_ctx.WsCtx) string {
	if auth := ctx.req.header.get(.authorization) {
		if auth.starts_with('Bearer ') {
			return auth[7..]
		}
		return auth
	}
	q := ctx.req.header.get_custom('X-Api-Key') or { '' }
	if q != '' {
		return q
	}
	return ctx.form['api_key'] or { '' }
}

// logged_user_id extrai o user_id do cookie JWT, se o usuario estiver autenticado.
fn logged_user_id(mut ctx web_ctx.WsCtx, env conf_env.EnvConfig) int {
	if env.session_secret == '' {
		return 0
	}
	token := ctx.get_cookie(env.session_cookie_name) or { return 0 }
	if !auth_user.verify(env.session_secret, token) {
		return 0
	}
	claims := auth_user.decode(token) or { return 0 }
	return claims.sub
}