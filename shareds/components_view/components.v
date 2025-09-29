module components_view

import veb
import shareds.constants

pub struct ComponentsView {}

pub fn (cv ComponentsView) footer() veb.RawHtml {
	year := constants.year
	return $tmpl('../../pages/footer.html')
}
