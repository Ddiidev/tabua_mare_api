module types

pub struct ErrorAPI {
pub:
	code    int
	message string
}

pub struct ResultAPI[T] {
pub:
	data  []T
	total int
	error ?ErrorAPI @[omitempty]
}

pub fn success[T](data []T) ResultAPI[T] {
	return ResultAPI[T]{
		data:  data
		total: data.len
	}
}

pub fn failure[T](code int, message string) ResultAPI[T] {
	return ResultAPI[T]{
		data:  []T{}
		total: 0
		error: ErrorAPI{
			code:    code
			message: message
		}
	}
}
