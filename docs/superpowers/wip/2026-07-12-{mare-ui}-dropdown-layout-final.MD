# UI - Layout final do dropdown

Gerado em: 2026-07-12

## Pedido Do Usuario

Dropdown deve ocupar mais largura lateral que o botão Executar e ficar um pouco menor na altura.

## Implementacao

- Grid do console passou para `minmax(0, 1fr) auto`.
- Dropdown ocupa a coluna flexível; botão mantém `92px`.
- Padding do resumo e das opções reduzido.
- Mobile passa para uma coluna, com botão abaixo.
- API/backend não alterados.

## Validacao

- Viewport `1440px`: dropdown `490.75px`, botão `92px`.
- `git diff --check`: passou.
