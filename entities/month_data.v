module entities

@[table: 'month_data']
pub struct MonthData {
pub mut:
	id           int @[primary; sql: serial]
	data_mare_id int
	month_name   string
	month        int
	days         []DayData @[fkey: 'month_data_id'; sql: '-']
}
