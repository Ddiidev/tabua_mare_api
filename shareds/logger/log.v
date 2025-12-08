module logger

import os
import log
import net.http
import shareds.conf_env

@[noinit]
pub struct Logger {
	id_application string
	new_relic_key  string
mut:
	log log.Log
	req http.Request
}

pub fn Logger.new(id_application string) !Logger {
	return $if prod {
		new_relic_log(id_application)!
	} $else {
		local_log(id_application)
	}
}

fn local_log(id_application string) Logger {
	if !os.exists('./logs') {
		os.mkdir('./logs') or {}
	}

	mut files_log := os.ls('./logs') or { [] }
	files_log.sort()

	last_log := if files_log.len > 0 {
		files_log.last()
	} else {
		'log-0.txt'
	}

	mut l := log.Log{}
	l.set_output_path('./logs/${generate_name_file(last_log)}')
	return Logger{
		id_application: id_application
		log:            l
	}
}

fn generate_name_file(last_log string) string {
	parts := last_log.split('-')
	number := parts[1] or { '0' }.int() + 1
	return 'log-${number}.txt'
}

fn new_relic_log(id_application string) !Logger {
	env := conf_env.load_env()
	return Logger{
		id_application: id_application
		new_relic_key:  env.new_relic_key
	}
}
