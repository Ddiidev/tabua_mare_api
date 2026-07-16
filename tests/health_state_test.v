import shareds.health
import shareds.infradb
import shareds.infradb_pg

fn test_readiness_starts_false_and_tracks_shutdown() {
	mut state := health.new_state()
	assert !state.is_ready()

	state.mark_ready()
	assert state.is_ready()

	state.begin_shutdown()
	assert !state.is_ready()

	state.mark_ready()
	assert !state.is_ready()
}

fn test_readiness_requires_sqlite_and_postgres_dependencies() {
	mut state := health.new_state()
	state.mark_ready()

	assert state.is_ready_with_dependencies(true, true)
	assert !state.is_ready_with_dependencies(false, true)
	assert !state.is_ready_with_dependencies(true, false)
}

fn test_sqlite_health_requires_a_working_pool() ! {
	mut pool_conn := infradb.new()!
	assert infradb.sqlite_is_healthy(mut pool_conn)

	pool_conn.close()
	assert !infradb.sqlite_is_healthy(mut pool_conn)
}

fn test_postgres_health_fails_closed_without_connection() {
	mut unavailable := &infradb_pg.PgHolder{}
	assert !unavailable.available()
	assert !unavailable.is_healthy()
}

fn test_postgres_pool_caps_open_connections() ! {
	holder := infradb_pg.new() or { return }
	mut db := holder.db()
	stats := db.stats()
	assert stats.max_open_connections == 5
	holder.close()
}
