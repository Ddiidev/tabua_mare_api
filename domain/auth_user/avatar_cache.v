module auth_user

import time
import sync

pub struct AvatarData {
pub:
	bytes        []u8
	content_type string
}

struct AvatarItem {
	bytes        []u8
	content_type string
	expire       time.Time
}

// AvatarCache guarda fotos de perfil em memoria com TTL configuravel (minutos).
pub struct AvatarCache {
mut:
	ttl   time.Duration
	lock  sync.Mutex
	items map[string]AvatarItem
}

// new_avatar_cache cria um cache com ttl em minutos.
pub fn new_avatar_cache(ttl_minutes int) &AvatarCache {
	return &AvatarCache{
		ttl: time.minute * ttl_minutes
	}
}

// get retorna o avatar se presente e nao expirado, ou none.
pub fn (mut c AvatarCache) get(key string) ?AvatarData {
	c.lock.lock()
	defer {
		c.lock.unlock()
	}
	if item := c.items[key] {
		if item.expire > time.now() {
			return AvatarData{
				bytes:        item.bytes
				content_type: item.content_type
			}
		}
		c.items.delete(key)
	}
	return none
}

// set armazena o avatar com expiracao ttl.
pub fn (mut c AvatarCache) set(key string, bytes []u8, content_type string) {
	c.lock.lock()
	defer {
		c.lock.unlock()
	}
	c.items[key] = AvatarItem{
		bytes:        bytes
		content_type: content_type
		expire:       time.now().add(c.ttl)
	}
}
