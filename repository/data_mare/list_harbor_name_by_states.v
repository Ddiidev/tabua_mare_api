module data_mare

import orm
import pool
import db.pg
import entities
import shareds.types
import shareds.constants
import repository.data_mare.dto

// list_harbor_name_by_states Lista os nomes dos portos por estado
pub fn list_harbor_name_by_states(mut pool_conn pool.ConnectionPool, state string) !types.ResultValues[dto.DTODataMareListHaborNameByState] {
	conn := pool_conn.get()!
	db := conn as pg.DB
	db.reset()!

	defer {
		pool_conn.put(conn) or {}
	}

	mut qb := orm.new_query[entities.DataMare](db)

	harbor_name := qb
		.where('year = ? && state = ?', constants.year, state)!
		.select('id', 'harbor_name', 'data_collection_institution', 'year')!
		.query()!

	return types.ResultValues{
		data:  harbor_name.map(dto.DTODataMareListHaborNameByState{
			id:                          it.id
			year:                        it.year
			harbor_name:                 it.harbor_name
			data_collection_institution: it.data_collection_institution
		})
		total: harbor_name.len
	}
}
