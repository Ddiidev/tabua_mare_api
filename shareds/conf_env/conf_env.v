module conf_env

import os
import ken0x0a.dotenv

// EnvConfig representa todas as variáveis de ambiente do arquivo .env
// Contém todas as configurações necessárias para a aplicação funcionar corretamente
pub struct EnvConfig {
pub:
	db_sqlite_path            string
	db_database               string
	db_host                   string
	db_port                   string
	db_user                   string
	db_pass                   string
	postgresql_conn_str       string
	url_env                   string
	new_relic_key             string
	current_port              string
	google_client_id          string
	google_client_secret      string
	google_redirect_uri       string
	google_auth_url           string
	google_token_url          string
	google_userinfo_url       string
	google_scope              string
	session_secret            string
	session_cookie_name       string
	session_ttl_hours         int
	avatar_cache_ttl_minutes  int
	rate_limit_free_rpm       int
	rate_limit_plan5_rpm      int
	rate_limit_plan10_rpm     int
	rate_limit_free_monthly   int
	rate_limit_plan5_monthly  int
	rate_limit_plan10_monthly int
	rate_limit_anon_rpm       int
	rate_limit_anon_monthly   int
	stripe_secret_key         string
	stripe_webhook_secret     string
	stripe_price_plan5        string
	stripe_price_plan10       string
	stripe_price_planannual   string
}

pub struct StripePriceIds {
pub:
	plan5      string
	plan10     string
	planannual string
}

// load_env carrega as variáveis de ambiente primeiro do sistema operacional e, se não encontradas,
// utiliza o arquivo .env como alternativa
// Retorna: Uma instância de EnvConfig com todas as variáveis de ambiente carregadas
pub fn load_env() EnvConfig {
	env_map := if !os.exists('.env') {
		map[string]string{}
	} else {
		dotenv.parse('.env')
	}

	prices := stripe_price_ids(env_map)

	// Create and populate the config struct
	return EnvConfig{
		db_sqlite_path:            get_env_or('DB_SQLITE_PATH', env_map, '').trim_space()
		db_database:               get_env_or('DB_DATABASE', env_map, '').trim_space()
		db_host:                   get_env_or('DB_HOST', env_map, '').trim_space()
		db_port:                   get_env_or('DB_PORT', env_map, '').trim_space()
		db_user:                   get_env_or('DB_USER', env_map, '').trim_space()
		db_pass:                   get_env_or('DB_PASS', env_map, '').trim_space()
		postgresql_conn_str:       get_env_or('POSTGRESQL_CONN_STR', env_map, '').trim_space()
		new_relic_key:             get_env_or('NEW_RELIC_KEY', env_map, '').trim_space()
		url_env:                   get_env_or('URL_ENV', env_map, '').trim_space()
		google_client_id:          get_env_or('GOOGLE_CLIENT_ID', env_map, '').trim_space()
		google_client_secret:      get_env_or('GOOGLE_CLIENT_SECRET', env_map, '').trim_space()
		google_redirect_uri:       get_env_or('GOOGLE_REDIRECT_URI', env_map, '').trim_space()
		google_auth_url:           get_env_or('GOOGLE_AUTH_URL', env_map,
			'https://accounts.google.com/o/oauth2/v2/auth').trim_space()
		google_token_url:          get_env_or('GOOGLE_TOKEN_URL', env_map,
			'https://oauth2.googleapis.com/token').trim_space()
		google_userinfo_url:       get_env_or('GOOGLE_USERINFO_URL', env_map,
			'https://www.googleapis.com/oauth2/v3/userinfo').trim_space()
		google_scope:              get_env_or('GOOGLE_SCOPE', env_map, 'openid email profile').trim_space()
		session_secret:            get_env_or('SESSION_SECRET', env_map, '').trim_space()
		session_cookie_name:       get_env_or('SESSION_COOKIE_NAME', env_map, 'tm_session').trim_space()
		session_ttl_hours:         get_env_or('SESSION_TTL_HOURS', env_map, '720').int()
		avatar_cache_ttl_minutes:  get_env_or('AVATAR_CACHE_TTL_MINUTES', env_map, '60').int()
		rate_limit_free_rpm:       get_env_or('RATE_LIMIT_FREE_RPM', env_map, '64').int()
		rate_limit_plan5_rpm:      get_env_or('RATE_LIMIT_PLAN5_RPM', env_map, '512').int()
		rate_limit_plan10_rpm:     get_env_or('RATE_LIMIT_PLAN10_RPM', env_map, '2048').int()
		rate_limit_free_monthly:   get_env_or('RATE_LIMIT_FREE_MONTHLY', env_map, '32000').int()
		rate_limit_plan5_monthly:  get_env_or('RATE_LIMIT_PLAN5_MONTHLY', env_map, '256000').int()
		rate_limit_plan10_monthly: get_env_or('RATE_LIMIT_PLAN10_MONTHLY', env_map, '0').int()
		rate_limit_anon_rpm:       get_env_or('RATE_LIMIT_ANON_RPM', env_map, '16').int()
		rate_limit_anon_monthly:   get_env_or('RATE_LIMIT_ANON_MONTHLY', env_map, '0').int()
		stripe_secret_key:         get_env_or('STRIPE_SECRET_KEY', env_map, '').trim_space()
		stripe_webhook_secret:     get_env_or('STRIPE_WEBHOOK_SECRET', env_map, '').trim_space()
		stripe_price_plan5:        prices.plan5
		stripe_price_plan10:       prices.plan10
		stripe_price_planannual:   prices.planannual
	}
}

pub fn stripe_price_ids(env_map map[string]string) StripePriceIds {
	$if env_dev ? {
		return StripePriceIds{
			plan5:      get_env_or('STRIPE_PRICE_PLAN5', env_map, '').trim_space()
			plan10:     get_env_or('STRIPE_PRICE_PLAN10', env_map, '').trim_space()
			planannual: get_env_or('STRIPE_PRICE_PLANANNUAL', env_map, '').trim_space()
		}
	} $else {
		return StripePriceIds{
			plan5:      'price_1TsmqjLZ5gTFc3B29AhoC9fq'
			plan10:     'price_1TsmsxLZ5gTFc3B2xsbFW6L8'
			planannual: 'price_1TsmtrLZ5gTFc3B2rQEaEmqY'
		}
	}
}

pub fn is_production(env EnvConfig) bool {
	return env.url_env.trim_right('/') == 'https://tabuamare.api.br'
}

fn is_placeholder_value(value string) bool {
	trimmed := value.trim_space()
	lower := trimmed.to_lower()
	if lower == ''
		|| lower in ['change-me', 'changeme', 'replace-me', 'replaceme', 'placeholder', 'todo', 'your-secret-here'] {
		return true
	}
	if lower.contains('precisa preencher') || lower.contains('placeholder')
		|| lower.contains('replace-me') {
		return true
	}
	return trimmed.starts_with('[') && trimmed.ends_with(']')
}

fn has_prefixed_payload(value string, prefix string, min_payload_len int) bool {
	trimmed := value.trim_space()
	return !is_placeholder_value(trimmed) && trimmed.starts_with(prefix)
		&& trimmed.len >= prefix.len + min_payload_len
}

pub fn validate_startup(env EnvConfig) ! {
	if !is_production(env) {
		return
	}

	secret := env.session_secret.trim_space()
	if secret.len < 32 || is_placeholder_value(secret) || secret.to_lower() == 'session_secret' {
		return error('SESSION_SECRET ausente, placeholder ou fraco para producao')
	}
	if is_placeholder_value(env.postgresql_conn_str) {
		return error('POSTGRESQL_CONN_STR obrigatoria em producao')
	}
	if is_placeholder_value(env.google_client_id) || env.google_client_id.trim_space().len < 20 {
		return error('GOOGLE_CLIENT_ID obrigatorio em producao')
	}
	if is_placeholder_value(env.google_client_secret)
		|| env.google_client_secret.trim_space().len < 16 {
		return error('GOOGLE_CLIENT_SECRET obrigatorio em producao')
	}
	if env.google_redirect_uri != 'https://tabuamare.api.br/auth/google/callback' {
		return error('GOOGLE_REDIRECT_URI deve usar o callback oficial de producao')
	}
	if !has_prefixed_payload(env.stripe_secret_key, 'sk_live_', 16) {
		return error('STRIPE_SECRET_KEY deve usar sk_live_ em producao')
	}
	if !has_prefixed_payload(env.stripe_webhook_secret, 'whsec_', 16) {
		return error('STRIPE_WEBHOOK_SECRET deve usar whsec_ em producao')
	}
	prices := [env.stripe_price_plan5, env.stripe_price_plan10, env.stripe_price_planannual]
	price_names := ['STRIPE_PRICE_PLAN5', 'STRIPE_PRICE_PLAN10', 'STRIPE_PRICE_PLANANNUAL']
	for index, price in prices {
		if !has_prefixed_payload(price, 'price_', 8) {
			return error('${price_names[index]} deve conter um price ID valido')
		}
	}
	if prices[0] == prices[1] || prices[0] == prices[2] || prices[1] == prices[2] {
		return error('Stripe prices devem ser distintos por plano')
	}
}

// get_env obtém o valor de uma variável de ambiente específica
// Parâmetros:
//   key - A chave da variável de ambiente a ser buscada
//   env_map - Um mapa contendo as variáveis de ambiente do arquivo .env
// Retorna: O valor da variável de ambiente ou gera um erro se não encontrada
fn get_env(key string, env_map map[string]string) string {
	sys_env := os.getenv(key)
	if sys_env != '' {
		return sys_env
	}
	return env_map[key] or { panic('Missing required environment variable: ${key}') }
}

fn get_env_or(key string, env_map map[string]string, default_value string) string {
	sys_env := os.getenv(key)
	if sys_env != '' {
		return sys_env
	}
	return env_map[key] or { default_value }
}
