module habor_mare

import orm
import pool
$if using_sqlite ? {
	import db.sqlite as db_provider
} $else {
	import db.pg as db_provider
}
import entities
import shareds.types
import shareds.constants
import repository.habor_mare.dto

// list_harbor_name_by_states Lista os nomes dos portos por estado
pub fn list_harbor_name_by_states(mut pool_conn pool.ConnectionPool, state string) !types.ResultValues[dto.DTOHaborMareListHaborNameByState] {
	conn := pool_conn.get()!
	mut db := conn as db_provider.DB
	db.reset()!

	mut qb := orm.new_query[entities.DataMare](db)

	harbor_name := qb
		.where('year = ? && state = ?', constants.year, state)!
		.select('id', 'harbor_name', 'data_collection_institution', 'year')!
		.query()!
		.map(dto.DTOHaborMareListHaborNameByState{
			id:                          it.id
			year:                        it.year
			harbor_name:                 it.harbor_name
			data_collection_institution: it.data_collection_institution
		})
	pool_conn.put(conn) or {}

	return types.ResultValues{
		data:  harbor_name
		total: harbor_name.len
	}
}
