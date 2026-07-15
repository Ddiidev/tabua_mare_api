module entities

@[table: 'monthly_credits']
pub struct MonthlyCredit {
pub mut:
	bucket    string @[sql_type: 'TEXT']
	plan      string @[sql_type: 'TEXT']
	month_key string @[sql_type: 'TEXT']
	used      int
	lim       int
	remaining int
	reset_at  string @[sql_type: 'TIMESTAMP']
}
