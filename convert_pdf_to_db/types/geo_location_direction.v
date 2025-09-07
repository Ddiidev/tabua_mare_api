module types

pub enum GeoLocationDirection {
	none = 0
	s    = 1
	n    = 2
	e    = 3
	w    = 4
}

pub fn GeoLocationDirection.from_str(str string) GeoLocationDirection {
	return match str.to_upper() {
		'S' { .s }
		'N' { .n }
		'E' { .e }
		'W' { .w }
		else { .none }
	}
}

pub fn (gld GeoLocationDirection) signal() rune {
	return match gld {
		.none { ` ` }
		.s, .w { `-` }
		.n, .e { `+` }
	}
}
