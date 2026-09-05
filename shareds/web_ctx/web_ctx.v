module web_ctx

import veb
import veb.request_id
import domain.auth_user
import shareds.types

pub enum PageRepresentation {
	html
	markdown
	not_acceptable
}

struct MediaPreference {
	quality     f64
	specificity int
	position    int
}

pub struct WsCtx {
	veb.Context
	request_id.RequestIdContext
pub mut:
	current_user ?auth_user.JwtClaims
	api_key      string
	ip           string
	plan         string
}

// select_page_representation escolhe entre as representacoes HTML e Markdown
// respeitando quality values, especificidade e ordem do header Accept.
pub fn select_page_representation(accept string) PageRepresentation {
	if accept.trim_space() == '' {
		return .html
	}

	markdown := best_media_preference(accept, 'text/markdown')
	html := best_media_preference(accept, 'text/html')
	if markdown == none && html == none {
		return .not_acceptable
	}
	if markdown == none {
		html_preference := html or { return .not_acceptable }
		return if html_preference.quality > 0 { .html } else { .not_acceptable }
	}
	if html == none {
		markdown_preference := markdown
		return if markdown_preference.quality > 0 { .markdown } else { .not_acceptable }
	}

	markdown_preference := markdown
	html_preference := html
	if markdown_preference.quality <= 0 && html_preference.quality <= 0 {
		return .not_acceptable
	}
	if markdown_preference.quality != html_preference.quality {
		return if markdown_preference.quality > html_preference.quality { .markdown } else { .html }
	}
	if markdown_preference.specificity != html_preference.specificity {
		return if markdown_preference.specificity > html_preference.specificity {
			.markdown
		} else {
			.html
		}
	}
	return if markdown_preference.position < html_preference.position { .markdown } else { .html }
}

fn best_media_preference(accept string, target string) ?MediaPreference {
	mut best := MediaPreference{
		quality: -1
		specificity: -1
		position: accept.len
	}
	for position, raw_range in accept.split(',') {
		parts := raw_range.split(';')
		media_range := parts[0].trim_space().to_lower()
		specificity := media_range_specificity(media_range, target)
		if specificity < 0 {
			continue
		}
		candidate := MediaPreference{
			quality: media_range_quality(parts)
			specificity: specificity
			position: position
		}
		if candidate.specificity > best.specificity
			|| (candidate.specificity == best.specificity && candidate.position < best.position) {
			best = candidate
		}
	}
	if best.specificity < 0 {
		return none
	}
	return best
}

fn media_range_specificity(media_range string, target string) int {
	if media_range == target {
		return 2
	}
	if media_range == '*/*' {
		return 0
	}
	parts := target.split('/')
	if parts.len == 2 && media_range == '${parts[0]}/*' {
		return 1
	}
	return -1
}

fn media_range_quality(parts []string) f64 {
	for parameter in parts[1..] {
		name_value := parameter.split('=')
		if name_value.len != 2 || name_value[0].trim_space().to_lower() != 'q' {
			continue
		}
		quality := name_value[1].trim_space().f64()
		return if quality >= 0 && quality <= 1 { quality } else { 0 }
	}
	return 1
}

pub fn (mut ctx WsCtx) not_found() veb.Result {
	ctx.res.set_status(.not_found)
	if ctx.req.url.starts_with('/api/') {
		return ctx.json(types.failure_with_resolution[string](404, 'Endpoint nao encontrado', 'Consulte /openapi.json ou /docs para localizar uma rota e parametros validos.'))
	}
	ctx.res.header.set(.vary, 'Accept, Accept-Encoding')
	return ctx.send_response_to_client('text/markdown; charset=utf-8', '# Recurso nao encontrado\n\n- [Documentacao da Tábua de Maré API](/docs)\n- [OpenAPI](/openapi.json)\n- [Instrucoes para agentes](/llms.txt)\n- [Mapa do site](/sitemap.xml)\n')
}
