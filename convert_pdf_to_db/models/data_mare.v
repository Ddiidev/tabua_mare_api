module models

import entities

pub struct DataMare {
pub mut:
	year                        int
	harbor_name                 string
	state                       string
	timezone                    string
	card                        string
	data_collection_institution string
	geo_location                GeoLocation
	mean_level                  string
	months                      []MonthData
}

pub fn (dm DataMare) to_entity() entities.DataMare {
	return entities.DataMare{
		year:                        dm.year
		harbor_name:                 dm.harbor_name
		state:                       dm.state
		timezone:                    dm.timezone
		card:                        dm.card
		data_collection_institution: dm.data_collection_institution
		geo_location:                [dm.geo_location.to_entity()]
		mean_level:                  dm.mean_level
		months:                      dm.months.map(it.to_entity())
	}
}
