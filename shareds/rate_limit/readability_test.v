module rate_limit

import shareds.conf_env

fn test_effective_plan_downgrades_a_key_to_user_plan() {
	assert effective_plan('plan30', 'free') == 'free'
	assert effective_plan('plan15', 'plan30') == 'plan15'
	assert effective_plan('free', 'free') == 'free'
}

fn test_plan_limits_per_plan() {
	env := conf_env.EnvConfig{
		rate_limit_free_rpm:       24
		rate_limit_free_monthly:   32000
		rate_limit_plan15_rpm:     512
		rate_limit_plan15_monthly: 256000
		rate_limit_plan30_rpm:     2048
		rate_limit_plan30_monthly: 0
		rate_limit_anon_rpm:       16
		rate_limit_anon_monthly:   0
	}
	rpm, monthly := plan_limits(env, 'anon')
	assert rpm == 16 && monthly == 0
	rpm2, monthly2 := plan_limits(env, 'free')
	assert rpm2 == 24 && monthly2 == 32000
	rpm3, monthly3 := plan_limits(env, 'plan15')
	assert rpm3 == 512 && monthly3 == 256000
	rpm4, monthly4 := plan_limits(env, 'plan70')
	assert rpm4 == 512 && monthly4 == 256000
	rpm5, monthly5 := plan_limits(env, 'plan30')
	assert rpm5 == 2048 && monthly5 == 0
	rpm6, monthly6 := plan_limits(env, 'plan150')
	assert rpm6 == 2048 && monthly6 == 0
}

fn test_is_plan_allowed_per_tier() {
	assert is_plan_allowed('free', 'free')
	assert is_plan_allowed('plan15', 'plan15')
	assert is_plan_allowed('plan15', 'plan70')
	assert is_plan_allowed('plan15', 'plan30')
	assert is_plan_allowed('plan15', 'plan150')
	assert !is_plan_allowed('plan70', 'plan15')
	assert is_plan_allowed('plan30', 'plan30')
	assert !is_plan_allowed('plan30', 'plan15')
	assert is_plan_allowed('plan150', 'plan150')
	assert !is_plan_allowed('plan150', 'plan30')
	assert !is_plan_allowed('plan15', 'free')
}
