module auth

import db.pg
import repository.auth.dto
import crypto.rand
import encoding.base64

// find_by_key retorna a api_key ativa (nao revogada) pelo seu valor, ou erro se nao encontrar.
pub fn find_by_key(mut db pg.DB, key_value string) !dto.ApiKey {
	rows := db.exec_param('SELECT id, user_id, key_value, label, plan, revoked_at FROM api_keys WHERE key_value = ($1) LIMIT 1',
		key_value)!
	if rows.len == 0 {
		return error('api key nao encontrada')
	}
	r := rows[0]
	revoked := str_from_row(r, 5) != ''
	return dto.ApiKey{
		id:        int_from_row(r, 0)
		user_id:   int_from_row(r, 1)
		key_value: str_from_row(r, 2)
		label:     str_from_row(r, 3)
		plan:      str_from_row(r, 4)
		revoked:   revoked
	}
}

// issue cria uma nova api_key para o usuario com o plano informado.
pub fn issue(mut db pg.DB, user_id int, label string, plan string) !string {
	raw := rand.bytes(32) or { return error('falha ao gerar api key') }
	key_value := 'tm_' + base64.url_encode(raw)

	db.exec_param_many('INSERT INTO api_keys (user_id, key_value, label, plan) VALUES (($1), ($2), ($3), ($4))',
		[user_id.str(), key_value, label, plan])!

	return key_value
}

// list_by_user retorna as api_keys de um usuario.
pub fn list_by_user(mut db pg.DB, user_id int) ![]dto.ApiKey {
	rows := db.exec_param('SELECT id, user_id, key_value, label, plan, revoked_at FROM api_keys WHERE user_id = ($1) ORDER BY id ASC',
		user_id.str())!

	mut keys := []dto.ApiKey{}
	for r in rows {
		keys << dto.ApiKey{
			id:        int_from_row(r, 0)
			user_id:   int_from_row(r, 1)
			key_value: str_from_row(r, 2)
			label:     str_from_row(r, 3)
			plan:      str_from_row(r, 4)
			revoked:   str_from_row(r, 5) != ''
		}
	}
	return keys
}

// revoke marca uma api_key como revogada.
pub fn revoke(mut db pg.DB, user_id int, key_id int) ! {
	db.exec_param_many('UPDATE api_keys SET revoked_at = now() WHERE id = ($1) AND user_id = ($2)',
		[key_id.str(), user_id.str()])!
}
