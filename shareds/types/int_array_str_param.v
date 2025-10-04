module types

import arrays

pub type IntArr = string

//ints convert string on format "[1,5-15]" to array of ints
pub fn (ids IntArr) ints() []int {
	mut inters := []int{}
	for id in ids.replace_each(['[', '', ']', '', ' ', '']).split(',') {
		if id.contains('-') {
			start := id.before('-').int()
			end := id.after('-').int()
			for i in start .. end + 1 {
				inters << i
			}
		} else {
			inters << id.int()
		}
	}
	return arrays.distinct(inters)
}
