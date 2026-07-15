module entities

@[table: 'user_identities']
pub struct UserIdentity {
pub mut:
	id           int    @[primary; sql: serial]
	user_id      int
	provider     string @[sql_type: 'TEXT']
	provider_uid string @[sql_type: 'TEXT']
	email        string @[sql_type: 'TEXT']
	name         string @[sql_type: 'TEXT']
	avatar_url   string @[sql_type: 'TEXT']
	raw_json     string @[sql_type: 'TEXT']
	created_at   string @[sql_type: 'TIMESTAMP']
	updated_at   string @[sql_type: 'TIMESTAMP']
}
