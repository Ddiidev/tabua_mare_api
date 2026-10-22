module resend

import encoding.base64
import encoding.html
import net.urllib

// Conteudo e imagem incorporados no binario; envio independe de template remoto.
pub fn welcome_email(to string, from string, reply_to string, app_url string) !ContentEmail {
	base_url := app_url.trim_space().trim_right('/')
	url := urllib.parse(base_url) or { return error('URL_ENV invalida para email') }
	if url.scheme !in ['http', 'https'] || url.host == '' || base_url.contains('@')
		|| url.raw_query != '' || url.fragment != '' || url.path !in ['', '/'] {
		return error('URL_ENV deve ser a origem HTTP(S) da aplicacao')
	}
	contact_email := if from.contains('<') {
		from.all_after_last('<').all_before('>').trim_space()
	} else {
		from.trim_space()
	}
	return ContentEmail{
		from:        from
		to:          [to]
		reply_to:    reply_to
		subject:     'Cadastro confirmado | Tábua de Marés API'
		html:        $embed_file('welcome.html').to_string().replace('{{APP_URL}}',
			html.escape(base_url)).replace('{{CONTACT_MAILTO}}', html.escape('mailto:' +
			urllib.path_escape(contact_email))).replace('{{CONTACT_EMAIL}}',
			html.escape(contact_email))
		text:        'Cadastro confirmado | Tábua de Marés API\n\nO cadastro na Tábua de Marés API foi concluído. A conta está disponível para consultar dados de marés e integrar o serviço a aplicações e operações.\n\nPara iniciar:\n1. Acesse o painel para criar e gerenciar chaves de API: ${base_url}/dashboard\n2. Consulte os endpoints e exemplos na documentação: ${base_url}/docs\n3. Experimente as consultas no playground: ${base_url}/playground\n4. Acompanhe artigos sobre marés e integração com a API no blog: https://tabuamare.api.br/blog\n\nNo painel, também é possível acompanhar o consumo e consultar os planos disponíveis.\n\nSolicitações e contato\nPara relatar problemas ou sugerir melhorias: https://github.com/Ddiidev/tabua_mare_api/issues\nPara contato por email: ${contact_email}\nContato direto com André Luiz: andreluiz.ddev@gmail.com\n\nAtenciosamente,\nEquipe Tábua de Marés API\n${base_url}\n\nEsta mensagem foi enviada em razão do cadastro na plataforma. Se o cadastro não foi solicitado, desconsidere esta mensagem.'
		attachments: [
			Attachment{
				filename:   'tabua-de-mares-api.jpg'
				content:    base64.encode($embed_file('../../../pages/assets/images/welcome-banner.jpg').to_bytes())
				content_id: 'welcome-banner'
			},
		]
	}
}
