module dto

pub struct DTODataMareGetHarbor {
pub mut:
	id                          int           @[omitempty]
	year                        int           @[omitempty]
	harbor_name                 string        @[omitempty]
	state                       string        @[omitempty]
	timezone                    string        @[omitempty]
	card                        string        @[omitempty]
	geo_location                []GeoLocation @[omitempty]
	data_collection_institution string        @[omitempty]
	mean_level                  f32           @[omitempty]
}
