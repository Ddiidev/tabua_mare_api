import shareds.infradb
import repository.habor_mare

fn test_harbor_batch_preserves_each_harbors_own_locations() ! {
	mut pool_conn := infradb.new()!
	defer {
		pool_conn.close()
	}
	first := habor_mare.get_harbor_by_ids(mut pool_conn, ['pb01'])!
	second := habor_mare.get_harbor_by_ids(mut pool_conn, ['pe01'])!
	assert first.total == 1
	assert second.total == 1
	assert first.data[0].geo_location.len > 0
	assert second.data[0].geo_location.len > 0
	assert first.data[0].geo_location != second.data[0].geo_location

	batch := habor_mare.get_harbor_by_ids(mut pool_conn, ['pb01', 'pe01'])!
	assert batch.total == 2
	for expected in [first.data[0], second.data[0]] {
		matches := batch.data.filter(it.id == expected.id)
		assert matches.len == 1
		assert matches[0].geo_location == expected.geo_location
	}
}
