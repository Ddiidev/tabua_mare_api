module infradb_pg

import pool
import time
import db.pg
import shareds.conf_env

// new cria um pool de conexões para o PostgreSQL externo (auth/dash/contadores/credits).
// Sempre-on (independente de -d using_sqlite).
pub fn new() !&pool.ConnectionPool {
	config := pool.ConnectionPoolConfig{
		max_conns:      10
		min_idle_conns: 2
		max_lifetime:   time.hour
		idle_timeout:   1 * time.minute
		get_timeout:    15 * time.second
	}

	return pool.new_connection_pool(create_conn, config)!
}

fn create_conn() !&pool.ConnectionPoolable {
	env := conf_env.load_env()

	config := pg.Config{
		host:     env.db_host
		port:     env.db_port.int()
		user:     env.db_user
		password: env.db_pass
		dbname:   env.db_database
	}
	db := pg.connect(config)!

	return &db
}
