# Plano: Webhooks Stripe, Portal de Faturamento e Cancelamento

> Criado em: 2026-07-06
> Objetivo: Fechar gaps de gerenciamento de assinatura Stripe no Tábua de Maré API.

## Checklist de implementação

- [x] 1. Adicionar colunas `stripe_customer_id` e `stripe_subscription_id` na tabela `users`
  - Arquivo: `shareds/infradb_pg/migrations.v`
  - Adicionar `ALTER TABLE users ADD COLUMN IF NOT EXISTS ...`

- [x] 2. Salvar `stripe_customer_id` no checkout
  - Arquivo: `auth_controller.v`, função `checkout`
  - Após criar a Checkout Session, atualizar `users.stripe_customer_id` se ainda estiver vazio.

- [x] 3. Salvar `stripe_subscription_id` no webhook
  - Arquivo: `auth_controller.v`, função `handle_stripe_checkout_completed`
  - Ler `session.subscription` e salvar em `users.stripe_subscription_id`.

- [x] 4. Expandir webhook para mais eventos
  - Arquivo: `auth_controller.v`, função `stripe_webhook`
  - Adicionar handlers para:
    - `customer.subscription.created`
    - `customer.subscription.updated`
    - `customer.subscription.deleted` (downgrade para free)
    - `invoice.payment_failed` (opcional: downgrade para free)

- [x] 5. Criar rota `POST /auth/billing-portal`
  - Arquivo: `auth_controller.v`
  - Requer usuário autenticado.
  - Criar sessão do Customer Portal via `v_stripe`.
  - Retornar URL para redirecionamento.
  - **Depende da lib `v_stripe` ter `create_billing_portal_session`**. Se a lib não tiver, precisa implementar nela também.

- [x] 6. Criar rota `POST /auth/cancel-subscription`
  - Arquivo: `auth_controller.v`
  - Requer usuário autenticado.
  - Usar `stripe.cancel_subscription(users.stripe_subscription_id)`.
  - Atualizar `users.plan = 'free'` após cancelar.
  - Fallback: se não tiver `subscription_id`, redirecionar para billing portal.

- [x] 7. Atualizar `pages/dashboard.html`
  - Corrigir textos de limites para `req/min` (já feito em alteração anterior).
  - Adicionar botão "Gerenciar assinatura" que chama `/auth/billing-portal`.
  - Adicionar botão "Cancelar assinatura" que chama `/auth/cancel-subscription`.

- [x] 8. Validar plano ativo do usuário no rate-limit
  - Arquivo: `shareds/rate_limit/middleware.v`
  - Quando a requisição usar api_key, verificar se o `user_id` da key ainda tem `plan` compatível com a key.
  - Se o usuário foi downgradeado, tratar a key como free/revogada.

- [x] 9. Corrigir `success_url` e `cancel_url`
  - Arquivo: `pages/dashboard.html`, função `checkout(plan)`
  - Enviar para `/dashboard?payment=success` ou `/dashboard?payment=cancel`.
  - No dashboard, detectar query string e recarregar dados do usuário.

- [x] 10. Atualizar nginx
  - Arquivo: `nginx/conf.d/maisfoco.conf` ou `nginx/nginx.conf`
  - Garantir que `/auth/webhook` seja acessível sem autenticação.
  - Não hardcodar domínio; usar proxy padrão.

- [x] 11. Documentar configuração de webhook no Stripe
  - Arquivo: `.env.template`
  - Sugerir múltiplos endpoints de webhook (produção e localhost) usando variáveis de ambiente.
  - Documentar eventos necessários.

- [x] 12. Compilar e validar
  - `v -d using_sqlite .`
  - `v test tests/`

- [x] 13. Revisar item a item
  - Verificar se cada item acima foi implementado corretamente.
