module auth

import db.pg
import repository.auth.dto

// UpsertResult eh o resultado do upsert por provider.
pub struct UpsertResult {
pub:
	user_id    int
	email      string
	name       string
	avatar_url string
	plan       string
	provider   string
}

// upsert_by_provider cria ou atualiza um usuario a partir de uma identidade provider.
// Se (provider, provider_uid) existe, atualiza name/email/avatar e retorna o user.
// Se nao, cria user + user_identity e retorna.
pub fn upsert_by_provider(mut db pg.DB, provider string, provider_uid string, email string, name string, avatar_url string, raw_json string) !UpsertResult {
	// tenta buscar identidade existente
	rows := db.exec_param_many('SELECT user_id FROM user_identities WHERE provider = ($1) AND provider_uid = ($2) LIMIT 1',
		[provider, provider_uid])!

	if rows.len > 0 {
		// existe: atualiza identity e user
		user_id := int_from_row(rows[0], 0)
		db.exec_param_many('UPDATE user_identities SET email = ($1), name = ($2), avatar_url = ($3), raw_json = ($4), updated_at = now() WHERE provider = ($5) AND provider_uid = ($6)',
			[email, name, avatar_url, raw_json, provider, provider_uid])!
		db.exec_param_many('UPDATE users SET email = ($1), name = ($2), avatar_url = ($3), updated_at = now() WHERE id = ($4)',
			[email, name, avatar_url, user_id.str()])!

		user_rows := db.exec_param('SELECT email, name, avatar_url, plan FROM users WHERE id = ($1) LIMIT 1', user_id.str())!
		if user_rows.len == 0 {
			return error('usuario nao encontrado apos upsert')
		}
		return row_to_upsert(user_rows[0], user_id, provider)
	}

	// nao existe: cria user + identity
	db.exec_param_many('INSERT INTO users (email, name, avatar_url, plan) VALUES (($1), ($2), ($3), ($4)) RETURNING id',
		[email, name, avatar_url, 'free'])!
	// busca o id recem criado pelo email
	created := db.exec_param('SELECT id FROM users WHERE email = ($1) LIMIT 1', email)!
	if created.len == 0 {
		return error('falha ao criar usuario')
	}
	user_id := int_from_row(created[0], 0)
	db.exec_param_many('INSERT INTO user_identities (user_id, provider, provider_uid, email, name, avatar_url, raw_json) VALUES (($1), ($2), ($3), ($4), ($5), ($6), ($7))',
		[user_id.str(), provider, provider_uid, email, name, avatar_url, raw_json])!

	return UpsertResult{
		user_id:    user_id
		email:      email
		name:       name
		avatar_url: avatar_url
		plan:       'free'
		provider:   provider
	}
}

// set_stripe_customer_id atualiza o stripe_customer_id do usuario.
pub fn set_stripe_customer_id(mut db pg.DB, user_id int, customer_id string) ! {
	db.exec_param_many('UPDATE users SET stripe_customer_id = ($1), updated_at = now() WHERE id = ($2)',
		[customer_id, user_id.str()])!
}

// set_stripe_subscription_id atualiza o stripe_subscription_id do usuario.
pub fn set_stripe_subscription_id(mut db pg.DB, user_id int, subscription_id string) ! {
	db.exec_param_many('UPDATE users SET stripe_subscription_id = ($1), updated_at = now() WHERE id = ($2)',
		[subscription_id, user_id.str()])!
}

// update_plan atualiza o plano do usuario.
pub fn update_plan(mut db pg.DB, user_id int, plan string) ! {
	db.exec_param_many('UPDATE users SET plan = ($1), updated_at = now() WHERE id = ($2)',
		[plan, user_id.str()])!
}

// find_plan_by_id retorna apenas o plano do usuario.
pub fn find_plan_by_id(mut db pg.DB, user_id int) !string {
	rows := db.exec_param('SELECT plan FROM users WHERE id = ($1) LIMIT 1', user_id.str())!
	if rows.len == 0 {
		return error('usuario nao encontrado')
	}
	return str_from_row(rows[0], 0)
}

// find_by_id retorna um usuario pelo id.
pub fn find_by_id(mut db pg.DB, user_id int) !dto.User {
	rows := db.exec_param('SELECT id, email, name, avatar_url, plan, stripe_customer_id, stripe_subscription_id FROM users WHERE id = ($1) LIMIT 1', user_id.str())!
	if rows.len == 0 {
		return error('usuario nao encontrado')
	}
	r := rows[0]
	return dto.User{
		id:                     int_from_row(r, 0)
		email:                  str_from_row(r, 1)
		name:                   str_from_row(r, 2)
		avatar_url:             str_from_row(r, 3)
		plan:                   str_from_row(r, 4)
		stripe_customer_id:     str_from_row(r, 5)
		stripe_subscription_id: str_from_row(r, 6)
	}
}

fn int_from_row(r pg.Row, idx int) int {
	if idx >= r.vals.len {
		return 0
	}
	if v := r.vals[idx] {
		return v.int()
	}
	return 0
}

fn str_from_row(r pg.Row, idx int) string {
	if idx >= r.vals.len {
		return ''
	}
	if v := r.vals[idx] {
		return v
	}
	return ''
}

fn row_to_upsert(r pg.Row, user_id int, provider string) UpsertResult {
	return UpsertResult{
		user_id:    user_id
		email:      str_from_row(r, 0)
		name:       str_from_row(r, 1)
		avatar_url: str_from_row(r, 2)
		plan:       str_from_row(r, 3)
		provider:   provider
	}
}
