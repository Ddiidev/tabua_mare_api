# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**See [AGENTS.md](AGENTS.md) for the full, up-to-date documentation.**

## Quick Reference

```bash
# Run locally (port required as argument)
v run -d using_sqlite . 3330

# Run tests
v test tests/

# Build production binary
v -prod . -o TabuaMareAPI
```

## Key Points

- **V language** + `veb` web framework. Tide table API for Brazilian ports.
- **Split persistence**: SQLite (tide data) + PostgreSQL external (auth/dash/rate_limit).
- **V2 is current** (`/api/v2`, harbor IDs are strings like `pb01`). V1 responds 410 Gone.
- **Auth**: Google OAuth + JWT HS256 (`SESSION_SECRET`). `/auth/me` reads plan from DB.
- **Rate limiting** (middleware on `/api/v2/*`): sem api_key 16 RPM por IP, Free com chave 64 RPM/32k mês, Plan5 512 RPM/256k, Plan10 2.048 RPM/unlimited, Anual 4.096 RPM/unlimited.
- **Stripe**: checkout, webhooks, billing portal, cancel subscription.
- **Templating**: `leafscale.veemarker` uses `${ ... }` — never use JS `${...}` template literals in `.html` files.
- **Dashboard**: PetiteVue, API keys masked (copy allowed, no reveal).

Full architecture, directory structure, and security notes in [AGENTS.md](AGENTS.md).
