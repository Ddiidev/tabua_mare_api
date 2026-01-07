module components_view

import leafscale.veemarker

pub fn (cv ComponentsView) navbar(current_page string) string {
	is_root := current_page == '/'
	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir: './pages'
		dev_mode:     true
	})
	return engine.render('navbar.html', {
		'is_root':      is_root
		'current_page': current_page
	}) or { '' }
}
