module main

import shareds.conf_env

fn test_live_stripe_price_ids_are_the_production_defaults() {
	prices := conf_env.stripe_price_ids({
		'STRIPE_PRICE_PLAN15':  'price_dev_plan15'
		'STRIPE_PRICE_PLAN70':  'price_dev_plan70'
		'STRIPE_PRICE_PLAN30':  'price_dev_plan30'
		'STRIPE_PRICE_PLAN150': 'price_dev_plan150'
	})
	$if env_dev ? {
		assert prices.plan15 == 'price_dev_plan15'
		assert prices.plan70 == 'price_dev_plan70'
		assert prices.plan30 == 'price_dev_plan30'
		assert prices.plan150 == 'price_dev_plan150'
		return
	}
	assert prices.plan15 == 'price_1UBvOvLZ5gTFc3B2rsINUKYf'
	assert prices.plan70 == 'price_1UBvP2LZ5gTFc3B2ZkSwr93b'
	assert prices.plan30 == 'price_1UBvP9LZ5gTFc3B2VBF3qClj'
	assert prices.plan150 == 'price_1UBvPFLZ5gTFc3B2TZLaM7YU'
}
