module rate_limit

fn test_effective_plan_downgrades_a_key_to_user_plan() {
	assert effective_plan('plan10', 'free') == 'free'
	assert effective_plan('plan5', 'plan10') == 'plan5'
	assert effective_plan('free', 'free') == 'free'
}
