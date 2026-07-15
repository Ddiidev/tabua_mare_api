# UI - Simplificação final do dropdown de endpoints

Gerado em: 2026-07-12
Sessao/contexto: mare-ui-endpoint-picker-final
Tipo de registro: QA visual

## Pedido Do Usuario

- Remover a seta duplicada do dropdown.
- Exibir somente título e rota como subtítulo.
- Remover o texto `ENDPOINT:` antes da rota.

## Implementacao Ou Alteracao

- [index.html](../../../pages/index.html:44) agora renderiza apenas título + caminho.
- Removidos os campos de descrição das sete opções.
- [custom-pico.css](../../../pages/assets/custom-pico.css:3980) neutraliza marcador nativo do `<summary>` e mantém uma única seta customizada.
- Prefixo `ENDPOINT:` removido do resumo e das opções.
- API/backend não alterados.

## Validacao

- Navegador/CDP: resumo renderizado como `Estados disponíveis` + `/api/v2/states`.
- Dropdown renderizou 7 opções.
- Pseudo-elemento `::before` nativo: `none`; uma única seta em `::after`.
- JS inline da home compilou via `vm.Script`.
- `git diff --check`: passou.
- Nenhum teste unitário de interface criado.

## Estado Git

- Worktree continua sujo com alterações da repaginação e externas; nenhum commit automático.
- Branch: `wip/auth-rate-limit-google-login-premium`.
