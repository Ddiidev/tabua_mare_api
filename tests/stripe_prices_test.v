module main

import shareds.conf_env

fn test_live_stripe_price_ids_are_the_production_defaults() {
	prices := conf_env.stripe_price_ids({
		'STRIPE_PRICE_PLAN5':      'price_dev_plan5'
		'STRIPE_PRICE_PLAN10':     'price_dev_plan10'
		'STRIPE_PRICE_PLANANNUAL': 'price_dev_planannual'
	})
	$if env_dev ? {
		assert prices.plan5 == 'price_dev_plan5'
		assert prices.plan10 == 'price_dev_plan10'
		assert prices.planannual == 'price_dev_planannual'
		return
	}
	assert prices.plan5 == 'price_1TsmqjLZ5gTFc3B29AhoC9fq'
	assert prices.plan10 == 'price_1TsmsxLZ5gTFc3B2xsbFW6L8'
	assert prices.planannual == 'price_1TsmtrLZ5gTFc3B2rQEaEmqY'
}
