module main

import os
import veb
import shareds.web_ctx
import shareds.infradb
import shareds.conf_env
import leafscale.veemarker
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
		env:       env
	}

	mut api_controller_v2 := &APIControllerV2{
		pool_conn: infradb.new()!
		env:       env
	}

	api_controller.init_cors()

	app.register_controller[APIController, web_ctx.WsCtx]('/api/v1', mut api_controller)!
	app.register_controller[APIControllerV2, web_ctx.WsCtx]('/api/v2', mut api_controller_v2)!
	app.mount_static_folder_at('./pages/assets', '/pages/assets')!

	println('Starting Tabua Mare API on port ${port}')
	veb.run[App, web_ctx.WsCtx](mut app, port)
}

@['/']
pub fn (app &App) index(mut ctx web_ctx.WsCtx) veb.Result {
	dump(ctx.ip())
	mut data := map[string]veemarker.Any{}
	data['navbar'] = app.navbar('/')
	data['og'] = app.open_graph(data)
	data['footer'] = app.footer()

	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir:  './pages'
		cache_enabled: true
	})

	return ctx.html(engine.render('index.html', data) or { '' })
}

@['/docs']
pub fn (app &App) docs(mut ctx web_ctx.WsCtx) veb.Result {
	mut data := map[string]veemarker.Any{}

	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir:  './pages'
		cache_enabled: true
	})
	data['og'] = app.open_graph(data)
	data['navbar'] = app.navbar('/docs')
	data['footer'] = app.footer()

	url_env := rlock app.env {
		app.env.url_env
	}
	data['url_env'] = url_env
	return ctx.html(engine.render('docs.html', data) or { '' })
}

@['/playground']
pub fn (app &App) playground(mut ctx web_ctx.WsCtx) veb.Result {
	mut data := map[string]veemarker.Any{}
	data['navbar'] = app.navbar('/playground')
	data['og'] = app.open_graph(data)
	data['footer'] = app.footer()

	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir:  './pages'
		cache_enabled: true
	})
	return ctx.html(engine.render('playground.html', data) or { '' })
}

@['/apoiar']
pub fn (app &App) apoiar(mut ctx web_ctx.WsCtx) veb.Result {
	mut data := map[string]veemarker.Any{}
	data['navbar'] = app.navbar('/apoiar')
	data['og'] = app.open_graph(data)
	data['footer'] = app.footer()

	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir:  './pages'
		cache_enabled: true
	})
	return ctx.html(engine.render('apoiar.html', data) or { '' })
}

@['/ping'; head]
pub fn (app &App) ping(mut ctx web_ctx.WsCtx) veb.Result {
	ctx.conn.write_string('HTTP/1.1 200 OK') or {}
	return ctx.no_content()
}
