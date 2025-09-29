module auth

import jwt
import time
import shareds.conf_env
import domain.auth_user

// create_jwt Criar um token de um usuário
pub fn create_jwt(user_uuid string, user auth_user.UserData) string {
	// Carrega configurações de ambiente
	env := conf_env.load_env()
	jwt_secret := env.jwt_secret

	payload := jwt.Payload[auth_user.UserData]{
		sub: user_uuid
		exp: time.now().add(time.hour * 48).str()
		iat: time.now().str()
		iss: 'ModerAI'
		ext: user
	}

	return jwt.Token.new(payload, jwt_secret).str()
}
