# Investigação de SEO — Tábua de Maré API

## Objetivo

Investigar por que o site **https://tabuamare.api.br/** não aparece nas pesquisas do Google com a frequência e posição esperadas, mesmo tendo obtido **100 pontos na categoria SEO do Lighthouse**.

O objetivo não é apenas validar metatags ou repetir o resultado do Lighthouse. A investigação deve identificar problemas reais de:

- indexação;
- rastreamento;
- canonicalização;
- migração de domínio;
- conteúdo duplicado;
- renderização JavaScript;
- arquitetura de páginas;
- intenção de busca;
- autoridade do domínio;
- links internos e externos;
- sitemap;
- dados estruturados;
- Search Console;
- qualidade e profundidade do conteúdo.

---

## Contexto do projeto

### Site atual

- Home: https://tabuamare.api.br/
- Documentação: https://tabuamare.api.br/docs
- Playground: https://tabuamare.api.br/playground

### Domínio antigo

- https://tabuamare.devtu.qzz.io/

O domínio atual substituiu o domínio antigo. É necessário investigar se a migração foi feita corretamente e se o domínio antigo ainda está sendo indexado, acessado ou considerado pelo Google.

### Produto

A Tábua de Maré API fornece dados de marés por API para aplicações, sistemas de turismo, embarcações, pesca, surf, praias, drones e outros casos de uso.

O público principal é formado por:

- desenvolvedores;
- empresas de turismo;
- sistemas para embarcações;
- guias e operadores de passeios;
- aplicações relacionadas a praias e marés;
- projetos que precisam consumir dados de maré em JSON.

---

## Evidências já conhecidas

Um teste recente do Lighthouse, realizado sem extensões no navegador, obteve **100 pontos em SEO**.

O relatório indicou que a home:

- possui meta description;
- retorna status HTTP válido;
- possui links rastreáveis;
- não está bloqueada por diretivas de indexação;
- possui `robots.txt` válido;
- possui `rel="canonical"` sintaticamente válido;
- possui links com textos descritivos;
- utiliza HTTPS.

Isso prova apenas que a página passa em verificações técnicas básicas.

O Lighthouse não avalia adequadamente:

- autoridade do domínio;
- backlinks;
- concorrência;
- qualidade da estratégia de palavras-chave;
- intenção de busca;
- páginas realmente indexadas;
- posição média;
- impressões;
- cliques;
- conteúdo duplicado entre domínios;
- canonical escolhido pelo Google;
- migração de domínio;
- qualidade do conteúdo;
- cobertura temática;
- páginas órfãs;
- sinais externos;
- histórico do domínio.

Portanto, não considerar a nota 100 como evidência de que o SEO está bom.

---

# Missão do agente

Realizar uma auditoria profunda e baseada em evidências.

Não fazer afirmações sem comprovação.

Para cada problema encontrado, apresentar:

1. evidência;
2. impacto provável;
3. nível de severidade;
4. como reproduzir;
5. correção recomendada;
6. prioridade;
7. esforço estimado;
8. como validar depois da correção.

Classificar cada conclusão como:

- **Confirmado**
- **Provável**
- **Possível**
- **Não encontrado**
- **Não foi possível verificar**

---

# Etapa 1 — Descobrir o que o Google conhece

Realizar pesquisas no Google e em outros buscadores.

Usar consultas como:

```text
site:tabuamare.api.br
site:tabuamare.devtu.qzz.io
"tabua de mare api"
"tábua de maré api"
"api de maré"
"api de marés"
"api tabua de mare"
"api tábua de marés"
"dados de maré json"
"api de maré gratuita"
"consultar maré por cidade api"
"consultar maré por coordenadas"
```

Registrar:

- URLs do domínio novo que aparecem;
- URLs do domínio antigo que aparecem;
- títulos exibidos;
- descrições exibidas;
- páginas duplicadas;
- resultados desatualizados;
- posição aproximada;
- consultas em que o site não aparece;
- concorrentes que aparecem acima;
- tipo de conteúdo dos concorrentes.

Verificar especialmente se o Google ainda mostra:

```text
tabuamare.devtu.qzz.io
tabuamare.devtu.qzz.io/docs
```

Caso apareça, documentar com evidência.

---

# Etapa 2 — Verificar a migração do domínio antigo

Testar todas as rotas importantes do domínio antigo.

Exemplo:

```bash
curl -I https://tabuamare.devtu.qzz.io/
curl -I https://tabuamare.devtu.qzz.io/docs
curl -I https://tabuamare.devtu.qzz.io/playground
curl -I https://tabuamare.devtu.qzz.io/privacidade
curl -I https://tabuamare.devtu.qzz.io/termos
```

Verificar:

- status retornado;
- presença do header `Location`;
- destino final;
- quantidade de redirecionamentos;
- existência de loops;
- redirecionamentos para páginas equivalentes;
- redirecionamento incorreto de todas as páginas para a home;
- páginas antigas ainda retornando `200 OK`;
- páginas antigas com conteúdo duplicado;
- redirecionamentos temporários `302` ou `307`;
- redirecionamentos permanentes `301` ou `308`.

O comportamento esperado é:

```text
dominio-antigo/rota → dominio-novo/rota-equivalente
```

Exemplo:

```text
https://tabuamare.devtu.qzz.io/docs
→
https://tabuamare.api.br/docs
```

Não considerar correto redirecionar todas as páginas antigas para a home.

---

# Etapa 3 — Canonicalização

Inspecionar o HTML inicial de cada página:

```bash
curl -s https://tabuamare.api.br/
curl -s https://tabuamare.api.br/docs
curl -s https://tabuamare.api.br/playground
curl -s https://tabuamare.api.br/privacidade
curl -s https://tabuamare.api.br/termos
```

Extrair as tags canonical:

```bash
curl -s https://tabuamare.api.br/docs | grep -i canonical
```

Verificar se cada página possui canonical autorreferente.

Resultado esperado:

```text
/           → https://tabuamare.api.br/
/docs       → https://tabuamare.api.br/docs
/playground → https://tabuamare.api.br/playground
/termos     → https://tabuamare.api.br/termos
/privacidade→ https://tabuamare.api.br/privacidade
```

Investigar:

- canonical de todas as páginas apontando para a home;
- canonical ausente;
- canonical com URL relativa problemática;
- canonical apontando para o domínio antigo;
- canonical divergente do sitemap;
- canonical divergente da URL final;
- canonical escolhido pelo Google diferente do declarado.

Se houver acesso ao Search Console, comparar:

- canonical declarado pelo usuário;
- canonical selecionado pelo Google.

---

# Etapa 4 — HTML inicial e renderização JavaScript

Comparar o HTML recebido por `curl` com o DOM renderizado no navegador.

Verificar se conteúdos importantes aparecem diretamente no HTML inicial:

- títulos;
- subtítulos;
- exemplos de código;
- descrições;
- respostas JSON;
- documentação dos endpoints;
- textos dos casos de uso;
- links internos.

Procurar placeholders como:

```text
{{code_estrutura_default}}
{{code_resposta_states}}
{{code_resposta_harbor_names}}
{{code_resposta_tabua_mare}}
{{ statusLabel }}
{{ selectedEndpoint.title }}
{{ responseText }}
```

Usar:

```bash
curl -s https://tabuamare.api.br/ | grep -E "\{\{.*\}\}"
curl -s https://tabuamare.api.br/docs | grep -E "\{\{.*\}\}"
```

Se os placeholders estiverem presentes no HTML inicial, verificar:

- se o Google consegue renderizar o conteúdo corretamente;
- se o conteúdo aparece no HTML renderizado do Search Console;
- se os exemplos importantes dependem totalmente de JavaScript;
- se existe atraso ou falha na hidratação;
- se o conteúdo renderizado é idêntico ao conteúdo original;
- se erros de JavaScript impedem o conteúdo de aparecer.

Registrar quais conteúdos deveriam ser renderizados no servidor ou incorporados diretamente ao HTML.

---

# Etapa 5 — Robots, headers e indexabilidade

Verificar:

```bash
curl -s https://tabuamare.api.br/robots.txt
curl -I https://tabuamare.api.br/
curl -I https://tabuamare.api.br/docs
curl -I https://tabuamare.api.br/playground
```

Procurar:

```text
X-Robots-Tag
noindex
nofollow
noarchive
nosnippet
```

Verificar também:

- bloqueio acidental de assets;
- bloqueio de páginas importantes;
- regras específicas para bots;
- comportamento para Googlebot;
- respostas diferentes por user agent;
- Cloudflare interferindo no crawler;
- desafios, captchas ou bloqueios;
- status `403`, `429` ou `5xx`;
- páginas retornando `200` com conteúdo de erro;
- soft 404;
- páginas vazias;
- erros intermitentes.

Testar com user agent do Googlebot:

```bash
curl -I \
  -A "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" \
  https://tabuamare.api.br/
```

---

# Etapa 6 — Sitemap

Verificar:

```text
https://tabuamare.api.br/sitemap.xml
https://tabuamare.api.br/sitemap_index.xml
```

Caso exista, validar:

- XML válido;
- todas as páginas importantes presentes;
- nenhuma URL do domínio antigo;
- nenhuma página com `noindex`;
- nenhuma URL redirecionada;
- nenhuma URL que retorna erro;
- URLs canônicas;
- datas `lastmod` coerentes;
- páginas legais incluídas quando apropriado;
- documentação incluída;
- futuras páginas de conteúdo incluídas.

Caso não exista, recomendar a criação.

Verificar se o sitemap está declarado no `robots.txt`:

```text
Sitemap: https://tabuamare.api.br/sitemap.xml
```

---

# Etapa 7 — Search Console

Caso exista acesso ao Google Search Console, investigar obrigatoriamente:

## Desempenho

Coletar dados dos últimos:

- 28 dias;
- 3 meses;
- 6 meses;
- 12 meses, se disponíveis.

Analisar:

- cliques;
- impressões;
- CTR;
- posição média;
- consultas;
- páginas;
- países;
- dispositivos;
- evolução após a troca de domínio.

Identificar:

- consultas com muitas impressões e poucos cliques;
- páginas com posição entre 8 e 30;
- consultas relevantes onde o site aparece;
- consultas irrelevantes;
- perda de impressões após a migração;
- crescimento ou queda do domínio novo;
- páginas antigas ainda recebendo impressões.

## Indexação

Verificar:

- páginas indexadas;
- páginas não indexadas;
- rastreada, mas não indexada;
- descoberta, mas não indexada;
- duplicada sem canonical selecionada;
- duplicada com canonical diferente;
- página com redirecionamento;
- soft 404;
- bloqueada pelo robots;
- excluída por `noindex`;
- erro de servidor;
- URL enviada e bloqueada;
- canonical escolhido pelo Google.

## Inspeção de URL

Inspecionar pelo menos:

```text
https://tabuamare.api.br/
https://tabuamare.api.br/docs
https://tabuamare.api.br/playground
```

Registrar:

- indexada ou não;
- última data de rastreamento;
- crawler utilizado;
- canonical declarado;
- canonical escolhido pelo Google;
- HTML rastreado;
- HTML renderizado;
- screenshot renderizado;
- recursos bloqueados;
- erros de JavaScript;
- elegibilidade para indexação.

## Mudança de endereço

Verificar se a ferramenta de mudança de endereço foi utilizada na migração do domínio antigo para o novo.

---

# Etapa 8 — Arquitetura de informação

Mapear todas as páginas rastreáveis do site.

Investigar se o site possui poucas URLs para muitas intenções de busca.

Atualmente, é possível que grande parte do conteúdo esteja concentrada em:

```text
/
/docs
/playground
```

Avaliar a criação de páginas específicas, por exemplo:

```text
/docs/primeiros-passos
/docs/autenticacao
/docs/tabua-de-mare
/docs/mare-por-geolocalizacao
/docs/listar-estados
/docs/listar-cidades
/docs/listar-portos
/docs/exemplos-csharp
/docs/exemplos-javascript
/docs/exemplos-python
/casos-de-uso/turismo
/casos-de-uso/surf
/casos-de-uso/pesca
/casos-de-uso/embarcacoes
```

Não recomendar páginas artificiais ou conteúdo gerado apenas para SEO.

Cada página deve resolver uma intenção real e possuir:

- título único;
- H1 único;
- descrição única;
- canonical autorreferente;
- conteúdo específico;
- exemplos;
- links internos;
- CTA coerente;
- dados estruturados adequados;
- URL descritiva.

---

# Etapa 9 — Conteúdo e intenção de busca

Identificar as pesquisas que pessoas reais fariam.

Separar por intenção:

## Intenção comercial

```text
api de maré
api de marés
api tábua de maré
api de maré gratuita
api de maré brasil
api de maré preço
```

## Intenção técnica

```text
dados de maré json
api maré c#
api maré javascript
api maré python
consultar maré por coordenadas
consultar maré por latitude longitude
api de maré por cidade
```

## Casos de uso

```text
api de maré para turismo
api de maré para embarcações
api de maré para pesca
api de maré para surf
api de maré para praias
```

Para cada consulta:

- identificar concorrentes;
- comparar profundidade;
- comparar clareza;
- comparar título;
- comparar conteúdo;
- comparar número de páginas;
- comparar autoridade;
- identificar lacunas que o site pode preencher.

Não usar volume de busca inventado.

Se não houver acesso a uma ferramenta de palavras-chave, declarar essa limitação.

---

# Etapa 10 — Títulos, descrições e headings

Extrair de todas as páginas:

```text
<title>
<meta name="description">
<h1>
<h2>
```

Verificar:

- títulos duplicados;
- descrições duplicadas;
- H1 ausente;
- múltiplos H1 sem necessidade;
- títulos excessivamente genéricos;
- falta de termos buscados;
- páginas diferentes usando o mesmo título;
- páginas legais competindo com páginas de produto;
- conteúdo importante escondido em elementos não semânticos.

Exemplo de direção desejada:

```text
Tábua de Maré API — Dados de marés em JSON para aplicações
```

Para documentação:

```text
Documentação da Tábua de Maré API — Endpoints e exemplos
```

Não alterar títulos apenas para repetir palavras-chave.

---

# Etapa 11 — Links internos

Mapear os links internos.

Verificar:

- páginas órfãs;
- documentação sem links da home;
- casos de uso sem links para endpoints;
- links apenas via JavaScript;
- links sem `href`;
- links com textos genéricos;
- navegação inconsistente;
- conteúdo enterrado;
- excesso de links para páginas pouco importantes;
- falta de breadcrumbs;
- ausência de links entre páginas relacionadas.

Gerar um mapa:

```text
página origem → texto do link → página destino
```

---

# Etapa 12 — Backlinks e autoridade

Investigar links externos apontando para:

```text
tabuamare.api.br
tabuamare.devtu.qzz.io
```

Verificar referências em:

- GitHub;
- README;
- descrição do repositório;
- TabNews;
- blogs;
- fóruns;
- projetos que utilizam a API;
- redes sociais;
- documentação de terceiros;
- diretórios de APIs;
- sites de parceiros;
- Drone Skull;
- Swell Check.

Identificar:

- backlinks apontando para o domínio antigo;
- links quebrados;
- links com `nofollow`;
- menções sem link;
- páginas externas relevantes que poderiam apontar para o domínio novo;
- projetos reais que utilizam a API e podem atribuir a fonte.

Não recomendar:

- compra de backlinks;
- spam em comentários;
- diretórios de baixa qualidade;
- redes privadas de blogs;
- troca artificial de links;
- técnicas manipulativas.

---

# Etapa 13 — Dados estruturados

Inspecionar JSON-LD e outros dados estruturados.

Verificar:

- validade sintática;
- tipo utilizado;
- conteúdo coerente com a página;
- URLs corretas;
- `termsOfService`;
- `url`;
- `name`;
- `description`;
- `provider`;
- duplicação em todas as páginas;
- dados da home reutilizados na documentação;
- marcação desnecessária;
- erros no Rich Results Test;
- avisos e campos recomendados.

Não assumir que a nota do Lighthouse valida os dados estruturados. A auditoria do Lighthouse para structured data pode ser apenas manual.

---

# Etapa 14 — Open Graph e compartilhamento

Verificar em cada página:

```text
og:title
og:description
og:url
og:image
twitter:card
twitter:title
twitter:description
twitter:image
```

Confirmar:

- conteúdo específico por página;
- `og:url` correto;
- domínio novo;
- imagem acessível;
- dimensões adequadas;
- ausência de metadados do domínio antigo;
- ausência de valores idênticos em todas as páginas.

Embora Open Graph não determine diretamente o ranqueamento, pode afetar compartilhamento e aquisição de links.

---

# Etapa 15 — Desempenho real

Não limitar a análise ao Lighthouse local.

Verificar Core Web Vitals reais, quando disponíveis:

- LCP;
- INP;
- CLS.

Analisar dados de campo no:

- Search Console;
- PageSpeed Insights;
- Chrome UX Report.

Distinguir:

- dados de laboratório;
- dados reais de usuários.

O relatório atual mostra uma página leve e rápida em laboratório, mas isso não prova desempenho real em todas as redes, dispositivos e regiões.

---

# Etapa 16 — Segurança e disponibilidade para crawlers

Investigar:

- Cloudflare;
- regras de firewall;
- rate limits;
- bloqueios geográficos;
- proteção contra bots;
- desafios JavaScript;
- cache;
- downtime;
- erros `5xx`;
- timeout;
- DNS;
- TLS;
- HTTP/2 ou HTTP/3;
- comportamento em IPv4 e IPv6.

Verificar se o Googlebot pode receber bloqueios diferentes de um navegador comum.

---

# Etapa 17 — Logs do servidor

Caso haja acesso aos logs, analisar requisições de crawlers.

Buscar user agents como:

```text
Googlebot
GoogleOther
Bingbot
DuckDuckBot
```

Investigar:

- frequência de rastreamento;
- URLs rastreadas;
- status retornados;
- erros;
- redirecionamentos;
- loops;
- páginas ignoradas;
- assets bloqueados;
- tráfego para o domínio antigo;
- rastreamento após mudanças.

Validar IPs de Googlebot antes de considerar o tráfego legítimo.

---

# Etapa 18 — Repositório e código

Auditar o código responsável por:

- geração de `<head>`;
- canonical;
- metadados;
- rotas;
- renderização da documentação;
- sitemap;
- robots;
- redirecionamentos;
- páginas de erro;
- placeholders;
- conteúdo compartilhado;
- JSON-LD;
- Open Graph.

Procurar por:

```text
canonical
og:url
meta name="description"
robots
sitemap
tabuamare.devtu.qzz.io
tabuamare.api.br
{{code_
{{ statusLabel }}
```

Verificar se existe um fragmento compartilhado que injeta os mesmos metadados em todas as páginas.

---

# Hipóteses prioritárias

Investigar estas hipóteses primeiro.

## Hipótese 1 — Autoridade dividida entre domínio antigo e novo

O domínio antigo pode ainda estar indexado ou servindo conteúdo.

### Validação

- pesquisa `site:`;
- `curl -I`;
- Search Console;
- backlinks;
- canonical;
- sitemap;
- logs.

## Hipótese 2 — Redirecionamentos incompletos

A home antiga pode redirecionar, mas rotas internas podem continuar retornando `200`.

### Validação

Testar todas as rotas equivalentes.

## Hipótese 3 — Conteúdo importante depende de JavaScript

Placeholders podem chegar ao crawler antes da renderização.

### Validação

Comparar:

- HTML de `curl`;
- DOM;
- HTML renderizado do Search Console;
- cache do Google;
- inspeção de URL.

## Hipótese 4 — Poucas páginas para muitas intenções

A documentação pode concentrar assuntos demais em `/docs`.

### Validação

Mapear tópicos, consultas e concorrentes.

## Hipótese 5 — Baixa autoridade externa

Poucos sites relevantes podem apontar para o domínio novo.

### Validação

Auditoria de backlinks, GitHub, TabNews e projetos consumidores.

## Hipótese 6 — Migração recente ainda não consolidada

O Google pode estar transferindo sinais lentamente.

### Validação

Comparar datas, impressões, rastreamento, backlinks e uso da mudança de endereço.

---

# Formato obrigatório do relatório final

O agente deve entregar um arquivo Markdown com esta estrutura:

```markdown
# Auditoria de SEO — Tábua de Maré API

## Resumo executivo

## Principais problemas

### 1. Nome do problema

**Status:** Confirmado / Provável / Possível  
**Severidade:** Crítica / Alta / Média / Baixa  
**Impacto:**  
**Evidência:**  
**Como reproduzir:**  
**Causa provável:**  
**Correção recomendada:**  
**Como validar:**  
**Esforço estimado:**  

## Indexação

## Migração de domínio

## Canonicalização

## Renderização JavaScript

## Sitemap e robots

## Conteúdo e arquitetura

## Palavras-chave e concorrentes

## Links internos

## Backlinks e autoridade

## Dados estruturados

## Search Console

## Plano de ação priorizado

### Agora

### Próximos 7 dias

### Próximos 30 dias

## Limitações da investigação

## Evidências coletadas

## Comandos utilizados
```

---

# Critérios de prioridade

Usar esta ordem:

1. bloqueios de indexação;
2. redirecionamentos errados;
3. domínio antigo servindo conteúdo;
4. canonical incorreto;
5. páginas importantes não indexadas;
6. conteúdo vazio ou dependente de JavaScript;
7. sitemap incorreto;
8. páginas duplicadas;
9. arquitetura de conteúdo;
10. links internos;
11. backlinks;
12. ajustes de título, descrição e dados estruturados.

Não gastar a maior parte da investigação em detalhes cosméticos enquanto existirem problemas de indexação ou migração.

---

# Regras da investigação

- Não confiar apenas no Lighthouse.
- Não presumir que “rastreadável” significa “indexado”.
- Não presumir que “indexado” significa “bem posicionado”.
- Não presumir que metatag válida é metatag correta.
- Não inventar volume de pesquisa.
- Não inventar backlinks.
- Não afirmar que o Google escolheu determinada canonical sem evidência.
- Não recomendar conteúdo genérico em massa.
- Não recomendar compra de links.
- Não confundir Open Graph com fator direto de ranqueamento.
- Não confundir dados de laboratório com dados reais.
- Não alterar produção sem apresentar evidência e impacto.
- Preservar URLs existentes quando possível.
- Propor redirecionamentos para qualquer mudança de URL.
- Produzir correções pequenas, testáveis e reversíveis.

---

# Resultado esperado

Ao final, deve ser possível responder claramente:

1. O Google indexou a home?
2. O Google indexou `/docs`?
3. O Google indexou `/playground`?
4. O domínio antigo ainda está indexado?
5. Existem páginas antigas retornando `200`?
6. Os redirecionamentos são permanentes e rota por rota?
7. O Google escolheu a canonical correta?
8. O conteúdo importante existe no HTML inicial?
9. O site possui sitemap completo?
10. O Search Console mostra exclusões ou problemas?
11. Para quais consultas o site recebe impressões?
12. Quais páginas têm potencial de crescimento?
13. Quais concorrentes aparecem acima e por quê?
14. O domínio novo recebe backlinks suficientes?
15. Quais são as três correções de maior impacto?

---

# Arquivos e fontes disponíveis

- Relatório Lighthouse da home realizado em 31 de julho de 2026.
- Site público atual.
- Domínio antigo.
- Repositório do projeto, caso esteja disponível.
- Google Search Console, caso o acesso seja fornecido.
- Logs do servidor, caso estejam disponíveis.

O relatório do Lighthouse deve ser tratado como uma fonte auxiliar, não como conclusão da auditoria.
