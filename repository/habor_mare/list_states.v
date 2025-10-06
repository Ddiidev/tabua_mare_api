module habor_mare

import orm
import pool
import db.pg
import cache
import arrays
import entities
import shareds.types
import shareds.constants

// list_States Lista apenas os estados
pub fn list_states(shared ctx_cache cache.Cache, mut pool_conn pool.ConnectionPool) !types.ResultValues[string] {
	distinct_states := lock ctx_cache {
		states_cache := ctx_cache.get('states')
		if states_cache != none {
			println('Tem cache')
			if states_cache is []string {
				return types.ResultValues[string]{
					data:  states_cache
					total: states_cache.len
				}
			}
		}

		conn := pool_conn.get()!
		db := conn as pg.DB
		db.reset()!

		mut qb := orm.new_query[entities.DataMare](db)

		data := arrays.distinct(qb
			.select('state')!
			.where('year = ?', constants.year)!
			.query()!
			.map(it.state))

		pool_conn.put(conn) or {}

		data
	}

	go fn [shared ctx_cache, distinct_states] () {
		lock ctx_cache {
			ctx_cache.set('states', distinct_states)
		}
	}()

	return types.ResultValues[string]{
		data:  distinct_states
		total: distinct_states.len
	}
}
