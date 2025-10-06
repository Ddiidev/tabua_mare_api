module cache

import repository.tabua_mare.dto as tabua_mare_dto
import repository.habor_mare.dto as harbor_mare_dto

pub type TypeCacheData = []harbor_mare_dto.DTOHaborMareListHaborNameByState
	| []harbor_mare_dto.DTOHaborMareGetHarbor
	| []tabua_mare_dto.DTODayData
	| []string