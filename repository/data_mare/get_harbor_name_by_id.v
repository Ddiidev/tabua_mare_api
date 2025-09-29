module data_mare

import orm
import pool
import db.pg
import entities
import shareds.types
import repository.data_mare.dto

// get_harbor_by_ids Pega o porto por ids
pub fn get_harbor_by_ids(mut pool_conn pool.ConnectionPool, ids []int) !types.ResultValues[dto.DTODataMareGetHarbor] {
	conn := pool_conn.get()!
	db := conn as pg.DB

	defer {
		db.close() or {}
		pool_conn.put(conn) or {}
	}

	mut qb := orm.new_query[entities.DataMare](db)

	harbors := qb
		.where('id IN ?', ids.map(orm.Primitive(it)))!
		.query()!

	geo_location := sql db {
		select from entities.GeoLocation where data_mare_id in ids
	}!

	return types.ResultValues[dto.DTODataMareGetHarbor]{
		data:  harbors.map(dto.DTODataMareGetHarbor{
			id:           it.id
			card:         it.card
			state:        it.state
			timezone:     it.timezone
			harbor_name:  it.harbor_name
			geo_location: geo_location.filter(it.data_mare_id == it.id).map(dto.GeoLocation{
				lat:           it.lat
				lng:           it.lng
				decimal_lat:   it.decimal_lat
				decimal_lng:   it.decimal_lng
				lat_direction: it.lat_direction
				lng_direction: it.lng_direction
			})
			mean_level:   it.mean_level
		})
		total: harbors.len
	}
}
