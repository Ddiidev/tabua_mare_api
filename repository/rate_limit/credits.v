module rate_limit

import pool
import db.pg
import time

// CreditCheck eh o resultado da checagem de creditos mensais.
pub struct CreditCheck {
pub:
	exceeded  bool
	remaining int
	used      int
	lim       int
}

// ensure_credit_row cria (se necessario) a linha de creditos do bucket+mes e retorna o estado atual.
// lim 0 significa ilimitado (remaining = -1).
pub fn ensure_credit_row(mut pool_conn pool.ConnectionPool, bucket string, plan string, lim int) !CreditCheck {
	conn := pool_conn.get()!
	mut db := conn as pg.DB
	defer {
		pool_conn.put(conn) or { println(err.msg()) }
	}

	month_key := window_key_month()
	reset_at := time.now().add(30 * 24 * time.hour).format_ss()

	remaining_init := if lim == 0 { -1 } else { lim }
	db.exec_param_many('INSERT INTO monthly_credits (bucket, month_key, plan, used, lim, remaining, reset_at) VALUES (($1), ($2), ($3), 0, ($4), ($5), ($6)) ON CONFLICT (bucket, month_key) DO NOTHING',
		[bucket, month_key, plan, lim.str(), remaining_init.str(), reset_at])!

	rows := db.exec_param_many('SELECT used, lim, remaining FROM monthly_credits WHERE bucket = ($1) AND month_key = ($2) LIMIT 1',
		[bucket, month_key])!
	if rows.len == 0 {
		return CreditCheck{exceeded: false, remaining: remaining_init, used: 0, lim: lim}
	}
	r := rows[0]
	used := val_int(r, 0)
	l := val_int(r, 1)
	remaining := val_int(r, 2)
	return CreditCheck{
		exceeded:  l != 0 && remaining == 0
		remaining: remaining
		used:      used
		lim:       l
	}
}

// decrement consome 1 credito mensal atomicamente. Retorna true se excedeu (sem credito).
// lim 0 (ilimitado) nunca excede; apenas conta used.
pub fn decrement(mut pool_conn pool.ConnectionPool, bucket string) !bool {
	conn := pool_conn.get()!
	mut db := conn as pg.DB
	defer {
		pool_conn.put(conn) or { println(err.msg()) }
	}

	month_key := window_key_month()
	res := db.exec_param_many('UPDATE monthly_credits SET used = used + 1, remaining = CASE WHEN lim = 0 THEN remaining WHEN remaining > 0 THEN remaining - 1 ELSE 0 END WHERE bucket = ($1) AND month_key = ($2) RETURNING lim, remaining',
		[bucket, month_key])!
	if res.len == 0 {
		return false
	}
	l := val_int(res[0], 0)
	remaining := val_int(res[0], 1)
	return l != 0 && remaining == 0
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