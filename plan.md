# Plan: Revisão de Legibilidade e Manutenibilidade

> **Objetivo:** reduzir carga cognitiva, eliminar duplicação, diminuir saltos entre arquivos para compreender uma lógica. Código legível para humanos, sem gambiarras, seguindo vertical slicing.

---

## ALTA PRIORIDADE — duplicação que força mudança em N lugares

---

### #1 — Extrair `plan_limits(env, plan)` → `(rpm, monthly)`

**Problema:** O mesmo `match` que converte um plano em `(limit_rpm, limit_monthly)` aparece **4 vezes** no codebase. Adicionar um plano ou mudar um limite exige atualizar 4 lugares — esquecer um é bug silencioso.

**Onde aparece (4 locais):**

| Arquivo | Linhas | Contexto |
|---|---|---|
| `shareds/rate_limit/middleware.v` | 62-75 | usuário logado no middleware |
| `shareds/rate_limit/middleware.v` | 95-108 | api_key no middleware |
| `auth_controller.v` | 829-842 | usuário logado em `rate_limit_status` |
| `auth_controller.v` | 864-877 | api_key em `rate_limit_status` |

**Como resolver:**

Criar **uma** função em `shareds/rate_limit/middleware.v` (ao lado de `is_plan_allowed`, que já é `pub` e reusada):

```v
// plan_limits resolve o RPM e a cota mensal para um plano.
// Plano anon usa env.rate_limit_anon_*; free usa rate_limit_free_*;
// plan5/plan10/planannual usam os campos correspondentes.
pub fn plan_limits(env conf_env.EnvConfig, plan string) (int, int) {
    return match plan {
        'anon' { env.rate_limit_anon_rpm, env.rate_limit_anon_monthly }
        'plan5' { env.rate_limit_plan5_rpm, env.rate_limit_plan5_monthly }
        'plan10', 'planannual' { env.rate_limit_plan10_rpm, env.rate_limit_plan10_monthly }
        else { env.rate_limit_free_rpm, env.rate_limit_free_monthly }
    }
}
```

**Substituir os 4 match-blocks por:**

```v
limit_rpm, limit_monthly := rate_limit.plan_limits(env, plan)
```

(No `auth_controller.v`, importar `shareds.rate_limit` — já importado.)

**Impacto:** -30 linhas, 4 pontos de mudança → 1.

---

### #2 — Simplificar `rate_limit_status` (90 → ~40 linhas)

**Problema:** `auth_controller.v:808-897` é a função mais difícil de ler do codebase. 90 linhas com lógica aninhada: defaults anon → se logado resolve plano+limites (match) → extrair api_key inline → se key válida resolve effective_plan+limites (match de novo) → query contadores → montar resposta.

Depende de #1 (`plan_limits`).

**Como resolver:**

Reescrever `rate_limit_status` usando `plan_limits`:

```v
@['/rate-limit-status'; get]
pub fn (mut ac AuthController) rate_limit_status(mut ctx web_ctx.WsCtx) veb.Result {
    mut db := ac.db_conn() or {
        ctx.res.set_status(.internal_server_error)
        return ctx.json(types.failure[string](500, 'banco indisponivel: ${err}'))
    }
    defer { db.close() or {} }

    // Defaults: anon por IP
    ip := ctx.ip()
    mut bucket := 'ip:${ip}'
    mut plan := 'anon'

    // Se logado, usa o plano do usuario
    uid := ac.current_user_id(mut ctx)
    if uid > 0 {
        plan = repo_auth.find_plan_by_id(mut db, uid) or { 'free' }
    }

    // Se tem api_key valida, ela sobrescreve plano e bucket
    if api_key := rate_limit.extract_api_key(mut ctx) {
        if key := find_valid_key(mut db, api_key) {
            user_plan := repo_auth.find_plan_by_id(mut db, key.user_id) or { '' }
            mut effective_plan := key.plan
            if !rate_limit.is_plan_allowed(key.plan, user_plan) {
                effective_plan = user_plan
            }
            bucket = 'key:${key.key_value}'
            plan = effective_plan
        }
    }

    limit_rpm, limit_monthly := rate_limit.plan_limits(ac.env, plan)

    minute_key := rl.window_key_minute()
    used_rpm := rl.get_count(mut db, bucket, 'minute', minute_key) or { 0 }
    monthly := rl.get_current_month_usage(mut db, bucket) or {
        rl.CreditCheck{ used: 0, remaining: limit_monthly, lim: limit_monthly }
    }

    return ctx.json(types.success([{
        'plan':              plan
        'limit_rpm':         limit_rpm.str()
        'used_rpm':          used_rpm.str()
        'remaining_rpm':     if limit_rpm == 0 { '-1' } else { (limit_rpm - used_rpm).str() }
        'limit_monthly':     limit_monthly.str()
        'used_monthly':      monthly.used.str()
        'remaining_monthly': if limit_monthly == 0 { '-1' } else { monthly.remaining.str() }
    }]))
}
```

Onde `find_valid_key` é um helper local privado (~8 linhas):

```v
fn find_valid_key(mut db pg.DB, key_value string) ?dto.ApiKey {
    key := repo_auth.find_by_key(mut db, key_value) or { return none }
    if key.revoked { return none }
    return key
}
```

**Impacto:** 90 → ~40 linhas. Lógica lê-se top-to-bottom sem indentação profunda.

---

### #3 — Extrair `find_id_by_stripe_customer(db, customer_id) !int`

**Problema:** Buscar `user_id` a partir de `stripe_customer_id` está duplicada em **3 handlers de webhook**. Cada um tem o mesmo bloco de 6 linhas (`exec_param` → checa len → extrai `.vals[0].int()` → valida `> 0`).

**Onde aparece (3 locais):**

| Arquivo | Linhas | Handler |
|---|---|---|
| `auth_controller.v` | 665-673 | `handle_stripe_subscription_updated` |
| `auth_controller.v` | 722-730 | `handle_stripe_subscription_deleted` |
| `auth_controller.v` | 771-779 | `handle_stripe_invoice_payment_failed` |

**Como resolver:**

Adicionar em `repository/auth/users.v`:

```v
// find_id_by_stripe_customer retorna o id do usuario associado ao customer_id.
pub fn find_id_by_stripe_customer(mut db pg.DB, customer_id string) !int {
    rows := db.exec_param('SELECT id FROM users WHERE stripe_customer_id = ($1) LIMIT 1',
        customer_id)!
    if rows.len == 0 {
        return error('usuario nao encontrado para customer ${customer_id}')
    }
    uid := int_from_row(rows[0], 0)
    if uid <= 0 {
        return error('user_id invalido para customer ${customer_id}')
    }
    return uid
}
```

**Substituir os 3 blocos por:**

```v
uid := repo_auth.find_id_by_stripe_customer(mut db, customer_id)!
```

**Impacto:** -15 linhas, 3x→1x. Erros centralizados (mensagens consistentes).

---

## MÉDIA PRIORIDADE — complexidade desnecessária

---

### #4 — Colapsar 9 structs de webhook em 3

**Problema:** Três hierarquias separadas de structs wrapper para decodificar `data.object.customer` do `raw_body` dos webhooks:

- `StripeWebhookSubscriptionWrapper` → `StripeWebhookSubscriptionObjectWrapper` → `StripeWebhookSubscriptionObject` (3 structs, campos: `id`, `customer`, `status`, `metadata`)
- `StripeWebhookDataWrapper` → `StripeWebhookObjectWrapper` → `StripeWebhookCustomerObject` (3 structs, campo: `customer`)
- `StripeWebhookInvoiceWrapper` → `StripeWebhookInvoiceObjectWrapper` → `StripeWebhookInvoiceCustomerObject` (3 structs, campo: `customer`)

Total: **9 structs**.

O `json.decode` do V ignora campos ausentes no JSON — uma única hierarquia com todos os campos serve para todos os eventos.

**Como resolver:**

Substituir as 9 structs por 3:

```v
// StripeWebhookEvent decodifica o raw_body de eventos do Stripe.
// json.decode ignora campos ausentes, então uma struct serve para
// todos os eventos (subscription.*, invoice.*).
struct StripeWebhookEvent {
    data StripeWebhookEventData
}

struct StripeWebhookEventData {
    object StripeWebhookEventObject
}

struct StripeWebhookEventObject {
    id       string
    customer string
    status   string
    metadata map[string]string
}
```

**Substituir nos 3 handlers:**

```v
// antes
parsed := json.decode(StripeWebhookSubscriptionWrapper, event.raw_body) or { ... }
// depois
parsed := json.decode(StripeWebhookEvent, event.raw_body) or { ... }
```

```v
// antes (subscription.deleted)
wrapper := json.decode(StripeWebhookDataWrapper, event.raw_body) or { ... }
// depois
wrapper := json.decode(StripeWebhookEvent, event.raw_body) or { ... }
```

```v
// antes (invoice.payment_failed)
invoice := json.decode(StripeWebhookInvoiceWrapper, event.raw_body) or { ... }
// depois
invoice := json.decode(StripeWebhookEvent, event.raw_body) or { ... }
```

**Impacto:** -25 linhas, 9 structs → 3. Decodificação unificada.

---

### #5 — Hoist `ensure_credit_row` em `apply_limits`

**Problema:** `middleware.v:144-167` chama `ensure_credit_row` em **ambos** os branches do `if limit_monthly != 0`:

```v
if limit_monthly != 0 {
    rl.ensure_credit_row(mut db, bucket, plan, limit_monthly) or { ... }  // duplicado
    exceeded_month := rl.decrement(mut db, bucket) or { ... }
    if exceeded_month { ... return false }
} else {
    rl.ensure_credit_row(mut db, bucket, plan, limit_monthly) or { ... }  // duplicado
    rl.inc(mut db, bucket, 'month', rl.window_key_month()) or { ... }
}
```

**Como resolver:**

Mover `ensure_credit_row` para **antes** do `if`:

```v
fn apply_limits(mut ctx web_ctx.WsCtx, mut db pg.DB, bucket string, plan string, limit_rpm int, limit_monthly int) bool {
    minute_key := rl.window_key_minute()
    exceeded_minute := rl.inc_and_check(mut db, bucket, 'minute', minute_key, limit_rpm) or {
        eprintln('rate_limit minute check failed: ${err}')
        false
    }
    if exceeded_minute {
        ctx.res.set_status(.too_many_requests)
        ctx.res.header.add(.retry_after, '60')
        ctx.json(types.failure[string](429, 'Limite por minuto excedido'))
        return false
    }

    // garante que a linha de creditos existe antes de qualquer operacao
    rl.ensure_credit_row(mut db, bucket, plan, limit_monthly) or {
        eprintln('rate_limit ensure_credit_row failed: ${err}')
    }

    if limit_monthly != 0 {
        exceeded_month := rl.decrement(mut db, bucket) or {
            eprintln('rate_limit monthly check failed: ${err}')
            false
        }
        if exceeded_month {
            ctx.res.set_status(.too_many_requests)
            ctx.res.header.add(.retry_after, '3600')
            ctx.json(types.failure[string](429, 'Cota mensal excedida'))
            return false
        }
    } else {
        // plano ilimitado: apenas conta used
        rl.inc(mut db, bucket, 'month', rl.window_key_month()) or {
            eprintln('rate_limit month count failed: ${err}')
        }
    }

    return true
}
```

**Impacto:** -3 linhas, leitura mais clara (pré-condição explícita antes do branch).

---

### #6 — Fix `db_conn()` branch morto

**Problema:** `auth_controller.v:30-36`:

```v
fn (ac &AuthController) db_conn() !&pg.DB {
    if ac.env.postgresql_conn_str != '' {
        return pg.connect_with_conninfo(ac.env.postgresql_conn_str)
    }
    cfg := infradb_pg.pg_config_from_connstr(ac.env.postgresql_conn_str)!  // connstr == '' aqui
    return pg.connect(cfg)
}
```

O `else` faz parse de uma string **vazia** — `pg_config_from_connstr('')` vai falhar ou produzir config inválido. É branch morto que mascara erro real (configuração faltando).

**Como resolver:**

```v
fn (ac &AuthController) db_conn() !&pg.DB {
    if ac.env.postgresql_conn_str == '' {
        return error('POSTGRESQL_CONN_STR nao configurado')
    }
    return pg.connect_with_conninfo(ac.env.postgresql_conn_str)
}
```

**Impacto:** Elimina bug latente. Erro fica explícito quando config falta. Remove import não usado de `infradb_pg` se for o único uso.

---

### #7 — `extract_api_key` → `pub`

**Problema:** `middleware.v:172` define `extract_api_key` como privada. `auth_controller.v:846-852` duplica a lógica inline porque não consegue importá-la.

**Onde a duplicação aparece:**

`auth_controller.v:846-852`:
```v
mut api_key := ctx.req.header.get(.authorization) or { '' }
if api_key.starts_with('Bearer ') {
    api_key = api_key[7..]
}
if api_key == '' {
    api_key = ctx.req.header.get_custom('X-Api-Key') or { '' }
}
```

vs `middleware.v:172-184`:
```v
fn extract_api_key(mut ctx web_ctx.WsCtx) string {
    if auth := ctx.req.header.get(.authorization) {
        if auth.starts_with('Bearer ') { return auth[7..] }
        return auth
    }
    q := ctx.req.header.get_custom('X-Api-Key') or { '' }
    if q != '' { return q }
    return ctx.form['api_key'] or { '' }
}
```

**Como resolver:**

1. Em `middleware.v`, mudar `fn extract_api_key` para `pub fn extract_api_key`.
2. Em `auth_controller.v:845-852`, substituir o bloco inline por:
   ```v
   api_key := rate_limit.extract_api_key(mut ctx)
   ```

**Impacto:** -7 linhas em `auth_controller.v`. Lógica de extração em um único lugar.

---

## BAIXA PRIORIDADE — polimento

---

### #8 — `current_user_id` usa `unsafe` sem necessidade

**Problema:** `auth_controller.v:929-941`:
```v
fn (mut ac AuthController) current_user_id(mut ctx web_ctx.WsCtx) int {
    cookie_name := unsafe { ac.env.session_cookie_name }
    secret := unsafe { ac.env.session_secret }
    ...
}
```

O equivalente `logged_user_id` em `middleware.v:187-196` acessa `env.session_cookie_name` e `env.session_secret` **sem** `unsafe`. Inconsistente.

**Como resolver:**

Remover o `unsafe{}`:
```v
fn (mut ac AuthController) current_user_id(mut ctx web_ctx.WsCtx) int {
    if ac.env.session_secret == '' { return 0 }
    token := ctx.get_cookie(ac.env.session_cookie_name) or { return 0 }
    if !auth_user.verify(ac.env.session_secret, token) { return 0 }
    claims := auth_user.decode(token) or { return 0 }
    return claims.sub
}
```

**Impacto:** Consistência. Se o checker do V reclamar, é porque `ac` é `mut` e o campo `env` é `pub` (não `pub mut`) — nesse caso, o acesso é read-only e seguro; o `unsafe` mascara isso.

---

### #9 — `int_from_row` / `val_int` duplicados entre módulos

**Problema:**
- `repository/auth/users.v:107-115` — `int_from_row(r, idx) int`
- `repository/rate_limit/credits.v:76-84` — `val_int(r, idx) int`

Fazem a mesma coisa: extrair int de `pg.Row.vals[idx]` com fallback seguro.

**Como resolver (opções):**

**Opção A (recomendada — baixo impacto):** Deixar como está. Cada módulo é independente, a duplicação é de 8 linhas isoladas, e mover para um módulo `shared` criaria uma nova dependência só para 8 linhas. O custo cognitivo de "viajar" para um terceiro módulo é maior que o benefício.

**Opção B (se preferir eliminar):** Criar `shareds/pg_helpers.v`:
```v
module pg_helpers
import db.pg
pub fn row_int(r pg.Row, idx int) int { ... }
pub fn row_str(r pg.Row, idx int) string { ... }
```
Importar em ambos módulos.

**Impacto:** Opcional. A duplicação é pequena e isolada. Recomendação: deixar como está.

---

### #10 — `is_plan_allowed` duplicado no frontend

**Problema:** `dashboard.html:651-657` replica a regra do backend:
```js
isPlanAllowed(keyPlan) {
    const userPlan = this.user && this.user.plan ? this.user.plan : 'free';
    if (keyPlan === 'free') return true;
    if (keyPlan === 'plan5') return ['plan5', 'plan10', 'planannual'].includes(userPlan);
    if (keyPlan === 'plan10') return ['plan10', 'planannual'].includes(userPlan);
    return false;
}
```

vs `middleware.v:118-129`:
```v
pub fn is_plan_allowed(key_plan string, user_plan string) bool {
    if key_plan == 'free' { return true }
    if key_plan == 'plan5' { return user_plan in ['plan5', 'plan10', 'planannual'] }
    if key_plan in ['plan10', 'planannual'] { return user_plan in ['plan10', 'planannual'] }
    return false
}
```

**Como resolver:**

Esta duplicação é **inevitável** no stack atual (backend V + frontend JS no dashboard). Opções:

**Opção A (recomendada — pragmática):** Documentar a dependência com comentário nos dois lados:
```v
// ATENCAO: regra espelhada em pages/dashboard.html:isPlanAllowed().
// Mudancas aqui exigem mudanca no frontend.
```
```js
// ATENCAO: espelha shareds/rate_limit/middleware.v:is_plan_allowed.
// Mudancas aqui exigem mudanca no backend.
```

**Opção B (se quiser single-source-of-truth):** Expor um endpoint `GET /auth/allowed-plans` que retorna os planos permitidos para o usuário corrente, e o dashboard consulta ao renderizar o dropdown. Custo: 1 request extra por load do dashboard.

**Impacto:** Polimento. Recomendação: Opção A (comentar a dependência).

---

## Resumo da ordem de execução

| Ordem | Item | Arquivos modificados | Depende de |
|---|---|---|---|
| 1 | #1 `plan_limits()` | `middleware.v`, `auth_controller.v` | — |
| 2 | #7 `extract_api_key` → pub | `middleware.v`, `auth_controller.v` | — |
| 3 | #2 Simplificar `rate_limit_status` | `auth_controller.v` | #1, #7 |
| 4 | #3 `find_id_by_stripe_customer` | `repository/auth/users.v`, `auth_controller.v` | — |
| 5 | #4 Colapsar 9 structs → 3 | `auth_controller.v` | — |
| 6 | #5 Hoist `ensure_credit_row` | `middleware.v` | — |
| 7 | #6 Fix `db_conn()` branch morto | `auth_controller.v` | — |
| 8 | #8 Remover `unsafe` de `current_user_id` | `auth_controller.v` | — |
| 9 | #9 `int_from_row` duplicado | (opcional) | — |
| 10 | #10 `is_plan_allowed` frontend | (comentar) | — |

**Itens 1-7 são os que trazem ganho real de legibilidade/manutenibilidade.**
**Itens 8-10 são polimento opcional.**

---

## Verificação pós-implementação

Após aplicar as mudanças, rodar:

```bash
# Build (verifica compilação)
v -d using_sqlite . 3330   # smoke test — iniciar e bater em /ping

# Testes
v test tests/
```

Verificar manualmente:
- Dashboard carrega perfil, keys, rate-limit-status
- Webhook Stripe continua processando (com struct unificada)
- Rate-limit continua bloqueando após limite
- API key com plano revogado cai para plano do usuário