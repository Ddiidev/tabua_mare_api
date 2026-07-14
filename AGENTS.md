# AGENTS.md

Guidance for AI coding agents (Claude Code, opencode, etc.) working in this repository.

## Project Overview

Brazilian tide table (Tábua de Marés) REST API built with **V language** (`vlang`) using the `veb` web framework. Serves tidal data for Brazilian coastal ports via PostgreSQL in production and SQLite for development. Includes Google OAuth login, Stripe subscriptions, API keys, and rate limiting.

## Common Commands

```bash
# Run locally (port required as argument)
v run . 3330

# Run with SQLite instead of PostgreSQL (development)
v run -d using_sqlite . 3330

# Build production binary
v -prod . -o TabuaMareAPI

# Run tests (requires DB connection)
v test tests/

# Run a single test file
v test tests/find_nearested_harbor_test.v

# Docker production build (Alpine, uma app por container)
docker build --platform linux/amd64 -t tabua-mare-api:local .

# Docker Compose local A/B
docker compose up -d --build
```

## Environment Setup

Copy `.env.template` to `.env`. Required variables:

```
DB_SQLITE_PATH=./taubinha.sqlite          # only for -d using_sqlite builds
POSTGRESQL_CONN_STR=postgresql://...      # external PG (auth/dash/rate_limit)
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GOOGLE_REDIRECT_URI=https://.../auth/google/callback
SESSION_SECRET=...                        # JWT HS256 signing key
STRIPE_SECRET_KEY=sk_test_...             # or sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_PLAN5=price_...
STRIPE_PRICE_PLAN10=price_...
STRIPE_PRICE_PLANANNUAL=price_...
RATE_LIMIT_FREE_RPM=64
RATE_LIMIT_PLAN5_RPM=512
RATE_LIMIT_PLAN10_RPM=2048
RATE_LIMIT_ANON_RPM=16
RATE_LIMIT_FREE_MONTHLY=32000
RATE_LIMIT_PLAN5_MONTHLY=256000
RATE_LIMIT_PLAN10_MONTHLY=0               # 0 = unlimited
RATE_LIMIT_ANON_MONTHLY=0
URL_ENV=http://localhost:3330
```

## Architecture

### Entry Point & Controllers

- **`main.v`** — starts the `veb` server, registers controllers and static file serving. The `App` struct handles HTML page routes (`/`, `/docs`, `/playground`, `/apoiar`, `/dashboard`).
- **`api.v`** — `APIController` for `/api/v1` (deprecated; all handlers respond 410 Gone with link to /docs).
- **`api_v2.v`** — `APIControllerV2` for `/api/v2` (current; harbor IDs are strings like `pb01`). Rate-limit middleware applied here.
- **`auth_controller.v`** — `AuthController` for `/auth` (Google OAuth login/callback/logout, /me, /avatar, /api-keys CRUD, /checkout, /webhook, /billing-portal, /cancel-subscription, /rate-limit-status). `db_conn()` returns error if `POSTGRESQL_CONN_STR` is empty (no silent fallback).

### Key Architectural Patterns

**Two database backends (split persistence):**
- **SQLite** (`shareds/infradb`) — tide data (data_mare, month_data, day_data, hour_data, geo_location). Always-on.
- **PostgreSQL external** (`shareds/infradb_pg`) — users, user_identities, session_tokens, api_keys, rate_limit_counters, monthly_credits, tabuamare_dash tables. Always-on (independent of `-d using_sqlite`). Postgres connection string comes from `POSTGRESQL_CONN_STR` env var.

Repositories of maré use SQLite (`db.sqlite`); repositories of auth/dash/rate_limit use PostgreSQL (`db.pg`). Do not cross pools.

**Connection pool usage** — every repository function must call `.get()` and defer `.put()`:
```v
conn := pool_conn.get()!
db := conn as db_provider.DB
defer {
    pool_conn.put(conn) or { println(err.msg()) }
}
```

**API response wrapper** — all endpoints return `types.ResultAPI[T]` via `types.success(data)` or `types.failure(code, message)`.

**Route parameter types** — custom types in `shareds/types/` are automatically parsed from URL segments:
- `types.IntRangeArr` — parses `[1,2,10-30]` into `[]int`
- `types.FloatArr` — parses `[-7.11509,-34.864]` into `[]f64`
- `types.StringRange` — parses `["pb01","pe02"]` into `[]string`

### Directory Structure

```
shareds/
  conf_env/        — .env loading into EnvConfig struct
  infradb/         — SQLite connection pool factory
  infradb_pg/      — PostgreSQL connection + migrations
  web_ctx/         — veb context type (WsCtx)
  types/           — shared API types (ResultAPI, FloatArr, IntRangeArr, etc.)
  rate_limit/      — rate-limit middleware
  logger/          — logging utilities
  components_view/ — HTML components (navbar, footer, open_graph) for pages

repository/
  habor_mare/      — harbor queries (find nearest, list by state, etc.)
  tabua_mare/      — tide table data queries with ORM
  auth/            — users, api_keys, user_identities (PostgreSQL)
  rate_limit/      — counters and monthly credits (PostgreSQL)
  tabuamare_dash/  — dashboard metrics and billing (PostgreSQL)

entities/          — ORM struct definitions (DataMare, MonthData, DayData, HourData)
cache/             — in-memory TTL cache (5-minute expiry)
domain/            — auth domain (JWT, Google OAuth, avatar cache)
pages/             — HTML templates rendered via leafscale.veemarker
tests/             — integration tests (_test.v files, require DB)
```

### V1 vs V2 Difference

- **V1**: harbor IDs are database integers — **deprecated, all handlers respond 410 Gone**. Kept registered to avoid rate-limit bypass and guide clients to V2. The UI (docs/playground) no longer exposes V1 as a selectable option; only V2 is shown.
- **V2**: harbor IDs are state-prefixed strings (e.g., `"pb01"`). New endpoints only here.

### Authentication & Rate Limiting

- **Google OAuth login** — `/auth/google` redirects to Google consent; `/auth/google/callback` exchanges code, upserts user in PostgreSQL, issues JWT (HS256), sets HttpOnly cookie. `/auth/logout` clears cookie. `/auth/me` returns current user (plan read from DB, not JWT, so it reflects webhook updates immediately).
- **JWT** — custom HS256 in `domain/auth_user/jwt.v` (not `veb.auth`). Stateless; `SESSION_SECRET` env var signs tokens. `hmac.equal` used for constant-time comparison.
- **Rate limiting** — middleware in `shareds/rate_limit/middleware.v`, applied to `/api/v2/*`:

| Tier | RPM | Monthly |
|---|---|---|
| Anon (sem api_key, por IP) | 16 | unlimited |
| Free (api_key) | 64 | 32.000 |
| Plan 5 (api_key) | 512 | 256.000 |
| Plan 10 (api_key) | 2.048 | unlimited |
| Anual (api_key) | 2.048 | unlimited |

  Counters and monthly credits persisted in PostgreSQL. Sem `api_key`, o middleware trata a requisição como anônima por IP, independentemente de JWT; a chave válida determina o plano e o bucket isolado. A aplicação é a única camada de rate-limit.

  **IP real em produção:** o fluxo é Cloudflare proxy → Traefik → app. `veb.Context.ip()` prioriza `CF-Connecting-IP`; esse header só é confiável porque 80/443 da origem aceitam exclusivamente ranges oficiais Cloudflare. Acesso direto ao IP deve permanecer bloqueado.

- **Priority tiers (planned, not yet implemented as a queue):**

| Priority | Tier | Bucket | Notes |
|---|---|---|---|
| 0 (highest) | Plan 10 / Anual | `key:...` | api_key required |
| 1 | Plan 5 | `key:...` | api_key required |
| 2 | Free with api_key | `key:...` | free tier but authenticated by key |
| 3 (lowest) | Anon / Free without api_key | `ip:...` | shared IP bucket — distributed among all clients without key on the same egress IP |

  Rationale: Free users **with** an api_key (priority 2) must take precedence over clients **without** an api_key (priority 3), because the key proves isolated identity. When a future priority queue is added, lower numeric priority wins; on contention, priority 3 requests are throttled first.

- **api_key** — sent via `Authorization: Bearer <key>` or `X-Api-Key` header. `is_plan_allowed(key_plan, user_plan)` prevents revoked/downgraded plans from using old paid keys. Valid plans for api_keys: `free`, `plan5`, `plan10`, `planannual`.
- **plan_limits(env, plan)** — single source of truth for `(limit_rpm, limit_monthly)` per plan. Defined in `shareds/rate_limit/middleware.v`, used by middleware and `/auth/rate-limit-status`.
- **extract_api_key(ctx)** — `pub` in `shareds/rate_limit/middleware.v`. Parses Bearer, `X-Api-Key` header, or `api_key` form field. Reused by middleware and `/auth/rate-limit-status`.
- **Stripe webhooks** — `/auth/webhook` verifies signature with `STRIPE_WEBHOOK_SECRET` (300s tolerance). Handles: `checkout.session.completed`, `customer.subscription.created/updated/deleted`, `invoice.payment_failed`. Updates `users.plan`, `stripe_customer_id`, `stripe_subscription_id`. All events decoded with a single `StripeWebhookEvent` struct (`json.decode` ignores absent fields).
- **find_id_by_stripe_customer** — `repository/auth/users.v`. Resolves `stripe_customer_id` → `user_id` used by webhook handlers.
- **Customer Portal** — `/auth/billing-portal` creates a Stripe hosted portal session for subscription management.
- **Cancel** — `/auth/cancel-subscription` calls Stripe API to cancel; falls back to billing portal if no `subscription_id` saved.

### Production Deployment

- **Root `Dockerfile`** — Alpine 3.22 multi-stage, uma instância V por container na porta `3330`, UID 10001 e volume `/app/data`.
- **`docker-compose.yml`** — somente validação local A/B; volumes `sqlite-a` e `sqlite-b` separados.
- **Produção** — duas aplicações regulares Coolify usando `ghcr.io/ddiidev/tabua-mare-api:sha-<commit>`, balanceadas pelo Traefik.
- **Fluxo público** — Cloudflare proxy → Traefik/Coolify → A ou B. Sem nginx, Cloudflare Tunnel, Swarm ou Compose de produção.
- **Operação** — scripts e runbook em `ops/`; deploy manual sequencial em `.github/workflows/deploy-production.yml`.

Production binary:
```
v -cc gcc -ldflags "-Wl,--gc-sections -ffunction-sections -fdata-sections" -gc boehm_incr_opt -d using_sqlite -d use_openssl -d new_veb -prod . -o TabuaMareAPI
```

### Templating

HTML pages use `leafscale.veemarker` (not V's built-in `$tmpl`). Templates live in `./pages/` and are rendered with a data map:
```v
engine := veemarker.new_engine(veemarker.EngineConfig{ template_dir: './pages', cache_enabled: true })
ctx.html(engine.render('index.html', data) or { '' })
```

**Important:** veemarker uses `${ ... }` for server-side interpolation. Do NOT use JS template literals with `${...}` inside `.html` templates — the engine will eat them. Use string concatenation instead.

### Interface e planos

- Docs e playground devem usar labels técnicos curtos, sem excesso de emojis decorativos.
- `code` inline próximo a texto deve permanecer alinhado à linha (`vertical-align: baseline`); não usar deslocamento vertical que faça o bloco “flutuar”.
- Blocos de código e respostas do playground devem ser compactos, mantendo apenas o espaço necessário para leitura e o botão de cópia.
- Validar mudanças visuais no navegador nas rotas `/docs` e `/playground`, além de conferir `git diff --check`.
- O plano anual (`planannual`) tem o mesmo limite do Plan 10: `2.048 req/min` e mensal ilimitado. A comunicação pública deve mostrar o valor anual e a economia em reais: `R$ 70/ano`, economia de `R$ 50/ano` contra doze mensalidades de R$ 10.
- Assets referenciados nas páginas devem existir e responder pela rota estática antes de serem usados; preferir assets locais ou URLs oficiais verificadas.

### Preços Stripe

- `stripe_price_ids` em `shareds/conf_env/conf_env.v` é a fonte única dos IDs.
- Com `-d env_dev`, os preços vêm de `STRIPE_PRICE_PLAN5`, `STRIPE_PRICE_PLAN10` e `STRIPE_PRICE_PLANANNUAL`.
- Sem `-d env_dev`, usar os IDs live fixos definidos no código. Não criar produtos ou prices durante mudanças de interface.

### Dashboard (`pages/dashboard.html`)

Uses **PetiteVue** (lightweight Vue) for client-side reactivity. Shows:
- User profile + plan badge + monthly usage (from `/auth/rate-limit-status`)
- Plan cards (Free/Plan5/Plan10/Anual) with Stripe checkout buttons
- Subscription management (billing portal opens in a new tab, cancel)
- API keys CRUD (masked display, copy allowed, no reveal; revoked keys are hidden from the list)
- Rate-limit test tool (configurable count, 5 parallel, stop button, optional api_key)

**Plan badge convention:** the internal plan value `planannual` is displayed visually as `plan∞` in badges via the `planLabel()` helper. The internal value `planannual` is preserved everywhere (Stripe, DB, JWT, API), only the display label changes.

## Security Notes

- `.env` is gitignored — never commit secrets.
- SQL queries use `exec_param`/`exec_param_many` (parameterized) for user input. DDL/migrations use `exec` with static strings only.
- `normalize_state_code` validates state is exactly 2 chars a-z before interpolation.
- JWT verification uses constant-time HMAC comparison.
- Stripe webhook signature verified before processing.
- API key values are masked in the dashboard list (only first 4 + last 4 chars visible). Copy works but reveal does not. Revoked keys are filtered out server-side (`revoked_at IS NULL`) and never returned to the frontend.
- `current_user_id` extracts uid from JWT cookie; returns 0 if unauthenticated (no panic).
