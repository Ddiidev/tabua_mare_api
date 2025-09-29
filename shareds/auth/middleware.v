module auth

import jwt
import shareds.types
import shareds.conf_env
import shareds.web_ctx

struct UserData {
pub:
	email string
	name  string
}

// auth_middleware valida o JWT e injeta os dados do usuário no contexto
pub fn auth_middleware(mut ctx web_ctx.WsCtx) bool {
	// Permitir requisições OPTIONS (preflight CORS)
	if ctx.req.method == .options {
		return true
	}

	// Excluir rotas que não precisam de autenticação
	if ctx.req.url.starts_with('/auth/') {
		return true
	}

	token_str := get_authorization(mut ctx) or { return false }

	// Carrega as configurações
	env := conf_env.load_env()
	jwt_secret := env.jwt_secret
	if jwt_secret.len == 0 {
		ctx.res.set_status(.internal_server_error)
		ctx.json({
			'error': 'JWT secret not configured'
		})
		return false
	}

	// Decodifica e valida o token
	token := jwt.from_str[UserData](token_str) or {
		ctx.res.set_status(.unauthorized)
		ctx.json({
			'error': 'Invalid token format'
		})
		return false
	}

	// Verifica se o token é válido
	if !token.valid(jwt_secret) {
		ctx.res.set_status(.unauthorized)
		ctx.json({
			'error': 'Invalid or expired token'
		})
		return false
	}

	ctx.req.add_cookie(name: 'Authorization', value: token.payload.sub or { return false })

	return true
}

fn get_authorization(mut ctx web_ctx.WsCtx) ?string {
	// Obtém o header Authorization
	auth_header := ctx.req.header.get(.authorization) or {
		ctx.res.set_status(.unauthorized)
		ctx.json({
			'error': 'Authorization header is required'
		})
		return none
	}

	// Verifica se o header tem o formato correto "Bearer <token>"
	if !auth_header.starts_with('Bearer ') {
		ctx.res.set_status(.unauthorized)
		ctx.json({
			'error': 'Invalid authorization header format'
		})
		return none
	}

	// Extrai o token
	token_str := auth_header[7..] // Remove "Bearer "
	if token_str.len == 0 {
		ctx.res.set_status(.unauthorized)
		ctx.json({
			'error': 'Token is required'
		})
		return none
	}

	return token_str
}

pub fn get_user_id(ctx web_ctx.WsCtx) ?types.UUID {
	return ctx.req.cookie('Authorization')?.value
}

pub fn get_user_name(mut ctx web_ctx.WsCtx) ?string {
	token_str := get_authorization(mut ctx)?

	// Carrega as configurações
	env := conf_env.load_env()
	jwt_secret := env.jwt_secret
	if jwt_secret.len == 0 {
		ctx.res.set_status(.internal_server_error)
		ctx.json({
			'error': 'JWT secret not configured'
		})
		return none
	}

	// Decodifica e valida o token
	token := jwt.from_str[UserData](token_str) or {
		ctx.res.set_status(.unauthorized)
		ctx.json({
			'error': 'Invalid token format'
		})
		return none
	}

	return token.payload.ext.name
}
