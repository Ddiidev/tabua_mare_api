module habor_mare

import math
import pool
import repository.habor_mare.dto

struct NominatimResponse {
	address map[string]string
}

const earth_radius_km = 6371.0

// distance calculates the distance in km between two geographic coordinates.
fn distance(lat1 f64, lon1 f64, lat2 f64, lon2 f64) f64 {
	d_lat := (lat2 - lat1) * (math.pi / 180.0)
	d_lon := (lon2 - lon1) * (math.pi / 180.0)

	a := math.pow(math.sin(d_lat / 2), 2) +
		math.cos(lat1 * (math.pi / 180.0)) * math.cos(lat2 * (math.pi / 180.0)) * math.pow(math.sin(d_lon / 2), 2)
	c := 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

	return earth_radius_km * c
}

// find_nearest_harbor encontra o porto mais próximo da coordenada informada.
pub fn find_nearest_harbor(mut pool_conn pool.ConnectionPool, lat f64, lng f64) !dto.DTOHaborMareGetHarbor {
	all_harbors := list_all_harbors(mut pool_conn)!

	if all_harbors.total == 0 {
		return error('No harbors found in the database.')
	}

	mut nearest_harbor := dto.DTOHaborMareGetHarbor{}
	mut shortest_distance := -1.0

	for harbor in all_harbors.data {
		if harbor.geo_location.len == 0 {
			continue
		}

		harbor_lat := harbor.geo_location[0].lat.f64()
		harbor_lng := harbor.geo_location[0].lng.f64()

		dist := distance(lat, lng, harbor_lat, harbor_lng)

		if shortest_distance == -1.0 || dist < shortest_distance {
			shortest_distance = dist
			nearest_harbor = harbor
		}
	}

	if shortest_distance == -1.0 {
		return error('Could not find a nearest harbor with valid coordinates.')
	}

	return nearest_harbor
}

// find_nearest_harbor_within_same_state encontra o porto mais próximo dentro do mesmo estado da coordenada informada.
pub fn find_nearest_harbor_within_same_state(mut pool_conn pool.ConnectionPool, lat f64, lng f64, state string) !dto.DTOHaborMareGetHarbor {
	if state.len != 2 {
		return error('É necessário informar o estado corretamente.')
	}

	all_harbors := list_all_harbors_by_state(mut pool_conn, state)!
	if all_harbors.len == 0 {
		return error('No harbors found in the database.')
	}

	mut nearest_harbor := dto.DTOHaborMareGetHarbor{}
	mut shortest_distance := -1.0
	for harbor in all_harbors {
		if harbor.geo_location.len == 0 {
			continue
		}

		if harbor.state != state {
			continue
		}
		harbor_lat := harbor.geo_location[0].lat.f64()
		harbor_lng := harbor.geo_location[0].lng.f64()
		dist := distance(lat, lng, harbor_lat, harbor_lng)

		if shortest_distance == -1.0 || dist < shortest_distance {
			shortest_distance = dist
			nearest_harbor = harbor
		}
	}
	if shortest_distance == -1.0 {
		return error('Nenhum porto encontrado no estado correspondente às coordenadas.')
	}
	return nearest_harbor
}
