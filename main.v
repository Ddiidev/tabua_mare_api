module main

import veb
import shareds.web_ctx

struct App {}

fn main() {
	mut app := &App{}

	veb.run[App, web_ctx.WebCtx](mut app, 4048)
}
