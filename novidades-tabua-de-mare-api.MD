# v_stripe - Novidades para Tábua de Maré API

Atualizado em: 2026-07-06
Commits relevantes: `1ff24d4`, `945e27c`, `39196bb`, `ccc7e41`

---

## Resumo

`v_stripe` agora suporta **Stripe Customer Portal** completo via `create_billing_portal_session`.
Cobre toda a API `/v1/billing_portal/sessions`: 5 flows, after_completion, retention, discounts, locale, on_behalf_of, customer_account.

---

## Nova função pública

```v
pub fn (mut c Client) create_billing_portal_session(params BillingPortalSessionCreateParams) !BillingPortalSession
pub fn (mut c Client) create_billing_portal_session_with_options(params BillingPortalSessionCreateParams, opts RequestOptions) !BillingPortalSession
```

---

## Novos structs públicos (import stripe)

### Response
- `BillingPortalSession` — id, object, configuration, created, customer, livemode, return_url, url, flow, locale, on_behalf_of, customer_account
- `BillingPortalFlow` — type_, after_completion, subscription_cancel, subscription_update, subscription_update_confirm
- Sub-structs de flow response: `BillingPortalFlowAfterCompletion`, `BillingPortalFlowHostedConfirmation`, `BillingPortalFlowRedirect`, `BillingPortalFlowSubscriptionCancel`, `BillingPortalFlowSubscriptionUpdate`, `BillingPortalFlowSubscriptionUpdateConfirm`

### Request params
- `BillingPortalSessionCreateParams` — customer (required), configuration, return_url, locale, on_behalf_of, customer_account, flow_data
- `BillingPortalFlowDataCreateParams` — type_, subscription_cancel, subscription_update, subscription_update_confirm, after_completion
- `BillingPortalSubscriptionCancelFlow` — subscription, retention
- `BillingPortalSubscriptionCancelRetention` — type_, coupon_offer
- `BillingPortalSubscriptionCancelRetentionCouponOffer` — coupon
- `BillingPortalSubscriptionUpdateFlow` — subscription
- `BillingPortalSubscriptionUpdateConfirmFlow` — subscription, items, discounts
- `BillingPortalSubscriptionUpdateConfirmItem` — id, price, quantity
- `BillingPortalSubscriptionUpdateConfirmDiscount` — coupon, promotion_code
- `BillingPortalAfterCompletion` — type_, hosted_confirmation, redirect
- `BillingPortalHostedConfirmation` — custom_message
- `BillingPortalRedirect` — return_url

---

## Flows suportados (flow_data.type_)

| Flow | Payload required | Payload opcional |
|---|---|---|
| `payment_method_update` | nenhum | after_completion |
| `subscription_cancel` | subscription | retention (coupon_offer), after_completion |
| `subscription_update` | subscription | after_completion |
| `subscription_update_confirm` | subscription + items[] | discounts[], after_completion |
| `invoice_history` | nenhum | after_completion |

after_completion.type_ values: `hosted_confirmation`, `portal_homepage`, `redirect`.

---

## Validação embutida na lib

- `customer` required
- cross-type rejeitado: subscription_cancel/update/confirm preenchidos com type_ diferente = erro
- type_ não suportado = erro antes de chamar API
- subscription_cancel sem subscription = erro
- subscription_update_confirm sem items = erro
- discounts[] sem coupon nem promotion_code = erro
- retention coupon_offer sem coupon = erro
- after_completion redirect sem return_url = erro

---

## Como usar no Tábua de Maré API

### Cenário 1: usuário gerencia assinatura (portal geral)

```v
portal := stripe_client.create_billing_portal_session(stripe.BillingPortalSessionCreateParams{
    customer:   user.stripe_customer_id
    return_url: '${env.url_env}/dashboard'
})!
// redirecionar frontend para portal.url
```

### Cenário 2: usuário cancela (deep link cancel)

```v
portal := stripe_client.create_billing_portal_session(stripe.BillingPortalSessionCreateParams{
    customer:   user.stripe_customer_id
    return_url: '${env.url_env}/dashboard'
    flow_data: stripe.BillingPortalFlowDataCreateParams{
        type_: 'subscription_cancel'
        subscription_cancel: stripe.BillingPortalSubscriptionCancelFlow{
            subscription: user.stripe_subscription_id
        }
    }
})!
```

### Cenário 3: update com desconto + redirect pós-completion

```v
portal := stripe_client.create_billing_portal_session(stripe.BillingPortalSessionCreateParams{
    customer:   user.stripe_customer_id
    return_url: '${env.url_env}/dashboard'
    locale:     'pt-BR'
    flow_data: stripe.BillingPortalFlowDataCreateParams{
        type_: 'subscription_update_confirm'
        subscription_update_confirm: stripe.BillingPortalSubscriptionUpdateConfirmFlow{
            subscription: 'sub_xxx'
            items: [stripe.BillingPortalSubscriptionUpdateConfirmItem{
                id:    'si_xxx'
                price: 'price_xxx'
                quantity: 1
            }]
            discounts: [stripe.BillingPortalSubscriptionUpdateConfirmDiscount{
                coupon: 'coupon_xxx'
            }]
        }
        after_completion: stripe.BillingPortalAfterCompletion{
            type_:    'redirect'
            redirect: stripe.BillingPortalRedirect{
                return_url: '${env.url_env}/done'
            }
        }
    }
})!
```

---

## Mudanças necessárias no Tábua de Maré API (still pending)

Conforme `requirment-v_stripe.md` §7, §8, §12:

1. Schema: `ALTER TABLE users ADD COLUMN stripe_customer_id TEXT NOT NULL DEFAULT ''; ADD COLUMN stripe_subscription_id TEXT NOT NULL DEFAULT '';`
2. Salvar `stripe_customer_id` no checkout
3. Salvar `stripe_subscription_id` no webhook `checkout.session.completed`
4. Nova rota `POST /auth/billing-portal` em AuthController (chamar `create_billing_portal_session`)
5. Webhook ouvir `customer.subscription.updated` + `customer.subscription.deleted`
6. Botão "Gerenciar assinatura" no dashboard

---

## Atualização do vmodules

Repo local `E:\GitHub\v-stripe` em `ccc7e41`.
Instalação em `C:\Users\andre\.vmodules\v_stripe` está atrás (em `0c808dc`).

Para sincronizar:
```powershell
cd C:\Users\andre\.vmodules\v_stripe
git pull origin master
```

---

## Testes

- 23 testes unitários (form builder: todos flows, validações, cross-type, after_completion, retention, discounts, all-fields-combined)
- 3 testes integração (basic, cancel flow, com assertion flow.type_)
- `v fmt -w .` limpo
- V 0.5.1 03c081a