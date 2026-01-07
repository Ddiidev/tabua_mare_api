module components_view

import veb
import leafscale.veemarker

pub fn (cv ComponentsView) open_graph(data map[string]veemarker.Any) string {
	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir: './pages'
		dev_mode:     true
	})

	return engine.render('og.html', data) or { '' }
}
