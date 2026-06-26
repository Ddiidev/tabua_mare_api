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

	// Create and populate the config struct
	return EnvConfig{
		db_sqlite_path:            get_env_or('DB_SQLITE_PATH', env_map, '').trim_space()
		db_database:               get_env_or('DB_DATABASE', env_map, '').trim_space()
		db_host:                   get_env_or('DB_HOST', env_map, '').trim_space()
		db_port:                   get_env_or('DB_PORT', env_map, '').trim_space()
		db_user:                   get_env_or('DB_USER', env_map, '').trim_space()
		db_pass:                   get_env_or('DB_PASS', env_map, '').trim_space()
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
		rate_limit_plan10_rpm:     get_env_or('RATE_LIMIT_PLAN10_RPM', env_map, '2560').int()
		rate_limit_free_monthly:   get_env_or('RATE_LIMIT_FREE_MONTHLY', env_map, '20000').int()
		rate_limit_plan5_monthly:  get_env_or('RATE_LIMIT_PLAN5_MONTHLY', env_map, '250000').int()
		rate_limit_plan10_monthly: get_env_or('RATE_LIMIT_PLAN10_MONTHLY', env_map, '0').int()
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
