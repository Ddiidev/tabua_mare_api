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

# Docker production build (single-container)
docker build -t tabua-mare-api-single .

# Docker production build (legacy compose)
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
RATE_LIMIT_FREE_RPM=24
RATE_LIMIT_PLAN5_RPM=128
RATE_LIMIT_PLAN10_RPM=256
RATE_LIMIT_ANON_RPM=5
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
- **`auth_controller.v`** — `AuthController` for `/auth` (Google OAuth login/callback/logout, /me, /avatar, /api-keys CRUD, /checkout, /webhook, /billing-portal, /cancel-subscription, /rate-limit-status).

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

- **V1**: harbor IDs are database integers — **deprecated, all handlers respond 410 Gone**. Kept registered to avoid rate-limit bypass and guide clients to V2.
- **V2**: harbor IDs are state-prefixed strings (e.g., `"pb01"`). New endpoints only here.

### Authentication & Rate Limiting

- **Google OAuth login** — `/auth/google` redirects to Google consent; `/auth/google/callback` exchanges code, upserts user in PostgreSQL, issues JWT (HS256), sets HttpOnly cookie. `/auth/logout` clears cookie. `/auth/me` returns current user (plan read from DB, not JWT, so it reflects webhook updates immediately).
- **JWT** — custom HS256 in `domain/auth_user/jwt.v` (not `veb.auth`). Stateless; `SESSION_SECRET` env var signs tokens. `hmac.equal` used for constant-time comparison.
- **Rate limiting** — middleware in `shareds/rate_limit/middleware.v`, applied to `/api/v2/*`:

| Tier | RPM | Monthly |
|---|---|---|
| Anon (no account, no api_key) | 5 | unlimited |
| Free (logged in, by IP) | 24 | 32.000 |
| Plan 5 (api_key) | 128 | 256.000 |
| Plan 10 / Anual (api_key) | 256 | unlimited |

  Counters and monthly credits persisted in PostgreSQL. The middleware reads the JWT cookie to distinguish anon from free-logged-in. nginx has no rate-limit; the app is the sole rate-limit layer.

- **api_key** — sent via `Authorization: Bearer <key>` or `X-Api-Key` header. `is_plan_allowed(key_plan, user_plan)` prevents revoked/downgraded plans from using old paid keys.
- **Stripe webhooks** — `/auth/webhook` verifies signature with `STRIPE_WEBHOOK_SECRET` (300s tolerance). Handles: `checkout.session.completed`, `customer.subscription.created/updated/deleted`, `invoice.payment_failed`. Updates `users.plan`, `stripe_customer_id`, `stripe_subscription_id`.
- **Customer Portal** — `/auth/billing-portal` creates a Stripe hosted portal session for subscription management.
- **Cancel** — `/auth/cancel-subscription` calls Stripe API to cancel; falls back to billing portal if no `subscription_id` saved.

### Production Deployment

- **Root `Dockerfile` (official single-container path)** — runs 2 app instances inside the same container on ports `3330` and `3340`, exposes nginx on `9090`, and optionally starts `cloudflared` when `CLOUDFLARE_TUNNEL_TOKEN` is present. Process management via `supervisord`.
- **`docker-compose.yml` (legacy path)** — 4-app topology behind nginx + cloudflared, builds from `dockerfiles/Dockerfile.compose`.

Production binary:
```
v -ldflags "-Wl,--gc-sections -march=native -ffunction-sections -fdata-sections" -gc boehm_incr_opt -d using_sqlite -d use_openssl -prod . -o TabuaMareAPI
```

### Templating

HTML pages use `leafscale.veemarker` (not V's built-in `$tmpl`). Templates live in `./pages/` and are rendered with a data map:
```v
engine := veemarker.new_engine(veemarker.EngineConfig{ template_dir: './pages', cache_enabled: true })
ctx.html(engine.render('index.html', data) or { '' })
```

**Important:** veemarker uses `${ ... }` for server-side interpolation. Do NOT use JS template literals with `${...}` inside `.html` templates — the engine will eat them. Use string concatenation instead.

### Dashboard (`pages/dashboard.html`)

Uses **PetiteVue** (lightweight Vue) for client-side reactivity. Shows:
- User profile + plan badge + monthly usage (from `/auth/rate-limit-status`)
- Plan cards (Free/Plan5/Plan10/Anual) with Stripe checkout buttons
- Subscription management (billing portal, cancel)
- API keys CRUD (masked display, copy allowed, no reveal)
- Rate-limit test tool (configurable count, 5 parallel, stop button, optional api_key)

## Security Notes

- `.env` is gitignored — never commit secrets.
- SQL queries use `exec_param`/`exec_param_many` (parameterized) for user input. DDL/migrations use `exec` with static strings only.
- `normalize_state_code` validates state is exactly 2 chars a-z before interpolation.
- JWT verification uses constant-time HMAC comparison.
- Stripe webhook signature verified before processing.
- API key values are masked in the dashboard list (only first 4 + last 4 chars visible). Copy works but reveal does not.
- `current_user_id` extracts uid from JWT cookie; returns 0 if unauthenticated (no panic).