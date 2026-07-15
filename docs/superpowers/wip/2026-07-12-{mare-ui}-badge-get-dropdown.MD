# UI - Badge GET dentro do dropdown

Gerado em: 2026-07-12
Sessao/contexto: mare-ui-get-badge
Tipo de registro: refinamento visual

## Pedido Do Usuario

O console usa somente requisições GET. Remover o badge solto ou colocá-lo dentro do dropdown, próximo da rota.

## Implementacao Ou Alteracao

- Removido o `.method-pill` isolado do console.
- Adicionado badge `GET` dentro da rota selecionada e de cada opção do dropdown.
- Título continua separado; subtítulo agora é `GET /api/v2/...`.
- [index.html](../../../pages/index.html:208) e [custom-pico.css](../../../pages/assets/custom-pico.css:4037) alterados somente na camada visual.
- API/backend não alterados.

## Validacao

- Home retornou `200`.
- JS inline compilou via `vm.Script`.
- Navegador confirmou ausência do badge standalone e resumo com `GET` junto da rota.
- `git diff --check`: passou.
- Nenhum teste unitário de interface criado.

## Estado Git

- Worktree continua sujo com alterações da repaginação e externas; nenhum commit automático.
