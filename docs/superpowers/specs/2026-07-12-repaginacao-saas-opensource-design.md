# Repaginação SaaS/Open Source — Design

Data: 2026-07-12

## Objetivo

Repaginar toda a interface do Tábua de Marés API com linguagem de SaaS open source, responsiva e acessível. A jornada principal começa com uso real da API sem cadastro. Planos e API keys aparecem depois da demonstração de valor.

## Invariante de escopo

Mudança estritamente visual e de experiência frontend.

Não alterar:

- rotas, endpoints ou contratos da API;
- formatos de request/response;
- limites, preços, nomes ou regras dos planos;
- autenticação Google, JWT ou sessão;
- Stripe, checkout, portal ou cancelamento;
- API keys, permissões ou revogação;
- rate-limit, prioridades ou persistência;
- bancos, migrations, repositories ou controllers.

Mudanças locais já presentes nesses fluxos devem ser preservadas. A repaginação pode reorganizar a apresentação e os controles, sem mudar comportamento.

## Direção

Nome: **Maré em Movimento**.

- Arquétipo primário: `landing-story`, responsável pela narrativa e hierarquia da home.
- Arquétipo secundário: `workspace`, limitado a docs, playground e dashboard.
- Estilo: `friendly-soft`, adulto, acolhedor e tecnicamente claro.
- Domínio visual específico: nenhum.
- DNA de composição: `type-as-image`, aplicado ao hero e fechamentos editoriais.
- DNA de motion: `weighted-spring`, limitado à assinatura de requisição; demais movimentos são funcionais.
- Assinatura: **requisição-maré**.

Referências de direção:

- `human-ui/references/catalog.md`: roteamento da direção.
- `human-ui/references/archetype-landing-story.md`: ordem narrativa e CTA da home.
- `human-ui/references/archetype-workspace.md`: estrutura operacional de docs, playground e dashboard.
- `human-ui/references/style-friendly-soft.md`: clareza amigável sem aparência infantil.
- `human-ui/references/style-expressive-raw.md`: avaliada como alternativa; não aplicada como estilo principal.
- `human-ui/references/dna-motion.md`: motion físico limitado e fallback reduzido.
- `human-ui/references/dna-composition.md`: tipografia como elemento de identidade.

## Público e tarefa principal

Público primário: desenvolvedores que precisam integrar dados de maré brasileiros rapidamente.

Tarefa principal: executar uma requisição real sem conta nem API key.

CTA principal: **Testar API sem cadastro**.

CTAs secundários: consultar documentação, abrir GitHub e criar conta para gerar API key.

## Sistema visual

### Cores

- Espuma: `#F7FAF9`, fundo principal.
- Azul profundo: `#082F49`, texto e superfícies de alta ênfase.
- Teal oceano: `#0891B2`, ação e identidade.
- Amarelo sol: `#F9C74F`, destaque e boia da assinatura.

Bordas finas azuladas organizam conteúdo. Sombras ficam restritas a elementos realmente elevados.

### Tipografia

- `Spectral`: títulos expressivos e momentos editoriais.
- Sans-serif do sistema: navegação, texto, formulários e controles.
- `Kode Mono`: endpoints, API keys, comandos e JSON.

Escala e quebra de linha devem funcionar sem corte em 360px. Tipografia expressiva não pode causar overflow horizontal.

### Geometria e densidade

Cantos moderados. Cards usados somente quando comunicam agrupamento ou estado. Docs, playground e dashboard usam alinhamento técnico, ritmo compacto e hierarquia clara.

## Motion

### Requisição-maré

Ao executar uma requisição:

1. uma linha de maré indica progresso;
2. uma boia amarela acompanha o avanço;
3. a resposta JSON sobe suavemente;
4. sucesso produz uma onda curta;
5. erro recua e expõe a causa técnica.

A assinatura aparece no console da home, playground e teste de RPM. Não deve bloquear leitura, entrada ou navegação.

Outros movimentos são funcionais: menu, accordion, cópia, loading, feedback e mudanças de estado. `prefers-reduced-motion: reduce` remove deslocamentos e mantém feedback imediato.

## Estrutura das telas

### Home `/`

1. Hero com promessa: “Dados de maré do Brasil. Uma requisição e pronto.”
2. CTA principal para testar sem cadastro.
3. Console real usando endpoint existente.
4. Explicação: acesso anônimo sem chave, limite por minuto e cota mensal conforme regras atuais.
5. Cobertura e recursos existentes.
6. Comparação dos planos atuais, sem alterar oferta.
7. Bloco open source com GitHub, transparência e contribuição.
8. CTA final para testar ou criar conta.

Sem depoimentos, métricas ou provas inventadas.

### Documentação `/docs`

- Sidebar fixa em desktop.
- Índice compacto e acessível no mobile.
- Autenticação opcional explicada cedo.
- Endpoints, parâmetros, exemplos e respostas mais escaneáveis.
- Ações de cópia com feedback acessível.
- Conteúdo técnico atual preservado.

### Playground `/playground`

- Bancada técnica para endpoints existentes.
- Desktop: parâmetros e request à esquerda; resposta à direita.
- Mobile: fluxo em coluna única.
- Loading, sucesso, erro e `429` claros.
- Nenhuma mudança nas chamadas ou parâmetros atuais.

### Dashboard `/dashboard`

- Workspace autenticado.
- Ordem: resumo de uso, API keys, planos/assinatura e teste de RPM.
- Checkout, billing portal, cancelamento, criação/cópia/revogação de chaves e testes preservam lógica atual.
- Estados vazio, carregando, erro, plano atual e ação indisponível ficam explícitos.
- Sem sessão, redirecionamento Google permanece inalterado.

### Apoiar `/apoiar`

- Contribuição ao projeto, PIX e ferramentas open source usadas.
- Integração visual ao restante do produto.
- Dados, links e forma de apoio permanecem iguais.

### Navegação e rodapé

Navegação: Produto, Docs, Playground, Planos, GitHub e Entrar/Dashboard. Menu mobile sem overflow, com foco gerenciado e estado ativo. Rodapé organiza projeto, recursos e contribuição sem competir com CTA principal.

## Estados e acessibilidade

Cobrir:

- loading, sucesso, erro HTTP, `429`, vazio e offline;
- conteúdo copiado;
- API key criada ou revogada;
- checkout em andamento ou falhou;
- usuário sem API key;
- plano atual e ações indisponíveis.

Requisitos:

- contraste mínimo WCAG AA;
- foco visível;
- navegação por teclado;
- HTML semântico;
- mensagens dinâmicas com `aria-live`;
- controles com nomes acessíveis;
- touch targets adequados;
- nenhuma dependência exclusiva de cor ou animação.

## Responsividade

Validar em 360px, 768px e 1440px ou superior. Prioridade:

- nenhum overflow horizontal;
- conteúdo principal e CTA visíveis cedo;
- navegação móvel funcional;
- código com rolagem interna, sem alargar página;
- tabelas e grids com fallback legível;
- workspace empilhado sem esconder ações frequentes.

## Arquitetura frontend

- Manter V, `veb`, leafscale.veemarker, Pico CSS e PetiteVue.
- Não adicionar biblioteca UI, animação, fonte ou ícones.
- Centralizar tokens, shell, componentes, motion e breakpoints em `pages/assets/custom-pico.css`.
- Manter lógica específica nos templates existentes.
- Extrair apenas JS realmente compartilhado para asset comum, se reduzir duplicação sem mudar comportamento.
- Não usar template literals JavaScript com `${...}` nos templates processados pelo veemarker.

## Validação

- Build V sem erro.
- Rotas `/`, `/docs`, `/playground` e `/apoiar` respondendo `200`.
- `/dashboard` preservando autenticação e redirecionamento quando sem sessão.
- Inspeção visual antes/depois nas mesmas dimensões.
- Teste de navegação, menu mobile, teclado, foco, cópia e execução da API.
- Verificação dos estados de resposta e `429` disponíveis sem mudar backend.
- Verificação de `prefers-reduced-motion`.
- Testes existentes relevantes, evitando conexão externa ou mutação de DB somente para validação visual.

## Critério de conclusão

Todas as superfícies compartilham linguagem coerente de SaaS open source, funcionam em mobile e desktop, apresentam o uso sem chave como entrada principal e preservam integralmente a API e regras existentes.
