# AGENTS.md

Guidance for AI coding agents (Claude Code, opencode, etc.) working in this repository.

## Project Overview

Brazilian tide table (Tábua de Marés) REST API built with **V language** (`vlang`) using the `veb` web framework. Tide data is stored in SQLite in both local and production deployments; PostgreSQL stores authentication, billing, and rate-limit data in both. Includes Google OAuth login, Stripe subscriptions, API keys, and rate limiting.

## Common Commands

```bash
# Run locally (port required as argument)
v run . 3330

# Alternate local build with the using_sqlite tag; auth/rate-limit persistence remains PostgreSQL
v run -d using_sqlite . 3330

# Quick local production-mode build (Docker build flags are listed below)
v -prod . -o TabuaMareAPI

# Run tests under tests/ (SQLite data file required; PostgreSQL migration tests are opt-in)
v test tests/

# Run a single test file
v test tests/find_nearested_harbor_test.v

# Build the per-route CSS assets used by the pages
npm ci
npm run css:build

# Docker production build (Alpine, uma app por container)
docker build --platform linux/amd64 -t tabua-mare-api:local .
```

Tests under `tests/` use `DB_SQLITE_PATH`. PostgreSQL migration tests run only when `RUN_POSTGRES_TEST=1` and `POSTGRESQL_CONN_STR` points to a test database. CI sets both dependencies and runs these tests plus Alpine image and A/B smoke checks.

## Environment Setup

Copy `.env.template` to `.env` and set the values needed for the environment. `DB_SQLITE_PATH` is used by the tide-data SQLite pool in every build. Production requires `POSTGRESQL_CONN_STR`; local/non-production builds can initialize PostgreSQL from `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USER`, and `DB_PASS` when the connection string is empty.

```
DB_SQLITE_PATH=./taubinha.sqlite          # SQLite file used for tide data in every build
POSTGRESQL_CONN_STR=postgresql://...      # required in production; auth/rate_limit/usage data
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GOOGLE_REDIRECT_URI=https://.../auth/google/callback
SESSION_SECRET=...                        # JWT HS256 signing key
STRIPE_SECRET_KEY=sk_test_...             # or sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_PLAN15=price_...
STRIPE_PRICE_PLAN70=price_...
STRIPE_PRICE_PLAN30=price_...
STRIPE_PRICE_PLAN150=price_...
RATE_LIMIT_FREE_RPM=24
RATE_LIMIT_PLAN15_RPM=512
RATE_LIMIT_PLAN30_RPM=2048
RATE_LIMIT_ANON_RPM=16
RATE_LIMIT_FREE_MONTHLY=32000
RATE_LIMIT_PLAN15_MONTHLY=256000
RATE_LIMIT_PLAN30_MONTHLY=0               # 0 = unlimited
RATE_LIMIT_ANON_MONTHLY=0
URL_ENV=http://localhost:3330
```

Rate-limit variables are optional and default to the values shown. `plan70` uses the limits configured for `plan15`; `plan150` uses those for `plan30`. Stripe price IDs come from `STRIPE_PRICE_*` only in builds with `-d env_dev`; other builds use the live IDs defined in code.

## Architecture

### Entry Point & Controllers

- **`main.v`** — starts the `veb` server, registers V2 and auth controllers, static assets, and health routes. `App` serves `/`, `/docs`, `/playground`, `/apoiar`, `/privacidade`, `/termos`, `/rate-limit-test`, and `/dashboard`; `/` negotiates HTML or Markdown from `Accept`.
- **`api_v2.v`** — `APIControllerV2` for `/api/v2` (current; harbor IDs are strings like `pb01`, and `/usage` reports monthly usage for an API key). Rate-limit middleware is applied to this controller.
- **`auth_controller.v`** — `AuthController` for `/auth` (Google OAuth login/callback/logout, `/me`, `/avatar`, API-key list/create/revoke, `/checkout`, `/webhook`, `/billing-portal`, `/cancel-subscription`, and `/rate-limit-status`). `PgHolder` uses `POSTGRESQL_CONN_STR`; local/non-production can also use `DB_*`. `db_conn()` errors when the holder is unavailable.
- **Machine-readable docs** — `/openapi.json` (OpenAPI 3.1.1) and `/llms.txt` are served from `pages/static/`.
- **Health routes** — `/ping`, `/health/live`, `/health/ready`, and `/health/debug`; readiness requires healthy SQLite and PostgreSQL. Nginx only forwards `/health/debug` when the deploy-slot secret matches.

### Key Architectural Patterns

**Two database backends (split persistence):**
- **SQLite** (`shareds/infradb`) — tide data (`data_mare`, `month_data`, `day_data`, `hour_data`, `geo_location`). Always used, including production; `using_sqlite` does not switch the auth database.
- **PostgreSQL** (`shareds/infradb_pg`) — users, identities, API keys, rate-limit counters, and monthly credits. `session_tokens` is still created by migration but is not used by the current JWT auth flow. The `tabuamare_dash` repository reads the same PostgreSQL tables; it does not have separate dashboard tables. Production requires `POSTGRESQL_CONN_STR`; outside production, `PgHolder` also accepts individual `DB_*` settings.

The app can start in non-production without PostgreSQL, but PostgreSQL-backed routes fail and `/health/ready` stays unavailable. Production startup validates `POSTGRESQL_CONN_STR`.

Repositories of maré use SQLite (`db.sqlite`); repositories of auth/dash/rate_limit use PostgreSQL (`db.pg`). Do not cross pools.

**SQLite connection pool usage** — repositories receive `pool.ConnectionPool`; return every connection with `.put()` on all exit paths. Use `defer` so query errors do not leak connections:
```v
conn := pool_conn.get()!
mut db := conn as sqlite.DB
defer {
    pool_conn.put(conn) or { println(err.msg()) }
}
```

PostgreSQL repositories receive the shared `&pg.DB` from `PgHolder`; the `pg.DB` driver manages its own thread-safe connection pool. Do not call SQLite pool `.get()`/`.put()` for PostgreSQL.

**API response wrapper** — JSON API handlers generally use `types.ResultAPI[T]` via `types.success(data)` or `types.failure(code, message)`. Page routes, redirects, health checks, and the Stripe webhook response have their own response shapes.

**Route parameter parsing** — Veb passes these path segments as strings; handlers explicitly convert them with helpers in `shareds/types/`:
- `types.IntRangeArr(days).ints()` — parses `[1,2,10-30]` into `[]int`
- `types.FloatArr(lat_lng).list_float()` — parses `[-7.11509,-34.864]` into `[]f64`
- `types.StringRange(ids).list_string()` — parses `[pb01,pe02]` into `[]string`

### Directory Structure

```
shareds/
  auth_user/       — JWT, Google OAuth client, avatar cache
  conf_env/        — .env loading into EnvConfig struct
  geohash/         — geohash encoding used by nearest-harbor lookup
  infradb/         — SQLite connection pool factory
  infradb_pg/      — PostgreSQL connection + migrations
  health/          — readiness and shutdown state
  instance/        — response header identifying the serving slot
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

entities/          — ORM/domain structs for tide data, users, API keys, and rate-limit records
cache/             — in-memory TTL cache (5-minute expiry)
domain/            — auth domain (JWT, Google OAuth, avatar cache)
pages/             — HTML templates rendered via leafscale.veemarker
tests/             — unit and integration tests; SQLite-backed tests need the local data file, PostgreSQL migration tests are opt-in
```

### V1 vs V2 Difference

- **V1**: no `/api/v1` controller is registered. Requests to that prefix reach the generic API not-found handler and return JSON 404; there are no V1 handlers returning 410.
- **V2**: the only registered API controller is `/api/v2`; harbor IDs are state-prefixed strings (e.g., `"pb01"`). The docs and playground expose V2.

### Authentication & Rate Limiting

- **Google OAuth login** — `/auth/google` redirects to Google consent; `/auth/google/callback` exchanges code, upserts user in PostgreSQL, issues JWT (HS256), and sets an HttpOnly cookie. `/auth/logout` clears cookie. `/auth/me` reads the plan from PostgreSQL and falls back to the JWT claim if that lookup fails.
- **JWT** — custom HS256 in `domain/auth_user/jwt.v` (not `veb.auth`). Stateless; `SESSION_SECRET` env var signs tokens. `hmac.equal` used for constant-time comparison.
- **Rate limiting** — middleware in `shareds/rate_limit/middleware.v`, applied to `/api/v2/*`:

| Tier | RPM | Monthly |
|---|---|---|
| Anon (sem api_key, por IP) | 16 | unlimited |
| Free (api_key) | 24 | 32.000 |
| Pro (`plan15`/`plan70`) | 512 | 256.000 |
| Ultra (`plan30`/`plan150`) | 2.048 | unlimited |

  Counters and monthly credits are persisted in PostgreSQL. Sem `api_key`, o middleware trata a requisição como anônima por IP (bucket compartilhado `ip:...`, 16 RPM); com `api_key` válida, o bucket é isolado por usuário (`user:<user_id>`) e os limites seguem o plano atual do usuário — Free com api_key tem 24 RPM **não concorrentes** (não divide cota com outros clientes do mesmo IP). O middleware da aplicação limita `/api/v2/*`; o Nginx também limita `/auth/checkout` a 5 req/min por IP, com burst de 10.

  **Preços/planos (nomenclatura interna = preço):** `plan15` Pro R$14,99/mês; `plan70` Pro anual R$69,99/ano; `plan30` Ultra R$29,99/mês; `plan150` Ultra anual R$149,99/ano. Migration `remap_legacy_plans` (infradb_pg) converte `plan5→plan15`, `plan10→plan30`, `planannual→plan150` no startup.

  **IP real em produção:** o fluxo é Cloudflare proxy → Nginx → Coolify A/B. Nginx configura `CF-Connecting-IP` como IP real e a regra de firewall em `ops/cloudflare-origin-firewall.sh` limita 80/443 às faixas Cloudflare. Preserve essa restrição: o cabeçalho só é confiável quando o acesso direto à origem está bloqueado.

- **Priority tiers (planned, not yet implemented as a queue):**

| Priority | Tier | Bucket | Notes |
|---|---|---|---|
| 0 (highest) | Ultra (`plan30`/`plan150`) | `user:<user_id>` | api_key required |
| 1 | Pro (`plan15`/`plan70`) | `user:<user_id>` | api_key required |
| 2 | Free with api_key | `user:<user_id>` | free tier but authenticated by key |
| 3 (lowest) | Anon / Free without api_key | `ip:<client_ip>` | shared IP bucket — distributed among all clients without key on the same egress IP |

  Rationale: Free users **with** an api_key (priority 2) must take precedence over clients **without** an api_key (priority 3), because the key proves isolated identity. When a future priority queue is added, lower numeric priority wins; on contention, priority 3 requests are throttled first.

- **api_key** — sent via `Authorization: Bearer <key>` or `X-Api-Key` header; `extract_api_key` also accepts a raw `Authorization` value or `api_key` form field. O banco ainda guarda um `plan` na linha da chave, mas o middleware atual ignora esse campo e usa o plano atual do usuário dono (`user:<user_id>`). `is_plan_allowed`/`effective_plan` existem com testes, mas não são usados pelo fluxo atual de resolução da chave.
- **plan_limits(env, plan)** — single source of truth for `(limit_rpm, limit_monthly)` per plan. Defined in `shareds/rate_limit/middleware.v`, used by middleware and `/auth/rate-limit-status`.
- **extract_api_key(ctx)** — `pub` in `shareds/rate_limit/middleware.v`. Accepts a Bearer or raw `Authorization` value, `X-Api-Key`, or `api_key` form field. Reused by middleware and `/auth/rate-limit-status`.
- **Stripe webhooks** — `/auth/webhook` verifies the signature with `STRIPE_WEBHOOK_SECRET` (300s tolerance). Handles `checkout.session.completed`, `customer.subscription.created/updated/deleted`, and `invoice.payment_failed`. Checkout completion fetches the Checkout Session from Stripe and updates plan/customer/subscription IDs. Subscription events set the plan from status and `plan_code` metadata; deletion sets Free. Payment failure sets Free only when Stripe reports no active subscription. Subscription/invoice raw bodies use `StripeWebhookEvent`, decoded with `json2.decode`.
- **find_id_by_stripe_customer** — `repository/auth/users.v`. Resolves `stripe_customer_id` → `user_id` used by webhook handlers.
- **Customer Portal** — `/auth/billing-portal` creates a Stripe hosted portal session for subscription management.
- **Cancel** — `/auth/cancel-subscription` calls Stripe and changes the database plan to Free immediately. If `subscription_id` is missing, it returns `portal_required`; the dashboard then opens `/auth/billing-portal` in a new tab.

### Production Deployment

- **Root `Dockerfile`** — Alpine 3.22 multi-stage, uma instância V por container na porta `3330`, UID 10001 e volume `/app/data`.
- **Produção** — duas aplicações regulares Coolify usando `ghcr.io/ddiidev/tabua-mare-api:sha-<commit>`, balanceadas pelo Nginx próprio; Compose não define os containers A/B da API.
- **CI e deploy** — `.github/workflows/ci-image.yml` roda testes nativos, build e validações da imagem Alpine, smoke A/B e publica a tag imutável no GHCR em pushes para `main`. `.github/workflows/deploy-production.yml` é manual e atualiza A, valida, depois atualiza B. Compose é usado nos serviços de Nginx de borda e observabilidade.
- **Blog** — aplicação separada (`Ddiidev/tabua-mare-api-blog`, app C no Nginx) servida em `/blog`, com `BLOG_BASE_PATH=/blog`. O blog publica o próprio `/blog/sitemap.xml` (dinâmico, um URL por post) e esse sitemap é declarado no `robots.txt` da borda (`pages/static/robots.txt`), junto com a entrada `/blog` do `pages/static/sitemap.xml`.
- **Fluxo público** — Cloudflare proxy → Nginx → A ou B; `coolify-admin` passa pelo `coolify-proxy` interno. Sem Cloudflare Tunnel ou Swarm.
- **Observabilidade de requests** — o Nginx de borda grava cada request em `/var/log/nginx/access.log` (IP real pós-Cloudflare, rota, status, latências, upstream e `slot=` do header `X-Tabuamare-Slot`). O header de slot é adicionado pelos middlewares de `/api/v2` e `/auth`; outras rotas da `App` podem aparecer sem `slot`. `TABUAMARE_SLOT` é distinta por app no Coolify. Rotação diária em `/etc/logrotate.d/tabuamare-nginx`. UIs de monitoramento via Compose próprio em `ops/observability/`: **Netdata** (RAM/CPU/rede por container, `:19999`) e **GoAccess** (dashboard do access log, `:7891`, WebSocket `:7890`), loopback-only (acesso por túnel SSH; no Sign-in do Netdata, usar "Skip and use the dashboard anonymously").
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
- O plano anual do Ultra (`plan150`) tem o mesmo limite do Ultra mensal: `2.048 req/min` e mensal ilimitado. A comunicação pública deve mostrar o valor anual e a economia em reais: Pro anual `R$ 69,99/ano` (economia de `R$ 110/ano` contra 12× R$14,99); Ultra anual `R$ 149,99/ano` (economia de `R$ 209/ano` contra 12× R$29,99).
- Assets referenciados nas páginas devem existir e responder pela rota estática antes de serem usados; preferir assets locais ou URLs oficiais verificadas.

### Preços Stripe

- `stripe_price_ids` em `shareds/conf_env/conf_env.v` é a fonte única dos IDs.
- Com `-d env_dev`, os preços vêm de `STRIPE_PRICE_PLAN15`, `STRIPE_PRICE_PLAN70`, `STRIPE_PRICE_PLAN30` e `STRIPE_PRICE_PLAN150`.
- Sem `-d env_dev`, usar os IDs live fixos definidos no código. Não criar produtos ou prices durante mudanças de interface.

### Dashboard (`pages/dashboard.html`)

Uses **PetiteVue** (lightweight Vue) for client-side reactivity. Shows:
- User profile + plan badge + monthly usage (from `/auth/rate-limit-status`)
- Plan cards (Free/Pro/Ultra); Pro and Ultra have annual billing toggles and Stripe checkout buttons
- Subscription management (billing portal opens in a new tab, cancel)
- API key list/create/revoke (dashboard masks values visually and has a copy action; there is no reveal control). `GET /auth/api-keys` currently returns full `key_value` values to the authenticated owner, so masking is client-side only. The stored key plan is informational for display; request limits follow the user's current plan. Revoked keys are filtered out server-side.
- Rate-limit test tool (configurable count, 5 parallel, stop button, optional api_key)

**Plan badge convention:** `planLabel()` in dashboard maps internal values to display labels: `plan15` → `pro`, `plan70` → `pro anual`, `plan30` → `ultra`, `plan150` → `ultra anual`. Internal values preserved everywhere (Stripe, DB, JWT, API).

## Security Notes

- `.env` is gitignored — never commit secrets.
- SQL queries use `exec_param`/`exec_param_many` (parameterized) for user input. DDL/migrations use `exec` with static strings; generated identifiers/clauses are built only from validated or internal values.
- `normalize_state_code` trims whitespace, lowercases, then requires exactly two letters before interpolation.
- JWT verification uses constant-time HMAC comparison.
- Stripe webhook signature verified before processing.
- API keys are stored as full values in PostgreSQL and returned in full by `GET /auth/api-keys`; the dashboard masks them visually (first 4 + last 4 chars) but its copy button uses the full value. Revoked keys are filtered out server-side (`revoked_at IS NULL`).
- `/api/v2` CORS is currently configured with wildcard origins, credentials enabled, and GET as the allowed method in `api_v2.v`.
- `current_user_id` extracts uid from JWT cookie; returns 0 if unauthenticated (no panic).
