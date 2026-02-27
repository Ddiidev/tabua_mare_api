module infradb

import pool
import time

$if using_sqlite ? {
	import db.sqlite as db_provider
} $else {
	import db.pg as db_provider
}
import shareds.conf_env

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

$if using_sqlite ? {
	fn create_conn() !&pool.ConnectionPoolable {
		env := conf_env.load_env()

		mut db := db_provider.connect(env.db_sqlite_path)!
		db.exec('PRAGMA journal_mode=WAL;') or {}
		db.exec('PRAGMA busy_timeout=5000;') or {}

		return &db
	}
} $else {
	fn create_conn() !&pool.ConnectionPoolable {
		env := conf_env.load_env()

		config := db_provider.Config{
			host:     env.db_host
			port:     env.db_port.int()
			user:     env.db_user
			password: env.db_pass
			dbname:   env.db_database
		}
		db := db_provider.connect(config)!

		return &db
	}
}
