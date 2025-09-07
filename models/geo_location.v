module models

import types
import entities

pub struct GeoLocation {
pub:
	lat           string
	lng           string
	decimal_lat   string
	decimal_lng   string
	lat_direction types.GeoLocationDirection
	lng_direction types.GeoLocationDirection
}

pub fn (gl GeoLocation) to_entity() entities.GeoLocation {
	return entities.GeoLocation{
		lat:           gl.lat
		lng:           gl.lng
		decimal_lat:   gl.decimal_lat
		decimal_lng:   gl.decimal_lng
		lat_direction: gl.lat_direction
		lng_direction: gl.lng_direction
	}
}
