module models

import entities

pub struct DayData {
pub mut:
	weekday_name string
	day          int
	hours        []HourData
}

pub fn (dd DayData) to_entity() entities.DayData {
	return entities.DayData{
		weekday_name: dd.weekday_name
		day:          dd.day
		hours:        dd.hours.map(it.to_entity())
	}
}
