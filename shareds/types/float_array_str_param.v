module types

pub type FloatArr = string

// ints convert string on format "[1,5.3,15]" to array of float
pub fn (ids FloatArr) list_float() []f64 {
	mut inters := []f64{}
	mut curr_number := ''
	for numbers in ids.replace_each(['[', '', ']', '', ' ', '']).split(',') {
		for num in numbers {
			if num in [`-`, `.`] {
				curr_number += num.ascii_str()
			} else if num.is_digit() {
				curr_number += num.ascii_str()
			}
		}
		inters << curr_number.f64()
		curr_number = ''
	}
	return inters
}
