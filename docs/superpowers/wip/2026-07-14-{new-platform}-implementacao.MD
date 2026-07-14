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

- O que foi feito: branch criada; estado anterior registrado no commit `0b029c3`; testes baseline executados.
- Por que foi feito: separar historico anterior do novo deploy.
- Onde foi feito: [repositorio](../../../)
- O que nao foi feito: tarefas de infraestrutura ainda em execucao.

## Commits Relacionados Ao Card

Repositorio: `tabua_mare_api`
- Branch: `feature/new-plataform`
- Base/destino: `wip/auth-rate-limit-google-login-premium` em `e9c036d`
- Commits:
  - `0b029c3` - `chore: preserve pre-platform work` - 2026-07-14 - baseline anterior a infraestrutura
- Push/PR: not pushed

## Validacao

- Validacoes feitas: `git diff --check`; scan de padroes de segredo; `v test tests/` com 2 arquivos aprovados.
- Validacoes nao feitas: Docker Alpine e producao.
- Motivo das validacoes nao feitas: implementacao ainda em curso; Docker local inicialmente indisponivel.

## Riscos E Pendencias

- Stripe local usa modo test; producao deve permanecer bloqueada.
- Token Cloudflare restrito, primeiro admin Coolify e configuracoes Google/Stripe exigem acao/credencial do usuario.
- Firewall de origem deve ser aplicado sem perder acesso SSH.

## Proximo Teste Esperado

- RED/GREEN dos endpoints de health e estado de shutdown.
