module main

import db.pg
import os
import shareds.infradb_pg

fn test_postgres_startup_migrations_are_idempotent() ! {
	if os.getenv('RUN_POSTGRES_TEST') != '1' {
		return
	}
	connstr := os.getenv('POSTGRESQL_CONN_STR')
	assert connstr != ''

	infradb_pg.apply_pg_startup_migrations()!
	infradb_pg.apply_pg_startup_migrations()!

	mut db := pg.connect_with_conninfo(connstr)!
	defer {
		db.close() or {}
	}
	rows := db.exec("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('users', 'user_identities', 'session_tokens', 'api_keys', 'rate_limit_counters', 'monthly_credits');")!
	assert rows.len == 1
	assert rows[0].vals.len == 1
	if count := rows[0].vals[0] {
		assert count.int() == 6
	} else {
		assert false
	}
}
