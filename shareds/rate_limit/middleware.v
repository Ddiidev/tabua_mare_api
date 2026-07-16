module rate_limit

import veb
import db.pg
import shareds.web_ctx
import shareds.conf_env
import shareds.types
import domain.auth_user
import repository.auth as repo_auth
import repository.rate_limit as rl
import shareds.infradb_pg

pub struct RateLimitOpts {
pub mut:
	env       conf_env.EnvConfig
	pg_holder &infradb_pg.PgHolder
}

pub struct ApiKeyIdentity {
pub:
	found     bool
	bucket    string
	plan      string
	key_value string
}

// rate_limit_middleware retorna um MiddlewareOptions para o veb que aplica rate-limit por IP/api_key.
// As consultas continuam ocorrendo em toda requisicao para preservar revogacao de
// chaves e limites atuais, mas usam o pool PostgreSQL compartilhado da aplicacao.
pub fn rate_limit_middleware(opts RateLimitOpts) veb.MiddlewareOptions[web_ctx.WsCtx] {
	env := opts.env
	pg_holder := opts.pg_holder
	return veb.MiddlewareOptions[web_ctx.WsCtx]{
		handler: fn [env, pg_holder] (mut ctx web_ctx.WsCtx) bool {
			return do_rate_limit(mut ctx, env, pg_holder)
		}
	}
}

// do_rate_limit executa a logica de rate-limit fora da closure para evitar
// o limite de niveis de expressao do checker do V.
fn do_rate_limit(mut ctx web_ctx.WsCtx, env conf_env.EnvConfig, pg_holder &infradb_pg.PgHolder) bool {
	ip := ctx.ip()
	ctx.ip = ip
	ctx.plan = 'anon'
	if !pg_holder.available() {
		return reject_dependency(mut ctx, 'PostgreSQL indisponivel')
	}

	mut db_pg := pg_holder.db()

	mut bucket := 'ip:${ip}'
	mut plan := 'anon'

	identity := resolve_api_key_identity(mut db_pg, extract_api_key(mut ctx)) or {
		eprintln('rate_limit api key lookup failed: ${err}')
		return reject_dependency(mut ctx, 'Falha ao consultar rate-limit')
	}
	if identity.found {
		bucket = identity.bucket
		ctx.api_key = identity.key_value
		plan = identity.plan
		ctx.plan = identity.plan
	}

	limit_rpm, limit_monthly := plan_limits(env, plan)
	return apply_limits(mut ctx, mut db_pg, bucket, plan, limit_rpm, limit_monthly)
}

// plan_limits resolve o RPM e a cota mensal para um plano.
// sem api_key, qualquer cliente (inclusive JWT logado) usa anon por IP;
// free usa rate_limit_free_* somente para api_keys Free;
// plan5/plan10/planannual usam os campos correspondentes.
// ATENCAO: regra espelhada em pages/dashboard.html:isPlanAllowed() — nao confundir.
pub fn plan_limits(env conf_env.EnvConfig, plan string) (int, int) {
	return match plan {
		'anon' { env.rate_limit_anon_rpm, env.rate_limit_anon_monthly }
		'plan5' { env.rate_limit_plan5_rpm, env.rate_limit_plan5_monthly }
		'plan10', 'planannual' { env.rate_limit_plan10_rpm, env.rate_limit_plan10_monthly }
		else { env.rate_limit_free_rpm, env.rate_limit_free_monthly }
	}
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

// effective_plan aplica a regra da chave ao plano atual do usuario.
// Uma chave antiga nunca pode manter privilegios depois de um downgrade.
pub fn effective_plan(key_plan string, user_plan string) string {
	if is_plan_allowed(key_plan, user_plan) {
		return key_plan
	}
	return user_plan
}

// resolve_api_key_identity concentra a consulta e a regra de downgrade de uma chave.
// Chave ausente/revogada vira anonimo; falha real no banco sobe para 503 no chamador.
pub fn resolve_api_key_identity(mut db pg.DB, api_key string) !ApiKeyIdentity {
	if api_key == '' {
		return ApiKeyIdentity{}
	}
	key := repo_auth.find_by_key(mut db, api_key) or {
		if err.msg() == 'api key nao encontrada' {
			return ApiKeyIdentity{}
		}
		return err
	}
	if key.revoked {
		return ApiKeyIdentity{}
	}
	user_plan := repo_auth.find_plan_by_id(mut db, key.user_id)!
	return ApiKeyIdentity{
		found:     true
		bucket:    'key:${key.key_value}'
		plan:      effective_plan(key.plan, user_plan)
		key_value: key.key_value
	}
}

fn apply_limits(mut ctx web_ctx.WsCtx, mut db pg.DB, bucket string, plan string, limit_rpm int, limit_monthly int) bool {
	minute_key := rl.window_key_minute()
	exceeded_minute := rl.inc_and_check(mut db, bucket, 'minute', minute_key, limit_rpm) or {
		eprintln('rate_limit minute check failed: ${err}')
		return reject_dependency(mut ctx, 'Falha ao registrar rate-limit')
	}
	if exceeded_minute {
		ctx.res.set_status(.too_many_requests)
		ctx.res.header.add(.retry_after, '60')
		ctx.json(types.failure[string](429, 'Limite por minuto excedido'))
		return false
	}

	// garante que a linha de creditos existe antes de qualquer operacao (decrement ou inc)
	rl.ensure_credit_row(mut db, bucket, plan, limit_monthly) or {
		eprintln('rate_limit ensure_credit_row failed: ${err}')
		return reject_dependency(mut ctx, 'Falha ao registrar rate-limit')
	}

	if limit_monthly != 0 {
		exceeded_month := rl.decrement(mut db, bucket) or {
			eprintln('rate_limit monthly check failed: ${err}')
			return reject_dependency(mut ctx, 'Falha ao registrar rate-limit')
		}
		if exceeded_month {
			ctx.res.set_status(.too_many_requests)
			ctx.res.header.add(.retry_after, '3600')
			ctx.json(types.failure[string](429, 'Cota mensal excedida'))
			return false
		}
	} else {
		// plano ilimitado: apenas conta used
		rl.inc(mut db, bucket, 'month', rl.window_key_month()) or {
			eprintln('rate_limit month count failed: ${err}')
			return reject_dependency(mut ctx, 'Falha ao registrar rate-limit')
		}
	}

	return true
}

fn reject_dependency(mut ctx web_ctx.WsCtx, message string) bool {
	ctx.res.set_status(.service_unavailable)
	ctx.json(types.failure[string](503, message))
	return false
}

pub fn extract_api_key(mut ctx web_ctx.WsCtx) string {
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
