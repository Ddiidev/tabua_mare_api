module habor_mare

import orm
import pool
import db.pg
import arrays
import entities
import shareds.types
import shareds.constants

// list_States Lista apenas os estados
pub fn list_states(mut pool_conn pool.ConnectionPool) !types.ResultValues[string] {
	conn := pool_conn.get()!
	db := conn as pg.DB
	db.reset()!

	mut qb := orm.new_query[entities.DataMare](db)

	distinct_states := arrays.distinct(qb
		.select('state')!
		.where('year = ?', constants.year)!
		.query()!
		.map(it.state))

	pool_conn.put(conn) or {}

	return types.ResultValues[string]{
		data:  distinct_states
		total: distinct_states.len
	}
}
