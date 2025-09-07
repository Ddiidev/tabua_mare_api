module models

import entities

pub struct MonthData {
pub mut:
	month_name string
	month      int
	days       []DayData
}

pub fn (md MonthData) to_entity() entities.MonthData {
	return entities.MonthData{
		month_name: md.month_name
		month:      md.month
		days:       md.days.map(it.to_entity())
	}
}
