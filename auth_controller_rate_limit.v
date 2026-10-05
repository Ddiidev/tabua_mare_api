module main

import db.pg
import veb
import shareds.rate_limit
import shareds.types
import shareds.web_ctx
import repository.rate_limit as rl

struct RateLimitSubject {
	bucket string
	plan   string
}

// rate_limit_subject resolve somente identidade da medicao. A consulta dos
// contadores fica no handler, deixando explicita a separacao entre identidade,
// limites e uso.
fn (ac &AuthController) rate_limit_subject(mut ctx web_ctx.WsCtx, mut db pg.DB) RateLimitSubject {
	subject := RateLimitSubject{
		bucket: 'ip:${ctx.ip()}'
		plan:   'anon'
	}
	api_key := rate_limit.extract_api_key(mut ctx)
	identity := rate_limit.resolve_api_key_identity(mut db, api_key) or { return subject }
	if !identity.found {
		return subject
	}
	return RateLimitSubject{
		bucket: identity.bucket
		plan:   identity.plan
	}
}

// rate_limit_status retorna o uso atual de rate-limit do usuario/ip/chave.
// Como este endpoint nao passa pelo middleware de rate-limit (só /api/v2/* passa),
// extraimos a api_key e determinamos o plano manualmente.
@['/rate-limit-status'; get]
pub fn (mut ac AuthController) rate_limit_status(mut ctx web_ctx.WsCtx) veb.Result {
	mut db := ac.db_conn() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
	}

	subject := ac.rate_limit_subject(mut ctx, mut db)
	limit_rpm, limit_monthly := rate_limit.plan_limits(ac.env, subject.plan)

	used_rpm := rl.get_count(mut db, subject.bucket, 'minute', rl.window_key_minute()) or { 0 }
	monthly := rl.get_current_month_usage(mut db, subject.bucket, limit_monthly) or {
		rl.CreditCheck{
			used:      0
			remaining: limit_monthly
			lim:       limit_monthly
		}
	}

	return ctx.json(types.success([
		{
			'plan':              subject.plan
			'limit_rpm':         limit_rpm.str()
			'used_rpm':          used_rpm.str()
			'remaining_rpm':     if limit_rpm == 0 { '-1' } else { (limit_rpm - used_rpm).str() }
			'limit_monthly':     limit_monthly.str()
			'used_monthly':      monthly.used.str()
			'remaining_monthly': if limit_monthly == 0 { '-1' } else { monthly.remaining.str() }
		},
	]))
}
