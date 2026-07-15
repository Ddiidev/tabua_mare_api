# UI - Console inicial mais largo

Gerado em: 2026-07-12
Sessao/contexto: mare-ui-console-width
Tipo de registro: QA visual

## Pedido Do Usuario

Alargar o console de requisição exibido na tela inicial.

## Implementacao Ou Alteracao

- [custom-pico.css](../../../pages/assets/custom-pico.css:3902) ajusta o grid do hero apenas em desktop (`min-width: 1024px`).
- Coluna do console passou a usar `1.12fr` e mínimo de `520px`; texto do hero usa `0.88fr`.
- Layout mobile/tablet continua em uma coluna.
- API/backend não alterados.

## Validacao

- Navegador/CDP em viewport `1440px`: copy `502.66px`, console `639.75px`.
- Em viewport menor, layout continua empilhado sem overflow.
- `git diff --check`: passou.

## Estado Git

- Worktree continua sujo com alterações da repaginação e externas; nenhum commit automático.
- Branch: `wip/auth-rate-limit-google-login-premium`.
