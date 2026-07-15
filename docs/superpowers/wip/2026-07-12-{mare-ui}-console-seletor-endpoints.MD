# UI - Seletor de endpoints no console inicial

Gerado em: 2026-07-12
Sessao/contexto: mare-ui-console-endpoints
Tipo de registro: implementação e QA visual

## Pedido Do Usuario

Permitir trocar o endpoint de teste no console de requisição da home. Ao abrir, cada item deve mostrar título, descrição e subtítulo `ENDPOINT: /api/v2/...`.

## Implementacao Ou Alteracao

- [index.html](../../../pages/index.html:42) agora usa `<details>` acessível como dropdown.
- Adicionados sete endpoints públicos V2, com exemplos válidos e sem API key.
- Cada opção mostra título, descrição e rota completa.
- A rota selecionada aparece no console; `Executar` usa a rota escolhida.
- Seleção reseta o estado/resposta e fecha o dropdown.
- [custom-pico.css](../../../pages/assets/custom-pico.css:3962) recebeu layout, estados de foco/seleção, menu rolável e responsividade mobile.
- API/backend não foram alterados.

## Validacao

- Navegador/CDP: dropdown abriu com `7` opções.
- Clique na segunda opção atualizou para `/api/v2/harbor_names/pb`.
- Execução da opção selecionada retornou `200 SUCESSO` e JSON real.
- JS inline da home compilou via `vm.Script`.
- Rotas `/`, `/docs`, `/playground`, `/apoiar`: `200`.
- `git diff --check`: passou.
- Nenhum teste unitário de interface criado.

## Estado Git

- Worktree continua sujo com alterações da repaginação e externas; nenhum commit automático.
- Branch: `wip/auth-rate-limit-google-login-premium`.
