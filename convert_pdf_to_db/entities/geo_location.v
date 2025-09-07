module entities

import types

@[table: 'geo_location']
pub struct GeoLocation {
pub mut:
	id            int @[primary; sql: serial]
	data_mare_id  int
	lat           string
	lng           string
	decimal_lat   string
	decimal_lng   string
	lat_direction types.GeoLocationDirection
	lng_direction types.GeoLocationDirection
}
