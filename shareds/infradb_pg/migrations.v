module infradb_pg

import db.pg
import shareds.conf_env

// apply_pg_startup_migrations cria as tabelas de domínio (auth/dash/contadores/credits)
// no PostgreSQL externo. Idempotente (IF NOT EXISTS). Não-fatal no main.
pub fn apply_pg_startup_migrations() ! {
	env := conf_env.load_env()
	mut db := pg.connect(pg.Config{
		host:     env.db_host
		port:     env.db_port.int()
		user:     env.db_user
		password: env.db_pass
		dbname:   env.db_database
	})!
	defer {
		db.close() or {}
	}

	ensure_users_tables(mut db)!
	ensure_rate_limit_tables(mut db)!
	ensure_monthly_credits_table(mut db)!
}

fn ensure_users_tables(mut db pg.DB) ! {
	db.exec('CREATE TABLE IF NOT EXISTS users (
		id SERIAL PRIMARY KEY,
		email TEXT NOT NULL UNIQUE,
		name TEXT NOT NULL DEFAULT \'\',
		avatar_url TEXT NOT NULL DEFAULT \'\',
		plan TEXT NOT NULL DEFAULT \'free\',
		created_at TIMESTAMP NOT NULL DEFAULT now(),
		updated_at TIMESTAMP NOT NULL DEFAULT now()
	);')!

	db.exec('CREATE TABLE IF NOT EXISTS user_identities (
		id SERIAL PRIMARY KEY,
		user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		provider TEXT NOT NULL,
		provider_uid TEXT NOT NULL,
		email TEXT NOT NULL DEFAULT \'\',
		name TEXT NOT NULL DEFAULT \'\',
		avatar_url TEXT NOT NULL DEFAULT \'\',
		raw_json TEXT NOT NULL DEFAULT \'\',
		created_at TIMESTAMP NOT NULL DEFAULT now(),
		updated_at TIMESTAMP NOT NULL DEFAULT now(),
		UNIQUE(provider, provider_uid)
	);')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_user_identities_user ON user_identities(user_id);')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_user_identities_provider ON user_identities(provider, provider_uid);')!

	db.exec('CREATE TABLE IF NOT EXISTS session_tokens (
		id SERIAL PRIMARY KEY,
		user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		value TEXT NOT NULL UNIQUE,
		expires_at TIMESTAMP NOT NULL,
		created_at TIMESTAMP NOT NULL DEFAULT now()
	);')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_session_tokens_value ON session_tokens(value);')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_session_tokens_user ON session_tokens(user_id);')!

	db.exec('CREATE TABLE IF NOT EXISTS api_keys (
		id SERIAL PRIMARY KEY,
		user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		key_value TEXT NOT NULL UNIQUE,
		label TEXT NOT NULL DEFAULT \'\',
		plan TEXT NOT NULL DEFAULT \'free\',
		created_at TIMESTAMP NOT NULL DEFAULT now(),
		revoked_at TIMESTAMP
	);')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_api_keys_value ON api_keys(key_value);')!
}

fn ensure_rate_limit_tables(mut db pg.DB) ! {
	db.exec('CREATE TABLE IF NOT EXISTS rate_limit_counters (
		bucket TEXT NOT NULL,
		window_kind TEXT NOT NULL,
		window_key TEXT NOT NULL,
		count INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY (bucket, window_kind, window_key)
	);')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_rate_limit_bucket ON rate_limit_counters(bucket, window_kind);')!
}

fn ensure_monthly_credits_table(mut db pg.DB) ! {
	db.exec('CREATE TABLE IF NOT EXISTS monthly_credits (
		bucket TEXT NOT NULL,
		month_key TEXT NOT NULL,
		plan TEXT NOT NULL DEFAULT \'free\',
		used INTEGER NOT NULL DEFAULT 0,
		lim INTEGER NOT NULL,
		remaining INTEGER NOT NULL,
		reset_at TIMESTAMP NOT NULL,
		PRIMARY KEY (bucket, month_key)
	);')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_monthly_credits_bucket ON monthly_credits(bucket, month_key);')!
}
