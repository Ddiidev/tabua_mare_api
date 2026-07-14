module main

import shareds.conf_env

fn production_env() conf_env.EnvConfig {
	fake_secret := 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
	return conf_env.EnvConfig{
		url_env:                 'https://tabuamare.api.br'
		postgresql_conn_str:     'postgresql://user:password@postgres.example.com:5432/tabuamare'
		google_client_id:        '123456789012345678901234567890.apps.googleusercontent.com'
		google_client_secret:    'client-secret-' + fake_secret
		google_redirect_uri:     'https://tabuamare.api.br/auth/google/callback'
		session_secret:          'test-only-session-' + fake_secret
		stripe_secret_key:       'sk_' + 'live_' + fake_secret
		stripe_webhook_secret:   'whsec_' + fake_secret
		stripe_price_plan5:      'price_live_plan5'
		stripe_price_plan10:     'price_live_plan10'
		stripe_price_planannual: 'price_live_planannual'
	}
}

fn assert_invalid(env conf_env.EnvConfig, expected string) {
	conf_env.validate_startup(env) or {
		assert err.msg().contains(expected)
		return
	}
	assert false, 'configuracao deveria ser rejeitada: ${expected}'
}

fn test_valid_production_config_is_accepted() ! {
	conf_env.validate_startup(production_env())!
}

fn test_localhost_config_does_not_require_production_secrets() ! {
	conf_env.validate_startup(conf_env.EnvConfig{
		url_env: 'http://localhost:3330'
	})!
}

fn test_production_rejects_missing_or_weak_session_secret() {
	missing := conf_env.EnvConfig{
		...production_env()
		session_secret: ''
	}
	assert_invalid(missing, 'SESSION_SECRET')

	weak := conf_env.EnvConfig{
		...production_env()
		session_secret: 'change-me'
	}
	assert_invalid(weak, 'SESSION_SECRET')

	template_placeholder := conf_env.EnvConfig{
		...production_env()
		session_secret: '[PRECISA PREENCHER - 32+ bytes aleatorios]'
	}
	assert_invalid(template_placeholder, 'SESSION_SECRET')
}

fn test_production_rejects_missing_postgres_and_google_config() {
	no_pg := conf_env.EnvConfig{
		...production_env()
		postgresql_conn_str: ''
	}
	assert_invalid(no_pg, 'POSTGRESQL_CONN_STR')

	no_google := conf_env.EnvConfig{
		...production_env()
		google_client_id: ''
	}
	assert_invalid(no_google, 'GOOGLE_CLIENT_ID')

	placeholder_google_id := conf_env.EnvConfig{
		...production_env()
		google_client_id: '[PRECISA PREENCHER]'
	}
	assert_invalid(placeholder_google_id, 'GOOGLE_CLIENT_ID')

	placeholder_google_secret := conf_env.EnvConfig{
		...production_env()
		google_client_secret: '[PRECISA PREENCHER]'
	}
	assert_invalid(placeholder_google_secret, 'GOOGLE_CLIENT_SECRET')

	short_google_id := conf_env.EnvConfig{
		...production_env()
		google_client_id: 'short-client-id'
	}
	assert_invalid(short_google_id, 'GOOGLE_CLIENT_ID')

	short_google_secret := conf_env.EnvConfig{
		...production_env()
		google_client_secret: 'short-secret'
	}
	assert_invalid(short_google_secret, 'GOOGLE_CLIENT_SECRET')

	wrong_redirect := conf_env.EnvConfig{
		...production_env()
		google_redirect_uri: 'http://localhost:3330/auth/google/callback'
	}
	assert_invalid(wrong_redirect, 'GOOGLE_REDIRECT_URI')
}

fn test_production_rejects_non_live_stripe_and_invalid_prices() {
	test_key := conf_env.EnvConfig{
		...production_env()
		stripe_secret_key: 'sk_test_example'
	}
	assert_invalid(test_key, 'STRIPE_SECRET_KEY')

	no_webhook := conf_env.EnvConfig{
		...production_env()
		stripe_webhook_secret: ''
	}
	assert_invalid(no_webhook, 'STRIPE_WEBHOOK_SECRET')

	prefix_only_key := conf_env.EnvConfig{
		...production_env()
		stripe_secret_key: 'sk_live_'
	}
	assert_invalid(prefix_only_key, 'STRIPE_SECRET_KEY')

	prefix_only_webhook := conf_env.EnvConfig{
		...production_env()
		stripe_webhook_secret: 'whsec_'
	}
	assert_invalid(prefix_only_webhook, 'STRIPE_WEBHOOK_SECRET')

	no_price := conf_env.EnvConfig{
		...production_env()
		stripe_price_plan5: ''
	}
	assert_invalid(no_price, 'STRIPE_PRICE_PLAN5')

	prefix_only_price := conf_env.EnvConfig{
		...production_env()
		stripe_price_plan5: 'price_'
	}
	assert_invalid(prefix_only_price, 'STRIPE_PRICE_PLAN5')

	duplicate_prices := conf_env.EnvConfig{
		...production_env()
		stripe_price_plan10: 'price_live_plan5'
	}
	assert_invalid(duplicate_prices, 'Stripe prices')
}
