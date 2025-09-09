module main

import veb
import shareds.web_ctx

@['/']
pub fn (app &App) index(mut ctx web_ctx.WebCtx) veb.Result {
	return ctx.ok('funcionou!')
}
