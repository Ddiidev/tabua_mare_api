module habor_mare

import math
import pool
import repository.habor_mare.dto

$if using_sqlite ? {
	import db.sqlite as db_provider
	import shareds.geohash
	import time
}

const earth_radius_km = 6371.0
const geohash_precisions = [5, 4, 3, 2, 1]

struct NearestHarborMatch {
	id              int
	harbor_state_id string
}

// distance calculates the distance in km between two geographic coordinates.
fn distance(lat1 f64, lon1 f64, lat2 f64, lon2 f64) f64 {
	d_lat := (lat2 - lat1) * (math.pi / 180.0)
	d_lon := (lon2 - lon1) * (math.pi / 180.0)

	a := math.pow(math.sin(d_lat / 2), 2) +
		math.cos(lat1 * (math.pi / 180.0)) * math.cos(lat2 * (math.pi / 180.0)) * math.pow(math.sin(d_lon / 2), 2)
	c := 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

	return earth_radius_km * c
}

fn normalize_state_code(state string) !string {
	normalized := state.to_lower().trim_space()
	if normalized.len != 2 {
		return error('É necessário informar o estado corretamente.')
	}

	for char_code in normalized.bytes() {
		if char_code < `a` || char_code > `z` {
			return error('É necessário informar o estado corretamente.')
		}
	}

	return normalized
}

fn find_nearest_harbor_match_in_memory(mut pool_conn pool.ConnectionPool, lat f64, lng f64) !NearestHarborMatch {
	all_harbors := list_all_harbors(mut pool_conn)!
	if all_harbors.total == 0 {
		return error('No harbors found in the database.')
	}

	mut nearest_match := NearestHarborMatch{}
	mut shortest_distance := -1.0

	for harbor in all_harbors.data {
		if harbor.geo_location.len < 1 {
			continue
		}

		harbor_lat := harbor.geo_location[0].lat.f64()
		harbor_lng := harbor.geo_location[0].lng.f64()
		current_distance := distance(lat, lng, harbor_lat, harbor_lng)

		if shortest_distance == -1.0 || current_distance < shortest_distance {
			shortest_distance = current_distance
			nearest_match = NearestHarborMatch{
				id:              harbor.id
				harbor_state_id: harbor.harbor_id
			}
		}
	}

	if shortest_distance == -1.0 {
		return error('Could not find a nearest harbor with valid coordinates.')
	}

	return nearest_match
}

fn find_nearest_harbor_match_within_same_state_in_memory(mut pool_conn pool.ConnectionPool, lat f64, lng f64, state string) !NearestHarborMatch {
	all_harbors := list_all_harbors_by_state(mut pool_conn, state)!
	if all_harbors.len == 0 {
		return error('No harbors found in the database.')
	}

	mut nearest_match := NearestHarborMatch{}
	mut shortest_distance := -1.0

	for harbor in all_harbors {
		if harbor.geo_location.len < 1 || harbor.state != state {
			continue
		}

		harbor_lat := harbor.geo_location[0].lat.f64()
		harbor_lng := harbor.geo_location[0].lng.f64()
		current_distance := distance(lat, lng, harbor_lat, harbor_lng)

		if shortest_distance == -1.0 || current_distance < shortest_distance {
			shortest_distance = current_distance
			nearest_match = NearestHarborMatch{
				id:              harbor.id
				harbor_state_id: harbor.harbor_id
			}
		}
	}

	if shortest_distance == -1.0 {
		return error('Nenhum porto encontrado no estado correspondente às coordenadas.')
	}

	return nearest_match
}

fn find_nearest_harbor_match(mut pool_conn pool.ConnectionPool, lat f64, lng f64) !NearestHarborMatch {
	$if using_sqlite ? {
		return find_nearest_harbor_match_sqlite(mut pool_conn, lat, lng, '')
	} $else {
		return find_nearest_harbor_match_in_memory(mut pool_conn, lat, lng)
	}
}

fn find_nearest_harbor_match_within_same_state(mut pool_conn pool.ConnectionPool, lat f64, lng f64, state string) !NearestHarborMatch {
	normalized_state := normalize_state_code(state)!
	$if using_sqlite ? {
		return find_nearest_harbor_match_sqlite(mut pool_conn, lat, lng, normalized_state)
	} $else {
		return find_nearest_harbor_match_within_same_state_in_memory(mut pool_conn, lat, lng,
			normalized_state)
	}
}

// find_nearest_harbor_id retorna o ID do porto mais próximo sem filtro de estado.
pub fn find_nearest_harbor_id(mut pool_conn pool.ConnectionPool, lat f64, lng f64) !string {
	nearest_match := find_nearest_harbor_match(mut pool_conn, lat, lng)!
	return nearest_match.harbor_state_id
}

// find_nearest_harbor_id_within_same_state retorna o ID do porto mais próximo dentro de um estado.
pub fn find_nearest_harbor_id_within_same_state(mut pool_conn pool.ConnectionPool, lat f64, lng f64, state string) !string {
	nearest_match := find_nearest_harbor_match_within_same_state(mut pool_conn, lat, lng, state)!
	return nearest_match.harbor_state_id
}

// find_nearest_harbor encontra o porto mais próximo da coordenada informada.
pub fn find_nearest_harbor(mut pool_conn pool.ConnectionPool, lat f64, lng f64) !dto.DTOHaborMareGetHarbor {
	nearest_match := find_nearest_harbor_match(mut pool_conn, lat, lng)!
	result := get_harbor_by_ids_v1(mut pool_conn, [nearest_match.id])!
	if result.total == 0 {
		return error('Could not find a nearest harbor with valid coordinates.')
	}

	return result.data[0]
}

// find_nearest_harbor_within_same_state encontra o porto mais próximo dentro do mesmo estado da coordenada informada.
pub fn find_nearest_harbor_within_same_state(mut pool_conn pool.ConnectionPool, lat f64, lng f64, state string) !dto.DTOHaborMareGetHarbor {
	nearest_match := find_nearest_harbor_match_within_same_state(mut pool_conn, lat, lng, state)!
	result := get_harbor_by_ids_v1(mut pool_conn, [nearest_match.id])!
	if result.total == 0 {
		return error('Nenhum porto encontrado no estado correspondente às coordenadas.')
	}
	return result.data[0]
}

// find_nearest_harbor_v2 wrapper para retornar DTO v2
pub fn find_nearest_harbor_v2(mut pool_conn pool.ConnectionPool, lat f64, lng f64) !dto.DTOHaborMareGetHarborV2 {
	harbor := find_nearest_harbor(mut pool_conn, lat, lng)!
	return dto.DTOHaborMareGetHarborV2{
		id:                          harbor.harbor_id
		year:                        harbor.year
		harbor_name:                 harbor.harbor_name
		state:                       harbor.state
		timezone:                    harbor.timezone
		card:                        harbor.card
		geo_location:                harbor.geo_location
		data_collection_institution: harbor.data_collection_institution
		mean_level:                  harbor.mean_level
	}
}

$if using_sqlite ? {
fn haversine_order_expr(lat f64, lng f64) string {
	return '((SIN(((CAST(g.lat AS REAL) - ${lat}) * 0.017453292519943295) / 2.0) * SIN(((CAST(g.lat AS REAL) - ${lat}) * 0.017453292519943295) / 2.0)) + (COS(${lat} * 0.017453292519943295) * COS(CAST(g.lat AS REAL) * 0.017453292519943295) * SIN(((CAST(g.lng AS REAL) - ${lng}) * 0.017453292519943295) / 2.0) * SIN(((CAST(g.lng AS REAL) - ${lng}) * 0.017453292519943295) / 2.0)))'
}

fn geohash_prefixes_for_query(lat f64, lng f64, precision int) []string {
	hash := geohash.encode(lat, lng, precision)
	neighbor_hashes := geohash.neighbors(hash)
	mut seen := map[string]bool{}
	mut prefixes := []string{}

	for item in neighbor_hashes {
		if item.len < precision {
			continue
		}
		prefix := item[..precision]
		if seen[prefix] {
			continue
		}
		seen[prefix] = true
		prefixes << prefix
	}

	return prefixes
}

fn query_nearest_harbor_match(db db_provider.DB, query string) !NearestHarborMatch {
	rows := db.exec(query)!
	if rows.len == 0 || rows[0].vals.len < 2 {
		return error('Nenhum porto encontrado perto das coordenadas fornecidas.')
	}

	nearest_match := NearestHarborMatch{
		id:              rows[0].vals[0].int()
		harbor_state_id: rows[0].vals[1]
	}
	if nearest_match.id <= 0 || nearest_match.harbor_state_id == '' {
		return error('Nenhum porto encontrado perto das coordenadas fornecidas.')
	}
	return nearest_match
}

fn try_find_nearest_harbor_match_by_geohash(db db_provider.DB, lat f64, lng f64, year int, state_filter string, precision int) !NearestHarborMatch {
	prefixes := geohash_prefixes_for_query(lat, lng, precision)
	if prefixes.len == 0 {
		return error('Nenhum geohash de busca foi gerado para as coordenadas informadas.')
	}

	state_clause := if state_filter == '' {
		''
	} else {
		" AND d.state = '${state_filter}'"
	}
	prefix_clause := prefixes.map("'${it}'").join(',')

	query := "SELECT d.id, d.id_harbor_state FROM data_mare d JOIN geo_location g ON g.data_mare_id = d.id WHERE d.year = ${year}${state_clause} AND substr(g.geo_hash, 1, ${precision}) IN (${prefix_clause}) ORDER BY ${haversine_order_expr(lat, lng)} ASC LIMIT 1;"
	return query_nearest_harbor_match(db, query)!
}

fn find_nearest_harbor_match_sqlite(mut pool_conn pool.ConnectionPool, lat f64, lng f64, state_filter string) !NearestHarborMatch {
	conn := pool_conn.get()!
	db := conn as db_provider.DB
	mut should_release_conn := true
	defer {
		if should_release_conn {
			pool_conn.put(conn) or { println(err.msg()) }
		}
	}

	year := time.now().year
	for precision in geohash_precisions {
		nearest_by_precision := try_find_nearest_harbor_match_by_geohash(db, lat, lng, year,
			state_filter, precision) or {
			continue
		}
		if nearest_by_precision.id > 0 && nearest_by_precision.harbor_state_id != '' {
			return nearest_by_precision
		}
	}

	state_clause := if state_filter == '' {
		''
	} else {
		" AND d.state = '${state_filter}'"
	}
	full_scan_query := "SELECT d.id, d.id_harbor_state FROM data_mare d JOIN geo_location g ON g.data_mare_id = d.id WHERE d.year = ${year}${state_clause} ORDER BY ${haversine_order_expr(lat, lng)} ASC LIMIT 1;"
	full_scan_match := query_nearest_harbor_match(db, full_scan_query) or {
		should_release_conn = false
		pool_conn.put(conn) or { println(err.msg()) }
		if state_filter == '' {
			return find_nearest_harbor_match_in_memory(mut pool_conn, lat, lng)
		}
		return find_nearest_harbor_match_within_same_state_in_memory(mut pool_conn, lat, lng,
			state_filter)
	}
	return full_scan_match
}
}

// find_nearest_harbor_within_same_state_v2 wrapper para retornar DTO v2
pub fn find_nearest_harbor_within_same_state_v2(mut pool_conn pool.ConnectionPool, lat f64, lng f64, state string) !dto.DTOHaborMareGetHarborV2 {
	harbor := find_nearest_harbor_within_same_state(mut pool_conn, lat, lng, state)!
	return dto.DTOHaborMareGetHarborV2{
		id:                          harbor.harbor_id
		year:                        harbor.year
		harbor_name:                 harbor.harbor_name
		state:                       harbor.state
		timezone:                    harbor.timezone
		card:                        harbor.card
		geo_location:                harbor.geo_location
		data_collection_institution: harbor.data_collection_institution
		mean_level:                  harbor.mean_level
	}
}
