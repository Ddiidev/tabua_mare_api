# API - Recreação de produtos Stripe em produção

Gerado em: 2026-07-13
Sessao/contexto: mare-api-stripe-live
Tipo de registro: validação externa bloqueada

## Pedido Do Usuario

Recriar os produtos e Prices `Plan5`, `Plan10` e `PlanAnual` usando a chave Stripe de produção.

## Evidencia Atual

- `stripe_get_stripe_account_info` retornou conta `acct_1QCRHWLZ5gTFc3B2`.
- Busca e criação disponíveis apontam para Stripe Test (`dashboard.stripe.com/test/...`).
- Produto criado durante a verificação retornou `livemode: false`:
  - produto: `prod_UsUczgh1B9GgIz`
  - Price padrão: `price_1Tsjd4LZ5gTFc3B2brscF7vS`
- Tentativa de arquivar o Price falhou porque ele é o preço padrão do produto.
- `.env` local usa `sk_test_`.

## Bloqueio

O conector Stripe MCP não está conectado em live mode nesta sessão. Não criar Plan10/PlanAnual em test nem atualizar `.env` com IDs de teste para um deploy de produção.

## Próximo Passo

Reconectar/selecionar o MCP Stripe live e então criar:

- Plan5: R$ 5/mês, RPM 512.
- Plan10: R$ 10/mês, RPM 2.048.
- PlanAnual: R$ 70/ano, RPM 4.096.
