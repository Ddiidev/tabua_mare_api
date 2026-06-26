module infradb

import pool
import time
import db.sqlite
import shareds.conf_env

// new cria um pool de conexões para o SQLite (dados de maré da API).
// Sempre-on (independente de flags de compilação). PostgreSQL (auth/dash) fica em shareds.infradb_pg.
pub fn new() !&pool.ConnectionPool {
	config := pool.ConnectionPoolConfig{
		max_conns:      10
		min_idle_conns: 5
		max_lifetime:   time.hour
		idle_timeout:   1 * time.minute
		get_timeout:    15 * time.second
	}

	return pool.new_connection_pool(create_conn, config)!
}

fn create_conn() !&pool.ConnectionPoolable {
	env := conf_env.load_env()

	mut db := sqlite.connect(env.db_sqlite_path)!
	db.exec('PRAGMA journal_mode=WAL;') or {}
	db.exec('PRAGMA busy_timeout=5000;') or {}

	return &db
}
