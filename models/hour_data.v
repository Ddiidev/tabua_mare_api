module models

import entities

pub struct HourData {
pub mut:
	hour  string
	level f32
}

pub fn (hd HourData) to_entity() entities.HourData {
	return entities.HourData{
		hour:  hd.hour
		level: hd.level
	}
}
