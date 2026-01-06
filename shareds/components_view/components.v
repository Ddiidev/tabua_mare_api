module components_view

import veb
import time

pub struct ComponentsView {}

pub fn (cv ComponentsView) footer() veb.RawHtml {
	year := time.now().year
	return $tmpl('../../pages/footer.html')
}
