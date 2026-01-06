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

// list_all_harbors lista todos os portos
pub fn list_all_harbors(mut pool_conn pool.ConnectionPool) !types.ResultValues[dto.DTOHaborMareGetHarbor] {
	conn := pool_conn.get()!
	db := conn as db_provider.DB

	mut qb := orm.new_query[entities.DataMare](db)

	harbors := qb.where('year = ?', time.now().year)!.query()!
	harbor_ids := harbors.map(it.id)

	geo_location := sql db {
		select from entities.GeoLocation where data_mare_id in harbor_ids
	}!

	mut data_harbors := []dto.DTOHaborMareGetHarbor{}
	for harbor in harbors {
		data_harbors << dto.DTOHaborMareGetHarbor{
			id:                          harbor.id
			harbor_id:                   harbor.id_harbor_state
			year:                        harbor.year
			card:                        harbor.card
			state:                       harbor.state
			timezone:                    harbor.timezone
			mean_level:                  harbor.mean_level
			harbor_name:                 harbor.harbor_name
			data_collection_institution: harbor.data_collection_institution
			geo_location:                geo_location.filter(it.data_mare_id == harbor.id).map(dto.GeoLocation{
				lat:           it.lat
				lng:           it.lng
				decimal_lat:   it.decimal_lat
				decimal_lng:   it.decimal_lng
				lat_direction: it.lat_direction
			})
		}
	}

	pool_conn.put(conn) or { dump(err) }

	return types.ResultValues[dto.DTOHaborMareGetHarbor]{
		data:  data_harbors
		total: data_harbors.len
	}
}

// list_all_harbors_by_state lista todos os portos de um estado específico
pub fn list_all_harbors_by_state(mut pool_conn pool.ConnectionPool, state string) ![]dto.DTOHaborMareGetHarbor {
	conn := pool_conn.get()!
	db := conn as db_provider.DB

	mut qb := orm.new_query[entities.DataMare](db)

	year := time.now().year
	harbors := qb.where('state = ? && year = ?', state, year)!.query()!
	data_mare_ids := harbors.map(it.id)

	geo_location := sql db {
		select from entities.GeoLocation where data_mare_id in data_mare_ids
	}!

	mut data_harbors := []dto.DTOHaborMareGetHarbor{}
	for harbor in harbors {
		data_harbors << dto.DTOHaborMareGetHarbor{
			id:                          harbor.id
			harbor_id:                   harbor.id_harbor_state
			year:                        harbor.year
			card:                        harbor.card
			state:                       harbor.state
			timezone:                    harbor.timezone
			mean_level:                  harbor.mean_level
			harbor_name:                 harbor.harbor_name
			data_collection_institution: harbor.data_collection_institution
			geo_location:                geo_location.filter(it.data_mare_id == harbor.id).map(dto.GeoLocation{
				lat:           it.lat
				lng:           it.lng
				decimal_lat:   it.decimal_lat
				decimal_lng:   it.decimal_lng
				lat_direction: it.lat_direction
			})
		}
	}

	pool_conn.put(conn) or { dump(err) }

	return data_harbors
}
