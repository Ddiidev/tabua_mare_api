# New Platform - Coolify A/B

Gerado em: 2026-07-14
Sessao/contexto: new-platform
Tipo de registro: implementacao

## Card

Arquivo do plano: [2026-07-14-new-production-platform.md](../plans/2026-07-14-new-production-platform.md)

Resumo:
- Migrar producao para Cloudflare proxy, Traefik/Coolify e duas apps V.
- Isolar SQLite por instancia e publicar imagem Alpine imutavel.
- Implantar A/B sequencial com health gate e rollback.

## Pedido Do Usuario

Pedido literal:
> PLEASE IMPLEMENT THIS PLAN: Nova plataforma de producao Tabua de Mares.

Classificacao:
- Pedido explicito: implementar integralmente aplicacao, imagem, CI, scripts operacionais e setup Coolify/VPS.
- Restricoes explicitas: sem nginx/Tunnel/Swarm; dois SQLite; Alpine; Coolify 4.1.2; Cloudflare proxy e Full strict; Stripe live antes do go-live.

## Interpretacao E Inferencias

- Inferencia operacional: manter checkout atual, criar `feature/new-plataform` e registrar todo estado sujo num commit baseline.
- Motivo: mudancas nao registradas pertencem ao usuario e o plano exige preserva-las antes da infraestrutura.
- Risco da inferencia: commit baseline grande, mas separado das alteracoes de plataforma.

## Implementacao Ou Alteracao

- Aplicacao: health live/ready, SIGTERM com retirada e drain, SQLite consultavel e dominio publico novo.
- Imagem: Alpine 3.22, V 0.5.2 fixo, usuario nao-root e seed SQLite atomico.
- Local: Compose A/B com volumes SQLite exclusivos.
- Entrega: CI/GHCR por SHA e deploy Coolify A/B sequencial com health, smoke e rollback.
- VPS: Ubuntu atualizado, fail2ban, swap 2 GiB, swappiness 10, firewall Cloudflare-only fail-closed e Coolify 4.1.2 fixo.
- Painel: porta 8000 bloqueada externamente; tunnel local ativo para cadastro inicial.
- Cloudflare: `CF_DNS_API_TOKEN` detectado em configuracao segura sem leitura do valor.

## Commits Relacionados Ao Card

Repositorio: `tabua_mare_api`
- Branch: `feature/new-plataform`
- Base/destino: `wip/auth-rate-limit-google-login-premium` em `e9c036d`
- Commits:
  - `0b029c3` - `chore: preserve pre-platform work` - 2026-07-14 - baseline anterior a infraestrutura
  - `4d0f942` - `docs: plan new production platform`
  - `721c59e` - `feat: add health checks and graceful shutdown`
  - `b49b1e6`..`f6a5919` - imagem Alpine e seed SQLite
  - `21a3c03`..`a903d2f` - Compose local A/B
  - `e8e57df`..`bba0f6d` - dominio de producao
  - `86ea0a6`..`3a8e014` - CI/GHCR/deploy Coolify
  - `3d9ee20`..`7e96d61` - automacao VPS e hardening fail-closed
- Push/PR: pendente da validacao integrada final.

## Validacao

- Locais: testes V, testes shell, `bash -n`, ShellCheck 0.11.0, actionlint 1.7.12, lint YAML, dominio e `git diff --check`.
- VPS: Coolify `docker.io/coollabsio/coolify:4.1.2` healthy; `LATEST_IMAGE=4.1.2`; `AUTOUPDATE=false`; firewall/fail2ban/Docker ativos; swap exata 2 GiB; `vm.swappiness=10`.
- Rede: 8000/6001/6002/80/443 bloqueadas no IP direto; painel responde 200 em `/register` via tunnel; ranges Cloudflare carregados em ipset (14 IPv4, 6 IPv6).
- Incidente controlado: primeiro bootstrap detectou recreate em tag `latest`, recusou o estado e saiu. Correcao persistiu `LATEST_IMAGE=4.1.2`; segunda execucao concluiu idempotentemente.
- Ainda nao validados: build/smoke Docker Alpine no GitHub Actions, TLS publico, login Google e Stripe live.

## Riscos E Pendencias

- Stripe local usa modo test; producao permanece bloqueada.
- Primeiro admin Coolify ainda precisa ser criado pelo usuario em `http://localhost:8000/register` pelo tunnel ativo.
- SSH por senha continua habilitado intencionalmente. Endurecer somente depois do admin e de nova conexao por chave.
- Aplicacoes A/B, TLS DNS-01, Google callback e Stripe live dependem do admin/credenciais finais.
- Recovery bundle inicial do Coolify ainda precisa ser salvo fora da VPS e do repositorio.

## Proximo Teste Esperado

- Criar admin Coolify; publicar branch; validar CI/GHCR; configurar apps A/B e TLS DNS-01.
