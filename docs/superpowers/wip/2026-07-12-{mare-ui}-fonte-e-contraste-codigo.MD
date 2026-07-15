# UI - Fonte de interface e contraste de código

Gerado em: 2026-07-12
Sessao/contexto: mare-ui-fonte-contraste
Tipo de registro: QA visual

## Pedido Do Usuario

O usuário esclareceu que o problema não era apenas peso bold: a fonte escolhida estava inadequada em vários pontos. Também pediu correção de legibilidade dos blocos de código.

## Diagnostico

- A interface declarava `Inter`, mas não carregava essa família; o navegador usava fallback sistêmico.
- O pareamento com Spectral ficou genérico e inconsistente entre navbar, controles e títulos de seção.
- Prism aplicava pontuação escura (`rgb(57, 58, 52)`) sobre o fundo azul-marinho dos exemplos.

## Implementacao Ou Alteracao

- Troca da sans de interface para `IBM Plex Sans` nos cinco templates públicos/autenticados e nas regras CSS existentes.
- Spectral continua reservada aos títulos display; Kode Mono continua nos exemplos e valores técnicos.
- Nova paleta Prism em [custom-pico.css](../../../pages/assets/custom-pico.css:3875): pontuação, propriedades, strings, números, operadores, keywords, funções e comentários receberam cores claras distintas sobre `#082f49`.
- Nenhuma alteração em API, backend, auth, Stripe, banco, rate-limit ou endpoints.
- Nenhum teste unitário de interface criado ou mantido.

## Validacao

- Navegador/CDP: `document.fonts.check('16px "IBM Plex Sans"')` retornou `true`.
- Home, docs e playground computaram `IBM Plex Sans` no corpo/interface.
- Blocos docs: corpo `#d9edf1`, propriedade `#72d8d4`, string `#ffd166`, pontuação `#b9d9e2`, número `#9be7c7`.
- Rotas públicas `/`, `/docs`, `/playground`, `/apoiar`: `200`.
- CSS servido em `/pages/assets/custom-pico.css`: `200`, marcadores de fonte/paleta presentes.
- `git diff --check`: passou.

## Estado Git

- Worktree permanece sujo com alterações da repaginação e externas; nenhum commit automático.
- Branch: `wip/auth-rate-limit-google-login-premium`.
