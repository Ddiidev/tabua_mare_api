module rate_limit

import pool
import db.pg
import time

// window_key_minute retorna a chave de janela de minuto (YYYYMMDDHHMM).
pub fn window_key_minute() string {
	now := time.now()
	return '${now.year}${now.month:02}${now.day:02}${now.hour:02}${now.minute:02}'
}

// window_key_month retorna a chave de janela de mes (YYYYMM).
pub fn window_key_month() string {
	now := time.now()
	return '${now.year}${now.month:02}'
}

// inc_and_check incrementa o contador da janela e retorna true se excedeu o limite.
// Limite 0 significa ilimitado (sempre false).
pub fn inc_and_check(mut pool_conn pool.ConnectionPool, bucket string, window_kind string, window_key string, limit int) !bool {
	if limit == 0 {
		inc(mut pool_conn, bucket, window_kind, window_key)!
		return false
	}

	conn := pool_conn.get()!
	mut db := conn as pg.DB
	defer {
		pool_conn.put(conn) or { println(err.msg()) }
	}

	db.exec_param_many('INSERT INTO rate_limit_counters (bucket, window_kind, window_key, count) VALUES (($1), ($2), ($3), 1) ON CONFLICT (bucket, window_kind, window_key) DO UPDATE SET count = rate_limit_counters.count + 1',
		[bucket, window_kind, window_key])!

	rows := db.exec_param_many('SELECT count FROM rate_limit_counters WHERE bucket = ($1) AND window_kind = ($2) AND window_key = ($3) LIMIT 1',
		[bucket, window_kind, window_key])!
	if rows.len == 0 {
		return false
	}
	if v := rows[0].vals[0] {
		return v.int() > limit
	}
	return false
}

// inc apenas incrementa o contador sem checar limite.
pub fn inc(mut pool_conn pool.ConnectionPool, bucket string, window_kind string, window_key string) ! {
	conn := pool_conn.get()!
	mut db := conn as pg.DB
	defer {
		pool_conn.put(conn) or { println(err.msg()) }
	}
	db.exec_param_many('INSERT INTO rate_limit_counters (bucket, window_kind, window_key, count) VALUES (($1), ($2), ($3), 1) ON CONFLICT (bucket, window_kind, window_key) DO UPDATE SET count = rate_limit_counters.count + 1',
		[bucket, window_kind, window_key])!
}