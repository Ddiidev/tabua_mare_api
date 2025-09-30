module components_view

import veb

pub fn (cv ComponentsView) navbar(current_page string) veb.RawHtml {
	is_root := current_page == '/'
	return $tmpl('../../pages/navbar.html')
}
