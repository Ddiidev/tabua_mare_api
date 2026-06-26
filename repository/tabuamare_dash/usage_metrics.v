module tabuamare_dash

import pool
import db.pg

// UsageSummary resume o uso de um bucket (ip ou api_key) no mes corrente.
pub struct UsageSummary {
pub:
	bucket    string
	used      int
	lim       int
	remaining int
	plan      string
}

// get_usage_month retorna o resumo de uso do bucket no mes corrente.
pub fn get_usage_month(mut pool_conn pool.ConnectionPool, bucket string) !UsageSummary {
	conn := pool_conn.get()!
	mut db := conn as pg.DB
	defer {
		pool_conn.put(conn) or { println(err.msg()) }
	}

	month_key := current_month_key()
	rows := db.exec_param_many('SELECT bucket, used, lim, remaining, plan FROM monthly_credits WHERE bucket = ($1) AND month_key = ($2) LIMIT 1',
		[bucket, month_key])!
	if rows.len == 0 {
		return UsageSummary{
			bucket:    bucket
			used:      0
			lim:       0
			remaining: 0
			plan:      'free'
		}
	}
	r := rows[0]
	return UsageSummary{
		bucket:    val_str(r, 0)
		used:      val_int(r, 1)
		lim:       val_int(r, 2)
		remaining: val_int(r, 3)
		plan:      val_str(r, 4)
	}
}

fn current_month_key() string {
	// reusa a logica de janela de mes do repository.rate_limit via SQL
	rows := db.exec('SELECT to_char(now(), \'YYYYMM\')') or { return '' }
	if rows.len == 0 || rows[0].vals.len == 0 {
		return ''
	}
	if v := rows[0].vals[0] {
		return v
	}
	return ''
}

fn val_int(r pg.Row, idx int) int {
	if idx >= r.vals.len {
		return 0
	}
	if v := r.vals[idx] {
		return v.int()
	}
	return 0
}

fn val_str(r pg.Row, idx int) string {
	if idx >= r.vals.len {
		return ''
	}
	if v := r.vals[idx] {
		return v
	}
	return ''
}