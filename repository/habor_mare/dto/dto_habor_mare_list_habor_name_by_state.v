module dto

pub struct DTOHaborMareListHaborNameByState {
pub:
	id                          string @[omitempty]
	year                        int    @[omitempty]
	harbor_name                 string @[omitempty]
	data_collection_institution string @[omitempty]
}

pub struct DTOHaborMareListHaborNameByStateV1 {
pub:
	id                          int    @[omitempty]
	year                        int    @[omitempty]
	harbor_name                 string @[omitempty]
	data_collection_institution string @[omitempty]
}
