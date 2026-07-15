# Repaginação SaaS/Open Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar a direção “Maré em Movimento” em todas as páginas, mantendo API e backend integralmente inalterados.

**Architecture:** A camada visual continua em templates veemarker, Pico CSS e PetiteVue. `pages/assets/custom-pico.css` concentra tokens, shell, componentes, responsividade e motion; cada template mantém apenas sua lógica atual e markup específico. Um teste V sem DB valida contratos estruturais da UI antes da verificação no navegador.

**Tech Stack:** V 0.5.1, veb, leafscale.veemarker, Pico CSS 2, PetiteVue 0.4.1, HTML/CSS/JavaScript sem bundler.

## Global Constraints

- Escopo estritamente visual/frontend.
- Não modificar `.v` de aplicação, controllers, repositories, migrations, bancos, endpoints, requests, responses, preços, limites, planos, auth, Stripe, API keys ou rate-limit.
- Preservar alterações locais já existentes em `pages/dashboard.html`, `pages/docs.html`, `pages/navbar.html`, `pages/playground.html` e `pages/assets/custom-pico.css`.
- Não usar template literals JavaScript com `${...}` dentro dos templates veemarker.
- Não adicionar biblioteca, fonte, framework de animação ou família de ícones.
- Não criar commits de implementação com arquivos previamente modificados pelo usuário sem autorização; usar checkpoints no WIP.

---

### Task 1: Contrato estrutural, tokens e shell compartilhado

**Files:**
- Create: `tests/ui_contract_test.v`
- Modify: `pages/assets/custom-pico.css`
- Modify: `pages/navbar.html`
- Modify: `pages/footer.html`

**Interfaces:**
- Consumes: templates renderizados por `shareds/components_view`.
- Produces: tokens `--ocean-950`, `--ocean-600`, `--sun-400`, `--foam-50`; classes `site-nav`, `site-footer`, `skip-link`; shell compartilhado para todas as páginas.

- [ ] **Step 1: Criar teste RED do shell**

```v
module main

import os

fn ui_file(path string) string {
    return os.read_file(path) or { panic(err) }
}

fn test_shared_shell_contract() {
    css := ui_file('pages/assets/custom-pico.css')
    navbar := ui_file('pages/navbar.html')
    footer := ui_file('pages/footer.html')
    assert css.contains('--ocean-950:')
    assert css.contains('--foam-50:')
    assert navbar.contains('class="skip-link"')
    assert navbar.contains('class="site-nav')
    assert navbar.contains('aria-expanded="false"')
    assert footer.contains('class="site-footer')
}
```

- [ ] **Step 2: Confirmar falha esperada**

Run: `v test tests/ui_contract_test.v`

Expected: FAIL em `--ocean-950:` ou `class="site-nav` ausente.

- [ ] **Step 3: Implementar shell mínimo**

Adicionar tokens no início de `custom-pico.css`, skip link antes do header, navegação com logo, Produto, Docs, Playground, Planos, GitHub e Entrar/Dashboard. Preservar condicionais veemarker existentes. Atualizar `aria-expanded` no mesmo handler do menu mobile. Reestruturar footer com blocos Projeto, Recursos e Comunidade.

```css
:root {
  --ocean-950: #082f49;
  --ocean-600: #0891b2;
  --sun-400: #f9c74f;
  --foam-50: #f7faf9;
  --line: #cfe3e8;
  --surface: #ffffff;
  --text: #102a37;
}
```

- [ ] **Step 4: Confirmar GREEN**

Run: `v test tests/ui_contract_test.v`

Expected: `1 passed`.

- [ ] **Step 5: Registrar checkpoint no WIP**

Documentar arquivos, RED/GREEN e ausência de commit por sobreposição com mudanças locais.

### Task 2: Home e console “requisição-maré”

**Files:**
- Modify: `tests/ui_contract_test.v`
- Modify: `pages/index.html`
- Modify: `pages/assets/custom-pico.css`

**Interfaces:**
- Consumes: `GET /api/v2/states`, sem chave.
- Produces: `home-hero`, `tide-console`, `tide-track`, `tide-buoy`, pricing e bloco open source.

- [ ] **Step 1: Adicionar teste RED da home**

```v
fn test_home_exposes_anonymous_live_request() {
    home := ui_file('pages/index.html')
    assert home.contains('class="home-hero')
    assert home.contains('data-ui="tide-console"')
    assert home.contains("fetch('/api/v2/states'")
    assert home.contains('aria-live="polite"')
    assert home.contains('id="planos"')
    assert home.contains('id="open-source"')
}
```

- [ ] **Step 2: Confirmar falha esperada**

Run: `v test -run-only test_home_exposes_anonymous_live_request tests/ui_contract_test.v`

Expected: FAIL em `home-hero` ausente.

- [ ] **Step 3: Implementar home**

Recompor `index.html` com hero, CTA “Testar API sem cadastro”, console real, prova de cobertura, recursos, planos atuais, bloco GitHub e CTA final. PetiteVue mantém estado `idle | loading | success | error`, chama apenas `/api/v2/states` e expõe resultado formatado no `aria-live`.

```html
<section class="home-hero" aria-labelledby="home-title">
  <p class="eyebrow">API brasileira · aberta por padrão</p>
  <h1 id="home-title">Dados de maré do Brasil. Uma requisição e pronto.</h1>
  <a href="#console" role="button">Testar API sem cadastro</a>
</section>
<section id="console" class="tide-console" data-ui="tide-console">
  <div class="tide-track" aria-hidden="true"><span class="tide-buoy"></span></div>
  <pre aria-live="polite"><code>{{ responseText }}</code></pre>
</section>
```

- [ ] **Step 4: Confirmar GREEN**

Run: `v test tests/ui_contract_test.v`

Expected: `2 passed`.

- [ ] **Step 5: Validar chamada real**

Run: `curl -sS -o /tmp/tabua-states.json -w '%{http_code}\n' http://localhost:3330/api/v2/states`

Expected: `200` ou `429` válido sem alteração de contrato.

### Task 3: Documentação responsiva

**Files:**
- Modify: `tests/ui_contract_test.v`
- Modify: `pages/docs.html`
- Modify: `pages/assets/custom-pico.css`

**Interfaces:**
- Consumes: conteúdo e IDs de seção existentes.
- Produces: `docs-workspace`, `docs-mobile-index`, navegação lateral e ações de cópia.

- [ ] **Step 1: Adicionar teste RED de docs**

```v
fn test_docs_has_responsive_workspace_navigation() {
    docs := ui_file('pages/docs.html')
    assert docs.contains('class="docs-workspace')
    assert docs.contains('class="docs-mobile-index')
    assert docs.contains('aria-label="Navegação da documentação"')
    assert docs.contains('data-copy-target=')
}
```

- [ ] **Step 2: Confirmar RED**

Run: `v test -run-only test_docs_has_responsive_workspace_navigation tests/ui_contract_test.v`

Expected: FAIL em `docs-workspace` ausente.

- [ ] **Step 3: Implementar layout de docs**

Preservar textos, exemplos, IDs e scripts atuais. Trocar estilos inline estruturais por classes. Em desktop, sidebar sticky e conteúdo; em mobile, `<details class="docs-mobile-index">` antes do conteúdo. Adicionar botões de cópia que apontam para o `<pre>` correspondente via `data-copy-target`.

```html
<div class="docs-workspace">
  <aside class="docs-sidebar" aria-label="Navegação da documentação">…</aside>
  <details class="docs-mobile-index">…</details>
  <div class="docs-content">…</div>
</div>
```

- [ ] **Step 4: Confirmar GREEN**

Run: `v test tests/ui_contract_test.v`

Expected: `3 passed`.

### Task 4: Playground como bancada técnica

**Files:**
- Modify: `tests/ui_contract_test.v`
- Modify: `pages/playground.html`
- Modify: `pages/assets/custom-pico.css`

**Interfaces:**
- Consumes: métodos PetiteVue, parâmetros e endpoints já existentes.
- Produces: `playground-workbench`, `request-pane`, `response-pane`; feedback de execução sem mudar chamadas.

- [ ] **Step 1: Adicionar teste RED do playground**

```v
fn test_playground_uses_request_response_workbench() {
    playground := ui_file('pages/playground.html')
    assert playground.contains('class="playground-workbench')
    assert playground.contains('class="request-pane')
    assert playground.contains('class="response-pane')
    assert playground.contains('aria-live="polite"')
}
```

- [ ] **Step 2: Confirmar RED**

Run: `v test -run-only test_playground_uses_request_response_workbench tests/ui_contract_test.v`

Expected: FAIL em `playground-workbench` ausente.

- [ ] **Step 3: Implementar bancada**

Reorganizar cada endpoint existente em request/response, sem renomear métodos PetiteVue nem mudar URLs/parâmetros. Usar coluna dupla acima de 1024px e coluna única abaixo. Respostas recebem `aria-live="polite"`; `429` usa mensagem técnica e `Retry-After` quando disponível.

```html
<article class="playground-workbench">
  <div class="request-pane">…controles existentes…</div>
  <div class="response-pane" aria-live="polite">…resposta existente…</div>
</article>
```

- [ ] **Step 4: Confirmar GREEN**

Run: `v test tests/ui_contract_test.v`

Expected: `4 passed`.

### Task 5: Dashboard e apoio no mesmo sistema

**Files:**
- Modify: `tests/ui_contract_test.v`
- Modify: `pages/dashboard.html`
- Modify: `pages/apoiar.html`
- Modify: `pages/assets/custom-pico.css`

**Interfaces:**
- Consumes: estado e métodos PetiteVue atuais do dashboard; dados e links atuais de apoio.
- Produces: `dashboard-workspace`, `usage-overview`, `key-workspace`, `support-layout`.

- [ ] **Step 1: Adicionar teste RED**

```v
fn test_dashboard_and_support_share_visual_system() {
    dashboard := ui_file('pages/dashboard.html')
    support := ui_file('pages/apoiar.html')
    assert dashboard.contains('class="dashboard-workspace')
    assert dashboard.contains('class="usage-overview')
    assert dashboard.contains('class="key-workspace')
    assert support.contains('class="support-layout')
}
```

- [ ] **Step 2: Confirmar RED**

Run: `v test -run-only test_dashboard_and_support_share_visual_system tests/ui_contract_test.v`

Expected: FAIL em `dashboard-workspace` ausente.

- [ ] **Step 3: Implementar dashboard visual**

Reordenar markup para resumo de uso, API keys, planos/assinatura e teste de RPM. Preservar todos os `v-if`, `v-model`, `@click`, métodos, URLs, payloads e valores internos. Aplicar `aria-live` aos erros e resultados.

- [ ] **Step 4: Implementar apoio visual**

Organizar apresentação do projeto, PIX e ferramentas usadas em `support-layout`. Preservar chave, QR code e links.

- [ ] **Step 5: Confirmar GREEN**

Run: `v test tests/ui_contract_test.v`

Expected: `5 passed`.

### Task 6: Responsividade, acessibilidade e verificação visual

**Files:**
- Modify: `tests/ui_contract_test.v`
- Modify: `pages/assets/custom-pico.css`
- Modify: templates somente se a inspeção revelar falha visível.
- Create: `docs/superpowers/wip/2026-07-12-repaginacao-saas-opensource.MD`

**Interfaces:**
- Consumes: todas as classes produzidas nas tasks anteriores.
- Produces: breakpoints 360/768/1440, foco visível, reduced motion e registro auditável.

- [ ] **Step 1: Adicionar teste RED de acessibilidade estrutural**

```v
fn test_css_has_accessible_motion_and_responsive_guards() {
    css := ui_file('pages/assets/custom-pico.css')
    assert css.contains(':focus-visible')
    assert css.contains('@media (prefers-reduced-motion: reduce)')
    assert css.contains('overflow-wrap: anywhere')
    assert css.contains('@media (max-width: 767px)')
}
```

- [ ] **Step 2: Confirmar RED**

Run: `v test -run-only test_css_has_accessible_motion_and_responsive_guards tests/ui_contract_test.v`

Expected: FAIL em regra ausente da nova camada visual.

- [ ] **Step 3: Implementar guards finais**

Adicionar foco de alto contraste, `overflow-wrap`, scroll interno em código, touch targets, layout mobile e reduced motion que remove transform/animation/transition sem remover feedback de estado.

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    scroll-behavior: auto !important;
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

- [ ] **Step 4: Rodar contrato completo**

Run: `v test tests/ui_contract_test.v`

Expected: `6 passed`.

- [ ] **Step 5: Verificar templates e backend fora do escopo**

Run: `git diff --name-only | sort`

Expected: nenhum novo arquivo `.v` de aplicação alterado; `tests/ui_contract_test.v` é a única mudança V nova.

Run: `rg -n '\$\{[^}]+\}' pages/*.html`

Expected: somente interpolações veemarker já válidas; nenhum template literal JavaScript novo.

- [ ] **Step 6: Verificar rotas**

Run: `for route in / /docs /playground /apoiar; do curl -sS -o /dev/null -w "$route %{http_code}\n" "http://localhost:3330$route"; done`

Expected: `200` em todas.

Run: `curl -sSI http://localhost:3330/dashboard | head -n 5`

Expected: `302` com redirecionamento para Google quando sem sessão.

- [ ] **Step 7: Inspecionar visualmente**

Capturar e comparar home, docs, playground e apoio em 360x844, 768x1024 e 1440x1200. Validar menu, foco, console da home, uma execução do playground, cópia e reduced motion. Dashboard: validar autenticado se sessão disponível; caso contrário, validar template e redirecionamento.

- [ ] **Step 8: Finalizar WIP**

Registrar pedidos explícitos, invariante visual-only, decisões, arquivos, verificações, bloqueios, riscos, commit da especificação `56f6fd0` e ausência/presença de commits de implementação.
