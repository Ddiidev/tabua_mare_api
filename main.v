module main

import os
import pool
import sync.stdatomic
import time
import veb
import shareds.web_ctx
import shareds.health
import shareds.infradb
import shareds.infradb_pg
import shareds.conf_env
import leafscale.veemarker
import shareds.components_view
import domain.auth_user

const shutdown_requested = stdatomic.new_atomic[bool](false)

struct App {
	veb.Controller
	veb.StaticHandler
	components_view.ComponentsView
	env shared conf_env.EnvConfig
mut:
	health_state &health.State
	health_pool  &pool.ConnectionPool
	server_ready chan &veb.Server
}

fn request_shutdown(_ os.Signal) {
	mut requested := shutdown_requested
	requested.store(true)
}

fn wait_for_shutdown(state &health.State, server_ready chan &veb.Server) {
	server := <-server_ready
	mut requested := shutdown_requested
	for !requested.load() {
		time.sleep(50 * time.millisecond)
	}

	state.begin_shutdown()
	time.sleep(6 * time.second)
	server.shutdown(timeout: 20 * time.second) or { eprintln('Graceful shutdown failed: ${err}') }
}

pub fn (mut app App) init_server(server &veb.Server) {
	app.server_ready <- server
}

pub fn (mut app App) before_accept_loop() {
	app.health_state.mark_ready()

	mut requested := shutdown_requested
	if requested.load() {
		app.health_state.begin_shutdown()
	}
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
	conf_env.validate_startup(env) or {
		eprintln('Configuracao de startup invalida: ${err}')
		exit(1)
	}

	infradb.apply_startup_migrations() or { eprintln('Startup migration skipped: ${err}') }
	infradb_pg.apply_pg_startup_migrations() or {
		if conf_env.is_production(env) {
			eprintln('PG startup migration failed: ${err}')
			exit(1)
		}
		eprintln('PG startup migration skipped: ${err}')
	}

	mut app := &App{
		env:          env
		health_state: health.new_state()
		health_pool:  infradb.new()!
		server_ready: chan &veb.Server{cap: 1}
	}

	mut api_controller := &APIController{
		pool_conn: infradb.new()!
		env:       env
	}

	mut api_controller_v2 := &APIControllerV2{
		pool_conn: infradb.new()!
		env:       env
	}

	mut auth_controller := &AuthController{
		env:          env
		avatar_cache: auth_user.new_avatar_cache(env.avatar_cache_ttl_minutes)
	}

	api_controller.init_cors()
	api_controller_v2.init_cors()
	api_controller_v2.init_rate_limit(env)

	app.register_controller[APIController, web_ctx.WsCtx]('/api/v1', mut api_controller)!
	app.register_controller[APIControllerV2, web_ctx.WsCtx]('/api/v2', mut api_controller_v2)!
	app.register_controller[AuthController, web_ctx.WsCtx]('/auth', mut auth_controller)!
	app.mount_static_folder_at('./pages/assets', '/pages/assets')!
	os.signal_opt(.term, request_shutdown) or {
		panic('Failed to register SIGTERM handler: ${err}')
	}
	spawn wait_for_shutdown(app.health_state, app.server_ready)

	println('Starting Tabua Mare API on port ${port}')
	veb.run[App, web_ctx.WsCtx](mut app, port)
}

fn (app &App) is_logged_in(mut ctx web_ctx.WsCtx) bool {
	cookie_name := rlock app.env {
		app.env.session_cookie_name
	}
	secret := rlock app.env {
		app.env.session_secret
	}
	if secret == '' {
		return false
	}
	token := ctx.get_cookie(cookie_name) or { return false }
	return auth_user.verify(secret, token)
}

@['/']
pub fn (app &App) index(mut ctx web_ctx.WsCtx) veb.Result {
	mut data := map[string]veemarker.Any{}
	data['navbar'] = app.navbar('/', app.is_logged_in(mut ctx))
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
	data['navbar'] = app.navbar('/docs', app.is_logged_in(mut ctx))
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
	data['navbar'] = app.navbar('/playground', app.is_logged_in(mut ctx))
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
	data['navbar'] = app.navbar('/apoiar', app.is_logged_in(mut ctx))
	data['og'] = app.open_graph(data)
	data['footer'] = app.footer()

	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir:  './pages'
		cache_enabled: true
	})
	return ctx.html(engine.render('apoiar.html', data) or { '' })
}

@['/privacidade']
pub fn (app &App) privacidade(mut ctx web_ctx.WsCtx) veb.Result {
	mut data := map[string]veemarker.Any{}
	data['navbar'] = app.navbar('/privacidade', app.is_logged_in(mut ctx))
	data['og'] = app.open_graph(data)
	data['footer'] = app.footer()

	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir:  './pages'
		cache_enabled: true
	})
	return ctx.html(engine.render('privacidade.html', data) or { '' })
}

@['/termos']
pub fn (app &App) termos(mut ctx web_ctx.WsCtx) veb.Result {
	mut data := map[string]veemarker.Any{}
	data['navbar'] = app.navbar('/termos', app.is_logged_in(mut ctx))
	data['og'] = app.open_graph(data)
	data['footer'] = app.footer()

	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir:  './pages'
		cache_enabled: true
	})
	return ctx.html(engine.render('termos.html', data) or { '' })
}

@['/rate-limit-test']
pub fn (app &App) rate_limit_test(mut ctx web_ctx.WsCtx) veb.Result {
	mut data := map[string]veemarker.Any{}
	data['navbar'] = app.navbar('', app.is_logged_in(mut ctx))
	data['og'] = app.open_graph(data)
	data['footer'] = app.footer()

	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir:  './pages'
		cache_enabled: true
	})
	return ctx.html(engine.render('rate_limit_test.html', data) or { '' })
}

@['/dashboard']
pub fn (app &App) dashboard(mut ctx web_ctx.WsCtx) veb.Result {
	if !app.is_logged_in(mut ctx) {
		return ctx.redirect('/auth/google?next=/dashboard', veb.RedirectParams{ typ: .found })
	}
	mut data := map[string]veemarker.Any{}
	data['navbar'] = app.navbar('/dashboard', true)
	data['og'] = app.open_graph(data)
	data['footer'] = app.footer()

	url_env := rlock app.env {
		app.env.url_env
	}
	data['url_env'] = url_env

	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir:  './pages'
		cache_enabled: true
	})
	return ctx.html(engine.render('dashboard.html', data) or { '' })
}

@['/ping'; get; head]
pub fn (app &App) ping(mut ctx web_ctx.WsCtx) veb.Result {
	ctx.res.set_status(.ok)
	return ctx.no_content()
}

@['/health/live'; get; head]
pub fn (app &App) health_live(mut ctx web_ctx.WsCtx) veb.Result {
	return ctx.no_content()
}

@['/health/ready'; get; head]
pub fn (mut app App) health_ready(mut ctx web_ctx.WsCtx) veb.Result {
	connstr := rlock app.env {
		app.env.postgresql_conn_str
	}
	if app.health_state.is_ready_with_dependencies(infradb.sqlite_is_healthy(mut app.health_pool),
		infradb_pg.is_healthy(connstr))
	{
		return ctx.no_content()
	}

	ctx.res.set_status(.service_unavailable)
	return ctx.send_response_to_client('', '')
}
