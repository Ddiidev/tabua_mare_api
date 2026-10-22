module main

import db.pg
import os
import rand
import repository.auth
import shareds.infradb_pg

// Usa apenas a base de teste explicitamente habilitada, como as migrations.
fn test_registration_first_login_concurrency_and_rollback() ! {
	if os.getenv('RUN_POSTGRES_TEST') != '1' {
		return
	}
	infradb_pg.apply_pg_startup_migrations()!
	mut db := pg.connect_with_conninfo(os.getenv('POSTGRESQL_CONN_STR'))!
	fixture := 'welcome-${rand.uuid_v4()}'
	email := '${fixture}@example.invalid'
	defer {
		db.exec_param('DELETE FROM users WHERE email = $1', email) or {}
		db.close() or {}
	}
	// Callbacks concorrentes devem criar uma conta e sinalizar apenas um primeiro cadastro.
	first_thread := spawn register_fixture(mut db, fixture, email)
	second_thread := spawn register_fixture(mut db, fixture, email)
	first := first_thread.wait()!
	second := second_thread.wait()!
	assert first.user_id == second.user_id
	assert first.is_new_user != second.is_new_user
	assert first.user_id > 0
	login :=
		auth.upsert_by_provider(mut db, 'google', fixture, email, 'Conta empresarial', '', '{}')!
	assert !login.is_new_user
	assert login.user_id == first.user_id
	assert login.name == 'Conta empresarial'
	counts := db.exec_param('SELECT count(*) FROM users WHERE email = $1', email)!
	count := counts[0].vals[0] or { '' }
	assert count == '1'

	// Uma falha na identity deve desfazer tambem o INSERT em users.
	mut rollback_db := pg.connect_with_conninfo(os.getenv('POSTGRESQL_CONN_STR'))!
	rollback_db.set_max_open_conns(1)
	rollback_db.set_max_idle_conns(1)
	defer { rollback_db.close() or {} }
	rollback_db.exec('CREATE TEMP TABLE users (id SERIAL PRIMARY KEY, email TEXT UNIQUE, name TEXT, avatar_url TEXT, plan TEXT)')!
	rollback_db.exec('CREATE TEMP TABLE user_identities (user_id INTEGER, provider TEXT, provider_uid TEXT, email TEXT, name TEXT, avatar_url TEXT, raw_json TEXT, CONSTRAINT reject_fixture CHECK (false))')!
	if _ := auth.upsert_by_provider(mut rollback_db, 'google', fixture, email, '', '', '{}') {
		assert false
	}
	rolled_back := rollback_db.exec('SELECT count(*) FROM users')!
	rollback_count := rolled_back[0].vals[0] or { '' }
	assert rollback_count == '0'
	// Duplicidade de email deve falhar sem criar uma segunda identidade.
	if _ := auth.upsert_by_provider(mut db, 'google', fixture + '-duplicate', email, '', '', '{}') {
		assert false
	}
	identities := db.exec_param('SELECT count(*) FROM user_identities WHERE provider_uid = $1',
		fixture + '-duplicate')!
	identity_count := identities[0].vals[0] or { '' }
	assert identity_count == '0'
}

fn register_fixture(mut db pg.DB, uid string, email string) !auth.UpsertResult {
	return auth.upsert_by_provider(mut db, 'google', uid, email, 'Conta de teste', '', '{}')
}
