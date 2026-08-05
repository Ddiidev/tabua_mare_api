module auth_user

import time
import json2
import crypto.hmac
import crypto.sha256
import encoding.base64

struct JwtHeader {
	alg string
	typ string
}

pub struct JwtClaims {
pub:
	sub   int    @[json: 'sub']
	email string @[json: 'email']
	name  string @[json: 'name']
	plan  string @[json: 'plan']
	iat   i64    @[json: 'iat']
	exp   i64    @[json: 'exp']
}

// make_token gera um JWT HS256 com as claims fornecidas e o secret.
pub fn make_token(secret string, claims JwtClaims) string {
	header :=
		base64.url_encode(json2.encode(JwtHeader{'HS256', 'JWT'}, escape_unicode: true).bytes())
	payload := base64.url_encode(json2.encode(claims, escape_unicode: true).bytes())
	signature := base64.url_encode(hmac.new(secret.bytes(), '${header}.${payload}'.bytes(),
		sha256.sum, sha256.block_size))
	return '${header}.${payload}.${signature}'
}

// verify valida a assinatura do token e que exp nao expirou.
pub fn verify(secret string, token string) bool {
	parts := token.split('.')
	if parts.len != 3 {
		return false
	}
	signature_mirror := hmac.new(secret.bytes(), '${parts[0]}.${parts[1]}'.bytes(), sha256.sum,
		sha256.block_size)
	signature_from_token := base64.url_decode(parts[2])
	if !hmac.equal(signature_from_token, signature_mirror) {
		return false
	}
	decoded := decode(token) or { return false }
	return !decoded.is_expired()
}

// decode decodifica as claims do token (sem validar assinatura). Use verify antes.
pub fn decode(token string) !JwtClaims {
	parts := token.split('.')
	if parts.len != 3 {
		return error('token invalido')
	}
	payload := base64.url_decode_str(parts[1])
	return json2.decode[JwtClaims](payload)!
}

// is_expired checa se exp ja passou (exp 0 = sem expiracao).
pub fn (c &JwtClaims) is_expired() bool {
	return c.exp > 0 && time.now().unix() > c.exp
}

// issue cria um token novo para um usuario com ttl_horas.
pub fn issue(secret string, user_id int, email string, name string, plan string, ttl_hours int) string {
	now := time.now().unix()
	claims := JwtClaims{
		sub:   user_id
		email: email
		name:  name
		plan:  plan
		iat:   now
		exp:   now + i64(ttl_hours) * 3600
	}
	return make_token(secret, claims)
}
