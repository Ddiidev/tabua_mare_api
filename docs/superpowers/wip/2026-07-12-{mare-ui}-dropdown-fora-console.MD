# UI - Lista do dropdown fora do recorte do console

Gerado em: 2026-07-12

## Pedido Do Usuario

A lista do dropdown estava passando sobre a navbar e sendo cortada pelo `overflow` do console. A lista deve sair visualmente para fora do console.

## Implementacao

- `.tide-console` agora usa `overflow: visible` para não cortar o menu.
- Console recebeu stacking controlado (`z-index: 1`).
- Navbar elevada para `z-index: 10000`.
- Menu do dropdown elevado para `z-index: 100` dentro do console.
- API/backend não alterados.

## Validacao

- Home retornou `200`.
- `git diff --check`: passou.
