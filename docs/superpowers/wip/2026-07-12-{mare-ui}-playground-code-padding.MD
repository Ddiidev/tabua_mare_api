# UI - Espaçamento dos códigos no playground

Gerado em: 2026-07-12

## Pedido Do Usuario

Reduzir a margem interna excessiva antes do código nos blocos da página Playground.

## Implementacao

- Sobrescrito o `padding-top: 60px` inline do playground.
- Blocos sem botão usam `0.7rem` de padding superior.
- Blocos com botão de cópia usam `1.7rem`, apenas o espaço necessário para o botão.
- Ajuste restrito à camada visual; API/backend não alterados.

## Validacao

- `/playground`: `200`.
- CSS usa `!important` para vencer o estilo inline original.
- `git diff --check`: passou.
