module habor_mare

import math
import pool
import time
import benchmark
import shareds.geohash
import db.sqlite as db_provider
import repository.habor_mare.dto

const earth_radius_km = 6371.0
const geohash_precisions = [5, 4, 3, 2, 1]!

struct NearestHarborMatch {
	id              int
	harbor_state_id string
}

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
	if normalized.len != 2 || !normalized[0].is_letter() || !normalized[1].is_letter() {
		return error('É necessário informar o estado corretamente.')
	}
	return normalized
}

fn geohash_prefixes_for_query(lat f64, lng f64, precision int) []string {
	hash := geohash.encode(lat, lng, precision)
	mut seen := map[string]bool{}
	mut prefixes := []string{}
	for item in geohash.neighbors(hash) {
		if item.len < precision {
			continue
		}
		prefix := item[..precision]
		if !seen[prefix] {
			seen[prefix] = true
			prefixes << prefix
		}
	}
	return prefixes
}

fn nearest_from_rows(rows []db_provider.Row, lat f64, lng f64) !NearestHarborMatch {
	mut nearest := NearestHarborMatch{}
	mut shortest_distance := -1.0
	for row in rows {
		if row.vals.len < 4 || row.vals[0] == '' || row.vals[1] == '' || row.vals[2] == ''
			|| row.vals[3] == '' {
			continue
		}

		mut b := benchmark.start()
		candidate_distance := distance(lat, lng, row.vals[2].f64(), row.vals[3].f64())
		b.measure('distance')
		if shortest_distance == -1.0 || candidate_distance < shortest_distance {
			shortest_distance = candidate_distance
			nearest = NearestHarborMatch{
				id:              row.vals[0].int()
				harbor_state_id: row.vals[1]
			}
		}
	}
	if nearest.id <= 0 || nearest.harbor_state_id == '' {
		return error('Nenhum porto encontrado perto das coordenadas fornecidas.')
	}
	return nearest
}

fn candidate_query(db db_provider.DB, lat f64, lng f64, year int, state string, precision int) !NearestHarborMatch {
	mut b := benchmark.start()
	prefixes := geohash_prefixes_for_query(lat, lng, precision)

	b.measure('geohash_prefixes_for_query')

	if prefixes.len == 0 { return error('Nenhum geohash de busca foi gerado.') }
	state_clause := if state == '' { '' } else { " AND d.state = '${state}'" }

	rows := if precision == 5 {
		prefix_clause := prefixes.map("'${it}'").join(',')
		db.exec('SELECT d.id, d.id_harbor_state, g.lat, g.lng FROM data_mare d JOIN geo_location g ON g.data_mare_id = d.id WHERE d.year = ${year}${state_clause} AND g.geo_hash IN (${prefix_clause});')!
	} else {
		mut like_clauses := []string{}
		for prefix in prefixes {
			like_clauses << "g.geo_hash LIKE '${prefix}%'"
		}
		prefix_clause := '(' + like_clauses.join(' OR ') + ')'

		db.exec('SELECT d.id, d.id_harbor_state, g.lat, g.lng FROM data_mare d JOIN geo_location g ON g.data_mare_id = d.id WHERE d.year = ${year}${state_clause} AND ${prefix_clause};')!
	}

	b.measure('db.exec')
	return nearest_from_rows(rows, lat, lng)
}

fn find_nearest_harbor_match(mut pool_conn pool.ConnectionPool, lat f64, lng f64, state string) !NearestHarborMatch {
	conn := pool_conn.get()!
	db := conn as db_provider.DB
	defer { pool_conn.put(conn) or { println(err.msg()) } }
	year := time.now().year
	for precision in geohash_precisions {
		nearest_match := candidate_query(db, lat, lng, year, state, precision) or { continue }
		return nearest_match
	}
	state_clause := if state == '' { '' } else { " AND d.state = '${state}'" }
	rows :=
		db.exec('SELECT d.id, d.id_harbor_state, g.lat, g.lng FROM data_mare d JOIN geo_location g ON g.data_mare_id = d.id WHERE d.year = ${year}${state_clause};')!
	return nearest_from_rows(rows, lat, lng)
}

pub fn find_nearest_harbor(mut pool_conn pool.ConnectionPool, lat f64, lng f64) !dto.DTOHaborMareGetHarbor {
	mut b := benchmark.start()
	nearest_match := find_nearest_harbor_match(mut pool_conn, lat, lng, '')!

	b.measure('find_nearest_harbor_match')
	result := get_harbor_by_ids(mut pool_conn, [nearest_match.harbor_state_id])!

	b.measure('get_harbor_by_ids')
	if result.total == 0 { return error('Could not find a nearest harbor with valid coordinates.') }
	return result.data[0]
}

pub fn find_nearest_harbor_within_same_state(mut pool_conn pool.ConnectionPool, lat f64, lng f64, state string) !dto.DTOHaborMareGetHarbor {
	nearest_match := find_nearest_harbor_match(mut pool_conn, lat, lng,
		normalize_state_code(state)!)!
	result := get_harbor_by_ids(mut pool_conn, [nearest_match.harbor_state_id])!
	if result.total == 0 {
		return error('Nenhum porto encontrado no estado correspondente às coordenadas.')
	}
	return result.data[0]
}

pub fn find_nearest_harbor_id(mut pool_conn pool.ConnectionPool, lat f64, lng f64) !string {
	return find_nearest_harbor(mut pool_conn, lat, lng)!.id
}

pub fn find_nearest_harbor_id_within_same_state(mut pool_conn pool.ConnectionPool, lat f64, lng f64, state string) !string {
	return find_nearest_harbor_within_same_state(mut pool_conn, lat, lng, state)!.id
}