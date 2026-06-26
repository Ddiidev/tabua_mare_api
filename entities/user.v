module entities

@[table: 'users']
pub struct User {
pub mut:
	id         int    @[primary; sql: serial]
	email      string @[sql_type: 'TEXT']
	name       string @[sql_type: 'TEXT']
	avatar_url string @[sql_type: 'TEXT']
	plan       string @[sql_type: 'TEXT']
	created_at string @[sql_type: 'TIMESTAMP']
	updated_at string @[sql_type: 'TIMESTAMP']
}
