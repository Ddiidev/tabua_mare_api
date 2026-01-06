module types

pub type StringRange = string

// list_string Retorna uma lista de strings a partir de uma string com range de valores separados por vírgula.
pub fn (ids StringRange) list_string() ![]string {
	if !ids.starts_with('[') || !ids.ends_with(']') {
		return error('Erro sintático: A lista deve começar com "[" e terminar com "]".')
	}

	content := ids[1..ids.len - 1]
	if content.trim_space() == '' {
		return []string{}
	}

	mut inters := []string{}
	parts := content.split(',')

	for i, raw_part in parts {
		part := raw_part.trim_space()

		if part == '' {
			return error('Erro sintático: Item vazio encontrado na posição ${i + 1}.')
		}

		// Validação manual: 2 letras + 2 dígitos
		if part.len != 4 {
			return error('Erro sintático no item "${part}" (posição ${i + 1}): Formato inválido. Esperado 2 letras seguidas de 2 dígitos (ex: pb01).')
		}

		if !part[0].is_letter() || !part[1].is_letter() {
			return error('Erro sintático no item "${part}" (posição ${i + 1}): Os dois primeiros caracteres devem ser letras.')
		}

		if !part[2].is_digit() || !part[3].is_digit() {
			return error('Erro sintático no item "${part}" (posição ${i + 1}): Os dois últimos caracteres devem ser números.')
		}

		inters << part
	}
	return inters
}
