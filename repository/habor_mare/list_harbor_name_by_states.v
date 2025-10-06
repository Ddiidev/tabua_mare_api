module habor_mare

import orm
import pool
import db.pg
import cache
import entities
import shareds.types
import shareds.constants
import repository.habor_mare.dto

// list_harbor_name_by_states Lista os nomes dos portos por estado
pub fn list_harbor_name_by_states(shared ctx_cache cache.Cache, mut pool_conn pool.ConnectionPool, state string) !types.ResultValues[dto.DTOHaborMareListHaborNameByState] {
	harbor_name := lock ctx_cache {
		list_harbor_name_by_states_cache := ctx_cache.get('list_harbor_name_by_states_${state}')

		if list_harbor_name_by_states_cache != none {
			if list_harbor_name_by_states_cache is []dto.DTOHaborMareListHaborNameByState {
				return types.ResultValues[dto.DTOHaborMareListHaborNameByState]{
					data:  list_harbor_name_by_states_cache
					total: list_harbor_name_by_states_cache.len
				}
			}
		}

		conn := pool_conn.get()!
		db := conn as pg.DB
		db.reset()!

		mut qb := orm.new_query[entities.DataMare](db)

		harbor_name := qb
			.where('year = ? && state = ?', constants.year, state)!
			.select('id', 'harbor_name', 'data_collection_institution', 'year')!
			.query()!
		pool_conn.put(conn) or {}

		harbor_name.map(dto.DTOHaborMareListHaborNameByState{
			id:                          it.id
			year:                        it.year
			harbor_name:                 it.harbor_name
			data_collection_institution: it.data_collection_institution
		})
	}

	go fn [shared ctx_cache, harbor_name, state] () {
		lock ctx_cache {
			ctx_cache.set('list_harbor_name_by_states_${state}', harbor_name)
		}
	}()

	return types.ResultValues{
		data:  harbor_name
		total: harbor_name.len
	}
}
