module resend

import net.http
import json2
import time

pub struct Client {
pub:
	api_key    string
	endpoint   string = 'https://api.resend.com/emails'
	timeout_ms int    = 8000
}

pub struct Attachment {
pub:
	filename   string
	content    string
	content_id string
}

@[params]
pub struct ContentEmail {
pub:
	from        string   @[required]
	to          []string @[required]
	subject     string   @[required]
	html        string   @[required]
	text        string
	reply_to    string
	attachments []Attachment
}

struct SendResponse {
	id string
}

// Retorna o id de aceite do provedor; nao confirma entrega na caixa de entrada.
pub fn (client Client) send(content ContentEmail, idempotency_key string) !string {
	if client.api_key.trim_space() == '' {
		return error('Resend nao configurado')
	}
	mut header := http.new_header_from_map({
		.authorization: 'Bearer ${client.api_key}'
		.content_type:  'application/json'
	})
	header.add_custom('Idempotency-Key', idempotency_key)!
	response := http.fetch(http.FetchConfig{
		method:                   .post
		url:                      client.endpoint
		header:                   header
		data:                     json2.encode(content)
		read_timeout:             i64(client.timeout_ms) * time.millisecond
		write_timeout:            i64(client.timeout_ms) * time.millisecond
		max_retries:              1 // A versao V fixada conta tentativas totais; 1 = sem retry.
		allow_redirect:           false
		validate:                 true
		disable_connection_reuse: true
	}) or {
		// Nao registrar request, chave, payload ou corpo de resposta do provedor.
		return error('falha de transporte no Resend')
	}
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Resend retornou HTTP ${response.status_code}')
	}
	result := json2.decode[SendResponse](response.body) or {
		return error('resposta invalida do Resend')
	}
	if result.id == '' {
		return error('Resend retornou resposta sem id')
	}
	return result.id
}
