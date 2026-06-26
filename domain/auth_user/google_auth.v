module auth_user

import net.http
import net.urllib
import json
import crypto.rand
import encoding.base64

pub struct GoogleUserInfo {
pub:
	sub            string @[json: 'sub']
	email          string @[json: 'email']
	name           string @[json: 'name']
	picture        string @[json: 'picture']
	email_verified bool   @[json: 'email_verified']
}

pub struct GoogleConfig {
pub:
	client_id     string
	client_secret string
	redirect_uri  string
	auth_url      string
	token_url     string
	userinfo_url  string
	scope         string
}

// random_state gera um state aleatorio para CSRF.
pub fn random_state() !string {
	raw := rand.bytes(24)!
	return base64.url_encode(raw)
}

// build_auth_url constroi a URL de consentimento do Google com state.
pub fn build_auth_url(cfg GoogleConfig, state string) string {
	params := [
		'client_id=${urllib.query_escape(cfg.client_id)}',
		'redirect_uri=${urllib.query_escape(cfg.redirect_uri)}',
		'response_type=code',
		'scope=${urllib.query_escape(cfg.scope)}',
		'state=${urllib.query_escape(state)}',
		'access_type=online',
		'prompt=consent',
	].join('&')
	return '${cfg.auth_url}?${params}'
}

// exchange_code troca o code por tokens e retorna o access_token.
pub fn exchange_code(cfg GoogleConfig, code string) !string {
	data := http.url_encode_form_data({
		'code':          code
		'client_id':     cfg.client_id
		'client_secret': cfg.client_secret
		'redirect_uri':  cfg.redirect_uri
		'grant_type':    'authorization_code'
	})

	resp := http.fetch(http.FetchConfig{
		method: .post
		header: http.new_header(http.HeaderConfig{ .content_type, 'application/x-www-form-urlencoded' })
		url:    cfg.token_url
		data:   data
	})!

	tokens := json.decode(TokenResponse, resp.body)!
	return tokens.access_token
}

// fetch_userinfo busca os dados do usuario no Google userinfo endpoint.
pub fn fetch_userinfo(cfg GoogleConfig, access_token string) !GoogleUserInfo {
	if access_token == '' {
		return error('access_token is required')
	}
	resp := http.fetch(http.FetchConfig{
		header: http.new_header(http.HeaderConfig{ .authorization, 'Bearer ${access_token}' })
		url:    cfg.userinfo_url
	})!
	return json.decode(GoogleUserInfo, resp.body)!
}

struct TokenResponse {
	access_token string @[json: 'access_token']
	expires_in   int    @[json: 'expires_in']
	token_type   string @[json: 'token_type']
}