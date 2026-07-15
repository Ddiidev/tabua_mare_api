# Execution Plan: Rate Limit por IP/api_key (por minuto + por mês), Login Google (extensível), Foto de Perfil em Cache, V1 Depreciada (410), Persistência Dividida (SQLite + Postgres externo) e Sugestões de Endpoints Premium

## Metadata

- Plan ID: 20260626-225030-9c1b4f
- Created at: 2026-06-26
- Updated at: 2026-06-26 (rev2: limites por minuto/mês, nginx sem rate-limit, V1 descontinuada; rev3: persistência dividida SQLite+Postgres, novo repository tabuamare_dash, créditos mensais; rev4: veb.auth nativo tentar primeiro, V1 com 410+link docs, Postgres externo via env do sistema)
- Request summary: Implementar rate-limit por IP para o nível free (64 req/min + 20k req/mês) com tiers pagos por api_key (R$5: 512 req/min + 250k req/mês; R$10: 2560 req/min + ilimitado/mês), remover o rate-limit do nginx (controle no app, que tem contexto de plano), V1 depreciada respondendo 410 Gone com link para /docs (evita bypass do free), sistema de login com Google (criando a conta automaticamente) com tabela genérica/extensível para futuras providers (GitHub), cache da foto de perfil do Google com expiração. **Sessão: tentar veb.auth nativo primeiro (fallback session_tokens própria só se incompatível com OAuth-only).** **Persistência dividida: dados de maré da API no SQLite; dados de usuário/login/dashboard/contadores/créditos no PostgreSQL externo (via env do sistema, não arquivo .env, não no compose).** Novo repository tabuamare_dash para o domínio de negócio (distinto da API). Nova infra db de PostgreSQL exclusiva para login/usuário. Consulta de créditos mensais via tabela enxuta no PostgreSQL (Redis avaliado e descartado para single-container). Fornecer sugestões de endpoints premium (Dados como Serviço) usando apenas os dados já existentes no SQLite.
- Mode: PLAN only
- Implementation allowed: No

## 1. Objective

Entregar três frentes de monetização para a Tábua de Maré API:

1. **Rate-limiting freemium** com duas dimensões (por minuto e por mês), controlado **no app** (nginx sem rate-limit). **Contadores e créditos mensais persistidos em PostgreSQL** (não no SQLite, que é volátil para essa finalidade).
   - Free (sem token, por IP): 64 req/min e 20k req/mês.
   - Plano R$ 5/mês (api_key): 512 req/min e 250k req/mês.
   - Plano R$ 10/mês (api_key): 2560 req/min e ilimitado req/mês.
2. **Login com Google (OAuth2)** com criação automática de conta (upsert) e foto de perfil cacheada com expiração, usando uma tabela de usuários genérica/extensível para que GitHubAuth possa ser adicionado depois sem alterar o schema principal. **Sessão via veb.auth (nativo) tentada primeiro; fallback session_tokens própria se incompatível.**
3. **Sugestões de Endpoints Premium (Dados como Serviço)** derivados **apenas** dos dados já existentes no banco SQLite (data_mare, month_data, day_data, hour_data, geo_location).
4. **Persistência dividida e domínio de dashboard**:
   - Dados de **maré** (API pública) continuam no **SQLite** (read-heavy, imutáveis no ano, regenerável da fonte oficial).
   - Dados de **usuário/login/dashboard/contadores/credits** vão para **PostgreSQL externo** (persistente; SQLite é volátil para isso; Postgres não está no docker-compose.yml deste repo, é um banco externo apontado por env do sistema — não arquivo .env).
   - Novo repository tabuamare_dash para o domínio de **negócio** (métricas de uso, painel, cobrança, créditos), distinto da API de maré.
   - Nova infra db de PostgreSQL **exclusiva para login/usuário** (pool separado do SQLite), sempre-on (independente de -d using_sqlite).
   - O PostgreSQL é externo; suas variáveis vêm do env do sistema/hospedeiro (não de um arquivo .env). O conf_env já prioriza os.getenv sobre o .env, então basta garantir que EnvConfig carrega DB_DATABASE/DB_USER/DB_HOST/DB_PASS/DB_PORT.
   - **Créditos mensais**: decisão por **PostgreSQL com tabela enxuta** (monthly_credits), não Redis (ver seção "Créditos mensais — Redis vs Postgres").

Também: **V1 depreciada respondendo 410 Gone** com link para /docs (evita bypass do rate-limit free, orienta o cliente a migrar), e fornecer as rotas exatas + valores para o Google Cloud Console (OAuth Client), incluindo o Redirect URI para https://tabuamare.devtu.qzz.io/.

## 2. Scope

### In scope

- [x] Definir e documentar as rotas de OAuth2 do Google (início, callback, logout) e os valores para o Google Cloud Console.
- [x] Projetar o schema de tabelas para autenticação (users + provider identities) extensível a GitHub, **em PostgreSQL externo**.
- [x] Projetar o middleware de rate-limiting por IP (free) e por api_key (pagos), com limite **por minuto** (64/512/2560 req/min) e **por mês** (20k/250k/ilimitado req/mês). **Contadores e créditos persistidos em PostgreSQL.**
- [x] Projetar a remoção do rate-limit do nginx (controle centralizado no app).
- [x] Projetar a V1 depreciada respondendo 410 Gone com link para /docs (sem bypass do free).
- [x] Projetar o cache de foto de perfil do Google com expiração (reaproveitando o padrão de cache/cache.v).
- [x] Projetar a divisão de infra de banco: **SQLite** (dados de maré da API, read-heavy) + **PostgreSQL externo** (usuários, login, dashboard, contadores de rate-limit, créditos mensais).
- [ ] Projetar o novo repository tabuamare_dash (domínio de negócio, distinto da API).
- [x] Projetar a nova infra shareds/infradb_pg (pool PostgreSQL sempre-on, exclusivo para login/usuário/dash/contadores).
- [x] Avaliar Redis vs PostgreSQL-tabela-enxuta para consulta de créditos mensais (decisão: PostgreSQL — ver seção "Créditos mensais — Redis vs Postgres").
- [x] Projetar a sessão via veb.auth (nativo) tentada primeiro, com fallback session_tokens própria.
- [x] Listar sugestões de endpoints premium derivados dos dados já existentes no SQLite.
- [x] Definir as variáveis de ambiente (Google OAuth + rate-limit config) e confirmar as do PostgreSQL externo já presentes no env do sistema.

### Out of scope

- [ ] Implementação efetiva de qualquer código de produção.
- [ ] Migrações executadas no banco.
- [ ] Integração com gateway de pagamento (a ser definida em plano futuro).
- [ ] Implementação de webhooks/alertas (apenas mencionado como sugestão premium).
- [ ] Implementação do GitHubAuth (apenas o schema será preparado para tal).
- [ ] Adicionar serviço PostgreSQL ao docker-compose.yml/Dockerfile (o banco é externo; apenas garantir que o app lê as vars DB_* do env do sistema).
- [ ] Remover o registro da V1 (decisão: manter registrada respondendo 410).

## 3. Methodical Analysis

### User request interpretation

O usuário quer (com revisões em 2026-06-26 rev2, rev3 e rev4):

1. **Modelo Freemium com rate limiting (por minuto + por mês)** — decisão final do usuário:
   - **Free (sem token, por IP)**: até 64 req/min e 20.000 req/mês.
   - **Plano R$ 5/mês (api_key)**: até 512 req/min e 250.000 req/mês (+ 20k/mês do free por IP, pois o IP continua podendo usar o free quando não envia a key).
   - **Plano R$ 10/mês (api_key)**: até 2.560 req/min e ilimitado req/mês.
   - A unidade passou de req/s para req/min (decisão do usuário). O R$10 é "ilimitado por mês"; o que muda entre R$5 e R$10 é a quantidade por minuto (512 vs 2560).
   - **Decisão sobre nginx**: remover o limit_req_zone do nginx e deixar o app decidir o barramento, porque só o app tem contexto de plano/api_key.
   - **Decisão sobre V1 (rev4)**: depreciar a V1 respondendo 410 Gone com mensagem "API v1 depreciada; use a v2" + link para /docs. V1 não serve dados de maré (evita bypass do rate-limit free) e orienta o cliente a migrar. Não "não registrada" (404), não redirect (IDs de porto mudam de int para string entre V1 e V2, redirect quebraria).

2. **Login com Google**:
   - Ao clicar em "Login", criar a conta automaticamente (upsert).
   - Tabela de login com Google, livre/extensível para no futuro adicionar GitHub.
   - Criar algo como GoogleAuth (e depois GithubAuth).
   - Salvar a foto de perfil do Google em cache com expiração para não buscar a imagem a cada request.
   - Fornecer as rotas e os valores para o Google Cloud Console OAuth.
   - Variáveis de ambiente fornecidas (algumas com placeholder [PRECISA PREENCHER]).
   - URL de produção: https://tabuamare.devtu.qzz.io/.
   - **Sessão (rev4)**: tentar veb.auth (nativo) primeiro; só implementar uma alternativa limpa (session_tokens própria) caso dê problemas.

3. **Sugestões de endpoints premium** usando apenas os dados já existentes no SQLite (dados de maré).

4. **Persistência dividida e domínio de dashboard** (rev3 + rev4):
   - Dados de maré (API pública) continuam no SQLite (read-heavy, imutáveis no ano).
   - Dados de usuário/login/dashboard/contadores/credits vão para PostgreSQL (persistente, volátil não é aceitável).
   - **PostgreSQL é externo** (rev4): não está no docker-compose.yml deste repo; suas variáveis vêm do env do sistema/hospedeiro (não de um arquivo .env). Nada a adicionar ao compose.
   - Novo repository tabuamare_dash para o domínio de negócio (distinto da API: métricas de uso, painel, cobrança, créditos). Vive sob repository/tabuamare_dash/.
   - Nova infra db de PostgreSQL exclusiva para login/usuário (pool separado do SQLite).
   - O conf_env já prioriza os.getenv sobre o .env, então basta garantir que EnvConfig carrega as vars DB_* do Postgres externo.
   - Pergunta do usuário: dá pra usar PostgreSQL como Redis (tabela enxuta) para consultar créditos do mês, ou é melhor um Redis de verdade? **Decisão: PostgreSQL com tabela enxuta** (ver seção "Créditos mensais — Redis vs Postgres").

### Current context inspected

Arquitetura (V + veb, SQLite via -d using_sqlite, pool de conexões, ORM, DTOs, ResultAPI[T], middlewares via veb.Middleware, CORS já configurado):

- [main.v](../../main.v) — registra APIController (V1) e APIControllerV2, serve estáticos em /pages/assets, páginas HTML em /, /docs, /playground, /apoiar, /ping.
- [api_v2.v](../../api_v2.v) — APIControllerV2 em /api/v2, com veb.Middleware[web_ctx.WsCtx] e init_cors(). Endpoints: /states, /harbor_names/:state, /harbors/:ids, /tabua-mare/:harbor/:month/:days, /geo-tabua-mare/:lat_lng/:state/:month/:days, /nearested-harbor/:state/:lat_lng, /nearest-harbor-independent-state/:lat_lng.
- [api.v](../../api.v) — V1 deprecated (@[deprecated_after: '2026-04-22']). **Decisão (rev4): manter registrada, mas todos os handlers respondem 410 Gone** com mensagem "API v1 depreciada; use a v2. Docs: /docs".
- [shareds/web_ctx/web_ctx.v](../../shareds/web_ctx/web_ctx.v) — WsCtx embeds veb.Context + request_id.RequestIdContext.
- [shareds/infradb/infradb.v](../../shareds/infradb/infradb.v) — pool com pool.ConnectionPool, create_conn condicional SQLite/PG. Hoje é SQLite-only quando -d using_sqlite. Precisaremos de um segundo pool para PostgreSQL (auth/dash) que funcione sempre (independente de -d using_sqlite).
- [shareds/infradb/migrations.v](../../shareds/infradb/migrations.v) — apply_startup_migrations() aplica migrações SQLite no startup (geo_hash). Padrão a seguir; novas migrações de PostgreSQL (auth/dash/contadores) em função/pool separado.
- [shareds/conf_env/conf_env.v](../../shareds/conf_env/conf_env.v) — EnvConfig já tem db_database/db_user/db_host/db_pass/db_port (Postgres) + db_sqlite_path. load_env() prioriza os.getenv sobre o .env, então as vars do Postgres externo (env do sistema) já são carregadas se presentes. Precisa adicionar campos Google + rate-limit.
- [entities/data_mare.v](../../entities/data_mare.v) — DataMare (id, year, id_harbor_state, harbor_name, state, timezone, card, data_collection_institution, mean_level, geo_location, months).
- [entities/month_data.v](../../entities/month_data.v) — MonthData (id, data_mare_id, month_name, month, days).
- [entities/day_data.v](../../entities/day_data.v) — DayData (id, month_data_id, weekday_name, day, hours).
- [entities/hour_data.v](../../entities/hour_data.v) — HourData (id, day_data_id, hour, level). Sem timestamp explícito; hour é string (ex: "0100").
- [entities/geo_location.v](../../entities/geo_location.v) — GeoLocation (id, data_mare_id, lat, lng, decimal_lat, decimal_lng, lat_direction, lng_direction).
- [repository/tabua_mare/tabua_mare.v](../../repository/tabua_mare/tabua_mare.v) — get_tabua_mare_by_month_days usa time.now().year (ano corrente). Atualmente só suporta ano corrente — importante para sugestão de histórico premium.
- [repository/tabua_mare/dto/dto_tabua_mare.v](../../repository/tabua_mare/dto/dto_tabua_mare.v) — DTOs de resposta.
- [repository/habor_mare/list_all_harbors.v](../../repository/habor_mare/list_all_harbors.v) — usa time.now().year.
- [shareds/types/result_api.v](../../shareds/types/result_api.v) — ResultAPI[T], success, failure.
- [cache/cache.v](../../cache/cache.v) — Cache com map[string]ItemCache, TTL de 5 minutos fixo. TypeCacheData é um sum type em [cache/type_cache_data.v](../../cache/type_cache_data.v) — precisa ser estendido para incluir foto de perfil (ou criar um cache separado).
- [domain/auth_user/auth.v](../../domain/auth_user/auth.v) — UserData { email, name } (rascunho para JWT, ainda não usado).
- [shareds/components_view/navbar.v](../../shareds/components_view/navbar.v) + [pages/navbar.html](../../pages/navbar.html) — navbar renderiza current_page; incluir botão "Login" aqui.
- [nginx/nginx.conf](../../nginx/nginx.conf) — existe limit_req_zone ... rate=1000r/m (global por IP). Decisão do usuário: remover/neutralizar essa zone e deixar o app decidir o barramento (só o app conhece plano/api_key). Ver Risk R1.
- [Dockerfile](../../Dockerfile) — single-container, nginx na 9090, app em 3000/9090; URL_ENV=https://tabuamare.devtu.qzz.io.
- [v.mod](../../v.mod) — deps: leafscale.veemarker, ken0x0a.dotenv. V lib inclui veb.oauth (módulo embutido) e veb.auth (tokens/DB).
- [.env.template](../../.env.template) — atualmente só tem DB_SQLITE_PATH + Postgres placeholders + URL_ENV + CLOUDFLARE_TUNNEL_TOKEN. As vars reais do Postgres externo vêm do env do sistema (não deste arquivo).

### Requirements

#### Functional requirements

- **FR-1 (Rate-limit free por IP, por minuto e por mês)**: Cada IP pode fazer até 64 req/min e 20.000 req/mês nos endpoints /api/v2/* sem token. Ao exceder qualquer um dos dois, responder 429 Too Many Requests com corpo ResultAPI de erro, header Retry-After e um campo indicando qual limite foi atingido (minute | month).
- **FR-1b (Rate-limit pago por api_key, por minuto e por mês)**: Requisições com Authorization: Bearer <api_key> (ou ?api_key=) válidas aplicam o limite do plano em vez do free:
  - Plano R$ 5: 512 req/min e 250.000 req/mês (+ 20k/mês do free por IP, usado quando a key não é enviada).
  - Plano R$ 10: 2.560 req/min e ilimitado req/mês.
  - api_key inválida/ausente caem no limite free por IP (não autenticada).
  - A cota mensal é por api_key (não por IP) para planos pagos; por IP para o free.
- **FR-3 (Login Google)**: Rota GET /auth/google redireciona para o consentimento do Google. Rota GET /auth/google/callback recebe code, troca por tokens, busca userinfo, faz upsert do usuário e da identidade Google (em PostgreSQL externo), emite um token de sessão via veb.auth (nativo) tentado primeiro (fallback session_tokens própria se incompatível — R3) e seta cookie HttpOnly + Secure; SameSite=Lax, redireciona para a página de origem (ou /).
- **FR-4 (Logout)**: Rota POST /auth/logout (ou GET) invalida o token de sessão (via veb.auth ou session_tokens, no PostgreSQL) e limpa o cookie.
- **FR-5 (Conta automática)**: Se o provider_uid (Google sub) não existir, criar user + user_identity; se existir, atualizar name/avatar_url/email conforme retornado pelo Google.
- **FR-6 (Cache de avatar)**: A foto de perfil (avatar_url do Google) deve ser cacheada em memória (com expiração, ex: 1h) e servida por uma rota tipo GET /auth/avatar/:user_id que devolve a imagem (content-type apropriado) ou redireciona 302 para a URL original caso o cache esteja frio.
- **FR-7 (Premium suggestions)**: Documentar sugestões de endpoints premium baseados APENAS em dados já existentes (seção 13).
- **FR-8 (V1 depreciada com 410)**: Manter APIController (V1) registrada em [main.v](../../main.v), mas todas as rotas respondem 410 Gone com corpo indicando "API v1 depreciada; use a v2" + link para a documentação (/docs). V1 não serve dados de maré (evita bypass do rate-limit free). Implementação: substituir o corpo de cada handler V1 por ctx.res.set_status(.gone); ctx.json(types.failure[string](410, 'API v1 depreciada; use a v2. Docs: /docs')).
- **FR-9 (Persistência dividida)**: Dados de maré da API continuam em SQLite (-d using_sqlite); dados de usuário/login/dashboard/contadores/credits em PostgreSQL externo (persistente). Repositories de auth/dash/rate_limit usam sempre o pool PostgreSQL; repositories de maré usam o SQLite (ou PG em prod sem a flag).
- **FR-10 (Créditos mensais)**: Consulta de créditos restantes no mês via tabela monthly_credits no PostgreSQL. Por request autenticado (ou por IP no free), decrementar remaining atomicamente; quando remaining == 0 (e limit != 0), responder 429 (limit_exceeded: month).

#### Non-functional requirements

- **NFR-1**: O rate-limit em nível de app deve ser thread-safe (o app roda 2 instâncias no container; ver R2 sobre estado compartilhado). Contadores e créditos persistidos em PostgreSQL externo (fonte de verdade compartilhada entre instâncias). Contadores de janela de minuto e janela de mês.
- **NFR-2**: OAuth state deve ser aleatório e validado no callback (proteção CSRF).
- **NFR-3**: Cookies HttpOnly, Secure em prod, SameSite=Lax.
- **NFR-4**: Não logar tokens/secrets.
- **NFR-5**: Reutilizar padrões: ResultAPI[T], pool.ConnectionPool, apply_startup_migrations, TypeCacheData sum type.
- **NFR-6**: Extensibilidade: o schema de identidades deve permitir adicionar github sem alterar users.
- **NFR-7**: Dois pools de conexão: shareds.infradb (SQLite, maré) e shareds/infradb_pg (PostgreSQL externo, auth/dash/contadores/credits). Repositories de auth/dash usam sempre o pool PG; repositories de maré usam o SQLite (em -d using_sqlite) ou PG (prod sem a flag).

### Assumptions

- **A1**: Limites revisados pelo usuário (decisão final): por minuto — free 64, R$5 512, R$10 2560 req/min. Por mês — free 20k, R$5 250k, R$10 ilimitado. A unidade anterior (req/s) foi descartada.
- **A2**: O app usa V lib veb.oauth.Context para a troca de token (form post) e net.http para buscar userinfo. Não há dependência externa extra para OAuth.
- **A3**: **Sessão via veb.auth (nativo) — decisão do usuário (rev4)**: tentar veb.auth primeiro. Como veb.auth requer User com password_hash/salt (não aplicável a OAuth-only), o User de OAuth terá password_hash/salt placeholders (login é via OAuth, não via senha). Se veb.auth não couber (R3), implementar session_tokens própria como fallback.
- **A4**: O rate-limit pago é identificado por api_key emitida no painel do usuário (não pelo cookie de sessão). O cookie de sessão autentica o usuário nas páginas/painel; a api_key autentica chamadas de API pagas. Quando a api_key não é enviada, aplica-se o free por IP.
- **A5**: URL de produção é https://tabuamare.devtu.qzz.io/ (do Dockerfile URL_ENV). O callback OAuth é https://tabuamare.devtu.qzz.io/auth/google/callback.
- **A6**: Decisão do usuário — nginx sem rate-limit: remover limit_req_zone e qualquer limit_req do nginx; o app decide o barramento (R1 resolvido).
- **A7**: Decisão do usuário (rev4) — **V1 depreciada com resposta 410**: manter APIController (V1) registrada em [main.v](../../main.v), mas todas as rotas respondem 410 Gone com mensagem "API v1 depreciada; use a v2" + link para /docs. Evita bypass do rate-limit (V1 não serve dados) e orienta o cliente a migrar.
- **A8**: Divisão de persistência (decisão do usuário): SQLite = dados de maré da API (read-heavy, imutáveis no ano, regenerável da fonte oficial). **PostgreSQL = externo** (não no docker-compose.yml deste repo) = usuários, login (Google/...), dashboard, contadores de rate-limit, créditos mensais (persistente; SQLite é volátil para isso). As variáveis de ambiente que apontam para o Postgres externo vêm do env do sistema/hospedeiro (não de um arquivo .env).
- **A9**: Novo repository tabuamare_dash (decisão do usuário): domínio de negócio (uso, métricas, cobrança, créditos, painel), distinto da API de maré. Vive sob repository/tabuamare_dash/.
- **A10**: Infra de PostgreSQL exclusiva para login/usuário (decisão do usuário): segundo pool, shareds/infradb_pg/, sempre conecta ao Postgres externo (não condicional a -d using_sqlite).
- **A11**: Créditos mensais — decisão: usar PostgreSQL com tabela enxuta (monthly_credits), não Redis. Justificativa: o app é single-container, já vai ter Postgres para auth/dash; adicionar Redis é mais um serviço/dependência. Volume de consultas de crédito é baixo-a-moderado (uma consulta por request autenticado, ou por IP no free); Postgres com índice em (bucket, month_key) aguenta. Redis só valeria a pena se houvesse dezenas de milhares de req/s ou se a latência do Postgres se tornasse gargalo (reavaliar em R12). Ver seção "Créditos mensais — Redis vs Postgres".

### Open questions

- Q1: ~~Confirma que "2.5 req/s" = 2500 req/s?~~ Resolvido pelo usuário: limites são por minuto/mês (A1).
- Q2: ~~nginx vs app?~~ Resolvido pelo usuário: app decide; nginx sem rate-limit (A6).
- Q3: ~~Sessão própria vs veb.auth?~~ Resolvido pelo usuário (rev4): tentar veb.auth (nativo) primeiro; só implementar alternativa limpa caso dê problemas (R3).
- Q4: api_key separada do cookie de sessão? (A4) — ainda aberta (assumido sim).
- Q5: ~~V1: 404 vs 410/redirect?~~ Resolvido pelo usuário (rev4): V1 responde 410 Gone com mensagem "API v1 depreciada; use a v2" + link para /docs.
- Q6: ~~PostgreSQL no compose?~~ Resolvido pelo usuário (rev4): o PostgreSQL é um banco externo (não no docker-compose.yml deste repo); apenas as variáveis de ambiente (em env do sistema, não em arquivo .env) apontam para ele. Nada a adicionar ao compose.
- Q7: Os repositories de maré (habor_mare, tabua_mare) devem continuar apontando para SQLite em -d using_sqlite? (A8) — sim, não mudar (confirmado pela arquitetura).

No blocking questions. Proceed with the assumptions above.

## 4. Pragmatic Approach

**Abordagem escolhida (rate-limit + persistência)**: Rate-limit em nível de app (middleware veb.Middleware), usando um repositório de contadores em PostgreSQL externo (tabela rate_limit_counters) com chave ip (free) ou api_key (pago). Duas janelas por bucket: minuto corrente (para req/min) e mês corrente (para req/mês). PostgreSQL é a fonte de verdade compartilhada entre as 2 instâncias do container (o SQLite da API é volátil para essa finalidade e não deve guardar créditos/contadores). O nginx fica sem limit_req_zone (decisão do usuário: só o app tem contexto de plano).

**Divisão de persistência**:
- **SQLite** (taubinha.sqlite, via -d using_sqlite): dados de maré da API (data_mare, month_data, day_data, hour_data, geo_location). Read-heavy, imutáveis no ano; pode ser regenerado da fonte oficial.
- **PostgreSQL externo** (sempre, pool shareds/infradb_pg): users, user_identities, session_tokens (ou tabela de tokens do veb.auth), api_keys, rate_limit_counters, monthly_credits (créditos restantes por ip/api_key no mês), e tabelas do tabuamare_dash (métricas de uso, painel, cobrança).

**Dois pools**:
- shareds.infradb (SQLite) — para repositories de maré (como hoje).
- shareds.infradb_pg (PostgreSQL externo, novo) — para repositories de auth, rate_limit, tabuamare_dash.

**Login Google**: usar veb.oauth.Context (V lib embutido) para troca do code, e net.http.get para userinfo em https://www.googleapis.com/oauth2/v3/userinfo. Upsert em transação no PostgreSQL. **Sessão via veb.auth (nativo)** (A3, decisão do usuário rev4): tentar primeiro; User de OAuth terá password_hash/salt placeholders (login é por OAuth, não por senha). Fallback session_tokens própria só se veb.auth não couber (R3).

**Extensibilidade**: tabela users (neutra) + user_identities (provider, provider_uid, ...). Adicionar GitHub depois = nova rota /auth/github + mesmo upsert em user_identities com provider='github'. Sem mudar users.

**Cache de avatar**: estender o sum type TypeCacheData em [cache/type_cache_data.v](../../cache/type_cache_data.v) para incluir AvatarCacheData { bytes []u8, content_type string } ou criar um AvatarCache separado. Como cache.v tem TTL fixo de 5 min, criar um AvatarCache simples com TTL configurável (ex: 1h) para não poluir o cache de API. Pragmático: domain/auth_user/avatar_cache.v novo.

**Porque esta abordagem (rate-limit + persistência)**:
- Dois contadores (minuto + mês) permitem barrar por estouro de minuto (abuso pontual) e por cota mensal (uso cumulativo), refletindo o modelo freemium real.
- Chave por api_key para pagos garante que a cota mensal seja do cliente, não do IP (evita um cliente usar vários IPs para fugir da cota).
- Chave por IP para free é o único viável sem token.
- PostgreSQL para contadores/créditos garante persistência entre reinícios (R9) e coerência entre as 2 instâncias (R2), sem adicionar Redis.
- SQLite continua para maré porque os dados são imutáveis e read-heavy; migrar maré para Postgres seria retrabalho sem ganho.

**Porque remover o rate-limit do nginx**:
- Só o app sabe o plano (free/plan5/plan10) e a api_key; o nginx só vê IP. Se o nginx barrar antes, um cliente pago pode ser bloqueado injustamente; se o nginx não barrar, o free precisa do app. Centralizar no app é mais coerente.

**Porque depreciar a V1 com 410 (em vez de 404/não-registrar)**:
- Sem rate-limit na V1, qualquer um usa /api/v1/* para fugir do free. Mesmo com rate-limit na V1, duplica a lógica. Decisão do usuário (Q5): manter V1 respondendo 410 Gone com mensagem "use a v2" + link /docs — V1 não serve dados (evita bypass) e orienta o cliente a migrar. Mais gentil que 404; não quebra como redirect (IDs de porto mudam de int para string entre V1 e V2).

**Porque tentar veb.auth (nativo) para sessão**:
- Decisão do usuário (Q3): é nativo, menos código para manter. Se exigir password_hash/salt incompatível com OAuth-only, usa-se placeholders (login é via OAuth, não via senha). Fallback session_tokens própria só se houver problema real (R3).

**Alternativas consideradas**:
- Rate-limit só no nginx: rejeitado porque o nginx só vê IP (não plano/api_key) e estrangularia clientes pagos.
- Redis para contadores: rejeitado por adicionar dependência/complexidade ao single-container (A11).
- veb.auth para sessão: tentar primeiro (decisão do usuário); fallback session_tokens própria só se exigir password_hash/salt incompatível com OAuth-only (R3).
- JWT stateless: adiado (complexidade de rotação de chaves); sessão em tabela é mais simples para invalidar no logout.

## 5. Affected Areas

- [main.v](../../main.v)
  - Reason: Registrar novo AuthController e (opcional) PremiumAPIController; passar pool_conn (SQLite) e pool_conn_pg (Postgres) e env. **Manter V1 registrada** (mas seus handlers respondem 410). Chamar infradb_pg.apply_pg_startup_migrations() junto com infradb.apply_startup_migrations(). Adicionar botão de login no fluxo das páginas.
- [api_v2.v](../../api_v2.v)
  - Reason: Aplicar middleware de rate-limit (api.use(rate_limit_middleware[WsCtx](...))) antes do CORS ou após. Determinar ordem (CORS pré-flight deve passar; rate-limit só em rotas de dados). O middleware usa o pool PostgreSQL.
- [api.v](../../api.v)
  - Reason: **Manter registrada**, mas trocar o corpo de cada handler para responder 410 Gone com mensagem "API v1 depreciada; use a v2. Docs: /docs" (Q5 decisão do usuário). Mantém CORS. V1 não serve dados.
- [shareds/web_ctx/web_ctx.v](../../shareds/web_ctx/web_ctx.v)
  - Reason: Adicionar campos na WsCtx (current_user, api_key, ip, plan) preenchidos pelo middleware de auth/rate-limit.
- [shareds/conf_env/conf_env.v](../../shareds/conf_env/conf_env.v)
  - Reason: Confirmar carregamento das vars Postgres já presentes no env do sistema (DB_DATABASE/DB_USER/DB_HOST/DB_PASS/DB_PORT) — load_env() já prioriza os.getenv. Adicionar campos Google OAuth + rate-limit config a EnvConfig e a load_env().
- [shareds/infradb/infradb.v](../../shareds/infradb/infradb.v)
  - Reason: Mantém pool SQLite (maré). Novo shareds/infradb_pg/infradb_pg.v — pool PostgreSQL externo (auth/dash/contadores).
- [shareds/infradb/migrations.v](../../shareds/infradb/migrations.v)
  - Reason: Mantém migrações SQLite de maré. Não adicionar tabelas de usuário aqui (vão para o pool PG).
- shareds/infradb_pg/migrations.v (novo)
  - Reason: ensure_users_tables(), ensure_rate_limit_tables(), ensure_monthly_credits_table(), ensure_dash_tables() em PostgreSQL (usando veb.auth se couber, ou session_tokens própria).
- [cache/type_cache_data.v](../../cache/type_cache_data.v)
  - Reason: Estender sum type se usar cache unificado; ou criar cache de avatar separado.
- [domain/auth_user/auth.v](../../domain/auth_user/auth.v)
  - Reason: Expandir UserData (adicionar id, avatar_url, provider) e adicionar funções de upsert/issue token.
- [pages/navbar.html](../../pages/navbar.html) e [shareds/components_view/navbar.v](../../shareds/components_view/navbar.v)
  - Reason: Adicionar botão "Login"/"Logout" + avatar.
- [.env.template](../../.env.template)
  - Reason: Documentar novas variáveis Google + rate-limit (as vars do Postgres externo vêm do env do sistema, não deste arquivo — apenas referência).
- [nginx/nginx.conf](../../nginx/nginx.conf) e [nginx/conf.d/maisfoco.conf](../../nginx/conf.d/maisfoco.conf)
  - Reason: Remover limit_req_zone e limit_req (decisão do usuário). O nginx passa a só fazer proxy; o app decide o barramento por plano/api_key.
- [docker-compose.yml](../../docker-compose.yml) e [Dockerfile](../../Dockerfile)
  - Reason: Não adicionar serviço PostgreSQL (o banco é externo, Q6). Garantir apenas que o app lê as vars DB_* do env do sistema (hospedeiro injeta, não arquivo .env). Confirmar que Dockerfile/compose não sobrescrevem DB_* com vazios.
- Novos arquivos (a serem criados pelo agente de implementação, não por este plano):
  - shareds/infradb_pg/infradb_pg.v, shareds/infradb_pg/migrations.v
  - domain/auth_user/google_auth.v, domain/auth_user/session.v (se veb.auth não couber), domain/auth_user/avatar_cache.v
  - repository/auth/ (users, user_identities, [session_tokens se fallback], api_keys) — pool PostgreSQL
  - repository/rate_limit/ (counters de minuto/mês por ip/api_key + credits mensais) — pool PostgreSQL
  - repository/tabuamare_dash/ (usage_metrics, billing, panel) — pool PostgreSQL
  - controllers/auth_controller.v (rotas /auth/*)
  - shareds/rate_limit/middleware.v

## 6. Execution Checklist

### Phase 1 — Preparation

- [x] Confirmar Q4 (api_key separada) apenas. Q3/Q5/Q6 resolvidos pelo usuário (A3/A7/A8). A1/A2/A6/A7/A8/A9/A10/A11 já decididos.
- [x] Confirmar nomes das vars Postgres no env do sistema (DB_DATABASE, DB_USER, DB_HOST, DB_PASS, DB_PORT) e que conf_env já as carrega (Postgres é externo, não via .env file).
- [ ] Definir variáveis de ambiente a adicionar ao .env.template (ver seção 10), já refletindo req/min + req/mês + Google.

### Phase 2 — Implementation Steps

- [x] Criar shareds/infradb_pg/infradb_pg.v (pool PostgreSQL externo sempre-on, new() !&pool.ConnectionPool, create_conn via db.pg.connect(config) lendo EnvConfig).
- [x] Criar shareds/infradb_pg/migrations.v com apply_pg_startup_migrations() criando em PostgreSQL: users, user_identities, [tabela de tokens do veb.auth ou session_tokens], api_keys, rate_limit_counters, monthly_credits, tabelas do tabuamare_dash (ver schema seção 10).
- [x] Chamar infradb_pg.apply_pg_startup_migrations() em [main.v](../../main.v) junto com infradb.apply_startup_migrations().
- [x] Estender EnvConfig em [shareds/conf_env/conf_env.v](../../shareds/conf_env/conf_env.v) com campos: google_client_id, google_client_secret, google_redirect_uri, google_auth_url, google_token_url, google_userinfo_url, google_scope, session_secret, rate_limit_free_rpm (64), rate_limit_plan5_rpm (512), rate_limit_plan10_rpm (2560), rate_limit_free_monthly (20000), rate_limit_plan5_monthly (250000), rate_limit_plan10_monthly (0 = ilimitado). Confirmar que db_database/db_user/db_host/db_pass/db_port (Postgres externo) já estão presentes e são carregados do env do sistema.
- [x] Adicionar carregamento dessas variáveis em load_env() (get_env com default onde aplicável).
- [x] **Tentar veb.auth para sessão**: criar User com password_hash/salt placeholders (login via OAuth, não via senha); usar veb.auth.add_token(user_id) para emitir o token de sessão. Se houver incompatibilidade (R3), criar repository/auth/session.v com tabela session_tokens própria.
- [x] Criar entidades ORM (PostgreSQL): entities/user.v, entities/user_identity.v, [entities/session_token.v se fallback], entities/api_key.v, entities/rate_limit_counter.v, entities/monthly_credit.v.
- [x] Criar repository/auth/users.v (upsert por provider+provider_uid, find by id, find by email) — usa pool PostgreSQL (infradb_pg).
- [x] Criar repository/auth/api_keys.v (issue, find by key, get plan by user) — pool PostgreSQL.
- [x] Criar repository/rate_limit/counters.v (inc_and_check(bucket, window_kind, window_key, limit) -> exceeded bool) — pool PostgreSQL.
- [x] Criar repository/rate_limit/credits.v (get_remaining_monthly(bucket, plan) -> int; decrement_on_request(...)) — pool PostgreSQL. Consulta de créditos mensais (free/pagos).
- [ ] Criar repository/tabuamare_dash/usage_metrics.v (contagem de uso por usuário/api_key), billing.v (status de plano/cobrança), panel.v (dados do painel). Distinto da API de maré; usa pool PostgreSQL.
- [x] Criar domain/auth_user/google_auth.v: build auth URL com state randômico, troca do code via veb.oauth.Context, fetch userinfo, mapear para UserData.
- [ ] Criar controllers/auth_controller.v (AuthController) com rotas GET /auth/google, GET /auth/google/callback, POST /auth/logout, GET /auth/me, GET /auth/avatar/:user_id.
- [ ] Registrar AuthController em [main.v](../../main.v) (base / ou /auth).
- [x] Criar shareds/rate_limit/middleware.v: função rate_limit_middleware[T](opts) que lê ctx.ip() e/ou Authorization/api_key, decide limite (por minuto + por mês), incrementa contadores (PostgreSQL) para a janela de minuto e de mês, decrementa crédito mensal (PostgreSQL monthly_credits) e retorna 429 se exceder qualquer um (com Retry-After e campo limit_exceeded: minute | month).
- [ ] Aplicar o middleware em [api_v2.v](../../api_v2.v) (e nos futuros endpoints premium). Não aplicar na V1 (que só responde 410, não serve dados).
- [ ] **V1 depreciada com 410**: manter APIController (V1) registrada em [main.v](../../main.v) e o init_cors(); em [api.v](../../api.v) trocar o corpo de cada handler para responder 410 Gone com mensagem "API v1 depreciada; use a v2. Docs: /docs" (não remover o registro, não 404). Evita bypass (V1 não serve dados).
- [ ] Remover rate-limit do nginx: em [nginx/nginx.conf](../../nginx/nginx.conf) remover a linha limit_req_zone $binary_remote_addr zone=api:10m rate=1000r/m; e quaisquer limit_req em [nginx/conf.d/maisfoco.conf](../../nginx/conf.d/maisfoco.conf).
- [x] Criar domain/auth_user/avatar_cache.v com TTL configurável (ex: 1h), get(user_id)/set(user_id, bytes, content_type); fallback para 302 na URL do Google.
- [ ] Adicionar botão "Login"/"Logout" + avatar em [pages/navbar.html](../../pages/navbar.html) e [shareds/components_view/navbar.v](../../shareds/components_view/navbar.v) (passar current_user para o template).
- [ ] Atualizar [pages/docs.html](../../pages/docs.html) (seção Authentication) para refletir os novos limites (por minuto/mês) e planos, e a depreciação da V1 (410 com link /docs).

### Phase 3 — Tests and Validation

- [ ] Teste manual: v run -d using_sqlite . 3330 → iniciar sem erros e aplicar migrações SQLite + PostgreSQL (Postgres externo precisa estar acessível via env do sistema).
- [ ] Teste manual: acessar http://localhost:3330/auth/google e validar redirecionamento para Google.
- [ ] Teste manual: callback com code válido cria usuário (verificar tabela users/user_identities no PostgreSQL externo).
- [ ] Teste manual: chamar /api/v2/states 65x em 1 min a partir do mesmo IP → 65ª retorna 429 (limit_exceeded: minute).
- [ ] Teste manual: chamar 20.001x no mês a partir do mesmo IP (free) → a 20.001ª retorna 429 (limit_exceeded: month).
- [ ] Teste manual: chamar com api_key do plano R$5 → permite até 512 req/min e 250k req/mês (simular).
- [ ] Teste manual: chamar com api_key do plano R$10 → permite até 2560 req/min, sem limite mensal.
- [ ] Teste manual: confirmar que /api/v1/* responde 410 Gone com mensagem "use a v2" + link /docs (e não serve dados de maré).
- [ ] Teste manual: confirmar que contadores/credits persistem após reinício do app (PostgreSQL externo).
- [ ] Teste de upsert: repetir login com mesmo Google → não duplica users, atualiza avatar_url/name.
- [ ] Teste de logout: invalida a sessão (veb.auth token ou session_tokens), cookie limpo.
- [ ] Teste de avatar cache: segundo acesso serve do cache (sem novo hit ao Google).
- [ ] Executar v test tests/ e confirmar que find_nearested_harbor_test.v continua passando.

### Phase 4 — Review

- [ ] Revisar que nenhum secret foi comitado.
- [ ] Revisar que o rate-limit não bloqueia /ping, /, /docs, /playground, /apoiar (páginas) — só /api/v2/* e premium.
- [ ] Revisar CORS: o rate-limit deve ocorrer após o pré-flight CORS ser respondido.
- [ ] Revisar que o nginx não tem mais limit_req_zone/limit_req.
- [ ] Revisar que repositories de maré usam SQLite e repositories de auth/dash/rate_limit usam PostgreSQL (sem cruzar pools).
- [ ] Revisar que veb.auth (se usado) funciona com User de OAuth (password_hash/salt placeholders) ou que session_tokens própria está implementada como fallback.

## 7. Validation Plan

### Automated validation

- [ ] v -d using_sqlite .  compila sem erros (com Postgres externo acessível via env do sistema para migração).
- [ ] v test tests/ passa (sem regressão no find_nearested_harbor).
- [ ] (Opcional) criar tests/auth_upsert_test.v, tests/rate_limit_test.v, tests/credits_test.v.

### Manual validation

- [ ] Fluxo completo Google login → cookie setado → /auth/me retorna usuário.
- [ ] Limite free 64 req/min rejeita o excesso com 429 + Retry-After (limit_exceeded: minute).
- [ ] Cota free 20k req/mês rejeita o excesso com 429 (limit_exceeded: month).
- [ ] Avatar cacheado serve em <50ms após o primeiro carregamento.
- [ ] Contadores/credits persistem entre reinícios (PostgreSQL externo).

### Regression checks

- [ ] Endpoints /api/v2/* existentes respondem igual (exceto quando rate-limited).
- [ ] /ping responde 200.
- [ ] Páginas HTML (/, /docs, /playground, /apoiar) continuam renderizando.

## 8. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---:|---|
| R1 — nginx limit_req_zone 1000r/m estrangularia clientes pagos e conflitaria com limites do app | High | Decisão do usuário: remover o rate-limit do nginx (A6). O app decide por plano/api_key. |
| R2 — Rate-limit in-memory por instância diverge entre as 2 instâncias do container | Medium | Usar tabela rate_limit_counters no PostgreSQL externo compartilhado como fonte de verdade (contadores de minuto e mês). |
| R3 — veb.auth exige password_hash/salt, pode ser incompatível com OAuth-only | Medium | Tentar veb.auth com password_hash/salt placeholders (login via OAuth, não via senha). Se incompatível, implementar session_tokens própria (PostgreSQL) — decisão do usuário: tentar nativo primeiro. |
| R4 — hour_data.hour é string (ex: "0100"), não timestamp — cálculos de "maré atual" exigem parsing + timezone | Medium | Documentar no endpoint premium de "maré atual"; usar DataMare.timezone para conversão. |
| R5 — Dados históricos só existem para o ano corrente (time.now().year hardcoded) | Medium | Confirmar se o SQLite contém anos anteriores; se não, histórico premium depende de coleta retroativa. |
| R6 — CSRF no callback OAuth | Medium | Validar state randômico guardado em cookie/estado efêmero. |
| R7 — Vazamento de client_secret | High | Nunca logar; só via EnvConfig; .env no .gitignore. |
| R8 — Multi-tenant de planos: onde fica o plano de cada api_key? | Medium | api_keys.plan (enum: free/plan5/plan10) definido na criação da key. Limites por minuto/mês lidos de EnvConfig ou de plan_limits. |
| R9 — Cota mensal por IP (free) requer persistência de contadores entre reinícios | Medium | rate_limit_counters e monthly_credits em PostgreSQL externo persistente; janela de mês usa YYYYMM na chave. |
| R10 — V1 ainda registrada em algum deploy antigo gera bypass | Medium | Confirmar que os handlers V1 respondem 410 (não servem dados) em todos os ambientes; documentar deprecation na [pages/docs.html](../../pages/docs.html). |
| R11 — PostgreSQL externo indisponível derruba login/rate-limit mesmo que a API de maré (SQLite) esteja ok | Medium | Middleware de rate-limit com fallback curto (ex: se PG falhar, aplicar limite free conservador in-memory por IP temporariamente, logar e não bloquear a API de maré). |
| R12 — Latência do PostgreSQL na consulta de crédito por request pode virar gargalo em alto RPS | Low/Medium | Índice em (bucket, month_key) + EXPLAIN; se virar gargalo, migrar contadores de minuto para Redis (manter créditos mensais no PG). Reavaliar após métricas. |

## 9. Dependencies

### Internal dependencies

- [shareds/infradb](../../shareds/infradb) (pool SQLite para maré).
- Novo shareds/infradb_pg (pool PostgreSQL externo para auth/dash/contadores/credits).
- [shareds/types](../../shareds/types) (ResultAPI).
- [cache](../../cache) (padrão de cache).
- [domain/auth_user](../../domain/auth_user) (UserData).
- [shareds/conf_env](../../shareds/conf_env) (env).
- [shareds/web_ctx](../../shareds/web_ctx) (context).
- [shareds/components_view](../../shareds/components_view) + [pages/](../../pages) (navbar/páginas).

### External dependencies

- db.pg (V lib embutido) — driver PostgreSQL para o novo pool.
- veb.oauth (V lib embutido) — troca de code OAuth.
- veb.auth (V lib embutido) — tentar usar para sessão (A3/Q3 decisão do usuário); User de OAuth com password_hash/salt placeholders. Fallback session_tokens própria só se incompatível.
- net.http — userinfo fetch.
- crypto.rand ou rand — gerar state/api_key.
- crypto.hmac/crypto.sha256 — assinar/validar session_token/api_key (se não usar tabela/veb.auth).
- Serviço PostgreSQL externo (Q6 — não está no docker-compose.yml deste repo; apontado por env vars do sistema/hospedeiro).

## 10. Implementation Notes for the Next Agent

### Variáveis de ambiente (Postgres externo via env do sistema, não arquivo .env)

> **Decisão do usuário**: o PostgreSQL é externo e suas variáveis vêm do env do sistema/hospedeiro (não de um arquivo .env). conf_env.load_env() já prioriza os.getenv sobre o .env (ver [shareds/conf_env/conf_env.v](../../shareds/conf_env/conf_env.v)), então basta garantir que EnvConfig carrega DB_DATABASE/DB_USER/DB_HOST/DB_PASS/DB_PORT. O .env.template aqui é só referência; as vars reais do Postgres são injetadas pelo hospedeiro.

```env
# PostgreSQL externo (auth/dash/contadores/credits) — vêm do env do sistema, não deste arquivo
DB_DATABASE=
DB_USER=
DB_HOST=
DB_PASS=
DB_PORT=5432
# SQLite (maré)
DB_SQLITE_PATH=./taubinha.sqlite
# Google OAuth
GOOGLE_CLIENT_ID=[PRECISA PREENCHER]
GOOGLE_CLIENT_SECRET=[PRECISA PREENCHER]
GOOGLE_REDIRECT_URI=https://tabuamare.devtu.qzz.io/auth/google/callback
GOOGLE_AUTH_URL=https://accounts.google.com/o/oauth2/v2/auth
GOOGLE_TOKEN_URL=https://oauth2.googleapis.com/token
GOOGLE_USERINFO_URL=https://www.googleapis.com/oauth2/v3/userinfo
GOOGLE_SCOPE=openid email profile
# Session
SESSION_SECRET=[PRECISA PREENCHER - 32+ bytes aleatórios]
SESSION_COOKIE_NAME=tm_session
SESSION_TTL_HOURS=720
# Avatar cache
AVATAR_CACHE_TTL_MINUTES=60
# Rate limit (per minute)
RATE_LIMIT_FREE_RPM=64
RATE_LIMIT_PLAN5_RPM=512
RATE_LIMIT_PLAN10_RPM=2560
# Rate limit (per month; 0 = unlimited)
RATE_LIMIT_FREE_MONTHLY=20000
RATE_LIMIT_PLAN5_MONTHLY=250000
RATE_LIMIT_PLAN10_MONTHLY=0
```

### Rotas a implementar (para o Google Cloud Console)

| Método | Rota | Propósito |
|---|---|---|
| GET | /auth/google | Inicia OAuth: gera state, redireciona para GOOGLE_AUTH_URL com client_id, redirect_uri, scope, state, access_type=online, prompt=consent. |
| GET | /auth/google/callback | Recebe ?code=&state=, valida state, troca code por tokens (veb.oauth.Context), busca userinfo (GOOGLE_USERINFO_URL), upsert user/identity (PostgreSQL externo), cria token de sessão (veb.auth.add_token ou session_tokens), seta cookie HttpOnly, redireciona para / (ou ?next=). |
| POST | /auth/logout | Invalida token de sessão (veb.auth.delete_tokens ou session_tokens) no PostgreSQL, limpa cookie, redireciona para /. |
| GET | /auth/me | Retorna JSON ResultAPI[UserData] do usuário corrente (ou 401). |
| GET | /auth/avatar/:user_id | Serve avatar cacheado (ou 302 para URL do Google). |
| GET | /auth/api-keys | (Painel) Lista api_keys do usuário. |
| POST | /auth/api-keys | (Painel) Cria nova api_key com plano. |

### Valores para o Google Cloud Console (OAuth Client ID — Web Application)

- **Authorized JavaScript origins (Origens autorizadas de JavaScript)**:
  - https://tabuamare.devtu.qzz.io
  - http://localhost:3330 (dev)
- **Authorized redirect URIs (URIs de redirecionamento autorizados)**:
  - https://tabuamare.devtu.qzz.io/auth/google/callback
  - http://localhost:3330/auth/google/callback (dev)
- **Application type**: Web application
- **Homepage URL**: https://tabuamare.devtu.qzz.io
- **Privacy policy URL**: (preencher)
- **Terms of service URL**: (preencher, opcional)
- **Scopes (consent screen)**: openid, email, profile
- **Support email**: (preencher)

### Schema de tabelas (PostgreSQL externo, criar em apply_pg_startup_migrations)

Pseudocode (não é código de produção):

```sql
-- users: neutra, independente de provider. Se veb.auth couber, pode ter password_hash/salt placeholders.
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL DEFAULT '',
  avatar_url TEXT NOT NULL DEFAULT '',
  plan TEXT NOT NULL DEFAULT 'free',
  password_hash TEXT NOT NULL DEFAULT '',  -- placeholder (login via OAuth, não via senha) se veb.auth
  salt TEXT NOT NULL DEFAULT '',           -- placeholder se veb.auth
  created_at TIMESTAMP NOT NULL DEFAULT now(),
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);

-- user_identities: extensível (google, github, ...)
CREATE TABLE IF NOT EXISTS user_identities (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  provider_uid TEXT NOT NULL,
  email TEXT NOT NULL DEFAULT '',
  name TEXT NOT NULL DEFAULT '',
  avatar_url TEXT NOT NULL DEFAULT '',
  raw_json TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMP NOT NULL DEFAULT now(),
  updated_at TIMESTAMP NOT NULL DEFAULT now(),
  UNIQUE(provider, provider_uid)
);
CREATE INDEX IF NOT EXISTS idx_user_identities_user ON user_identities(user_id);
CREATE INDEX IF NOT EXISTS idx_user_identities_provider ON user_identities(provider, provider_uid);

-- session_tokens: só criar se veb.auth não couber (fallback R3)
CREATE TABLE IF NOT EXISTS session_tokens (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  value TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_session_tokens_value ON session_tokens(value);
CREATE INDEX IF NOT EXISTS idx_session_tokens_user ON session_tokens(user_id);

-- api_keys: chaves para chamadas de API pagas
CREATE TABLE IF NOT EXISTS api_keys (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key_value TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL DEFAULT '',
  plan TEXT NOT NULL DEFAULT 'free',
  created_at TIMESTAMP NOT NULL DEFAULT now(),
  revoked_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_api_keys_value ON api_keys(key_value);

-- rate_limit_counters: contadores por janela (minuto ou mês) por ip ou api_key
CREATE TABLE IF NOT EXISTS rate_limit_counters (
  bucket TEXT NOT NULL,                -- 'ip:1.2.3.4' ou 'key:abc123'
  window_kind TEXT NOT NULL,           -- 'minute' | 'month'
  window_key TEXT NOT NULL,            -- 'YYYYMMDDHHMM' para minute; 'YYYYMM' para month
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (bucket, window_kind, window_key)
);
CREATE INDEX IF NOT EXISTS idx_rate_limit_bucket ON rate_limit_counters(bucket, window_kind);

-- monthly_credits: créditos mensais restantes (consultados por request; tabela enxuta)
CREATE TABLE IF NOT EXISTS monthly_credits (
  bucket TEXT NOT NULL,                -- 'ip:1.2.3.4' ou 'key:abc123'
  month_key TEXT NOT NULL,             -- 'YYYYMM'
  plan TEXT NOT NULL DEFAULT 'free',
  used INTEGER NOT NULL DEFAULT 0,
  limit INTEGER NOT NULL,               -- 20000, 250000, 0 (ilimitado)
  remaining INTEGER NOT NULL,           -- limit - used (ou -1 para ilimitado)
  reset_at TIMESTAMP NOT NULL,
  PRIMARY KEY (bucket, month_key)
);
CREATE INDEX IF NOT EXISTS idx_monthly_credits_bucket ON monthly_credits(bucket, month_key);
```

### Ordem do middleware

1. CORS (já existe em init_cors()) — pré-flight passa sempre.
2. Rate-limit (decide 64/512/2560 req/min + 20k/250k/ilimitado req/mês via PostgreSQL externo; responde 429 se excedido, com Retry-After e limit_exceeded).
3. (Opcional) Auth resolver (preenche ctx.current_user se houver cookie, não bloqueia).

### Créditos mensais — Redis vs Postgres

**Decisão: PostgreSQL com tabela enxuta (monthly_credits).**

Razões:
- O app é single-container e já vai ter Postgres para auth/dash; adicionar Redis é mais um serviço, mais uma dependência e mais um ponto de falha.
- Volume de consultas de crédito: uma consulta por request autenticado (ou uma por IP no free). Em 2560 req/min (plano R$10), são ~43 req/s — Postgres com índice em (bucket, month_key) resolve em <1ms sem suar.
- Redis valeria a pena se: (a) houvesse dezenas de milhares de req/s, (b) a latência do Postgres se tornasse gargalo (R12), ou (c) quisesse contadores de minuto com expiração automática (TTL nativo). Para crédito mensal (granularidade grossa, reset por mês), Postgres é suficiente.
- A tabela monthly_credits é enxuta (bucket, month_key, plan, used, limit, remaining, reset_at); a consulta é SELECT remaining FROM monthly_credits WHERE bucket=? AND month_key=? — uma linha por bucket/mês.
- Reavaliar para Redis só se métricas mostrarem gargalo (R12).

**Implementação**:
- No middleware, por request: ler/criar a linha de monthly_credits para o bucket+mês corrente; se remaining == 0 (e limit != 0), responder 429 (limit_exceeded: month); senão decrementar remaining e incrementar used atomicamente (transação ou UPDATE ... WHERE remaining > 0).
- Reset mensal: job (ou on-demand no primeiro request do mês) cria nova linha com month_key novo e remaining = limit.

### V1 — Depreciada (410 Gone)

- Em [main.v](../../main.v): manter APIController (V1) registrada e o init_cors(). Em [api.v](../../api.v), trocar o corpo de cada handler para responder 410 Gone com mensagem "API v1 depreciada; use a v2. Docs: /docs".
- Risco de bypass: V1 não serve dados (só 410), então o free não é burlável pela V1.
- Decisão do usuário (Q5): 410 Gone com link para /docs (não 404, não redirect — redirect quebraria porque IDs de porto mudam de int para string entre V1 e V2).

### nginx — Remover rate-limit

- Em [nginx/nginx.conf](../../nginx/nginx.conf): remover limit_req_zone $binary_remote_addr zone=api:10m rate=1000r/m;.
- Em [nginx/conf.d/maisfoco.conf](../../nginx/conf.d/maisfoco.conf): remover qualquer limit_req zone=api ...;.
- Justificativa (usuário): o app tem o contexto de plano/api_key; o nginx só vê IP e barraria clientes pagos. O app passa a ser a única camada de rate-limit.
- O nginx mantém as demais funções (proxy, gzip, healthcheck).

### Sessão — veb.auth (nativo) tentar primeiro

- Decisão do usuário (Q3): tentar veb.auth primeiro (é nativo, menos código).
- veb.auth requer User com password_hash/salt; para OAuth-only, usar placeholders (login é via Google, não via senha).
- veb.auth.add_token(user_id) emite o token; veb.auth.find_token(value) valida; veb.auth.delete_tokens(user_id) invalida no logout.
- Se houver incompatibilidade real (R3), implementar repository/auth/session.v com tabela session_tokens própria e fallback.

### Persistência dividida (resumo)

- **SQLite** (-d using_sqlite, pool shareds.infradb): data_mare, month_data, day_data, hour_data, geo_location (maré). Repositories habor_mare, tabua_mare.
- **PostgreSQL externo** (sempre, pool shareds/infradb_pg): users, user_identities, [tabela de tokens do veb.auth ou session_tokens], api_keys, rate_limit_counters, monthly_credits, tabelas tabuamare_dash. Repositories auth, rate_limit, tabuamare_dash.
- Não cruzar pools: maré nunca escreve no Postgres; auth/dash nunca lê SQLite.

## 11. Completion Criteria

- [ ] Login com Google funcional em prod (https://tabuamare.devtu.qzz.io/auth/google).
- [ ] Conta criada automaticamente no primeiro login; não duplicada no segundo (PostgreSQL externo).
- [ ] Foto de perfil servida via cache (sem hit ao Google no segundo acesso).
- [ ] Rate-limit free 64 req/min e 20k req/mês por IP retorna 429 ao exceder (com limit_exceeded).
- [ ] api_key dos planos R$5/R$10 aplica 512/2560 req/min e 250k/ilimitado req/mês.
- [ ] Logout invalida a sessão (veb.auth token ou session_tokens, no PostgreSQL externo).
- [ ] Tabelas de auth/dash/contadores/credits criadas via apply_pg_startup_migrations em PostgreSQL externo (sem SQL manual).
- [ ] Contadores e credits persistem entre reinícios (PostgreSQL externo).
- [ ] .env.template atualizado com todas as variáveis (vars do Postgres externo são referência; as reais vêm do env do sistema).
- [ ] Google Cloud Console configurado com as URIs desta seção.
- [ ] nginx sem limit_req_zone; rate-limit centralizado no app.
- [ ] V1 responde 410 Gone com mensagem "use a v2" + link /docs — sem bypass do free.
- [ ] Repositories de maré usam SQLite; auth/dash/rate_limit usam PostgreSQL externo (sem cruzar pools).
- [ ] Novo repository tabuamare_dash criado (domínio de negócio).
- [ ] Consulta de créditos mensais funcional via monthly_credits (PostgreSQL externo).
- [ ] Sessão via veb.auth (nativo) tentada primeiro; fallback session_tokens própria se incompatível.
- [ ] Sugestões de endpoints premium documentadas (seção 13).

## 12. Self-Validation

- [ ] The plan does not implement anything.
- [ ] All tasks are actionable.
- [ ] All tasks are ordered.
- [ ] Each task has a validation path.
- [ ] Risks and assumptions are documented.
- [ ] File references are included where useful.
- [ ] The plan is stored only under .plans/20260626-225030-9c1b4f-auth-rate-limit-google-login-premium-suggestions/.
- [ ] Limites refletidos como req/min + req/mês (não req/s).
- [ ] nginx marcado para remoção do rate-limit (A6).
- [ ] V1 marcada para responder 410 Gone com link /docs (A7).
- [ ] Persistência dividida: SQLite (maré) + PostgreSQL externo (auth/dash/contadores/credits) (A8).
- [ ] PostgreSQL é externo (env do sistema, não .env file, não no compose) (A8/Q6).
- [ ] Novo repository tabuamare_dash (negócio) e shareds/infradb_pg (pool PG) (A9/A10).
- [ ] Créditos mensais via tabela enxuta no PostgreSQL (A11).
- [ ] Tentar veb.auth nativo para sessão; fallback session_tokens própria se incompatível (A3/Q3).

## 13. Sugestões de Endpoints Premium (Dados como Serviço)

> **Premissa**: usar APENAS os dados já existentes no SQLite: data_mare (ano, porto, estado, timezone, card, mean_level, instituição), month_data, day_data (weekday_name, day), hour_data (hour string + level f32), geo_location (lat/lng). Não há timestamp Unix; hour é string (ex: "0100"). Não há anos anteriores confirmados (R5) — histórico depende do conteúdo real do banco.

### 13.1 Endpoints de inteligência derivada

- **GET /api/v2/premium/tide-extremes/:harbor/:month**
  - Para cada dia do mês, retorna a maré alta máxima e a maré baixa mínima (maior e menor level do dia), com horários.
  - Valor: surfistas, pescadores, operações portuárias.
  - Dados usados: day_data + hour_data.

- **GET /api/v2/premium/tide-summary/:harbor/:month**
  - Estatísticas mensais: maior maré, menor maré, amplitude média, nº de marés altas/baixas, dias com maré < mean_level.
  - Dados usados: hour_data.level agregado por mês + data_mare.mean_level.

- **GET /api/v2/premium/day-types/:harbor/:month**
  - Classifica cada dia: "maré de sizígia" (amplitude grande) vs "maré de quadratura" (amplitude pequena), baseado na diferença entre máxima e mínima do dia.
  - Dados usados: hour_data por dia.

- **GET /api/v2/premium/nearest-high-tide/:harbor/:month/:day**
  - Próxima maré alta após um horário de referência (ex: "agora"), considerando data_mare.timezone.
  - Dados usados: hour_data + data_mare.timezone.

- **GET /api/v2/premium/safe-window/:harbor/:month/:day?min_level=:x&max_level=:y**
  - Janelas contínuas do dia em que o nível fica dentro de [min_level, max_level] (ex: para navegação segura, atracação).
  - Dados usados: hour_data.level ordenado por hour.

### 13.2 Endpoints de geolocalização/nearest

- **GET /api/v2/premium/harbors-within/:lat/:lng/:radius_km**
  - Lista portos dentro de um raio (km) das coordenadas, usando geo_location + geohash (já indexado).
  - Valor: apps multi-porto.
  - Dados usados: geo_location + data_mare.

- **GET /api/v2/premium/coverage-map**
  - GeoJSON com todos os portos e suas coordenadas (geo_location), agrupados por estado, para mapas.
  - Dados usados: data_mare + geo_location.

### 13.3 Endpoints de histórico/series (se houver anos anteriores no banco)

- **GET /api/v2/premium/history/:harbor/:year**
  - Tábua completa de um porto para um ano inteiro (todos os meses/dias). Atualmente get_tabua_mare_by_month_days filtra por time.now().year; este endpoint ignora o filtro de ano corrente e aceita year como parâmetro.
  - **Risco R5**: confirmar se o SQLite tem dados de anos anteriores. Se só tiver o ano corrente, este endpoint retorna 404 até haver coleta histórica.
  - Dados usados: data_mare.year + month_data + day_data + hour_data.

- **GET /api/v2/premium/yearly-comparison/:harbor?years=2024,2025,2026**
  - Compara a média mensal de maré entre anos para o mesmo porto.
  - Dados usados: hour_data.level agregado por mês/ano.

### 13.4 Endpoints de exportação

- **GET /api/v2/premium/export/:harbor/:year?format=csv|json**
  - Exporta a tábua anual completa em CSV/JSON (bulk). Útil para pesquisadores.
  - Dados usados: todas as tabelas de maré.

- **GET /api/v2/premium/bulk-tabua/:state/:month/:days**
  - Tábua de todos os portos de um estado em uma única chamada (economiza N requests para quem consome todos os portos).
  - Dados usados: list_all_harbors_by_state + get_tabua_mare_by_month_days por porto.

### 13.5 Endpoints de alerta (ideia para futuro — exige infra de scheduling)

> Estes não são puramente "dados já existentes" porque exigem um scheduler/webhook, mas a lógica de detecção usa só dados existentes. Listados como sugestão de evolução (fora do escopo "apenas dados").

- **POST /api/v2/premium/alerts** — cadastra webhook URL + harbor + nível crítico.
- Worker periódico avalia hour_data (do dia) e dispara POST ao webhook quando o nível cruza o threshold.
- Valor: logística portuária.

### 13.6 Sugestão de priorização

1. tide-extremes e tide-summary — alto valor, baixo esforço (agregação sobre hour_data).
2. safe-window — bom nicho (navegação).
3. history/:year — alto valor, mas depende de R5 (dados retroativos).
4. bulk-tabua — economia de requests para B2B.
5. export — fácil de fazer sobre o DTO existente.
6. harbors-within / coverage-map — reaproveita geohash já indexado.
