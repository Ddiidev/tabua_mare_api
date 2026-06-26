module rate_limit

import veb
import pool
import shareds.web_ctx
import shareds.conf_env
import shareds.types
import repository.auth as repo_auth
import repository.rate_limit as rl

pub struct RateLimitOpts {
pub mut:
	pool_conn_pg &pool.ConnectionPool = unsafe { nil }
	env          conf_env.EnvConfig
}

// rate_limit_middleware retorna um MiddlewareOptions para o veb que aplica rate-limit por IP/api_key.
pub fn rate_limit_middleware(opts RateLimitOpts) veb.MiddlewareOptions[web_ctx.WsCtx] {
	mut pool_conn_pg := opts.pool_conn_pg
	env := opts.env
	return veb.MiddlewareOptions[web_ctx.WsCtx]{
		handler: fn [mut pool_conn_pg, env] (mut ctx web_ctx.WsCtx) bool {
			ip := ctx.ip()
			ctx.ip = ip

			mut bucket := 'ip:${ip}'
			mut plan := 'free'
			mut limit_rpm := env.rate_limit_free_rpm
			mut limit_monthly := env.rate_limit_free_monthly

			api_key := extract_api_key(mut ctx)
			if api_key != '' {
				key := repo_auth.find_by_key(mut pool_conn_pg, api_key) or {
					return apply_limits(mut ctx, mut pool_conn_pg, bucket, limit_rpm, limit_monthly)
				}
				if key.revoked {
					return apply_limits(mut ctx, mut pool_conn_pg, bucket, limit_rpm, limit_monthly)
				}
				bucket = 'key:${key.key_value}'
				plan = key.plan
				ctx.api_key = key.key_value
				ctx.plan = plan
				match plan {
					'plan5' {
						limit_rpm = env.rate_limit_plan5_rpm
						limit_monthly = env.rate_limit_plan5_monthly
					}
					'plan10' {
						limit_rpm = env.rate_limit_plan10_rpm
						limit_monthly = env.rate_limit_plan10_monthly
					}
					else {
						limit_rpm = env.rate_limit_free_rpm
						limit_monthly = env.rate_limit_free_monthly
					}
				}
			}

			return apply_limits(mut ctx, mut pool_conn_pg, bucket, limit_rpm, limit_monthly)
		}
	}
}

fn apply_limits(mut ctx web_ctx.WsCtx, mut pool_conn pool.ConnectionPool, bucket string, limit_rpm int, limit_monthly int) bool {
	minute_key := rl.window_key_minute()
	exceeded_minute := rl.inc_and_check(mut pool_conn, bucket, 'minute', minute_key, limit_rpm) or {
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
		exceeded_month := rl.decrement(mut pool_conn, bucket) or {
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
		rl.inc(mut pool_conn, bucket, 'month', rl.window_key_month()) or {
			eprintln('rate_limit month count failed: ${err}')
		}
	}

	return true
}

fn extract_api_key(mut ctx web_ctx.WsCtx) string {
	if auth := ctx.req.header.get(.authorization) {
		if auth.starts_with('Bearer ') {
			return auth[8..]
		}
		return auth
	}
	q := ctx.req.header.get_custom('X-Api-Key') or { '' }
	if q != '' {
		return q
	}
	return ctx.form['api_key'] or { '' }
}
