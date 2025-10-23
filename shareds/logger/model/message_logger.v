module model

import time
import shareds.types

@[params]
pub struct MsgLog {
pub:
	timestamp      time.Time = time.now()
	id             string
	msg            string
	id_application string
	level          string = 'info'
	error          ?types.ErrorMsg @[omitempty]
}
