module instance

import os
import veb
import shareds.web_ctx

// middleware marca toda resposta com X-Tabuamare-Slot para observabilidade de
// borda: o Nginx grava esse header no access log (campo slot=), revelando qual
// slot (A ou B) atendeu cada requisicao.
// Com TABUAMARE_SLOT vazio, usa o hostname do container (id curto do Docker)
// como fallback — distingue as instancias em execucao, embora mude a cada deploy.
pub fn middleware(configured_slot string) veb.MiddlewareOptions[web_ctx.WsCtx] {
	fallback := os.hostname() or { 'unknown' }
	slot := if configured_slot != '' { configured_slot } else { fallback }
	return veb.MiddlewareOptions[web_ctx.WsCtx]{
		handler: fn [slot] (mut ctx web_ctx.WsCtx) bool {
			ctx.res.header.add_custom('X-Tabuamare-Slot', slot) or {}
			return true
		}
	}
}
