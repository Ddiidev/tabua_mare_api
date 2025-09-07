module entities

@[table: 'hour_data']
pub struct HourData {
pub mut:
	id          int @[primary; sql: serial]
	day_data_id int
	hour        string
	level       f32
}
