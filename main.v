module main

import veb
import shareds.web_ctx
import os

struct App {}

fn main() {
	mut app := &App{}

	port := os.getenv_opt('PORT') or { '4048' }.int()

	println('Starting Tabua Mare API on port ${port}')
	veb.run[App, web_ctx.WebCtx](mut app, port)
}
