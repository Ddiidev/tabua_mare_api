module entities

@[table: 'data_mare']
pub struct DataMare {
pub mut:
	id                          int @[primary; sql: serial]
	year                        int
	harbor_name                 string        @[sql_type: 'VARCHAR(255)']
	state                       string        @[sql_type: 'VARCHAR(2)']
	timezone                    string        @[sql_type: 'VARCHAR(20)']
	card                        string        @[sql_type: 'VARCHAR(20)']
	data_collection_institution string        @[sql_type: 'VARCHAR(10)']
	geo_location                []GeoLocation @[fkey: 'data_mare_id'; sql: '-']
	mean_level                  f32           @[sql_type: 'REAL']
	months                      []MonthData   @[fkey: 'data_mare_id'; sql: '-']
}
