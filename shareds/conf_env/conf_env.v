module conf_env

import os
import dotenv

// EnvConfig representa todas as variáveis de ambiente do arquivo .env
// Contém todas as configurações necessárias para a aplicação funcionar corretamente
pub struct EnvConfig {
pub:
	db_database string
	db_host     string
	db_port     string
	db_user     string
	db_pass     string
	url_env     string
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
		db_database: get_env('DB_DATABASE', env_map).trim_space()
		db_host:     get_env('DB_HOST', env_map).trim_space()
		db_port:     get_env('DB_PORT', env_map).trim_space()
		db_user:     get_env('DB_USER', env_map).trim_space()
		db_pass:     get_env('DB_PASS', env_map).trim_space()
		url_env:     get_env('URL_ENV', env_map).trim_space()
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
