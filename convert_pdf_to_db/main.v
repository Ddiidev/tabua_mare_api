module main

import os
import db.pg
import entities

const conn_str = r'postgresql://moderaqui:pU,j$wFC1OD+$;9iX5:D5kE|@postgres:5432/tabua_mare'

fn main() {
	mut dbase := pg.connect_with_conninfo(conn_str)!

	sql dbase {
		create table entities.GeoLocation
		create table entities.HourData
		create table entities.DayData
		create table entities.MonthData
		create table entities.DataMare
	}!

	dbase.close()!

	dbase = pg.connect_with_conninfo(conn_str)!
	for current_path in list_all_pdf('.${os.path_separator}pdf') {
		dump(current_path)
		output := convert_pdf_to_text(current_path)!

		text_normalized := normalize_pdf_to_text(output)!

		data := text_normalized.to_entity()

		sql dbase {
			insert data into entities.DataMare
		}!
	}

	dbase.close()!
}

fn convert_pdf_to_text(path_pdf string) !string {
	real_path := os.real_path(path_pdf)
	output_file_name := os.file_name(real_path)
	output_path := real_path.split(os.path_separator)#[..-1].join(os.path_separator)
	output_file := '${output_path}${os.path_separator}${output_file_name}.txt'

	if os.exists(output_file) {
		os.rm(output_file)!
	}
	os.system('pdftotext -raw -enc UTF-8 "${real_path}" "${output_file}"')
	return output_file
}

fn list_all_pdf(path string) []string {
	mut pdfs := []string{}
	real_path := os.real_path(path)
	for mut current_path in os.ls(real_path) or { [] } {
		current_path = '${real_path}${os.path_separator}${current_path}'

		if os.is_dir(current_path) {
			pdfs << list_all_pdf(current_path)
		} else if os.is_file(current_path) {
			if current_path.ends_with('.pdf') {
				pdfs << current_path
			}
		}
	}
	return pdfs
}
