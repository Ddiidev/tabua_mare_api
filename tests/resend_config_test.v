module main

import os
import shareds.conf_env

fn test_resend_key_precedence_and_legacy_fallback() {
	previous_key := os.getenv('RESEND_API_KEY')
	previous_alias := os.getenv('EMAIL_RESEND')
	defer {
		os.setenv('RESEND_API_KEY', previous_key, true)
		os.setenv('EMAIL_RESEND', previous_alias, true)
	}
	os.setenv('EMAIL_RESEND', ' legacy-fixture ', true)
	os.setenv('RESEND_API_KEY', ' primary-fixture ', true)
	assert conf_env.load_env().email_resend == 'primary-fixture'
	// Campo primario em branco nao deve mascarar a chave legada.
	os.setenv('RESEND_API_KEY', ' ', true)
	assert conf_env.load_env().email_resend == 'legacy-fixture'
	os.setenv('EMAIL_RESEND', ' ', true)
	assert conf_env.load_env().email_resend == ''
}
