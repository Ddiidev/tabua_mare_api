module main

import shareds.conf_env

fn test_safe_redirect_path_accepts_only_local_paths() {
	assert safe_redirect_path('/dashboard') == '/dashboard'
	assert safe_redirect_path('/docs?from=oauth') == '/docs?from=oauth'
	assert safe_redirect_path('') == '/'
	assert safe_redirect_path('dashboard') == '/'
	assert safe_redirect_path('https://evil.example/') == '/'
	assert safe_redirect_path('//evil.example/') == '/'
}

fn test_stripe_price_id_is_selected_from_plan() {
	env := conf_env.EnvConfig{
		stripe_price_plan5:      'price_plan5'
		stripe_price_plan10:     'price_plan10'
		stripe_price_planannual: 'price_annual'
	}
	assert stripe_price_id(env, 'plan5') or { '' } == 'price_plan5'
	assert stripe_price_id(env, 'plan10') or { '' } == 'price_plan10'
	assert stripe_price_id(env, 'planannual') or { '' } == 'price_annual'
	assert stripe_price_id(env, 'free') or { '' } == ''
}
