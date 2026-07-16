# Tábua de Marés – API Brasileira

![Logo Tábua de Marés](pages/assets/logo-tabua-mare.svg)

Uma API pública para consultar dados precisos de marés em todo o litoral brasileiro. Interface REST simples, sem necessidade de chave de API, com cobertura nacional e exemplos práticos.

- Site oficial: https://tabuamare.api.br/
- Documentação: `/docs`
- Playground: `/playground`
- Apoiar o projeto: `/apoiar`

## Recursos

- Dados precisos e atualizados de marés.
- Interface REST simples e fácil de integrar.
- Cobertura nacional (todos os estados costeiros do Brasil).
- Uso livre, sem autenticação.
- Banco SQLite atualizado do ano corrente, com dados reais utilizados em produção, disponível para utilização em seus próprios projetos.
- Consulta por geolocalização: obtenha a tábua de maré informando latitude, longitude e estado, sem precisar conhecer o porto.

## Base de API

- Prefixo V2 (Atual): `/api/v2`
- Prefixo V1 (Depreciado): `/api/v1`

## Mudanças na V2 (Versão Atual)

A versão 2 da API traz uma mudança importante na identificação dos portos:
- **IDs de Portos agora são strings baseadas no estado** (ex: `pb01`, `rj02`, `sp03`).
- Na V1, os IDs eram numéricos (ex: 1, 2, 3).
- Todos os endpoints da V1 estão disponíveis na V2, mas devem ser acessados com o prefixo `/api/v2` e utilizando os novos IDs de string.

## Como usar a API

Para saber como utilizar a API, incluindo todos os endpoints disponíveis e estrutura de resposta, acesse: **https://tabuamare.api.br/docs**

### Principais Endpoints (V2)

- `GET /api/v2/states`
  - Lista as siglas dos estados costeiros disponíveis.
  - Exemplo: `curl -X GET "http://localhost:3330/api/v2/states"`

- `GET /api/v2/harbor_names/{state}`
  - Lista os nomes dos portos de um estado.
  - Parâmetro `state`: sigla do estado em minúsculas (`pb`, `rj`, `sp`).
  - Exemplo: `curl -X GET "http://localhost:3330/api/v2/harbor_names/pb"`

- `GET /api/v2/harbors/{ids}`
  - Retorna dados de um ou mais portos por ID.
  - Parâmetro `ids`: lista de strings no formato `["pb01","pe02"]`.
  - Exemplo: `curl -X GET "http://localhost:3330/api/v2/harbors/['pb01']"`

- `GET /api/v2/tabua-mare/{harbor}/{month}/{days}`
  - Tábua de maré para um porto específico.
  - Parâmetros: `harbor` (ID String ex: `pb01`), `month` (`1-12`), `days` (ex.: `[1,2,10-30]`).
  - Exemplo: `curl -X GET "http://localhost:3330/api/v2/tabua-mare/pb01/1/[1,2,3]"`

- `GET /api/v2/nearested-harbor/{state}/{lat_lng}`
  - Porto mais próximo dentro do estado informado.
  - Parâmetros: `state` (sigla minúscula), `lat_lng` como string no formato `[lat,lng]`.
  - Exemplo: `curl -X GET "http://localhost:3330/api/v2/nearested-harbor/pb/[-7.11509,-34.864]"`

- `GET /api/v2/nearest-harbor-independent-state/{lat_lng}`
  - Porto mais próximo sem limitar por estado.
  - Parâmetros: `lat_lng` como string no formato `[lat,lng]`.
  - Exemplo: `curl -X GET "http://localhost:3330/api/v2/nearest-harbor-independent-state/[-7.11509,-34.864]"`

### Obter tábua de maré por geolocalização

Agora é possível consultar a tábua de maré sem saber o porto, informando apenas as coordenadas geográficas (latitude e longitude) e a sigla do estado. A API identifica o porto mais próximo dentro do estado e retorna a tábua de maré para o período solicitado.

- Endpoint: `GET /api/v2/geo-tabua-mare/{lat_lng}/{state}/{month}/{days}`
- Parâmetros:
  - `lat_lng`: string no formato `[lat,lng]` (ex.: `[-7.11509,-34.864]`)
  - `state`: sigla do estado em minúsculas (ex.: `pb`, `rj`, `sp`)
  - `month`: mês desejado (`1-12`)
  - `days`: dias no formato de array, podendo combinar dias específicos e intervalos (ex.: `[1,2,10-30]`)

Exemplo de requisição:

```
curl -X GET "http://localhost:3330/api/v2/geo-tabua-mare/[-7.11509,-34.864]/pb/1/[1,2,3]"
```

Observações:
- O cálculo do porto é feito com base na menor distância às coordenadas fornecidas, respeitando o estado informado.
- O formato de `days` aceita combinações como `[1,5-13,27]`.

## Limites e uso

- Sem api_key (anônimo por IP): 16 req/min, ilimitado/mês.
- Free com api_key: 64 req/min, 32k req/mês.
- Plan 5 (R$ 5/mês, api_key): 512 req/min, 256k req/mês.
- Plan 10 (R$ 10/mês, api_key): 2.048 req/min, ilimitado/mês.
- Plan Anual (R$ 70/ano, api_key): 4.096 req/min, ilimitado/mês.

## Executando localmente

### Pré-requisitos

- **V Language**: Instale seguindo as instruções em https://github.com/vlang/v#installing-v-from-source
- **PostgreSQL**: Banco de dados necessário para armazenar os dados de marés. (Como instalar https://modules.vlang.io/db.pg.html)
- **Arquivo .env**: Configure as variáveis de ambiente (veja seção abaixo)

> **Observação**: O projeto utiliza PostgreSQL em produção, mas ofereço um banco SQLite com dados atualizados do ano corrente. O banco de dados está disponível para facilitar testes locais e desenvolvimento.

### Configuração do ambiente

1. Copie o arquivo `.env.template` para `.env`:

```bash
cp .env.template .env
```

2. Configure as seguintes variáveis no arquivo `.env`:

```
DB_SQLITE_PATH=./taubinha.sqlite
POSTGRESQL_CONN_STR=postgresql://usuario:senha@localhost:5432/tabuamare
GOOGLE_REDIRECT_URI=http://localhost:3330/auth/google/callback
URL_ENV=http://localhost:3330
```

### Desenvolvimento

Execute com V informando a porta:

```
v run . 3330
```

A aplicação iniciará e servirá:

- API em `http://localhost:3330/api/v2`
- Páginas: `http://localhost:3330/`, `/docs`, `/playground`, `/apoiar`

### Imagem de produção Alpine

1. Construa a imagem usando o `Dockerfile` na raiz:

```bash
docker build --platform linux/amd64 -t tabua-mare-api:local .
```

2. Suba uma instância com volume SQLite próprio:

```bash
docker run --rm -p 3330:3330 \
  --env-file .env \
  -v tabuamare-sqlite:/app/data \
  tabua-mare-api:local
```

- Alpine 3.22, `linux/amd64`, processo V como UID `10001`.
- Uma instância por container, porta interna `3330`.
- O seed SQLite é validado e atualizado atomicamente em `/app/data/taubinha.sqlite`.
- Health checks: `/health/live` e `/health/ready`.

### Produção Coolify

Produção usa duas aplicações regulares Coolify baseadas na mesma imagem GHCR imutável, atrás de Cloudflare e Traefik. Não usa nginx, Cloudflare Tunnel, Swarm ou Compose de produção.

Setup, firewall, DNS-01, volumes, A/B e deploy: [ops/README.md](ops/README.md).

## Apoie o projeto

Você pode apoiar este projeto de várias formas:

- **Financeiramente**: Acesse https://tabuamare.api.br/apoiar para contribuir e ajudar a pagar uma VPS melhor
- **Desenvolvimento**: Crie issues, pull requests ou contribua com código
- **Divulgação**: Compartilhe o projeto com outros desenvolvedores

## Contribuindo

- Issues e pull requests são bem-vindos.
- Mantenha o estilo do código e a organização existente.

## Licença

Este projeto está licenciado sob a MIT License. Consulte o arquivo `LICENSE` para os termos completos.
