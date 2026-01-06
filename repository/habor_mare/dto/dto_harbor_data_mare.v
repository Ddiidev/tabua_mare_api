module dto

pub struct DTOHaborMareGetHarbor {
pub mut:
	id                          int           @[omitempty]
	harbor_id                   string        @[json: 'id_harbor_state'; omitempty]
	year                        int           @[omitempty]
	harbor_name                 string        @[omitempty]
	state                       string        @[omitempty]
	timezone                    string        @[omitempty]
	card                        string        @[omitempty]
	geo_location                []GeoLocation @[omitempty]
	data_collection_institution string        @[omitempty]
	mean_level                  f32           @[omitempty]
}

pub struct DTOHaborMareGetHarborV2 {
pub mut:
	id                          string        @[omitempty]
	year                        int           @[omitempty]
	harbor_name                 string        @[omitempty]
	state                       string        @[omitempty]
	timezone                    string        @[omitempty]
	card                        string        @[omitempty]
	geo_location                []GeoLocation @[omitempty]
	data_collection_institution string        @[omitempty]
	mean_level                  f32           @[omitempty]
}
