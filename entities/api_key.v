module entities

@[table: 'api_keys']
pub struct ApiKey {
pub mut:
	id         int     @[primary; sql: serial]
	user_id    int
	key_value  string  @[sql_type: 'TEXT']
	label      string  @[sql_type: 'TEXT']
	plan       string  @[sql_type: 'TEXT']
	created_at string  @[sql_type: 'TIMESTAMP']
	revoked_at ?string @[sql_type: 'TIMESTAMP'; null]
}
