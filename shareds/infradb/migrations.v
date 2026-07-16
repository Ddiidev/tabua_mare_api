module infradb

import db.sqlite
import shareds.conf_env
import shareds.geohash

// apply_startup_migrations keeps SQLite schema ready for geospatial nearest-harbor queries.
// SQLite é sempre-on (dados de maré). PostgreSQL (auth/dash) tem migrações próprias em shareds.infradb_pg.
pub fn apply_startup_migrations() ! {
	env := conf_env.load_env()
	mut db := sqlite.connect(env.db_sqlite_path)!
	defer {
		db.close() or {}
	}
	// WAL mode allows concurrent reads while writing (essential with multiple containers)
	// busy_timeout makes SQLite wait instead of immediately failing when locked
	db.exec('PRAGMA journal_mode=WAL;') or {}
	db.exec('PRAGMA busy_timeout=5000;') or {}

	ensure_geo_hash_column(mut db)!
	ensure_geo_hash_indexes(mut db)!
	backfill_geo_hash(mut db)!
}

fn ensure_geo_hash_column(mut db sqlite.DB) ! {
	column_rows := db.exec("PRAGMA table_info('geo_location');")!
	mut has_geo_hash := false
	for row in column_rows {
		if row.vals.len > 1 && row.vals[1] == 'geo_hash' {
			has_geo_hash = true
			break
		}
	}

	if has_geo_hash {
		return
	}

	db.exec("ALTER TABLE geo_location ADD COLUMN geo_hash TEXT NOT NULL DEFAULT '';")!
}

fn ensure_geo_hash_indexes(mut db sqlite.DB) ! {
	db.exec('CREATE INDEX IF NOT EXISTS idx_geo_location_data_mare_id ON geo_location(data_mare_id);')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_data_mare_year_state ON data_mare(year, state);')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_geo_hash_p5 ON geo_location(substr(geo_hash, 1, 5));')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_geo_hash_p4 ON geo_location(substr(geo_hash, 1, 4));')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_geo_hash_p3 ON geo_location(substr(geo_hash, 1, 3));')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_geo_hash_p2 ON geo_location(substr(geo_hash, 1, 2));')!
	db.exec('CREATE INDEX IF NOT EXISTS idx_geo_hash_p1 ON geo_location(substr(geo_hash, 1, 1));')!
}

fn backfill_geo_hash(mut db sqlite.DB) ! {
	rows :=
		db.exec("SELECT id, CAST(lat AS REAL), CAST(lng AS REAL) FROM geo_location WHERE geo_hash = '' OR geo_hash IS NULL;")!
	for row in rows {
		if row.vals.len < 3 {
			continue
		}

		id := row.vals[0].int()
		if id <= 0 {
			continue
		}

		lat := row.vals[1].f64()
		lng := row.vals[2].f64()
		hash := geohash.encode(lat, lng, 5)

		db.exec("UPDATE geo_location SET geo_hash = '${hash}' WHERE id = ${id};")!
	}
}
