module tabua_mare

import orm
import time
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
pub fn get_tabua_mare_by_month_days(mut pool_conn pool.ConnectionPool, harbor_id string, month int, days []int) !types.ResultValues[dto.DTOTabuaMare] {
	conn := pool_conn.get()!
	db := conn as db_provider.DB
	defer {
		pool_conn.put(conn) or {
			println(err.msg())
		}
	}

	mut qb_month := orm.new_query[entities.MonthData](db)
	mut qb_harbor := orm.new_query[entities.DataMare](db)

	year := time.now().year
	harbor := qb_harbor
		.where('id_harbor_state = ? && year = ?', harbor_id, year)!
		.query()!

	if harbor.len == 0 {
		return error('Nenhum dado de porto encontrado para o ID especificado')
	}

	mut month_data := qb_month
		.where('data_mare_id = ? && month = ?', harbor[0].id, month)!
		.query()!

	mut qb_month_days := orm.new_query[entities.DayData](db)
	mut qb_hours := orm.new_query[entities.HourData](db)

	if month_data.len == 0 {
		return error('Nenhum dado mensal encontrado para o porto e mês especificados')
	}

	mut days_data := qb_month_days
		.where('month_data_id = ? && day IN ?', month_data[0].id, days.map(orm.Primitive(it)))!
		.order(.asc, 'day')!
		.query()!

	mut hours_from_days := qb_hours
		.where('day_data_id IN ?', orm.Primitive(days_data.map(orm.Primitive(it.id))))!
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

	result := dto.DTOTabuaMare{
		id:                          harbor[0].id_harbor_state
		year:                        harbor[0].year
		card:                        harbor[0].card
		harbor_name:                 harbor[0].harbor_name
		state:                       harbor[0].state
		timezone:                    harbor[0].timezone
		data_collection_institution: harbor[0].data_collection_institution
		mean_level:                  harbor[0].mean_level
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

// get_tabua_mare_by_month_days Retorna os dados da tábua de maré de um determinado porto, mês e dias
@[deprecated: 'Use get_tabua_mare_by_month_days ao invés de get_tabua_mare_by_month_days_v1, isso porque get_tabua_mare_by_month_days_v1 busca por id do banco, o get_tabua_mare_by_month_days busca por id do estado']
@[deprecated_after: '2026-02-22']
pub fn get_tabua_mare_by_month_days_v1(mut pool_conn pool.ConnectionPool, harbor_id int, month int, days []int) !types.ResultValues[dto.DTOTabuaMareV1] {
	conn := pool_conn.get()!
	db := conn as db_provider.DB
	defer {
		pool_conn.put(conn) or {
			println(err.msg())
		}
	}

	mut qb_month := orm.new_query[entities.MonthData](db)

	mut harbor := habor_mare.get_harbor_by_ids_v1(mut pool_conn, [
		harbor_id,
	])!

	mut month_data := qb_month
		.where('data_mare_id = ? && month = ?', harbor_id, month)!
		.query()!

	mut qb_month_days := orm.new_query[entities.DayData](db)
	mut qb_hours := orm.new_query[entities.HourData](db)

	if month_data.len == 0 {
		return error('Nenhum dado mensal encontrado para o porto e mês especificados')
	}

	mut days_data := qb_month_days
		.where('month_data_id = ? && day IN ?', month_data[0].id, days.map(orm.Primitive(it)))!
		.order(.asc, 'day')!
		.query()!

	mut hours_from_days := qb_hours
		.where('day_data_id IN ?', orm.Primitive(days_data.map(orm.Primitive(it.id))))!
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

	if harbor.data.len == 0 {
		return error('Nenhum dado de porto encontrado para o ID especificado')
	}

	result := dto.DTOTabuaMareV1{
		id:                          harbor.data[0].id
		id_harbor_state:             harbor.data[0].harbor_id
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

	return types.ResultValues[dto.DTOTabuaMareV1]{
		data:  [result]
		total: 1
	}
}
