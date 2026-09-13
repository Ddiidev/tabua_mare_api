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
		stripe_price_plan15:  'price_plan15'
		stripe_price_plan70:  'price_plan70'
		stripe_price_plan30:  'price_plan30'
		stripe_price_plan150: 'price_plan150'
	}
	assert stripe_price_id(env, 'plan15') or { '' } == 'price_plan15'
	assert stripe_price_id(env, 'plan70') or { '' } == 'price_plan70'
	assert stripe_price_id(env, 'plan30') or { '' } == 'price_plan30'
	assert stripe_price_id(env, 'plan150') or { '' } == 'price_plan150'
	assert stripe_price_id(env, 'free') or { '' } == ''
}
