module habor_mare

import orm
import pool
import time

$if using_sqlite ? {
	import db.sqlite as db_provider
} $else {
	import db.pg as db_provider
}
import entities
import shareds.types
import repository.habor_mare.dto

// get_harbor_by_ids Pega o porto por ids
pub fn get_harbor_by_ids(mut pool_conn pool.ConnectionPool, harbor_ids []string) !types.ResultValues[dto.DTOHaborMareGetHarborV2] {
	mut ids_ordered := harbor_ids.clone()
	ids_ordered.sort()

	conn := pool_conn.get()!
	db := conn as db_provider.DB
	defer {
		pool_conn.put(conn) or {
			println(err.msg())
		}
	}

	mut qb := orm.new_query[entities.DataMare](db)

	// harbors := []entities.DataMare{}
	year := time.now().year
	harbors := qb.where('year = ? && id_harbor_state IN ?', orm.Primitive(year), ids_ordered.map(orm.Primitive(it)))!.query()!
	ids := harbors.map(it.id)

	geo_location := sql db {
		select from entities.GeoLocation where data_mare_id in ids
	}!

	mut data_harbors := []dto.DTOHaborMareGetHarborV2{}
	for harbor in harbors {
		data_harbors << dto.DTOHaborMareGetHarborV2{
			id:                          harbor.id_harbor_state
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

	return types.ResultValues[dto.DTOHaborMareGetHarborV2]{
		data:  data_harbors
		total: data_harbors.len
	}
}

// get_harbor_by_ids Pega o porto por ids
@[deprecated: 'Ao invés deste use get_harbor_by_ids, isso porque get_harbor_by_ids_v1 busca por id do banco, o get_harbor_by_ids busca por id do estado']
@[deprecated_after: '2026-04-22']
pub fn get_harbor_by_ids_v1(mut pool_conn pool.ConnectionPool, ids []int) !types.ResultValues[dto.DTOHaborMareGetHarbor] {
	mut ids_ordered := ids.clone()
	ids_ordered.sort()

	conn := pool_conn.get()!
	db := conn as db_provider.DB
	defer {
		pool_conn.put(conn) or {
			println(err.msg())
		}
	}

	mut qb := orm.new_query[entities.DataMare](db)

	harbors := qb
		.where('id IN ?', orm.Primitive(ids.map(orm.Primitive(it))))!
		.query()!

	geo_location := sql db {
		select from entities.GeoLocation where data_mare_id in ids
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
				lng_direction: it.lng_direction
			})
		}
	}

	return types.ResultValues[dto.DTOHaborMareGetHarbor]{
		data:  data_harbors
		total: data_harbors.len
	}
}
