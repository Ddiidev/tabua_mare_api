module rate_limit

fn test_credit_remaining_allows_the_last_credit() {
	assert credit_remaining(1, 0) == 1
	assert credit_remaining(1, 1) == 0
	assert credit_remaining(32000, 31999) == 1
}

fn test_credit_remaining_keeps_unlimited_as_minus_one() {
	assert credit_remaining(0, 0) == -1
	assert credit_remaining(0, 9000) == -1
}
