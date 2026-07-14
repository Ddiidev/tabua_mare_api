# UI - Uma única seta no dropdown

Gerado em: 2026-07-12
Sessao/contexto: mare-ui-dropdown-arrow
Tipo de registro: correção visual

## Pedido Do Usuario

Remover a seta cinza duplicada e manter somente a seta laranja do dropdown de endpoints.

## Diagnostico

O Pico CSS aplica indicador visual próprio em `summary::after`; o seletor customizado também desenhava uma seta laranja. O resultado eram dois indicadores sobrepostos.

## Implementacao Ou Alteracao

- [custom-pico.css](../../../pages/assets/custom-pico.css:4016) agora força `background: none !important` no pseudo-elemento customizado.
- Marcador nativo e `::-webkit-details-marker` continuam ocultos.
- A seta textual laranja `⌄` permanece como único indicador.
- API/backend não alterados.

## Validacao

- CSS servido pela home com status `200`.
- `git diff --check`: passou.
- Nenhum teste unitário de interface criado.

## Estado Git

- Worktree continua sujo com alterações da repaginação e externas; nenhum commit automático.
