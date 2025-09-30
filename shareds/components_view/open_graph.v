module components_view

import veb

pub fn (cv ComponentsView) open_graph() veb.RawHtml {
	return $tmpl('../../pages/og.html')
}
