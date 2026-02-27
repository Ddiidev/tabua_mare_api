module geohash

const geohash_base32 = '0123456789bcdefghjkmnpqrstuvwxyz'
const geohash_bits = [16, 8, 4, 2, 1]

struct BoundingBox {
	lat_min f64
	lat_max f64
	lng_min f64
	lng_max f64
}

fn base32_index(ch u8) int {
	for idx, item in geohash_base32.bytes() {
		if item == ch {
			return idx
		}
	}
	return -1
}

fn normalize_precision(precision int) int {
	if precision < 1 {
		return 1
	}
	if precision > 12 {
		return 12
	}
	return precision
}

fn clamp_lat(lat f64) f64 {
	if lat <= -90.0 {
		return -89.999999
	}
	if lat >= 90.0 {
		return 89.999999
	}
	return lat
}

fn normalize_lng(lng f64) f64 {
	mut normalized := lng
	for normalized < -180.0 {
		normalized += 360.0
	}
	for normalized > 180.0 {
		normalized -= 360.0
	}
	return normalized
}

// encode encodes latitude/longitude into a base32 geohash string.
pub fn encode(lat f64, lng f64, precision int) string {
	hash_len := normalize_precision(precision)
	mut lat_interval := [-90.0, 90.0]
	mut lng_interval := [-180.0, 180.0]
	mut is_even := true
	mut bit_idx := 0
	mut char_idx := 0
	mut output := []u8{cap: hash_len}

	for output.len < hash_len {
		if is_even {
			mid := (lng_interval[0] + lng_interval[1]) / 2.0
			if lng > mid {
				char_idx |= geohash_bits[bit_idx]
				lng_interval[0] = mid
			} else {
				lng_interval[1] = mid
			}
		} else {
			mid := (lat_interval[0] + lat_interval[1]) / 2.0
			if lat > mid {
				char_idx |= geohash_bits[bit_idx]
				lat_interval[0] = mid
			} else {
				lat_interval[1] = mid
			}
		}

		is_even = !is_even
		if bit_idx < 4 {
			bit_idx++
			continue
		}

		output << geohash_base32[char_idx]
		bit_idx = 0
		char_idx = 0
	}

	return output.bytestr()
}

fn decode_bbox(hash string) BoundingBox {
	mut lat_interval := [-90.0, 90.0]
	mut lng_interval := [-180.0, 180.0]
	mut is_even := true

	for ch in hash.bytes() {
		char_pos := base32_index(ch)
		if char_pos < 0 {
			continue
		}
		for bit in geohash_bits {
			if is_even {
				mid := (lng_interval[0] + lng_interval[1]) / 2.0
				if (char_pos & bit) != 0 {
					lng_interval[0] = mid
				} else {
					lng_interval[1] = mid
				}
			} else {
				mid := (lat_interval[0] + lat_interval[1]) / 2.0
				if (char_pos & bit) != 0 {
					lat_interval[0] = mid
				} else {
					lat_interval[1] = mid
				}
			}
			is_even = !is_even
		}
	}

	return BoundingBox{
		lat_min: lat_interval[0]
		lat_max: lat_interval[1]
		lng_min: lng_interval[0]
		lng_max: lng_interval[1]
	}
}

// neighbors returns the geohash cell and its 8 surrounding neighbors.
pub fn neighbors(hash string) []string {
	if hash == '' {
		return []string{}
	}

	box := decode_bbox(hash)
	lat_step := box.lat_max - box.lat_min
	lng_step := box.lng_max - box.lng_min
	center_lat := (box.lat_min + box.lat_max) / 2.0
	center_lng := (box.lng_min + box.lng_max) / 2.0
	precision := hash.len

	mut seen := map[string]bool{}
	mut result := []string{cap: 9}

	for dy in [-1, 0, 1] {
		for dx in [-1, 0, 1] {
			next_lat := clamp_lat(center_lat + (lat_step * f64(dy)))
			next_lng := normalize_lng(center_lng + (lng_step * f64(dx)))
			neighbor := encode(next_lat, next_lng, precision)
			if seen[neighbor] {
				continue
			}
			seen[neighbor] = true
			result << neighbor
		}
	}

	return result
}
