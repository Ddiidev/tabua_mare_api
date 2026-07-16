module rate_limit

import db.pg

// CreditCheck eh o resultado da checagem de creditos mensais.
pub struct CreditCheck {
pub:
	exceeded  bool
	remaining int
	used      int
	lim       int
}

// credit_remaining e a regra comum para limites novos e planos alterados.
pub fn credit_remaining(lim int, used int) int {
	if lim == 0 {
		return -1
	}
	remaining := lim - used
	return if remaining > 0 { remaining } else { 0 }
}

// ensure_credit_row cria (se necessario) a linha de creditos do bucket+mes e retorna o estado atual.
// lim 0 significa ilimitado (remaining = -1).
pub fn ensure_credit_row(mut db pg.DB, bucket string, plan string, lim int) !CreditCheck {
	month_key := window_key_month()
	remaining_init := credit_remaining(lim, 0)
	db.exec_param_many("INSERT INTO monthly_credits (bucket, month_key, plan, used, lim, remaining, reset_at)
		VALUES (($1), ($2), ($3), 0, ($4), ($5), date_trunc('month', CURRENT_TIMESTAMP) + interval '1 month')
		ON CONFLICT (bucket, month_key) DO UPDATE SET
			plan = EXCLUDED.plan,
			lim = EXCLUDED.lim,
			remaining = CASE
				WHEN EXCLUDED.lim = 0 THEN -1
				ELSE GREATEST(EXCLUDED.lim - monthly_credits.used, 0)
			END,
			reset_at = EXCLUDED.reset_at", [
		bucket,
		month_key,
		plan,
		lim.str(),
		remaining_init.str(),
	])!

	rows := db.exec_param_many('SELECT used, lim, remaining FROM monthly_credits WHERE bucket = ($1) AND month_key = ($2) LIMIT 1', [
		bucket,
		month_key,
	])!
	if rows.len == 0 {
		return CreditCheck{
			exceeded:  false
			remaining: remaining_init
			used:      0
			lim:       lim
		}
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

// get_current_month_usage retorna o estado atual dos créditos mensais sem decrementar.
pub fn get_current_month_usage(mut db pg.DB, bucket string, default_lim int) !CreditCheck {
	month_key := window_key_month()
	rows := db.exec_param_many('SELECT used, lim, remaining FROM monthly_credits WHERE bucket = ($1) AND month_key = ($2) LIMIT 1', [
		bucket,
		month_key,
	])!
	if rows.len == 0 {
		return CreditCheck{
			exceeded:  false
			remaining: credit_remaining(default_lim, 0)
			used:      0
			lim:       default_lim
		}
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

// decrement consome 1 credito mensal atomicamente. Retorna true se excediu (sem credito).
// So decrementa used e remaining quando ainda ha credito (remaining > 0).
// Requests bloqueadas (remaining == 0) nao incrementam used.
// lim 0 (ilimitado) nunca excede; apenas conta used (chamado via inc, nao decrement).
pub fn decrement(mut db pg.DB, bucket string) !bool {
	month_key := window_key_month()
	res := db.exec_param_many('UPDATE monthly_credits SET used = used + 1, remaining = remaining - 1 WHERE bucket = ($1) AND month_key = ($2) AND remaining > 0 RETURNING lim, remaining', [
		bucket,
		month_key,
	])!
	if res.len == 0 {
		// nenhuma linha atualizada — verifica se e excedido (remaining <= 0)
		// ou se a linha nao existe (ensure_credit_row falhou)
		rows := db.exec_param_many('SELECT lim, remaining FROM monthly_credits WHERE bucket = ($1) AND month_key = ($2) LIMIT 1', [
			bucket,
			month_key,
		])!
		if rows.len == 0 {
			return error('monthly credit row ausente')
		}
		l := val_int(rows[0], 0)
		remaining := val_int(rows[0], 1)
		return l != 0 && remaining <= 0
	}
	// A linha foi atualizada: remaining == 0 e o ultimo credito ainda e valido.
	return false
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
