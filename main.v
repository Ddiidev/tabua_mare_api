module main

import os
import veb
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
	if os.args.len < 2 {
		println('Usage: v . <port>')
		return
	}
	port := os.args[1].int()
	env := conf_env.load_env()
	mut app := &App{
		env: env
	}
	mut api_controller := &APIController{
		pool_conn: infradb.new()!
		env:       env
	}

	app.register_controller[APIController, web_ctx.WsCtx]('/api/v1', mut api_controller)!
	app.mount_static_folder_at('./pages/assets', '/pages/assets')!

	println('Starting Tabua Mare API on port ${port}')
	veb.run[App, web_ctx.WsCtx](mut app, port)
}

@['/']
pub fn (app &App) index(mut ctx web_ctx.WsCtx) veb.Result {
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

@['/ping'; get]
pub fn (app &App) ping(mut ctx web_ctx.WsCtx) veb.Result {
	return ctx.ok('pong')
}
