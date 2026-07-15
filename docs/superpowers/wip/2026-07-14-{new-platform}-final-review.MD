# New Platform - correcoes da revisao final

Gerado em: 2026-07-14
Sessao/contexto: final-review
Tipo de registro: alteracao

## Card

Arquivo do card: [plano da nova plataforma](../plans/2026-07-14-new-production-platform.md)

Resumo:
- Fechar rate-limit e readiness quando PostgreSQL falha.
- Bloquear startup inseguro no dominio real de producao.
- Garantir smoke publico por slot e preflight Coolify antes de qualquer alteracao.

## Pedido Do Usuario

Pedido literal:
> Fix all final review Critical/Important findings in repo /home/andre/projetos/tabua_mare_api, branch feature/new-plataform.

Classificacao:
- Pedido explicito: corrigir quatro findings, adicionar regressao V/shell, atualizar operacao/WIP e commitar.
- Restricoes explicitas: sem VPS, sem push, TDD, sem atribuicao a IA.

## Interpretacao E Inferencias

- Inferencia operacional: `URL_ENV=https://tabuamare.api.br` identifica producao real; localhost/dev/CI nao exige credenciais live.
- Motivo: criterio fornecido na revisao e dominio canonico ja adotado no projeto.
- Risco da inferencia: outro dominio de producao futuro exigira ampliar explicitamente a deteccao.
- Inferencia operacional: preflight usa somente campos oficiais do GET de app/storages; seguranca de troca vem do stop-first com polling de estado.
- Motivo: OpenAPI publica portas/limites/health/storages, mas nao settings de nome consistente ou stop grace.
- Risco da inferencia: o default de 30s depende da versao Coolify `4.1.2` fixada e deve ser conferido manualmente na UI.

## Implementacao Ou Alteracao

- Rate-limit: ausencia/conexao/consulta/contador PG agora responde 503; somente limite comprovadamente excedido responde 429. Onde: [middleware](../../../shareds/rate_limit/middleware.v).
- Readiness: exige estado do servidor, SQLite e consulta `SELECT 1` no PostgreSQL; live e paginas continuam disponiveis. Onde: [main](../../../main.v), [health](../../../shareds/health/health.v), [PostgreSQL](../../../shareds/infradb_pg/infradb_pg.v).
- Startup: producao valida SESSION_SECRET, PG, Google, callback, Stripe live/webhook e prices distintos; migracao PG falha de forma fatal. Onde: [config](../../../shareds/conf_env/conf_env.v).
- Correcao da revisao independente: validacao central rejeita os placeholders literais `[PRECISA PREENCHER]` e `[PRECISA PREENCHER - 32+ bytes aleatorios]`, qualquer template entre colchetes e prefixos Stripe/Price sem payload minimo.
- Deploy: preflight das duas apps e storages valida health, recursos, porta e storage exclusivo antes do stop-first. Onde: [deploy](../../../scripts/coolify_deploy.sh).
- Smoke: header de slot seleciona routers A/B de prioridade 100; rota normal continua balanceada. Onde: [Traefik](../../../ops/traefik/dynamic/tabuamare.yaml).
- Revisao final 2: removidos gates JSON nao publicados de consistent-name/stop grace; deploy e rollback fazem stop-first e aguardam `exited`/`stopped` antes de PATCH/start, mantendo o outro slot saudavel.
- Revisao final 2: routers de slot tambem exigem `__DEPLOY_SMOKE_SECRET__`; script/workflow exigem `DEPLOY_SMOKE_SECRET` com no minimo 32 caracteres e nunca o registram.
- Revisao final 3: preflight exige A/B `running:healthy` e cada stop revalida o peer. Rollback B -> A interrompe se B falhar, sem parar o ultimo peer saudavel A.
- O que nao foi feito: nenhum acesso a VPS, deploy, push ou alteracao externa.

## Commits Relacionados Ao Card

Repositorio: `tabua_mare_api`
- Branch: `feature/new-plataform`
- Base/destino: `origin/feature/new-plataform` em `4d34297`
- Commits:
  - `4d34297` - `docs: record production platform rollout` - 2026-07-14 - estado anterior a revisao final.
  - Commit local deste lote: pendente no momento de gerar este registro; assunto `fix: close production deployment safety gaps`.
- Push/PR: not pushed.

## Validacao

- `v test tests/`: 5/5.
- Regressao de configuracao cobre placeholders exatos do `.env.template`, Google curto e `sk_live_`/`whsec_`/`price_` sem payload.
- Nove contratos shell, incluindo lifecycle e fake Coolify: passaram.
- Fake Coolify cobre peer down antes do deploy e falha no restore B, provando zero stop adicional do ultimo peer saudavel.
- `bash -n` em scripts shell: passou.
- ShellCheck 0.11.0 nos scripts alterados: passou.
- actionlint 1.7.12: passou.
- `v fmt -verify` e `git diff --check`: passaram.
- Nao feita: runtime Docker/Compose e build Alpine; Docker indisponivel no WSL.
- Nao feita: teste PostgreSQL real (`RUN_POSTGRES_TEST=1`); conexao de teste nao fornecida nesta sessao.

## Riscos E Pendencias

- Confirmar manualmente na UI do Coolify `4.1.2` que stop grace esta vazio/default ou em `30s`.
- Validar build/runtime Docker e PostgreSQL efemero no CI.
- Warnings V preexistentes de deprecacao `get_harbor_by_ids_v1` permanecem.

## Proximo Teste Esperado

- Executar CI com PostgreSQL efemero e Docker; depois inspecionar preflight real sem iniciar deploy.
