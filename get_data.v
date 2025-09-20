module main

import veb
import shareds.web_ctx

@['/ping'; get]
pub fn (app &App) ping(mut ctx web_ctx.WebCtx) veb.Result {
	return ctx.ok('pong')
}

@['/']
pub fn (app &App) index(mut ctx web_ctx.WebCtx) veb.Result {
	return ctx.ok('funcionou! on port ${app.port}')
}
