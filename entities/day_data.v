module entities

@[table: 'day_data']
pub struct DayData {
pub mut:
	id            int @[primary; sql: serial]
	month_data_id int
	weekday_name  string
	day           int
	hours         []HourData @[fkey: 'day_data_id'; sql: '-']
}
