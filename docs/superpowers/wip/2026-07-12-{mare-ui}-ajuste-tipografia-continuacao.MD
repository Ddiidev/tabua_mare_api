# UI - Ajuste de peso tipográfico

Gerado em: 2026-07-12
Sessao/contexto: mare-ui-ajuste-tipografia
Tipo de registro: QA visual

## Card

Registro anterior: [continuação e validação](2026-07-12-%7Bmare-ui%7D-continuacao-validacao.MD)

Arquivo principal: [custom-pico.css](../../../pages/assets/custom-pico.css)

## Pedido Do Usuario

O usuário apontou que navbar e botões usavam fontes diferentes e que os pesos bold estavam agressivamente grossos. Confirmou que a mudança deve ser apenas visual e que não quer testes unitários para a interface.

## Diagnostico

Inspeção no navegador mostrou pesos `700`/`800` em links, conta, CTA, console e eyebrow, enquanto títulos display usam Spectral. O contraste de peso, não a coexistência das famílias, causava o destoamento.

## Implementacao Ou Alteracao

- Ajustado somente [custom-pico.css](../../../pages/assets/custom-pico.css).
- Peso comum de controles e links reduzido para `500`.
- Marca e nomes de plano mantidos em `600`; títulos display continuam Spectral.
- Seletor explícito aplicado ao `.button-sun` para vencer a especificidade anterior `800`.
- Nenhuma alteração em API, backend, auth, Stripe, banco, rate-limit ou endpoints.
- Nenhum teste unitário de interface mantido ou adicionado.

## Validacao

- Navegador/CDP: marca `600`; links e conta `500`; `.button-sun` `500`; `.console-run` `500`; `.eyebrow` `600`.
- Rotas públicas: `/`, `/docs`, `/playground`, `/apoiar` retornaram `200`.
- CSS servido em `/pages/assets/custom-pico.css` retornou `200` e contém `--weight-ui-strong: 500`.
- `git diff --check -- pages/assets/custom-pico.css`: passou.
- Screenshot de home revisado após o ajuste: CTA/nav sem peso excessivo.

## Estado Git

- Worktree continua com alterações externas e da repaginação; não criar commit automático para não misturar autoria.
- Branch: `wip/auth-rate-limit-google-login-premium`.

## Pendencias

- Dashboard autenticado ainda depende de sessão Google para validação visual completa.
- Persistência de um documento formal de design system continua opcional.
