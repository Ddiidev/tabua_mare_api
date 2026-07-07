module components_view

import leafscale.veemarker

pub fn (cv ComponentsView) navbar(current_page string, is_logged_in bool) string {
	is_root := current_page == '/'
	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir: './pages'
		dev_mode:     true
	})
	return engine.render('navbar.html', {
		'is_root':       is_root
		'current_page':  current_page
		'is_logged_in':  is_logged_in
	}) or { '' }
}
