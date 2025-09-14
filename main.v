module main

import os
import veb
import shareds.web_ctx

struct App {
pub:
	port int
}

fn main() {
	if os.args.len == 0 {
		return
	}
	port := os.args[1].int()
	mut app := &App{
		port: port
	}

	println('Starting Tabua Mare API on port ${app.port}')
	veb.run[App, web_ctx.WebCtx](mut app, app.port)
}
