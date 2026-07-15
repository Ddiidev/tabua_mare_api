# Requisitos de Evolução da Lib `v_stripe`

> Status: pendente de implementação na lib `v_stripe` (`~/.vmodules/v_stripe`).
> Escopo deste documento: descrever, com o máximo de detalhe, o que falta na lib para que o Tábua de Maré API possa oferecer gerenciamento de assinatura (cancelamento, atualização de cartão, histórico de faturas, etc.) aos usuários logados.

---

## 1. Contexto

O Tábua de Maré API usa a lib `v_stripe` (`v_stripe.stripe`) para processar pagamentos via Stripe. Hoje a integração consegue:

- Criar Stripe Checkout Sessions (`create_checkout_session`).
- Buscar/criar Customers (`list_customers`, `create_customer`).
- Verificar webhooks (`verify_webhook_event`).
- Buscar uma Checkout Session (`get_checkout_session`).
- Listar/Cancelar subscriptions (`list_subscriptions`, `cancel_subscription`).

Porém, a lib **não possui suporte ao Stripe Customer Portal** (`/v1/billing_portal/sessions`). Isso deixa um gap importante: depois que o usuário paga, ele não tem uma forma nativa e self-service de gerenciar a própria assinatura dentro do Tábua de Maré API.

---

## 2. O que é o Stripe Customer Portal

O Stripe Customer Portal é uma página hospedada pelo Stripe que permite ao cliente:

- Visualizar o histórico de faturas (invoices).
- Baixar faturas em PDF.
- Atualizar dados de pagamento (cartão, Pix, boleto, etc., dependendo da configuração).
- Alterar entre planos (se configurado).
- Cancelar a assinatura.
- Reativar uma assinatura cancelada (dentro do período de carência).

A vantagem de usar o portal é que o Stripe cuida de toda a UI, compliance, validação de pagamento e webhooks. O desenvolvedor só precisa gerar um link de sessão do portal e redirecionar o usuário.

Documentação oficial: https://stripe.com/docs/billing/subscriptions/integrating-customer-portal

---

## 3. Endpoint da API Stripe

### `POST /v1/billing_portal/sessions`

Cria uma sessão temporária do Customer Portal e retorna uma URL única onde o cliente pode gerenciar sua assinatura.

#### Parâmetros do body

| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `customer` | string | sim | ID do Customer Stripe (`cus_xxx`). |
| `configuration` | string | não | ID de uma configuração customizada do portal (`bpc_xxx`). Se omitido, usa a configuração padrão da conta. |
| `flow_data` | object | não | Dados para iniciar um fluxo específico do portal (ex: cancelamento, atualização de plano). |
| `flow_data.type` | string | condicional | Tipo do fluxo. Ex: `payment_method_update`, `subscription_cancel`, `subscription_update`. |
| `flow_data.subscription_cancel[subscription]` | string | condicional | ID da subscription a ser cancelada quando `type=subscription_cancel`. |
| `return_url` | string | não | URL para onde o Stripe redireciona o cliente ao sair do portal. |

#### Resposta da API

```json
{
  "id": "bps_xxx",
  "object": "billing_portal.session",
  "configuration": "bpc_xxx",
  "created": 1234567890,
  "customer": "cus_xxx",
  "livemode": false,
  "return_url": "https://tabuamare.api.br/dashboard",
  "url": "https://billing.stripe.com/session/{secret}"
}
```

O campo `url` é o que deve ser usado para redirecionar o usuário.

---

## 4. O que falta na lib `v_stripe`

### 4.1. Estrutura de dados: `BillingPortalSession`

A lib precisa de um tipo que represente a resposta do Stripe. Exemplo de definição esperada em V:

```v
pub struct BillingPortalSession {
pub:
	id            string
	object        string
	configuration string
	created       i64
	customer      string
	livemode      bool
	return_url    string
	url           string
	flow          BillingPortalFlowData
}

pub struct BillingPortalFlowData {
pub:
	type_ string @[json: 'type']
}
```

### 4.2. Estrutura de dados: `BillingPortalSessionCreateParams`

Parâmetros para criar a sessão do portal:

```v
pub struct BillingPortalSessionCreateParams {
pub:
	customer      string
	configuration string
	return_url    string
	flow_data     BillingPortalFlowDataCreateParams
}

pub struct BillingPortalFlowDataCreateParams {
pub:
	type_              string                            @[json: 'type']
	subscription_cancel BillingPortalSubscriptionCancelFlow @[json: 'subscription_cancel']
}

pub struct BillingPortalSubscriptionCancelFlow {
pub:
	subscription string
}
```

Observação: o Stripe aceita vários tipos de `flow_data`. Os mais comuns são:

- `payment_method_update`
- `subscription_cancel`
- `subscription_update`
- `subscription_update_confirm`
- `invoice_history`

Para o Tábua de Maré API, o mais importante inicialmente é `subscription_cancel`, para levar o usuário direto à tela de cancelamento.

### 4.3. Função na `Client`

A lib precisa expor uma função como:

```v
pub fn (mut c Client) create_billing_portal_session(params BillingPortalSessionCreateParams) !BillingPortalSession {
	form := build_billing_portal_session_form(params)!
	response := c.do_request(.post, '/billing_portal/sessions', map[string]string{}, form, RequestOptions{})!
	return json.decode(BillingPortalSession, response.body) or {
		return error('failed to decode billing portal session response: ${err.msg()}')
	}
}
```

### 4.4. Função auxiliar para construir o form

Similar ao que já existe em `checkout_sessions.v`. Exemplo:

```v
fn build_billing_portal_session_form(params BillingPortalSessionCreateParams) !map[string]FormValue {
	if params.customer.trim_space() == '' {
		return error('customer is required')
	}

	mut form := map[string]FormValue{}
	form['customer'] = params.customer

	if params.configuration != '' {
		form['configuration'] = params.configuration
	}
	if params.return_url != '' {
		form['return_url'] = params.return_url
	}
	if params.flow_data.type_ != '' {
		mut flow := map[string]FormValue{}
		flow['type'] = params.flow_data.type_
		if params.flow_data.subscription_cancel.subscription != '' {
			mut cancel := map[string]FormValue{}
			cancel['subscription'] = params.flow_data.subscription_cancel.subscription
			flow['subscription_cancel'] = cancel
		}
		form['flow_data'] = flow
	}

	return form
}
```

---

## 5. Por que isso é necessário no Tábua de Maré API

### 5.1. Problema atual: cancelamento só via `cancel_subscription`

A lib `v_stripe` já tem `cancel_subscription(subscription_id string)`. Porém, essa função exige que o backend do Tábua de Maré API guarde o `subscription_id` (`sub_xxx`) retornado pelo Stripe.

Hoje o Tábua de Maré API não guarda `subscription_id` na tabela `users`. Ele apenas atualiza o campo `plan` quando recebe o webhook `checkout.session.completed`. Isso significa que:

- O backend não sabe qual subscription cancelar.
- Mesmo que soubesse, cancelar por API diretamente sem confirmação do usuário é uma experiência ruim e arriscada.
- Não é possível oferecer ao usuário opções como "pausar", "trocar de cartão" ou "ver faturas".

### 5.2. Vantagem do Customer Portal

Com o Customer Portal:

- O usuário clica em "Gerenciar assinatura" no dashboard.
- O backend cria uma sessão do portal via `/v1/billing_portal/sessions`.
- O backend redireciona o usuário para a URL do Stripe.
- O Stripe cuida de toda a UI e emite webhooks (`customer.subscription.updated`, `customer.subscription.deleted`, etc.).
- O backend atualiza o plano do usuário ao receber os webhooks.

Isso evita que o Tábua de Maré API precise construir telas próprias de gerenciamento de pagamento.

---

## 6. Fluxo esperado no Tábua de Maré API

### 6.1. Configuração inicial (no Stripe Dashboard)

1. Acessar: https://dashboard.stripe.com/settings/billing/portal
2. Ativar o Customer Portal.
3. Configurar quais ações o cliente pode fazer:
   - Cancelar assinaturas.
   - Atualizar método de pagamento.
   - Visualizar histórico de faturas.
   - Alternar entre produtos (opcional).
4. Definir a URL de retorno padrão (pode ser sobrescrita por API).

### 6.2. Cenário 1: usuário quer gerenciar assinatura

1. Usuário logado acessa `/dashboard`.
2. Clica em "Gerenciar assinatura".
3. Frontend chama `POST /auth/billing-portal`.
4. Backend:
   - Verifica JWT do cookie.
   - Busca `stripe_customer_id` no banco (requer novo campo na tabela `users`).
   - Chama `create_billing_portal_session` da lib `v_stripe`.
   - Retorna `{ "url": "https://billing.stripe.com/session/..." }`.
5. Frontend redireciona o usuário para essa URL.
6. Usuário faz alterações no portal Stripe.
7. Stripe envia webhooks para `/auth/webhook`.
8. Backend atualiza `users.plan` conforme eventos.

### 6.2. Cenário 2: usuário quer cancelar diretamente

1. Usuário logado clica em "Cancelar assinatura".
2. Frontend chama `POST /auth/billing-portal` com body `{ "flow": "subscription_cancel" }`.
3. Backend cria sessão do portal com `flow_data.type = 'subscription_cancel'` e `subscription` preenchida.
4. Usuário é levado diretamente para a tela de confirmação de cancelamento no Stripe.
5. Após cancelar, Stripe envia `customer.subscription.deleted`.
6. Backend atualiza `users.plan = 'free'`.

---

## 7. Mudanças necessárias no schema do Tábua de Maré API

Para usar o Customer Portal corretamente, o banco PostgreSQL precisa guardar mais informações do Stripe:

```sql
ALTER TABLE users
ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT NOT NULL DEFAULT '',
ADD COLUMN IF NOT EXISTS stripe_subscription_id TEXT NOT NULL DEFAULT '';
```

- `stripe_customer_id`: necessário para criar sessões do portal e reutilizar em futuros checkouts.
- `stripe_subscription_id`: necessário para fluxos direcionados como cancelamento.

---

## 8. Mudanças necessárias no backend do Tábua de Maré API

### 8.1. Salvar `stripe_customer_id` e `stripe_subscription_id`

No handler `checkout` de `auth_controller.v`, ao criar a Checkout Session:

1. O `customer` retornado na session deve ser salvo em `users.stripe_customer_id`.
2. Após o webhook `checkout.session.completed`, o campo `session.subscription` deve ser salvo em `users.stripe_subscription_id`.

### 8.2. Nova rota: `POST /auth/billing-portal`

Criar um handler no `AuthController` que:

1. Verifica se o usuário está autenticado.
2. Busca `stripe_customer_id` e `stripe_subscription_id`.
3. Opcionalmente aceita um body `{ "flow": "subscription_cancel" }`.
4. Chama a lib `v_stripe` para criar a sessão do portal.
5. Retorna a URL para o frontend redirecionar.

Exemplo de payload de retorno:

```json
{
  "data": [
    {
      "url": "https://billing.stripe.com/session/{secret}"
    }
  ]
}
```

### 8.3. Atualizar webhook para mais eventos

Além de `checkout.session.completed`, o Tábua de Maré API deve ouvir:

- `customer.subscription.updated` — plano alterado, pagamento confirmado, etc.
- `customer.subscription.deleted` — assinatura cancelada.
- `invoice.payment_failed` — pagamento falhou (opcional: downgrade para free).

---

## 9. Considerações técnicas importantes

### 9.1. `FormValue` e objetos aninhados

A lib `v_stripe` usa `map[string]FormValue` para serializar os parâmetros no formato `application/x-www-form-urlencoded` esperado pela API Stripe. O tipo `FormValue` provavelmente é um sum type que aceita `string`, `int`, `bool`, `map[string]FormValue` e `[]FormValue`.

Para objetos aninhados (como `flow_data` e `subscription_cancel`), a serialização deve seguir a convenção do Stripe:

```
flow_data[type]=subscription_cancel
flow_data[subscription_cancel][subscription]=sub_xxx
```

Isso já é feito para `line_items` e `subscription_data` em `checkout_sessions.v`, então o padrão existe na lib.

### 9.2. Idempotência

A criação de sessão do portal não é idempotente por padrão. Cada chamada gera uma URL única. Se necessário, pode-se passar `Idempotency-Key` via `RequestOptions`.

### 9.3. Segurança

- Só usuários autenticados podem criar sessões do portal.
- O backend deve garantir que o `customer` usado pertence ao usuário logado.
- Nunca exponha o `stripe_customer_id` no frontend sem necessidade.

### 9.4. Teste

A lib `v_stripe` já tem testes em `tests/`. Deve-se adicionar testes de integração para:

- Criar sessão do portal com customer válido.
- Criar sessão do portal com `flow_data` de cancelamento.
- Decodificação correta da resposta JSON.

---

## 10. Exemplo de uso futuro no Tábua de Maré API

```v
import v_stripe.stripe

pub fn (mut ac AuthController) billing_portal(mut ctx web_ctx.WsCtx) veb.Result {
	uid := ac.current_user_id(mut ctx)
	if uid == 0 {
		return ctx.json(types.failure[string](401, 'nao autenticado'))
	}

	mut db := ac.db_conn() or {
		return ctx.json(types.failure[string](500, 'banco indisponivel'))
	}
	defer { db.close() or {} }

	user := repo_auth.find_by_id(mut db, uid) or {
		return ctx.json(types.failure[string](404, 'usuario nao encontrado'))
	}

	if user.stripe_customer_id == '' {
		return ctx.json(types.failure[string](400, 'sem assinatura ativa'))
	}

	mut stripe_client := stripe.new_client(stripe.ClientConfig{
		secret_key: ac.env.stripe_secret_key
	}) or {
		return ctx.json(types.failure[string](500, 'stripe client init failed'))
	}

	portal := stripe_client.create_billing_portal_session(stripe.BillingPortalSessionCreateParams{
		customer:   user.stripe_customer_id
		return_url: '${ac.env.url_env}/dashboard'
	}) or {
		return ctx.json(types.failure[string](500, 'falha ao criar portal: ${err}'))
	}

	return ctx.json(types.success([{'url': portal.url}]))
}
```

---

## 11. Checklist de implementação na lib `v_stripe`

- [ ] Criar `BillingPortalSession` struct em `types.v`.
- [ ] Criar `BillingPortalSessionCreateParams`, `BillingPortalFlowDataCreateParams` e `BillingPortalSubscriptionCancelFlow` structs.
- [ ] Criar arquivo `billing_portal_sessions.v` com:
  - `create_billing_portal_session(params)`
  - `build_billing_portal_session_form(params)`
- [ ] Garantir serialização correta de `flow_data` aninhado no form url-encoded.
- [ ] Adicionar testes em `tests/`.
- [ ] Atualizar `README.MD` da lib com exemplo de uso.

---

## 12. Checklist de implementação no Tábua de Maré API

- [ ] Adicionar colunas `stripe_customer_id` e `stripe_subscription_id` na tabela `users`.
- [ ] Salvar `stripe_customer_id` no momento do checkout.
- [ ] Salvar `stripe_subscription_id` ao processar `checkout.session.completed`.
- [ ] Criar rota `POST /auth/billing-portal` no `AuthController`.
- [ ] Adicionar botão "Gerenciar assinatura" no `pages/dashboard.html`.
- [ ] Adicionar handler de webhook para `customer.subscription.updated` e `customer.subscription.deleted`.
- [ ] (Opcional) Adicionar handler para `invoice.payment_failed`.
- [ ] Atualizar `.env.template` com `STRIPE_WEBHOOK_SECRET` já existente, mas garantir que esteja documentado.

---

## 13. Links de referência

- Documentação oficial do Customer Portal: https://stripe.com/docs/billing/subscriptions/integrating-customer-portal
- API Reference - Create Billing Portal Session: https://stripe.com/docs/api/customer_portal/sessions/create
- API Reference - Customer Portal Configurations: https://stripe.com/docs/api/customer_portal/configurations
- Lib `v_stripe` local: `~/.vmodules/v_stripe/stripe/`
