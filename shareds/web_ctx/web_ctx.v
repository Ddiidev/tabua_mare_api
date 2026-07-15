module web_ctx

import veb
import veb.request_id
import domain.auth_user

pub struct WsCtx {
	veb.Context
	request_id.RequestIdContext
pub mut:
	current_user ?auth_user.JwtClaims
	api_key      string
	ip           string
	plan         string
}
