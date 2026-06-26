module main

import veb
import pool
import net.http
import json
import shareds.web_ctx
import shareds.conf_env
import shareds.types
import domain.auth_user
import repository.auth as repo_auth

// AuthController trata das rotas de autenticacao (login Google, logout, /me, avatar).
pub struct AuthController {
	veb.Controller
	veb.Middleware[web_ctx.WsCtx]
pub mut:
	pool_conn_pg &pool.ConnectionPool = unsafe { nil }
	env          conf_env.EnvConfig
}

// google_login inicia o fluxo OAuth do Google: gera state, seta cookie efemero e
// redireciona para a URL de consentimento.
@['/google'; get]
pub fn (mut ac AuthController) google_login(mut ctx web_ctx.WsCtx) veb.Result {
	state := auth_user.random_state() or {
		ctx.res.set_status(.internal_server_error)
		return ctx.text('erro ao gerar state')
	}

	// state efemero em cookie (HttpOnly, curta duracao) para validar no callback
	ctx.set_cookie(http.Cookie{
		name:     'tm_oauth_state'
		value:    state
		path:     '/'
		max_age:  600
		http_only: true
		same_site: .same_site_lax_mode
	})

	cfg := ac.google_config()
	url := auth_user.build_auth_url(cfg, state)
	return ctx.redirect(url, veb.RedirectParams{ typ: .found })
}

// google_callback recebe ?code=&state=, valida state, troca code por tokens,
// busca userinfo, faz upsert do usuario no PostgreSQL, emite JWT e seta cookie
// de sessao HttpOnly. Redireciona para / (ou ?next=).
@['/google/callback'; get]
pub fn (mut ac AuthController) google_callback(mut ctx web_ctx.WsCtx) veb.Result {
	code := ctx.query['code'] or {
		ctx.res.set_status(.bad_request)
		return ctx.text('code ausente')
	}
	state := ctx.query['state'] or {
		ctx.res.set_status(.bad_request)
		return ctx.text('state ausente')
	}

	// valida state contra o cookie efemero
	expected_state := ctx.get_cookie('tm_oauth_state') or {
		ctx.res.set_status(.bad_request)
		return ctx.text('state cookie ausente')
	}
	if state != expected_state {
		ctx.res.set_status(.bad_request)
		return ctx.text('state invalido')
	}

	cfg := ac.google_config()

	access_token := auth_user.exchange_code(cfg, code) or {
		ctx.res.set_status(.unauthorized)
		return ctx.text('falha ao trocar code: ${err}')
	}

	user_info := auth_user.fetch_userinfo(cfg, access_token) or {
		ctx.res.set_status(.unauthorized)
		return ctx.text('falha ao obter userinfo: ${err}')
	}

	raw_json := json.encode(user_info)

	upsert := repo_auth.upsert_by_provider(mut ac.pool_conn_pg, 'google', user_info.sub,
		user_info.email, user_info.name, user_info.picture, raw_json) or {
		ctx.res.set_status(.internal_server_error)
		return ctx.text('falha ao criar/atualizar usuario: ${err}')
	}

	token := auth_user.issue(ac.env.session_secret, upsert.user_id, upsert.email, upsert.name,
		upsert.plan, ac.env.session_ttl_hours)

	// cookie de sessao HttpOnly (frontend nao le o JWT; usa /auth/me)
	secure := ac.env.url_env.starts_with('https')
	ctx.set_cookie(http.Cookie{
		name:     ac.env.session_cookie_name
		value:    token
		path:     '/'
		max_age:  ac.env.session_ttl_hours * 3600
		secure:   secure
		http_only: true
		same_site: .same_site_lax_mode
	})

	// limpa o cookie efemero de state
	ctx.set_cookie(http.Cookie{
		name:    'tm_oauth_state'
		value:   ''
		path:    '/'
		max_age: -1
	})

	next := ctx.query['next'] or { '/' }
	return ctx.redirect(next, veb.RedirectParams{ typ: .found })
}

// logout invalida a sessao limpando o cookie. (JWT e stateless; nao ha tabela
// de sessao para invalidar — basta o cliente descartar o cookie.)
@['/logout'; get; post]
pub fn (mut ac AuthController) logout(mut ctx web_ctx.WsCtx) veb.Result {
	ctx.set_cookie(http.Cookie{
		name:    ac.env.session_cookie_name
		value:   ''
		path:    '/'
		max_age: -1
	})
	return ctx.redirect('/', veb.RedirectParams{ typ: .found })
}

// me retorna o usuario corrente (lendo o cookie de sessao JWT) como ResultAPI.
@['/me'; get]
pub fn (mut ac AuthController) me(mut ctx web_ctx.WsCtx) veb.Result {
	token := ctx.get_cookie(ac.env.session_cookie_name) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}

	if !auth_user.verify(ac.env.session_secret, token) {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'token invalido ou expirado'))
	}

	claims := auth_user.decode(token) or {
		ctx.res.set_status(.unauthorized)
		return ctx.json(types.failure[string](401, 'token invalido'))
	}

	user := auth_user.UserData{
		id:         claims.sub
		email:      claims.email
		name:       claims.name
		plan:       claims.plan
		provider:   'google'
	}
	return ctx.json(types.success([user]))
}

fn (ac &AuthController) google_config() auth_user.GoogleConfig {
	return auth_user.GoogleConfig{
		client_id:     ac.env.google_client_id
		client_secret: ac.env.google_client_secret
		redirect_uri:  ac.env.google_redirect_uri
		auth_url:      ac.env.google_auth_url
		token_url:     ac.env.google_token_url
		userinfo_url:  ac.env.google_userinfo_url
		scope:         ac.env.google_scope
	}
}
