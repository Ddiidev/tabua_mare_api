module main

import os
import veb
import cache
import shareds.logger
import shareds.web_ctx
import shareds.infradb
import shareds.conf_env
import shareds.components_view

struct App {
	veb.Controller
	veb.StaticHandler
	components_view.ComponentsView
	env shared conf_env.EnvConfig
}

fn main() {
	at_exit(on_panic)!

	if os.args.len < 2 {
		println('Usage: tabua-mare-api <port>')
		return
	}
	port := os.args[1].int()
	env := conf_env.EnvConfig{
		...conf_env.load_env()
		current_port: port.str()
	}

	mut app := &App{
		env: env
	}
	mut api_controller := &APIController{
		pool_conn: infradb.new()!
		cache:     cache.Cache{}
		log:       logger.Logger.new(port.str())!
		env:       env
	}

	api_controller.init_cors()

	app.register_controller[APIController, web_ctx.WsCtx]('/api/v1', mut api_controller)!
	app.mount_static_folder_at('./pages/assets', '/pages/assets')!

	println('Starting Tabua Mare API on port ${port}')
	veb.run[App, web_ctx.WsCtx](mut app, port)
}

@['/']
pub fn (app &App) index(mut ctx web_ctx.WsCtx) veb.Result {
	dump(ctx.ip())
	return $veb.html('./pages/index.html')
}

@['/docs']
pub fn (app &App) docs(mut ctx web_ctx.WsCtx) veb.Result {
	url_env := rlock app.env {
		'${app.env.url_env}/api/v1'
	}
	return $veb.html('./pages/docs.html')
}

@['/playground']
pub fn (app &App) playground(mut ctx web_ctx.WsCtx) veb.Result {
	return $veb.html('./pages/playground.html')
}

@['/apoiar']
pub fn (app &App) apoiar(mut ctx web_ctx.WsCtx) veb.Result {
	return $veb.html('./pages/apoiar.html')
}

@['/ping'; head]
pub fn (app &App) ping(mut ctx web_ctx.WsCtx) veb.Result {
	ctx.conn.write_string('HTTP/1.1 200 OK') or {}
	return ctx.no_content()
}
