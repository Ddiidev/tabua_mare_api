module entities

@[table: 'rate_limit_counters']
pub struct RateLimitCounter {
pub mut:
	bucket      string @[sql_type: 'TEXT']
	window_kind string @[sql_type: 'TEXT']
	window_key  string @[sql_type: 'TEXT']
	count       int
}
