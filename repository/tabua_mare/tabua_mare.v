module tabua_mare

import orm
import pool

$if using_sqlite ? {
	import db.sqlite as db_provider
} $else {
	import db.pg as db_provider
}
import entities
import shareds.types
import repository.habor_mare
import repository.tabua_mare.dto

// get_tabua_mare_by_month_days Retorna os dados da tábua de maré de um determinado porto, mês e dias
pub fn get_tabua_mare_by_month_days(mut pool_conn pool.ConnectionPool, harbor_id int, month int, days []int) !types.ResultValues[dto.DTOTabuaMare] {
	conn := pool_conn.get()!
	db := conn as db_provider.DB

	mut qb_month := orm.new_query[entities.MonthData](db)

	mut harbor := habor_mare.get_harbor_by_ids(mut pool_conn, [
		harbor_id,
	])!

	mut month_data := qb_month
		.where('data_mare_id = ? && month = ?', harbor_id, month)!
		.query()!

	mut qb_month_days := orm.new_query[entities.DayData](db)
	mut qb_hours := orm.new_query[entities.HourData](db)

	mut days_data := qb_month_days
		.where('month_data_id = ? && day IN ?', month_data[0].id, days.map(orm.Primitive(it)))!
		.order(.asc, 'day')!
		.query()!

	mut hours_from_days := qb_hours
		.where('day_data_id IN ?', days_data.map(orm.Primitive(it.id)))!
		.query()!

	mut days_data_with_hours := []dto.DTODayData{}
	for curr_day in days_data {
		days_data_with_hours << dto.DTODayData{
			day:          curr_day.day
			weekday_name: curr_day.weekday_name
			hours:        hours_from_days.filter(it.day_data_id == curr_day.id).map(dto.DTOHourData{
				hour:  it.hour
				level: it.level
			})
		}
	}

	pool_conn.put(conn) or { dump(err) }

	result := dto.DTOTabuaMare{
		year:                        harbor.data[0].year
		card:                        harbor.data[0].card
		harbor_name:                 harbor.data[0].harbor_name
		state:                       harbor.data[0].state
		timezone:                    harbor.data[0].timezone
		data_collection_institution: harbor.data[0].data_collection_institution
		mean_level:                  harbor.data[0].mean_level
		months:                      [
			dto.DTOMonthData{
				month:      month_data[0].month
				month_name: month_data[0].month_name
				days:       days_data_with_hours
			},
		]
	}

	return types.ResultValues[dto.DTOTabuaMare]{
		data:  [result]
		total: 1
	}
}
