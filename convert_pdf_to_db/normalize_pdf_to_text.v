module main

import os
import time
import types
import models

const year = time.now().year

fn is_month_name(name string) bool {
	months := ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto',
		'Setembro', 'Outubro', 'Novembro', 'Dezembro']
	return name in months
}

fn is_numeric(line &string) bool {
	return if line.len == 0 {
		false
	} else {
		line.bytes().all(it.is_digit())
	}
}

fn is_weekday(s string) bool {
	weekdays := ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM']
	return s in weekdays
}

fn weekday_short_to_long(short_weekday string) string {
	weekdays := ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM']
	long_weekdays := ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo']
	return long_weekdays[weekdays.index(short_weekday)]
}

fn is_time_format(s string) bool {
	return s.len == 4 && is_numeric(s)
}

fn is_height_format(s string) bool {
	if s.len == 0 {
		return false
	}
	for i, c in s {
		if !c.is_digit() && c != `.` && !(i == 0 && c == `-`) {
			return false
		}
	}
	return true
}

fn get_month_number(month_name string) int {
	return match month_name {
		'Janeiro' { 1 }
		'Fevereiro' { 2 }
		'Março' { 3 }
		'Abril' { 4 }
		'Maio' { 5 }
		'Junho' { 6 }
		'Julho' { 7 }
		'Agosto' { 8 }
		'Setembro' { 9 }
		'Outubro' { 10 }
		'Novembro' { 11 }
		'Dezembro' { 12 }
		else { 1 }
	}
}

pub fn normalize_pdf_to_text(file_pdf_converted_for_txt string) !models.DataMare {
	pdf := os.read_lines(file_pdf_converted_for_txt)!
	mut geo_location := models.GeoLocation{}
	mut data_mare := models.DataMare{}
	mut current_month := models.MonthData{}
	mut current_day := models.DayData{}
	mut months := []models.MonthData{}
	mut in_month_data := false
	state := file_pdf_converted_for_txt.split(os.path_separator)#[-2..-1][0]
	mut recently_captured_page_number := false

	line_is_hour_and_level := fn (line &string) bool {
		line_parts := line.split(' ')
		return if line_parts.len == 2 {
			is_numeric(line_parts[0])
		} else {
			false
		}
	}

	idenfied_number_page := fn (line &string) bool {
		return line.bytes().all(it.is_digit())
	}

	for i, line in pdf {
		line_apply_trim := line.trim_space()
		if line_apply_trim == '' {
			continue
		}

		// Identificação do número da página no documento PDF
		if idenfied_number_page(line_apply_trim) {
			recently_captured_page_number = true
		}

		if line_apply_trim.contains('HORA ALT(m)') {
			continue
		}
		// Extração do nome do porto e ano a partir do cabeçalho do documento
		else if recently_captured_page_number && (line_apply_trim.contains('- ${year}')
			|| line_apply_trim.count('-') == 2) {
			recently_captured_page_number = false
			parts := line_apply_trim.split('-')
			if parts.len >= 2 {
				data_mare = models.DataMare{
					...data_mare
					harbor_name: parts#[0..-1].map(it.trim_space()).join(' ')
					state:       state
					year:        year
				}
			}
		}
		// Processamento das coordenadas geográficas (latitude e longitude)
		else if line_apply_trim.contains('Latitude') && line_apply_trim.contains('Longitude') {
			// Conversão da latitude de formato graus-minutos para decimal
			lat_part := line_apply_trim.all_after('Latitude ').all_before(' Longitude')
			lat_value := lat_part.replace('°', '').replace("'", '').trim_space()
			lat_parts := lat_value.split(' ')
			if lat_parts.len >= 3 {
				lat_degrees := lat_parts[0].f64()
				lat_minutes := lat_parts[1].f64()
				lat_direction := types.GeoLocationDirection.from_str(lat_parts[lat_parts.len - 1])

				lat_decimal := lat_degrees + (lat_minutes / 60.0)
				coord_lat := if lat_direction.signal() == `-` {
					-lat_decimal
				} else {
					lat_decimal
				}

				geo_location = models.GeoLocation{
					...geo_location
					lat:           coord_lat.str()
					decimal_lat:   lat_part
					lat_direction: lat_direction
				}
			}

			// Conversão da longitude de formato graus-minutos para decimal
			lng_part := line_apply_trim.all_after('Longitude ').all_before(' Fuso')
			lng_clean := lng_part.replace('°', ' ').replace("'", ' ')
			lng_parts := lng_clean.split(' ').filter(it.trim_space() != '')
			if lng_parts.len >= 3 {
				lng_degrees := lng_parts[0].f64()
				lng_minutes := lng_parts[1].f64()
				lng_direction := types.GeoLocationDirection.from_str(lng_parts[lng_parts.len - 1])

				lng_decimal := lng_degrees + (lng_minutes / 60.0)
				coord_lng := if lng_direction.signal() == `-` {
					-lng_decimal
				} else {
					lng_decimal
				}

				geo_location = models.GeoLocation{
					...geo_location
					lng:           coord_lng.str()
					decimal_lng:   lng_part
					lng_direction: lng_direction
				}
			}

			// Extração do fuso horário da localização
			if line_apply_trim.contains('Fuso ') {
				data_mare = models.DataMare{
					...data_mare
					timezone: line_apply_trim.all_after('Fuso ').all_before(' horas')
				}
			}
		}
		// Processamento de informações institucionais e dados da carta náutica
		else if ['Nível Médio', 'Carta'].all(line_apply_trim.contains(it)) {
			data_mare.mean_level = line_apply_trim.all_after('Nível Médio ').all_before(' m')
			data_mare.card = line_apply_trim.all_after('Carta ').trim_space()
			data_mare.geo_location = geo_location
			data_mare.data_collection_institution = line_apply_trim.before(' ')
		}
		// Detecção e início do processamento dos dados mensais de maré
		else if is_month_name(line_apply_trim) {
			// Finalização e armazenamento do mês anterior processado
			if current_month.month_name != '' {
				if current_day.weekday_name != '' {
					current_month.days << current_day
				}
				months << current_month
			}

			// Inicialização de nova estrutura para o mês atual
			current_month = models.MonthData{
				month_name: line_apply_trim
				month:      get_month_number(line_apply_trim)
				days:       []
			}
			current_day = models.DayData{}
			in_month_data = true
		}
		// Processamento de números de dias e identificação de dias da semana
		else if in_month_data && is_numeric(line_apply_trim) {
			// Finalização e armazenamento do dia anterior processado
			if current_day.weekday_name != '' {
				current_month.days << current_day
			}

			// Busca antecipada pelo nome do dia da semana na próxima linha
			if i + 1 < pdf.len {
				weekday := pdf[i + 1].trim_space()
				if is_weekday(weekday) {
					day_num := line_apply_trim.int()
					current_day = models.DayData{
						weekday_name: weekday_short_to_long(weekday)
						day:          day_num
						hours:        []
					}
				}
			}
		} else if current_day.weekday_name != '' && line_is_hour_and_level(line_apply_trim) {
			// Processamento de dados horários e níveis de maré
			line_parts := line_apply_trim.split(' ')
			hour_text := line_parts[0]
			hour_parts := [hour_text[0..2], hour_text[2..]]
			level := line_parts[1].replace_char(`,`, `.`, 1).f32()
			current_day.hours << models.HourData{
				hour:  time.Time{
					hour:   hour_parts[0].int()
					minute: hour_parts[1].int()
				}.hhmmss()
				level: level
			}
			// Código de depuração comentado para análise específica
			// l := current_day.hours.last()
			// if data_mare.harbor_name == 'PORTO DO AÇU (ESTADO DO RIO DE JANEIRO)' && l.hour == '23:46:00' {
			// 	$dbg;
			// }
		}
	}

	// Garantir que o último mês processado seja incluído na lista final
	if !months.any(it.month_name == current_month.month_name) {
		months << current_month
	}

	// Consolidar todos os dados mensais processados na estrutura principal
	data_mare.months << months

	return data_mare
}
