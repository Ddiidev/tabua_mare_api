module logger

import json
import net.http
import shareds.types
import shareds.logger.model

pub fn (mut l Logger) save(params model.MsgLog) {
	msg := json.encode(model.MsgLog{
		...params
		id_application: 'app: ${l.id_application}'
	})
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

pub struct ParamsLogger {
pub:
	req_id string
	error  ?types.ErrorMsg
	msg    string
pub mut:
	log Logger
}

pub fn Logger.async_save(params ParamsLogger) {
	mut log := params.log
	error := params.error
	req_id := params.req_id
	msg := params.msg

	go fn [mut log, error, req_id, msg] () {
		log.save(
			id:    req_id
			error: error
			msg:   msg
		)
	}()
}
