# UI - Repaginação SaaS/Open Source

Gerado em: 2026-07-12
Sessao/contexto: mare-ui
Tipo de registro: implementacao

## Card

Arquivo da especificação: [design aprovado](../specs/2026-07-12-repaginacao-saas-opensource-design.md)

Plano: [plano de implementação](../plans/2026-07-12-repaginacao-saas-opensource.md)

Resumo:
- Repaginação visual completa das páginas web do Tábua de Marés API.
- Direção “Maré em Movimento”, SaaS open source, responsiva e acessível.

## Pedido Do Usuario

Pedido literal:
> execute a especificação

Confirmação literal de escopo:
> só para confirmar não é modificar nada da api, somente visual

Classificacao:
- Pedido explicito: executar a especificação visual aprovada.
- Restricoes explicitas: não alterar API; comunicação curta em pt-BR; preservar código, nomes e erros técnicos.

## Interpretacao E Inferencias

- Inferencia operacional: trabalhar no checkout atual porque templates-alvo já possuem alterações locais sobrepostas que devem ser preservadas.
- Motivo: novo worktree não carregaria mudanças locais que fazem parte da base visual e funcional atual.
- Risco da inferencia: diff final mistura mudanças visuais novas com alterações locais anteriores nos mesmos templates; nenhuma delas deve ser descartada.
- Inferencia de escopo: `tests/ui_contract_test.v` pode ser criado por validar somente contratos do frontend, sem alterar aplicação ou API.

## Implementacao Ou Alteracao

- O que foi feito: direção “Maré em Movimento” aplicada ao shell, home, docs, playground, dashboard e apoio; console anônimo real; motion de maré; layouts responsivos; estados e feedback acessível; contrato estrutural RED/GREEN.
- Por que foi feito: dar linguagem SaaS/open source coerente, mantendo acesso sem chave como entrada principal.
- Onde foi feito: [teste estrutural](../../../tests/ui_contract_test.v), [CSS](../../../pages/assets/custom-pico.css), [navbar](../../../pages/navbar.html), [footer](../../../pages/footer.html), [home](../../../pages/index.html), [docs](../../../pages/docs.html), [playground](../../../pages/playground.html), [dashboard](../../../pages/dashboard.html) e [apoio](../../../pages/apoiar.html).
- O que nao foi feito: nenhum controller, endpoint, repository, banco, migration, plano, preço, limite, auth, Stripe, API key ou regra de rate-limit foi alterado por esta implementação.

## Commits Relacionados Ao Card

Repositorio: `/home/andre/projetos/tabua_mare_api`
- Branch: `wip/auth-rate-limit-google-login-premium`
- Base/destino: `origin/wip/auth-rate-limit-google-login-premium`
- Commits:
  - `56f6fd0` - `docs: define SaaS open source visual redesign` - 2026-07-12 - especificação aprovada; somente local neste checkpoint.
  - `e9c036d` - `docs: plan visual redesign implementation` - 2026-07-12 - plano executável; somente local neste checkpoint.
- Implementação visual: não commitada. Motivo: arquivos-alvo já continham mudanças locais do usuário; um commit misturaria autoria e escopos.
- Push/PR: not pushed.

## Validacao

- Validacoes feitas:
  - TDD: cada contrato de shell, home, docs, playground, dashboard/apoio e acessibilidade foi observado falhando antes da implementação; suíte final passou.
  - Build: `v -prod -d using_sqlite . -o /tmp/tabua_mare_api_ui_check` terminou com código 0; somente dois notices preexistentes de depreciação V1.
  - Rotas: `/`, `/docs`, `/playground` e `/apoiar` retornaram `200`; `/dashboard` retornou `302` para `/auth/google?next=/dashboard`; `/api/v2/states` retornou `200` e 17 estados.
  - JavaScript: blocos inline dos seis templates modificados passaram em `node --check`.
  - Visual: home, docs, playground e apoio inspecionados em 1440x1200, 768x1024, 500x900 e emulação real 360x800.
  - Mobile 360: `documentElement.scrollWidth == 360` nas quatro rotas; menu exibido e `aria-expanded` mudou para `true`.
  - Interação: console da home executou `/api/v2/states`, mostrou `200 sucesso` e JSON real.
  - Acessibilidade: primeiro `Tab` focou `.skip-link` com outline de 3px; `prefers-reduced-motion: reduce` foi reconhecido e reduziu animação/transição.
- Validacoes nao feitas: fluxo autenticado do dashboard e suíte completa `v test tests/`.
- Motivo das validacoes nao feitas: não havia sessão autenticada no navegador de validação; testes de integração do projeto exigem DB e estão fora da alteração estritamente visual.

## Riscos E Pendencias

- Dashboard validado estruturalmente e pelo redirecionamento, mas não visualmente com dados autenticados.
- CSS legado permanece no mesmo arquivo sob uma camada de overrides para preservar superfícies existentes; possível limpeza futura, fora deste lote.
- Mudanças visuais não foram commitadas por sobreposição com alterações locais anteriores.

## Proximo Teste Esperado

- Abrir o dashboard com sessão real e conferir API keys, checkout e teste de RPM antes de publicar.

## Ajuste Pontual — Cabeçalho do Dashboard

Pedido do usuario:
> corrija esse texto que aparece na tela de dashboard no topo com "seu consumo, suas chaves" porém ele fica na frente dos outros e está destoante dos demais componentes e estilos. Não modifique nada além disso.

> é esse elemento que está sendo exibido todo quebrado.
> `<header class="dashboard-heading">` (eyebrow + h1 "Seu consumo, suas chaves." + lead)

Escopo confirmado:
- Reparo local restrito ao cabeçalho `.dashboard-heading` do dashboard.
- Sem reclassificação de direção; direção "Maré em Movimento" mantida (repair, nao refine/reimagine).

Diagnóstico observado:
- Na primeira tentativa alinhei `.dashboard-heading h1` aos heroes de landing (`home-hero`, `docs-hero`, `playground-hero`) com `font-size: clamp(3rem, 6vw, 5.7rem)` e `line-height: 0.94`. Isso estava errado para um workspace: o título "Seu consumo, suas chaves." quebra em múltiplas linhas sem `<br>` de controle, e `line-height: 0.94` faz as linhas se sobreporem, dominando o layout do dashboard.
- Causa de fundo: dashboard é arquétipo `workspace`, não `landing-story`. Os heroes de landing usam escala editorial gigante porque são narrativa; o cabeçalho do dashboard é hierarquia operacional e deve ser compacto.

Implementação final (arquivo único: `pages/assets/custom-pico.css:1403-1426`):
- `.dashboard-heading`: padding `clamp(0.75rem, 1.5vw, 1.25rem) 0 1.25rem` (respiro coerente, sem competir com `padding-block` da página).
- `.dashboard-heading h1`: `font-size: clamp(1.7rem, 3.2vw, 2.3rem)`, `letter-spacing: -0.02em`, `line-height: 1.2`, `color: var(--ocean-950)`, `font-weight: 700` (escala de workspace, sem sobreposição de linhas).
- `.dashboard-heading > p:last-child`: `font-size: 0.95rem`, `line-height: 1.55`, `margin-top: 0.5rem` (lead compacto, sem competir com o h1).
- Nenhum HTML, JS, controller, endpoint ou teste modificado.
- Nenhum commit criado.

Validação:
- `v test tests/ui_contract_test.v`: 1 passed (5 testes verde), sem regressão.
- CSS servido em `GET /pages/assets/custom-pico.css`: HTTP 200, novo bloco presente no browser.
- Inspeção visual com sessão autenticada: não executada (sem sessão Google neste ambiente); alteração é puramente de tokens visuais já alinhados ao sistema existente.

Preservado:
- Markup HTML `<header class="dashboard-heading">` com eyebrow "Workspace da API", h1 "Seu consumo, suas chaves." e lead intactos.
- Estrutura `.dashboard-workspace` grid, ordens `order`, `grid-column` e demais regras do dashboard intactos.
- Tokens do sistema "Maré em Movimento" intactos.

## Ajuste Pontual — Cabeçalho do Dashboard (correção da causa raiz)

Pedido do usuario:
> veja que ainda continua aparecendo, não modifique nada apenas descreva o que acontece para o próximo modelo.
> Agora que tem o contexto visual, corrija isso.

Causa raiz encontrada (não era apenas escala tipográfica):
- Em `pages/assets/custom-pico.css:141` existe uma regra legada `header { ... }` (seletor de elemento genérico) que aplica:
  - `background: linear-gradient(135deg, var(--pico-primary-600), var(--pico-primary-700))` (azul/ciano sólido)
  - `color: white`
  - `padding: var(--spacing-md) 0`
  - `position: sticky; top: 0; z-index: 9999`
  - `box-shadow: 0 2px 10px rgba(0,0,0,0.1)`
- O `<header class="dashboard-heading">` é um `<header>`, então herda essa regra legada. Como `.dashboard-heading` não sobrescrevia `background`, `position`, `z-index`, `color`, `box-shadow`, o elemento virava um banner sticky azul que "ficava na frente dos outros" e "destoava dos demais componentes e estilos".
- A navbar `<header class="site-nav-shell">` é afetada pela mesma regra legada, mas `.site-nav-shell` sobrescreve `background`, `position`, etc., então funciona. O `.dashboard-heading` não sobrescrevia, então quebrava.
- Outros `<header>` na base (`<header class="tide-console__header">` em `pages/index.html`, `<header class="modal-header">` em `pages/playground.html`) também herdam essa regra legada; não foram tocados neste reparo por estarem fora do escopo solicitado.

Implementação (arquivo único: `pages/assets/custom-pico.css:1403-1413`):
- Adicionadas ao `.dashboard-heading` as propriedades que neutralizam a herança problemática do seletor `header {}` legado:
  - `background: transparent`
  - `color: var(--text)`
  - `position: static`
  - `z-index: auto`
  - `box-shadow: none`
- Tipografia workspace mantida da iteração anterior: h1 `clamp(1.7rem, 3.2vw, 2.3rem)`, `line-height: 1.2`, `letter-spacing: -0.02em`, `color: var(--ocean-950)`, `font-weight: 700`; lead `font-size: 0.95rem`, `line-height: 1.55`, `color: var(--muted)`.
- Nenhum HTML, JS, controller, endpoint ou teste modificado.
- Nenhum commit criado.

Validação:
- `v test tests/ui_contract_test.v`: 1 passed (5 testes verde), sem regressão.
- CSS servido em `GET /pages/assets/custom-pico.css`: HTTP 200, novo bloco com `background: transparent`, `position: static`, `z-index: auto`, `box-shadow: none` confirmado no browser.
- Inspeção visual com sessão autenticada: não executada neste ambiente (sem sessão Google). A correção ataca diretamente a causa raiz observada no screenshot (bloco azul sticky vindo do seletor `header {}` legado).

Preservado:
- Markup HTML `<header class="dashboard-heading">` intacto — eyebrow "Workspace da API", h1 "Seu consumo, suas chaves." e lead intactos.
- Estrutura `.dashboard-workspace` grid, ordens `order`, `grid-column` e demais regras do dashboard intactos.
- Regra legada `header {}` em `custom-pico.css:141` não foi removida (preserva a navbar e outros `<header>` que dependem dela); apenas neutralizada localmente em `.dashboard-heading`.
- Tokens do sistema "Maré em Movimento" intactos.

Nota para próxima iteração:
- A regra legada `header {}` em `pages/assets/custom-pico.css:141` é uma dívida técnica visual. Ela afeta todos os `<header>` da base. Hoje só a navbar e o dashboard-heading eram visíveis, mas `.tide-console__header` (home) e `.modal-header` (playground) também herdam heranças problemáticas (sticky + z-index 9999 + color white). Se surgirem bugs visuais nesses elementos, a origem provavelmente é a mesma. Uma limpeza futura poderia remover essa regra legada e mover os estilos necessários apenas para `.site-nav-shell`.
