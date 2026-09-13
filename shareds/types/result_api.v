module types

pub struct ErrorAPI {
pub:
	code       int
	message    string
	resolution string
}

pub struct ResultAPI[T] {
pub:
	data  []T
	total int
	error ?ErrorAPI @[omitempty]
}

pub fn success[T](data []T) ResultAPI[T] {
	return ResultAPI[T]{
		data: data
		total: data.len
	}
}

pub fn failure[T](code int, message string) ResultAPI[T] {
	return failure_with_resolution[T](code, message, resolution_for_status(code))
}

pub fn failure_with_resolution[T](code int, message string, resolution string) ResultAPI[T] {
	return ResultAPI[T]{
		data: []T{}
		total: 0
		error: ErrorAPI{
			code: code
			message: message
			resolution: resolution
		}
	}
}

fn resolution_for_status(code int) string {
	return match code {
		400 { 'Revise os parametros e o formato da requisicao.' }
		401 { 'Envie uma API key valida ou autentique-se antes de tentar novamente.' }
		403 { 'Revise as permissoes e o plano associado a conta.' }
		404 { 'Consulte /openapi.json ou /docs para localizar uma rota e parametros validos.' }
		410 { 'Use a versao atual da API em /api/v2.' }
		429 { 'Aguarde o periodo indicado em Retry-After antes de repetir a requisicao.' }
		503 { 'Tente novamente em instantes; se persistir, consulte /health/ready.' }
		else { 'Tente novamente ou consulte /docs para orientacao de integracao.' }
	}
}
