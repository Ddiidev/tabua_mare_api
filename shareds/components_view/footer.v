module components_view

import veb
import time
import leafscale.veemarker

pub fn (cv ComponentsView) footer() string {
	mut engine := veemarker.new_engine(veemarker.EngineConfig{
		template_dir: './pages'
		dev_mode:     true
	})
	mut data := map[string]veemarker.Any{}
	data['year'] = time.now().year

	return engine.render('footer.html', data) or { '' }
}
