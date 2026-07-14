# Stripe Pricing and Annual Plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Separar Prices dev/live por flag de compilação e exibir o Plano Anual com economia nominal consistente.

**Architecture:** `shareds/conf_env` seleciona IDs via `$if env_dev`; sem a flag usa os IDs live fixos. As páginas públicas, dashboard e docs compartilham os mesmos valores comerciais visíveis: R$ 10/mês, R$ 70/ano, 2.048 req/min e economia de R$ 50/ano.

**Tech Stack:** V, veemarker, PetiteVue, testes V.

## Global Constraints

- `-d env-dev` mantém os Prices atuais vindos de `STRIPE_PRICE_*`.
- Sem `-d env-dev`, usar somente os IDs live definidos pelo requisito.
- Não alterar Prices antigos na Stripe.
- Não exibir economia percentual como destaque.

### Task 1: Seleção de Prices

**Files:** `shareds/conf_env/conf_env.v`, `tests/stripe_prices_test.v`

- [ ] Testar IDs live padrão.
- [ ] Rodar `v test tests/stripe_prices_test.v` e confirmar falha antes da implementação.
- [ ] Implementar seleção compile-time e manter leitura de `.env` em `env-dev`.
- [ ] Rodar testes padrão e `v -d env-dev test tests/stripe_prices_test.v`.

### Task 2: Interface e documentação de planos

**Files:** `pages/index.html`, `pages/dashboard.html`, `pages/docs.html`

- [ ] Adicionar card público do anual.
- [ ] Exibir R$ 50/ano de economia e 2.048 req/min.
- [ ] Remover divergências de 4.096 req/min e percentuais.
- [ ] Validar referências restantes com `rg`.

### Task 3: Verificação

- [ ] Rodar `v test tests/`.
- [ ] Rodar build/check disponível para o projeto.
- [ ] Revisar diff e preservar alterações pré-existentes.
