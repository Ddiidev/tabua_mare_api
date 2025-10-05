module habor_mare

import orm
import pool
import db.pg
import entities
import shareds.types
import repository.habor_mare.dto

// get_harbor_by_ids Pega o porto por ids
pub fn get_harbor_by_ids(mut pool_conn pool.ConnectionPool, ids []int) !types.ResultValues[dto.DTOHaborMareGetHarbor] {
	conn := pool_conn.get()!
	db := conn as pg.DB
	db.reset()!

	defer {
		pool_conn.put(conn) or {}
	}

	mut qb := orm.new_query[entities.DataMare](db)

	harbors := qb
		.where('id IN ?', ids.map(orm.Primitive(it)))!
		.query()!

	geo_location := sql db {
		select from entities.GeoLocation where data_mare_id in ids
	}!

	mut data_harbors := []dto.DTOHaborMareGetHarbor{}
	for harbor in harbors {
		data_harbors << dto.DTOHaborMareGetHarbor{
			id:                          harbor.id
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
				lng_direction: it.lng_direction
			})
		}
	}

	return types.ResultValues[dto.DTOHaborMareGetHarbor]{
		data:  data_harbors
		total: data_harbors.len
	}
}
