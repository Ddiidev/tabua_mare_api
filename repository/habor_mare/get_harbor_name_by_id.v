module habor_mare

import orm
import pool
import time
import entities
import benchmark
import shareds.types
import db.sqlite as db_provider
import repository.habor_mare.dto

// get_harbor_by_ids Pega o porto por ids
pub fn get_harbor_by_ids(mut pool_conn pool.ConnectionPool, harbor_ids []string) !types.ResultValues[dto.DTOHaborMareGetHarbor] {
	mut b := benchmark.start()
	mut ids_ordered := harbor_ids.clone()
	ids_ordered.sort()

	conn := pool_conn.get()!
	db := conn as db_provider.DB
	defer {
		pool_conn.put(conn) or { println(err.msg()) }
	}

	mut qb := orm.new_query[entities.DataMare](db)

	b.measure('config_init')

	// harbors := []entities.DataMare{}
	year := time.now().year
	harbors := qb.where('year = ? && id_harbor_state IN ?', orm.Primitive(year),
		ids_ordered.map(orm.Primitive(it)))!.query()!
	ids := harbors.map(it.id)

	b.measure('query to get harbors')

	geo_location := sql db {
		select from entities.GeoLocation where data_mare_id in ids
	}!

	b.measure('query to get geo_location')

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

	b.measure('query to get geo_location
	')
	return types.ResultValues[dto.DTOHaborMareGetHarbor]{
		data:  data_harbors
		total: data_harbors.len
	}
}
