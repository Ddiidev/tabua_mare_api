import shareds.health
import shareds.infradb

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

fn test_sqlite_health_requires_a_working_pool() ! {
	mut pool_conn := infradb.new()!
	assert infradb.sqlite_is_healthy(mut pool_conn)

	pool_conn.close()
	assert !infradb.sqlite_is_healthy(mut pool_conn)
}
