module dto

// HourData represents the tide level for a specific hour.
pub struct DTOHourData {
pub mut:
	hour  string
	level f32
}

// DayData contains the tide data for all hours of a specific day.
pub struct DTODayData {
pub mut:
	weekday_name string
	day          int
	hours        []DTOHourData
}

// MonthData contains the tide data for all days of a specific month.
pub struct DTOMonthData {
pub mut:
	month_name string
	month      int
	days       []DTODayData
}

// TabuaMare is the main DTO that holds the complete tide table for a specific harbor and year.
pub struct DTOTabuaMare {
pub mut:
	id                          string
	year                        int
	harbor_name                 string
	state                       string
	timezone                    string
	card                        string
	data_collection_institution string
	mean_level                  f32
	months                      []DTOMonthData
}

// DTOTabuaMareV1 is the main DTO for V1 that holds the complete tide table for a specific harbor and year.
pub struct DTOTabuaMareV1 {
pub mut:
	id                          int
	id_harbor_state             string
	year                        int
	harbor_name                 string
	state                       string
	timezone                    string
	card                        string
	data_collection_institution string
	mean_level                  f32
	months                      []DTOMonthData
}
