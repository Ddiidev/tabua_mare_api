# UI - Página de teste de rate-limit via túnel

Gerado em: 2026-07-12
Sessao/contexto: mare-ui-rate-limit-page
Tipo de registro: ferramenta operacional

## Pedido Do Usuario

Criar uma página para acessar pelo túnel e testar o rate-limit usando o IP real da conexão, em vez de `localhost`.

## Implementacao Ou Alteracao

- Nova rota pública `/rate-limit-test` em [main.v](../../../main.v:131).
- Novo template [rate_limit_test.html](../../../pages/rate_limit_test.html:1).
- Botão dispara 5 `fetch` simultâneos para `/api/v2/states`.
- Exibe status, tempo, resposta, bloqueios `429` e `Retry-After`.
- Após `Retry-After`, executa uma requisição automática para confirmar liberação.
- Página informa que o servidor verá o IP do acesso via túnel.
- Estilos adicionados ao [custom-pico.css](../../../pages/assets/custom-pico.css:3914).
- Nenhuma alteração no endpoint, middleware ou regra de rate-limit.

## Validacao

- `v -prod -d using_sqlite . -o /tmp/tabua_mare_api_rate_page_check`: compilou; somente avisos V1 já existentes.
- `/rate-limit-test`: `200`.
- JavaScript inline compilou via `vm.Script`.
- `git diff --check`: passou.

## Uso

Abrir no domínio público do túnel:

```text
https://SEU-DOMINIO/rate-limit-test
```

O navegador fará as requisições pelo túnel, permitindo observar o IP real recebido pelo serviço.

## Estado Git

- Worktree continua sujo com alterações da repaginação e externas; nenhum commit automático.
