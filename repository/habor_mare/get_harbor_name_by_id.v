module habor_mare

import orm
import pool
import time
import entities
import shareds.types
import db.sqlite as db_provider
import repository.habor_mare.dto

// get_harbor_by_ids Pega o porto por ids
pub fn get_harbor_by_ids(mut pool_conn pool.ConnectionPool, harbor_ids []string) !types.ResultValues[dto.DTOHaborMareGetHarbor] {
	mut ids_ordered := harbor_ids.clone()
	ids_ordered.sort()

	conn := pool_conn.get()!
	db := conn as db_provider.DB
	defer {
		pool_conn.put(conn) or { println(err.msg()) }
	}

	mut qb := orm.new_query[entities.DataMare](db)

	year := time.now().year
	harbors := qb.where('year = ? && id_harbor_state IN ?', year, ids_ordered.map(it))!.select('id_harbor_state',
		'year', 'card', 'state', 'timezone', 'mean_level', 'harbor_name',
		'data_collection_institution')!.query()!
	dump(harbors)
	ids := harbors.map(it.id)

	geo_location := sql db {
		select from entities.GeoLocation where data_mare_id in ids
	}!

	mut data_harbors := []dto.DTOHaborMareGetHarbor{}
	for harbor in harbors {
		filtered_geo := geo_location.filter(it.data_mare_id == harbor.id)
		data_harbors << dto.DTOHaborMareGetHarbor{
			id:                          harbor.id_harbor_state
			year:                        harbor.year
			card:                        harbor.card
			state:                       harbor.state
			timezone:                    harbor.timezone
			mean_level:                  harbor.mean_level
			harbor_name:                 harbor.harbor_name
			data_collection_institution: harbor.data_collection_institution
			geo_location:                filtered_geo.map(dto.GeoLocation{
				lat:           it.lat
				lng:           it.lng
				decimal_lat:   it.decimal_lat
				decimal_lng:   it.decimal_lng
				lat_direction: it.lat_direction
				lng_direction: it.lng_direction
			})
		}
	}

	return types.ResultValues[dto.DTOHaborMareGetHarbor]{
		data:  data_harbors
		total: data_harbors.len
	}
}

// get_harbor_by_ids Pega o porto por ids
pub fn get_harbor_by_ids_only_id(mut pool_conn pool.ConnectionPool, harbor_ids []string) !string {
	mut ids_ordered := harbor_ids.clone()
	ids_ordered.sort()

	conn := pool_conn.get()!
	db := conn as db_provider.DB
	defer {
		pool_conn.put(conn) or { println(err.msg()) }
	}

	mut qb := orm.new_query[entities.DataMare](db)

	year := time.now().year
	harbors := qb.where('year = ? && id_harbor_state IN ?', year, ids_ordered.map(it))!
		.select('id_harbor_state')!
		.query()!

	dump(harbors)
	return harbors[0] or { return error('Não foi encontrado um porto perto das coordenadas') }.id_harbor_state
}
