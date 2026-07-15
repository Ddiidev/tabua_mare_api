# UI - Contraste e espaçamento dos blocos de código

Gerado em: 2026-07-12
Sessao/contexto: mare-ui-code-spacing
Tipo de registro: QA visual

## Pedido Do Usuario

O texto comum dos blocos de código estava difícil de enxergar e havia margem interna excessiva.

## Implementacao Ou Alteracao

- Texto base dos blocos docs/playground ajustado para `#f2fbfc` sobre `#082f49`.
- Padding padrão reduzido para `0.7rem 0.8rem`.
- Blocos com botão de cópia mantêm somente espaço superior necessário (`2.15rem`).
- Tokens coloridos existentes foram preservados.
- API/backend não alterados.

## Validacao

- Navegador/CDP: texto computado `rgb(242, 251, 252)`.
- Fundo computado `rgb(8, 47, 73)`.
- Screenshot revisado: texto mais claro e bloco mais compacto.
- `git diff --check`: passou.
- Nenhum teste unitário de interface criado.

## Estado Git

- Worktree continua sujo com alterações da repaginação e externas; nenhum commit automático.
- Branch: `wip/auth-rate-limit-google-login-premium`.
