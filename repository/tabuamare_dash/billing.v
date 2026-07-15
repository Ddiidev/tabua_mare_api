module tabuamare_dash

import db.pg
import repository.auth.dto

// PlanStatus representa o status de plano/cobranca de um usuario.
pub struct PlanStatus {
pub:
	user_id  int
	plan     string
	api_keys []dto.ApiKey
}

// get_plan_status retorna o plano do usuario e suas api_keys ativas.
pub fn get_plan_status(mut db pg.DB, user_id int) !PlanStatus {
	rows := db.exec_param('SELECT plan FROM users WHERE id = ($1) LIMIT 1', user_id.str())!
	plan := if rows.len > 0 {
		if v := rows[0].vals[0] { v } else { 'free' }
	} else {
		'free'
	}

	key_rows := db.exec_param('SELECT id, user_id, key_value, label, plan, revoked_at FROM api_keys WHERE user_id = ($1) ORDER BY id ASC',
		user_id.str())!

	mut keys := []dto.ApiKey{}
	for r in key_rows {
		keys << dto.ApiKey{
			id:        val_int(r, 0)
			user_id:   val_int(r, 1)
			key_value: val_str(r, 2)
			label:     val_str(r, 3)
			plan:      val_str(r, 4)
			revoked:   val_str(r, 5) != ''
		}
	}

	return PlanStatus{
		user_id:  user_id
		plan:     plan
		api_keys: keys
	}
}
