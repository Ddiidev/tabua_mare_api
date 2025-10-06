module cache

import time

pub struct Cache {
mut:
	itens map[string]ItemCache
}

pub struct ItemCache {
	expire time.Time
	value  TypeCacheData
}

pub fn (mut ctx_cache Cache) get(key string) ?TypeCacheData {
	if item := ctx_cache.itens[key] {
		if item.expire > time.now() {
			return item.value
		}
	}
	return none
}

pub fn (mut ctx_cache Cache) set(key string, value TypeCacheData) {
	ctx_cache.itens[key] = ItemCache{
		expire: time.now().add(time.minute * 5)
		value:  value
	}
}