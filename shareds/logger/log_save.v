module logger

import json2
import net.http
import shareds.types
import shareds.logger.model

pub fn (mut l Logger) save(params model.MsgLog) {
	msg := json2.encode(model.MsgLog{
		...params
		id_application: 'app: ${l.id_application}'
	},
		escape_unicode: true
	)
	$if prod {
		l.new_relic_info(msg) or {}
	} $else {
		if params.level == 'info' {
			l.log.info(msg)
		} else if params.level == 'error' {
			l.log.error(msg)
		}
	}
}

@[params]
pub struct ParamsLogger {
pub:
	id    string
	level string
	error ?types.ErrorMsg
	msg   string
}

pub fn (mut l Logger) async_save(params ParamsLogger) {
	error := params.error
	id := params.id
	level := params.level
	msg := params.msg

	go fn [mut l, error, id, level, msg] () {
		l.save(
			id:    id
			level: level
			error: error
			msg:   msg
		)
	}()
}

fn (l Logger) new_relic_info(msg string) ! {
	http.fetch(http.FetchConfig{
		url:    'https://log-api.newrelic.com/log/v1'
		method: .post
		header: http.new_custom_header_from_map({
			'Api-Key': l.new_relic_key
		})!
		data:   msg
	})!
}
