# Nova Plataforma de Producao - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publicar a API em duas aplicacoes Coolify com imagem Alpine, SQLite exclusivo por instancia, TLS Cloudflare/Let's Encrypt e deploy A/B sequencial com rollback.

**Architecture:** Cloudflare proxy encaminha somente para Traefik do Coolify. Traefik distribui entre `tabuamare-a` e `tabuamare-b`; cada app usa volume SQLite proprio e PostgreSQL externo comum. GitHub Actions publica imagem GHCR imutavel e aciona A, valida, depois B.

**Tech Stack:** V 0.5.2 (`45ae01d23168b6372f734eeb38a77360bbcf184a`), veb `new_veb`, Alpine 3.22, Docker, GHCR, GitHub Actions, Coolify 4.1.2, Traefik, Cloudflare DNS-01.

## Global Constraints

- Branch: `feature/new-plataform`; baseline anterior a infraestrutura: `0b029c3`.
- Imagem `linux/amd64`; V e bases fixados; sem `-march=native`; sem tag `latest`.
- Producao: duas aplicacoes regulares Coolify, nao Compose, nginx, Cloudflare Tunnel ou Swarm.
- Nunca compartilhar volume/arquivo SQLite entre A e B.
- Deploy stop-first em uma app por vez; outra app permanece saudavel.
- `GET` e `HEAD` em `/health/live` e `/health/ready`; `/ping` continua compativel.
- SIGTERM: readiness falsa, espera 6s, drain de ate 20s; stop grace 30s.
- Dominio publico `https://tabuamare.api.br`; callback Google e webhook Stripe nesse dominio.
- Producao bloqueada enquanto Stripe usar `sk_test_*`.
- Segredos fora do Git; nenhum valor secreto em log, imagem ou workflow.

---

### Task 1: Estado de saude e desligamento gracioso

**Files:**
- Modify: `main.v`
- Modify: `shareds/infradb/infradb.v`
- Create: `tests/health_state_test.v`

**Interfaces:**
- Produces: estado atomico de readiness; `sqlite_is_healthy() bool`; rotas 204/503; ciclo `init_server`/SIGTERM.

- [ ] Escrever teste que exige readiness inicial falsa, transicao para verdadeira e retorno a falsa durante shutdown.
- [ ] Rodar `v test tests/health_state_test.v` e confirmar falha pela API ausente.
- [ ] Implementar estado thread-safe e consulta SQLite `select 1` usando pool com `get()`/`put()`.
- [ ] Adicionar handlers `GET`/`HEAD` para live/ready e manter `/ping`.
- [ ] Integrar `-d new_veb`: readiness verdadeira somente apos bind; SIGTERM marca falsa, espera 6s e chama `server.shutdown(timeout: 20 * time.second)`.
- [ ] Remover `dump(ctx.ip())`.
- [ ] Rodar teste novo e suite `v test tests/`.

### Task 2: Imagem Alpine e seed SQLite atomico

**Files:**
- Replace: `Dockerfile`
- Create: `dockerfiles/entrypoint-alpine.sh`
- Create: `scripts/test_seed_sqlite.sh`
- Modify: `.dockerignore`

**Interfaces:**
- Produces: `/app/TabuaMareAPI`, `/app/seed/taubinha.sqlite`, `/app/seed/taubinha.sqlite.sha256`, volume `/app/data` e UID nao-root.

- [ ] Escrever teste shell com volume vazio, seed igual, seed novo valido e seed corrompido.
- [ ] Confirmar RED: `bash scripts/test_seed_sqlite.sh` falha sem entrypoint novo.
- [ ] Criar builder/runtime `alpine:3.22`; checkout V no commit exato; instalar dependencias build/runtime minimas.
- [ ] Compilar com `-cc gcc -ldflags "-Wl,--gc-sections -ffunction-sections -fdata-sections" -gc boehm_incr_opt -d using_sqlite -d use_openssl -d new_veb -prod`.
- [ ] Validar seed com `PRAGMA quick_check`; copiar para temporario, `chown`, `mv` atomico; remover `-wal`/`-shm`; usar `su-exec` e `tini`.
- [ ] Rodar teste shell, `docker build --platform linux/amd64` e `scanelf --needed` quando Docker estiver disponivel.

### Task 3: Compose local A/B

**Files:**
- Replace: `docker-compose.yml`
- Remove from active path: `dockerfiles/Dockerfile.compose`, `dockerfiles/Dockerfile.tabuamare`, `dockerfiles/entrypoint.sh`, `deploy.sh`
- Create: `scripts/smoke_compose.sh`

**Interfaces:**
- Produces: `tabuamare-a` e `tabuamare-b`, portas locais distintas, volumes `sqlite-a` e `sqlite-b`.

- [ ] Criar teste de configuracao `docker compose config` que rejeita volume SQLite compartilhado.
- [ ] Definir duas instancias da mesma imagem/build, sem nginx/cloudflared, cada uma com volume proprio em `/app/data`.
- [ ] Adicionar healthcheck `/health/ready`, `stop_grace_period: 30s`, limites 2 CPU/512 MiB e reserva 256 MiB.
- [ ] Subir, confirmar mount IDs diferentes e executar smoke em `/health/ready` e `/api/v2`.

### Task 4: Dominio e configuracao publica

**Files:**
- Modify: `.env.template`, `README.md`, `main.v`, `pages/*.html`, `shareds/components_view/**`

**Interfaces:**
- Produces: canonical/OG/runtime apontando para `https://tabuamare.api.br`.

- [ ] Criar verificacao que falha se o dominio antigo permanecer em arquivos ativos.
- [ ] Trocar canonical, OG, exemplos, `URL_ENV` e callback por novo dominio.
- [ ] Manter redirect do dominio antigo fora do escopo.
- [ ] Rodar busca pelo dominio antigo e validar `/docs` e `/playground` localmente.

### Task 5: CI, GHCR e deploy Coolify A/B

**Files:**
- Create: `.github/workflows/ci-image.yml`
- Create: `.github/workflows/deploy-production.yml`
- Create: `scripts/coolify_deploy.sh`
- Create: `scripts/test_coolify_deploy.sh`

**Interfaces:**
- Consumes: `COOLIFY_TOKEN`; vars `COOLIFY_URL`, `COOLIFY_APP_A_UUID`, `COOLIFY_APP_B_UUID`.
- Produces: `ghcr.io/ddiidev/tabua-mare-api:sha-<40-char-sha>` e atualizacao sequencial via API.

- [ ] Testar cliente Coolify contra servidor HTTP fake: salva tags, atualiza A, espera healthy, smoke, B; falha restaura tags antigas.
- [ ] CI em PR/push: V tests com PostgreSQL efemero, build `linux/amd64`, `scanelf`, smoke e push GHCR somente em eventos autorizados.
- [ ] Deploy somente `workflow_dispatch`; validar SHA, existencia da imagem e variaveis.
- [ ] Implementar polling com timeout, mensagens sem token e rollback dos dois apps.
- [ ] Rodar testes do script e validar YAML.

### Task 6: Automacao da VPS, firewall e Traefik

**Files:**
- Create: `run_ssh.sh`
- Create: `ops/bootstrap_vps.sh`
- Create: `ops/cloudflare-origin-firewall.sh`
- Create: `ops/traefik/dynamic/tabuamare.yaml`
- Create: `ops/README.md`

**Interfaces:**
- Consumes local: `~/.config/tabua-mare/ssh.env`; key `/mnt/c/Users/andre/.ssh/tabua-api`.
- Consumes VPS: `/root/.config/tabua-mare/cloudflare.env` modo 600.
- Produces: Coolify 4.1.2, swap 2 GiB, swappiness 10, fail2ban, firewall Cloudflare-only e LB A/B.

- [ ] Testar `run_ssh.sh --dry-run` sem imprimir senha e preferindo chave.
- [ ] Criar bootstrap idempotente para Ubuntu 24.04; fixar Coolify 4.1.2 e desativar auto-update.
- [ ] Criar atualizador idempotente de ranges IPv4/IPv6 Cloudflare em `ipset`/`DOCKER-USER`; bloquear 8000/6001/6002 e acesso direto a 80/443.
- [ ] Criar Traefik DNS-01 `cloudflare`, routers apex/www/admin, redirect www e service A/B com healthcheck 5s/2s.
- [ ] Validar scripts com `bash -n` e `shellcheck` quando disponivel.
- [ ] Executar bootstrap por SSH; cadastro inicial do Coolify continua manual via tunnel localhost:8000.
- [ ] Antes de endurecer SSH, abrir nova conexao por chave; entao aplicar `PasswordAuthentication no` e `PermitRootLogin prohibit-password`.

### Task 7: Integracao e aceite

**Files:**
- Update: `docs/superpowers/wip/2026-07-14-{new-platform}-implementacao.MD`

**Interfaces:**
- Consumes: todas as entregas anteriores.

- [ ] Rodar `git diff --check`, testes V, testes shell e build Alpine.
- [ ] Testar SIGTERM com request em voo e saida menor que 30s.
- [ ] Verificar volumes A/B diferentes, health, API v2 e ausencia de 5xx durante troca sequencial.
- [ ] Confirmar TLS, cache bypass, IP real, portas bloqueadas, Google OAuth e Stripe live.
- [ ] Registrar validacoes impossiveis e credenciais/acoes manuais pendentes sem expor segredos.
