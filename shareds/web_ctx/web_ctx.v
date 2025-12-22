module web_ctx

import veb
import veb.request_id

pub struct WsCtx {
	veb.Context
	request_id.RequestIdContext
}