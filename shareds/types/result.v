module types

pub struct ResultValues[T] {
pub:
	data  []T
	total int
	error ?ErrorMsg @[omitempty]
}
