module main

import encoding.base64
import json2
import net
import net.http
import shareds.email.resend
import time

struct ResendMock {
	requests chan http.Request
}

fn (mut mock ResendMock) handle(request http.Request) http.Response {
	mock.requests <- request
	match request.url {
		'/emails' {
			return http.new_response(body: '{"id":"local-email-id"}')
		}
		'/invalid' {
			return http.new_response(body: '{broken')
		}
		'/empty' {
			return http.new_response(body: '{}')
		}
		'/slow' {
			time.sleep(200 * time.millisecond)
			return http.new_response(body: '{"id":"too-late"}')
		}
		'/redirect' {
			mut response := http.new_response(status: .temporary_redirect)
			response.header.set(.location, '/emails')
			return response
		}
		else {
			return http.new_response(status: .too_many_requests, body: 'private provider details')
		}
	}
}

fn test_resend_request_and_failures_without_external_delivery() ! {
	listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	port := listener.addr()!.port()!
	requests := chan http.Request{cap: 10}
	mut server := &http.Server{
		listener:             listener
		handler:              ResendMock{
			requests: requests
		}
		show_startup_message: false
		accept_timeout:       50 * time.millisecond
		worker_num:           1
	}
	server_thread := spawn server.listen_and_serve()
	server.wait_till_running()!
	defer {
		server.close()
		server_thread.wait()
	}
	content := resend.welcome_email('fixture@example.invalid',
		'Tábua de Marés API <contato@tabuamare.api.br>', 'contato@tabuamare.api.br',
		'https://tabuamare.api.br/')!
	client := resend.Client{
		api_key:  'local-secret'
		endpoint: 'http://127.0.0.1:${port}/emails'
	}
	assert client.send(content, 'welcome-user/42')! == 'local-email-id'
	request := <-requests
	assert request.method == .post
	assert (request.header.get(.authorization) or { '' }) == 'Bearer local-secret'
	assert (request.header.get(.content_type) or { '' }) == 'application/json'
	assert (request.header.get_custom('Idempotency-Key') or { '' }) == 'welcome-user/42'
	payload := json2.decode[resend.ContentEmail](request.data)!
	assert payload.to == ['fixture@example.invalid']
	assert payload.reply_to == 'contato@tabuamare.api.br'
	assert payload.subject == 'Cadastro confirmado | Tábua de Marés API'
	assert payload.html.contains('src="cid:welcome-banner"')
	assert payload.html.contains('href="https://tabuamare.api.br/dashboard"')
	assert !payload.html.contains('{{APP_URL}}')
	assert payload.text.contains('https://tabuamare.api.br/docs')
	assert payload.attachments.len == 1
	assert payload.attachments[0].content_id == 'welcome-banner'
	image := base64.decode(payload.attachments[0].content)
	assert image.len > 1000 && image.len < 300000
	assert image[0] == 0xff && image[1] == 0xd8 // JPEG real.

	for path, expected in {
		'rejected': 'Resend retornou HTTP 429'
		'invalid':  'resposta invalida do Resend'
		'empty':    'Resend retornou resposta sem id'
		'redirect': 'Resend retornou HTTP 307'
	} {
		bad_client := resend.Client{
			api_key:  'local-secret'
			endpoint: 'http://127.0.0.1:${port}/${path}'
		}
		if _ := bad_client.send(content, 'welcome-user/42') {
			assert false, 'resposta deveria falhar: ${path}'
		} else {
			assert err.msg() == expected
		}
		_ = <-requests
	}
	slow_client := resend.Client{
		api_key:    'local-secret'
		endpoint:   'http://127.0.0.1:${port}/slow'
		timeout_ms: 30
	}
	if _ := slow_client.send(content, 'welcome-user/42') {
		assert false, 'timeout deveria falhar'
	} else {
		assert err.msg() == 'falha de transporte no Resend'
	}
	_ = <-requests
	assert requests.len == 0 // Nem retries ocultos, nem redirect seguido.
	if _ := (resend.Client{}).send(content, 'welcome-user/42') {
		assert false
	} else {
		assert err.msg() == 'Resend nao configurado'
	}
}

fn test_welcome_rejects_non_origin_links() {
	for app_url in ['javascript:alert(1)', '//example.invalid', '',
		'https://user:password@example.invalid', 'https://example.invalid/path',
		'https://example.invalid?next=x', 'https://example.invalid#fragment'] {
		if _ := resend.welcome_email('fixture@example.invalid', 'sender@example.invalid',
			'reply@example.invalid', app_url)
		{
			assert false, 'origem invalida aceita: ${app_url}'
		}
	}
}
