module dto

import types

pub struct GeoLocation {
pub:
	lat           string                     @[omitempty]
	lng           string                     @[omitempty]
	decimal_lat   string                     @[omitempty]
	decimal_lng   string                     @[omitempty]
	lat_direction types.GeoLocationDirection @[omitempty]
	lng_direction types.GeoLocationDirection @[omitempty]
}
