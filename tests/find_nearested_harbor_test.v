import shareds.infradb
import repository.habor_mare as repo_habor_mare

struct LatLng {
	lat f64
	lng f64
}

type State = string

const state_latlng_map = {
	'pb': [
		LatLng{
			lat: -7.11509
			lng: -34.864
		},
		LatLng{
			lat: -7.00250
			lng: -34.84000
		},
		LatLng{
			lat: -7.04200
			lng: -34.84800
		},
	]
	'rj': [
		LatLng{
			lat: -22.90680
			lng: -43.17290
		},
		LatLng{
			lat: -22.88320
			lng: -43.10340
		},
		LatLng{
			lat: -22.90100
			lng: -43.20750
		},
	]
	'sp': [
		LatLng{
			lat: -23.95400
			lng: -46.33800
		},
		LatLng{
			lat: -23.79900
			lng: -45.40100
		},
		LatLng{
			lat: -24.00800
			lng: -46.40300
		},
	]
	'rs': [
		LatLng{
			lat: -32.03490
			lng: -52.10750
		},
		LatLng{
			lat: -29.98400
			lng: -50.13200
		},
		LatLng{
			lat: -30.02800
			lng: -50.21000
		},
	]
	'ba': [
		LatLng{
			lat: -12.97180
			lng: -38.50110
		},
		LatLng{
			lat: -14.79300
			lng: -39.04800
		},
		LatLng{
			lat: -13.01000
			lng: -38.51100
		},
	]
	'al': [
		LatLng{
			lat: -9.64900
			lng: -35.70800
		},
		LatLng{
			lat: -9.70900
			lng: -35.89500
		},
		LatLng{
			lat: -9.57100
			lng: -35.76300
		},
	]
	'ce': [
		LatLng{
			lat: -3.73190
			lng: -38.52670
		},
		LatLng{
			lat: -4.55900
			lng: -37.76700
		},
		LatLng{
			lat: -3.87000
			lng: -38.62400
		},
	]
	'pe': [
		LatLng{
			lat: -8.04760
			lng: -34.87700
		},
		LatLng{
			lat: -7.99900
			lng: -34.85100
		},
		LatLng{
			lat: -8.05800
			lng: -34.90500
		},
	]
	'es': [
		LatLng{
			lat: -20.31550
			lng: -40.31280
		},
		LatLng{
			lat: -20.66600
			lng: -40.50400
		},
		LatLng{
			lat: -20.36000
			lng: -40.28000
		},
	]
	'sc': [
		LatLng{
			lat: -27.59350
			lng: -48.55800
		},
		LatLng{
			lat: -26.90200
			lng: -48.65400
		},
		LatLng{
			lat: -27.21200
			lng: -48.61000
		},
	]
	'pr': [
		LatLng{
			lat: -25.51600
			lng: -48.52200
		},
		LatLng{
			lat: -25.70100
			lng: -48.49100
		},
		LatLng{
			lat: -25.48100
			lng: -48.54200
		},
	]
	'rn': [
		LatLng{
			lat: -5.79450
			lng: -35.21100
		},
		LatLng{
			lat: -5.10600
			lng: -36.63200
		},
		LatLng{
			lat: -5.78000
			lng: -35.23000
		},
	]
	'ma': [
		LatLng{
			lat: -2.53900
			lng: -44.28200
		},
		LatLng{
			lat: -2.41700
			lng: -44.10000
		},
		LatLng{
			lat: -2.55000
			lng: -44.30000
		},
	]
	'pa': [
		LatLng{
			lat: -1.45500
			lng: -48.50300
		},
		LatLng{
			lat: -0.61700
			lng: -47.35600
		},
		LatLng{
			lat: -1.48000
			lng: -48.48000
		},
	]
	'se': [
		LatLng{
			lat: -10.94700
			lng: -37.07300
		},
		LatLng{
			lat: -10.90800
			lng: -37.04000
		},
		LatLng{
			lat: -10.98000
			lng: -37.05000
		},
	]
	'ap': [
		LatLng{
			lat: 0.03400
			lng: -51.06900
		},
		LatLng{
			lat: -0.05200
			lng: -51.17800
		},
		LatLng{
			lat: 0.05000
			lng: -51.07000
		},
	]
}

// pub fn test_find_nearested_harbor() ! {
//     mut pool_conn := infradb.new()!
//     conn := pool_conn.get()!

// 	for state, latlngs in state_latlng_map {
//         for i, latlng in latlngs {
//             lat := latlng.lat
//             lng := latlng.lng
//             nearest_harbor := repo_habor_mare.find_nearest_port_within_same_state(mut pool_conn, lat, lng) or {
//                 assert false, 'state: ${state}[$i] | nearest_harbor: ${nearest_harbor} | error: ${err}'
// 				break
//             }

//             assert (nearest_harbor.state == state.to_lower()), 'state: ${state}[$i] | nearest_harbor: ${nearest_harbor}'
//         }
//     }
// }

pub fn test_find_nearest_harbor_within_same_state() ! {
	infradb.apply_startup_migrations()!
	mut pool_conn := infradb.new()!

	for state, latlngs in state_latlng_map {
		for i, latlng in latlngs {
			lat := latlng.lat
			lng := latlng.lng
			nearest_harbor := repo_habor_mare.find_nearest_harbor_within_same_state(mut pool_conn,
				lat, lng, state) or {
				assert false, 'state: ${state} | error: ${err}'
				break
			}

			assert nearest_harbor.state == state.to_lower(), 'state: ${state}[${i}] | nearest_harbor: ${nearest_harbor}'
		}
	}
}

pub fn test_find_nearest_harbor_id_within_same_state() ! {
	infradb.apply_startup_migrations()!
	mut pool_conn := infradb.new()!

	for state, latlngs in state_latlng_map {
		for i, latlng in latlngs {
			harbor_id := repo_habor_mare.find_nearest_harbor_id_within_same_state(mut pool_conn,
				latlng.lat, latlng.lng, state) or {
				assert false, 'state: ${state} | error: ${err}'
				break
			}

			assert harbor_id.starts_with(state.to_lower()), 'state: ${state}[${i}] | harbor_id: ${harbor_id}'
		}
	}
}
