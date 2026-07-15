module infradb_pg

import db.pg
import net.urllib
import sync
import shareds.conf_env

// PgConn e' a conexao PostgreSQL (pg.DB tem pool interno thread-safe).
// Usamos uma unica &pg.DB em vez de pool.ConnectionPool do V (bug em V 0.5.1).
pub type PgConn = &pg.DB

// PgHolder envolve a &pg.DB para que closures de middleware capturem o holder
// (struct wrapper) em vez da &pg.DB direta, evitando o bug de captura de
// referencia &pg.DB em closures no V 0.5.1 (handler trava no primeiro acesso).
@[nocopy]
pub struct PgHolder {
mut:
	lock sync.Mutex
	db   &pg.DB = unsafe { nil }
}

// new cria e retorna um holder com a conexao PG (e guarda a conexao internamente).
// Retorna none se a conexao falhar (o app continua; auth/rate-limit fica desligado).
pub fn new() ?&PgHolder {
	env := conf_env.load_env()

	mut db := if env.postgresql_conn_str != '' {
		pg.connect_with_conninfo(env.postgresql_conn_str) or { return none }
	} else {
		pg.connect(pg_config_from_env(env)) or { return none }
	}

	return &PgHolder{
		db: unsafe { &db }
	}
}

// is_healthy confirma que o PostgreSQL obrigatorio aceita conexao e consulta.
pub fn is_healthy(connstr string) bool {
	if connstr == '' {
		return false
	}
	mut db := pg.connect_with_conninfo(connstr) or { return false }
	defer {
		db.close() or {}
	}
	db.exec('SELECT 1') or { return false }
	return true
}

// db retorna a conexao PG do holder (thread-safe).
pub fn (mut h PgHolder) db() &pg.DB {
	h.lock.lock()
	defer {
		h.lock.unlock()
	}
	return h.db
}

// raw retorna a conexao PG bruta (para repositories que usam mut db pg.DB).
pub fn (mut h PgHolder) raw() &pg.DB {
	return h.db
}

// pg_config_from_env constroi um pg.Config a partir das vars individuais (DB_*).
fn pg_config_from_env(env conf_env.EnvConfig) pg.Config {
	return pg.Config{
		host:     env.db_host
		port:     env.db_port.int()
		user:     env.db_user
		password: env.db_pass
		dbname:   env.db_database
	}
}

// pg_config_from_connstr parseia uma URI postgresql://... em pg.Config.
// Formato esperado: postgresql://user:pass@host:port/dbname?sslmode=...
pub fn pg_config_from_connstr(connstr string) !pg.Config {
	url := urllib.parse(connstr)!
	mut host := ''
	mut port := 0
	if url.host != '' {
		// url.host pode ser "host:port"
		parts := url.host.split(':')
		host = parts[0]
		if parts.len > 1 {
			port = parts[1].int()
		}
	}
	mut user := ''
	mut password := ''
	if u := url.user {
		user = u.username
		password = u.password
	}
	mut dbname := ''
	// path vem como "/dbname"; remove a barra inicial
	if url.path.len > 1 {
		dbname = url.path[1..]
	}
	return pg.Config{
		host:     host
		port:     port
		user:     user
		password: password
		dbname:   dbname
	}
}
