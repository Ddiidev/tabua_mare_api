module main

import net.http
import os
import veb
import shareds.types
import shareds.web_ctx

fn agentic_context(path string, accept string) web_ctx.WsCtx {
	mut header := http.new_header()
	if accept != '' {
		header.set(.accept, accept)
	}
	return web_ctx.WsCtx{
		Context: veb.Context{
			req: http.Request{
				url: path
				header: header
			}
		}
	}
}

fn test_markdown_negotiation_respects_accept_preferences() {
	assert web_ctx.select_page_representation('') == .html
	assert web_ctx.select_page_representation('text/markdown;q=1, text/html;q=0.5') == .markdown
	assert web_ctx.select_page_representation('text/html;q=1, text/markdown;q=1') == .html
	assert web_ctx.select_page_representation('text/*;q=0.6, text/markdown;q=0.6') == .markdown
	assert web_ctx.select_page_representation('*/*') == .html
	assert web_ctx.select_page_representation('text/markdown;q=0') == .not_acceptable
	assert web_ctx.select_page_representation('application/json') == .not_acceptable
}

fn test_homepage_markdown_contract_is_available() {
	assert agent_home_markdown.starts_with('# Tábua de Maré API')
	assert agent_home_markdown.contains('/openapi.json')
	assert agent_home_markdown.contains('/llms.txt')
	assert web_ctx.select_page_representation('text/markdown') == .markdown
	assert web_ctx.select_page_representation('application/json') == .not_acceptable
}

fn test_not_found_uses_markdown_for_site_and_json_for_api() {
	mut site_ctx := agentic_context('/missing', '')
	site_ctx.not_found()
	assert site_ctx.res.status_code == int(http.Status.not_found)
	assert site_ctx.res.header.get(.content_type) or { '' } == 'text/markdown; charset=utf-8'
	assert site_ctx.res.body.contains('[OpenAPI](/openapi.json)')
	assert site_ctx.res.body.contains('[Instrucoes para agentes](/llms.txt)')

	mut api_ctx := agentic_context('/api/v2/missing', '')
	api_ctx.not_found()
	assert api_ctx.res.status_code == int(http.Status.not_found)
	assert api_ctx.res.header.get(.content_type) or { '' } == 'application/json'
	assert api_ctx.res.body.contains('"code":404')
	assert api_ctx.res.body.contains('"message":"Endpoint nao encontrado"')
	assert api_ctx.res.body.contains('"resolution":')
}

fn test_api_errors_include_resolution() {
	error_response := types.failure[string](429, 'Limite por minuto excedido')
	assert error_response.error != none
	assert error_response.error?.code == 429
	assert error_response.error?.resolution.contains('Retry-After')
}

fn test_agent_machine_readable_resources_are_well_formed() ! {
	openapi_source := os.read_file('pages/static/openapi.json')!
	assert openapi_source.contains('"openapi": "3.1.1"')
	assert openapi_source.contains('"title": "Tábua de Maré API"')
	assert openapi_source.contains('"/api/v2/states"')
	assert openapi_source.contains('"/api/v2/usage"')
	assert openapi_source.contains('"resolution"')

	llms := os.read_file('pages/static/llms.txt')!
	assert llms.starts_with('# Tábua de Maré API\n\n> ')
	assert llms.contains('**Quando usar:**')
	assert llms.contains('[Especificação OpenAPI 3.1](https://tabuamare.api.br/openapi.json)')

	og := os.read_file('pages/og.html')!
	assert og.contains('"@type": "Organization"')
	assert og.contains('"url": "https://tabuamare.api.br"')
	assert og.contains('"sameAs": [')
	assert og.contains('"logo": {')
}
