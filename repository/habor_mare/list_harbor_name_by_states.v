module habor_mare

import orm
import pool

$if using_sqlite ? {
	import db.sqlite as db_provider
} $else {
	import db.pg as db_provider
}
import time
import entities
import shareds.types
import repository.habor_mare.dto

// list_harbor_name_by_states Lista os nomes dos portos por estado
pub fn list_harbor_name_by_states(mut pool_conn pool.ConnectionPool, state string) !types.ResultValues[dto.DTOHaborMareListHaborNameByState] {
	conn := pool_conn.get()!
	mut db := conn as db_provider.DB
	defer {
		pool_conn.put(conn) or {
			println(err.msg())
		}
	}
	
	year := time.now().year

	mut qb := orm.new_query[entities.DataMare](db)

	harbor_name := qb
		.where('year = ? && state = ?', year, state)!
		.select('id_harbor_state', 'harbor_name', 'data_collection_institution', 'year')!
		.query()!
		.map(dto.DTOHaborMareListHaborNameByState{
			id:                          it.id_harbor_state
			year:                        it.year
			harbor_name:                 it.harbor_name
			data_collection_institution: it.data_collection_institution
		})

	return types.ResultValues{
		data:  harbor_name
		total: harbor_name.len
	}
}

// list_harbor_name_by_states_v1 Lista os nomes dos portos por estado (V1 - retorna ID do banco)
pub fn list_harbor_name_by_states_v1(mut pool_conn pool.ConnectionPool, state string) !types.ResultValues[dto.DTOHaborMareListHaborNameByStateV1] {
	conn := pool_conn.get()!
	mut db := conn as db_provider.DB
	defer {
		pool_conn.put(conn) or {
			println(err.msg())
		}
	}
	year := time.now().year

	mut qb := orm.new_query[entities.DataMare](db)

	harbor_name := qb
		.where('year = ? && state = ?', year, state)!
		.select('id', 'harbor_name', 'data_collection_institution', 'year')!
		.query()!
		.map(dto.DTOHaborMareListHaborNameByStateV1{
			id:                          it.id
			year:                        it.year
			harbor_name:                 it.harbor_name
			data_collection_institution: it.data_collection_institution
		})

	return types.ResultValues{
		data:  harbor_name
		total: harbor_name.len
	}
}
