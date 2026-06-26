# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Brazilian tide table (Tábua de Marés) REST API built with **V language** (`vlang`) using the `veb` web framework. Serves tidal data for Brazilian coastal ports via PostgreSQL in production and SQLite for development.

## Common Commands

```bash
# Run locally (port required as argument)
v run . 3330

# Build production binary
v -prod . -o TabuaMareAPI

# Run with SQLite instead of PostgreSQL
v run -d using_sqlite . 3330

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

Copy `.env.template` to `.env` with these variables:

```
DB_DATABASE=
DB_USER=
DB_HOST=localhost
DB_PASS=
DB_PORT=5432
DB_SQLITE_PATH=./data.db   # only for -d using_sqlite builds
NEW_RELIC_KEY=
URL_ENV=http://localhost:3330
```

## Architecture

### Entry Point & Controllers

- **`main.v`** — starts the `veb` server, registers two API controllers and static file serving. The `App` struct handles HTML page routes (`/`, `/docs`, `/playground`, `/apoiar`).
- **`api.v`** — `APIController` for `/api/v1` (deprecated; harbor IDs are integers).
- **`api_v2.v`** — `APIControllerV2` for `/api/v2` (current; harbor IDs are strings like `pb01`).
- **`api.v`** — `APIController` for `/api/v1` (deprecated; all handlers respond 410 Gone with link to /docs).
- **`auth_controller.v`** — `AuthController` for `/auth` (Google OAuth login, callback, logout, /me).

### Key Architectural Patterns

**Two database backends (split persistence):**
- **SQLite** (`shareds/infradb`) — tide data (data_mare, month_data, day_data, hour_data, geo_location). Always-on.
- **PostgreSQL external** (`shareds/infradb_pg`) — users, user_identities, session_tokens, api_keys, rate_limit_counters, monthly_credits, tabuamare_dash tables. Always-on (independent of `-d using_sqlite`). Postgres is external (env vars `DB_*` from the system environment, not from `.env` file).

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
  conf_env/    — .env loading into EnvConfig struct
  infradb/     — connection pool factory (SQLite/PG conditional)
  web_ctx/     — veb context type (WsCtx)
  types/       — shared API types (ResultAPI, FloatArr, IntRangeArr, etc.)
  logger/      — logging utilities
  components_view/ — HTML components (navbar, footer, open_graph) for pages

repository/
  habor_mare/  — harbor queries (find nearest, list by state, etc.)
  tabua_mare/  — tide table data queries with ORM

entities/      — ORM struct definitions (DataMare, MonthData, DayData, HourData)
cache/         — in-memory TTL cache (5-minute expiry)
domain/        — auth domain
pages/         — HTML templates rendered via leafscale.veemarker
tests/         — integration tests (_test.v files, require DB)
```

### V1 vs V2 Difference

The only structural difference between V1 and V2 is how harbor IDs are handled:
- **V1**: harbor IDs are database integers (`harbor_id int`) — **deprecated, all handlers respond 410 Gone** with message "API v1 depreciada; use a v2. Docs: /docs".
- **V2**: harbor IDs are state-prefixed strings (`harbor_id string`, e.g., `"pb01"`)

V1 is kept registered (responds 410, no data) to avoid free rate-limit bypass and to guide clients to migrate. New endpoints should only be added to V2.

### Authentication & Rate Limiting

- **Google OAuth login** — `/auth/google` redirects to Google consent; `/auth/google/callback` exchanges code, upserts user in PostgreSQL, issues JWT (HS256), sets HttpOnly cookie. `/auth/logout` clears cookie. `/auth/me` returns current user.
- **JWT** — custom HS256 implementation in `domain/auth_user/jwt.v` (not `veb.auth`). Stateless; `SESSION_SECRET` env var signs tokens.
- **Rate limiting** — middleware in `shareds/rate_limit/middleware.v`, applied to `/api/v2/*`. Free (by IP): 64 req/min + 20k req/month. Paid (by api_key): 512/2560 req/min + 250k/unlimited req/month. Counters and monthly credits persisted in PostgreSQL (`rate_limit_counters`, `monthly_credits` tables). nginx has no rate-limit (removed `limit_req_zone`); the app is the sole rate-limit layer.
- **api_key** — sent via `Authorization: Bearer <key>` or `X-Api-Key` header; identifies paid plans.

### Production Deployment

The repository supports two deployment modes:

- **Root `Dockerfile` (official single-container path)** — runs 2 app instances inside the same container on ports `3330` and `3340`, exposes nginx on `9090`, and optionally starts `cloudflared` when `CLOUDFLARE_TUNNEL_TOKEN` is present. Process management is handled by `supervisord`.
- **`docker-compose.yml` (legacy path)** — keeps the current 4-app topology behind nginx + cloudflared and explicitly builds from `dockerfiles/Dockerfile.compose`.

The production binary is compiled with boehm incremental GC and OpenSSL:
```
v -ldflags "-Wl,--gc-sections -march=native -ffunction-sections -fdata-sections" -gc boehm_incr_opt -d using_sqlite -d use_openssl -prod . -o TabuaMareAPI
```

### Templating

HTML pages use `leafscale.veemarker` (not V's built-in `$tmpl`). Templates live in `./pages/` and are rendered with a data map:
```v
engine := veemarker.new_engine(veemarker.EngineConfig{ template_dir: './pages', cache_enabled: true })
ctx.html(engine.render('index.html', data) or { '' })
```
