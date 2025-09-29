module types

pub type IntArr = string

pub fn (ids IntArr) ints() []int {
	return ids.after('[').before(']').split(',').map(it.int())
}
