# Tábua de Marés – API Brasileira

![Logo Tábua de Marés](pages/assets/logo-tabua-mare.svg)

Uma API pública para consultar dados precisos de marés em todo o litoral brasileiro. Interface REST simples, sem necessidade de chave de API, com cobertura nacional e exemplos práticos.

- Site oficial: https://tabuamare.devtu.qzz.io/
- Documentação: `/docs`
- Playground: `/playground`
- Apoiar o projeto: `/apoiar`

## Recursos

- Dados precisos e atualizados de marés.
- Interface REST simples e fácil de integrar.
- Cobertura nacional (todos os estados costeiros do Brasil).
- Uso livre, sem autenticação.
- Banco SQLite atualizado do ano corrente, com dados reais utilizados em produção, disponível para utilização em seus próprios projetos.

## Base de API

- Prefixo: `/api/v1`

## Como usar a API

Para saber como utilizar a API, incluindo todos os endpoints disponíveis e estrutura de resposta, acesse: **https://tabuamare.devtu.qzz.io/docs**

## Limites e uso

- Uso livre: não é necessária chave de API.
- Limite: 500 requisições por minuto por IP.

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
DB_DATABASE=nome_do_banco
DB_USER=usuario_do_banco
DB_HOST=localhost
DB_PASS=senha_do_banco
DB_PORT=5432
NEW_RELIC_KEY=CHAVE
URL_ENV=http://localhost:3330
```

### Desenvolvimento

Execute com V informando a porta:

```
v run . 3330
```

A aplicação iniciará e servirá:

- API em `http://localhost:3330/api/v1`
- Páginas: `http://localhost:3330/`, `/docs`, `/playground`, `/apoiar`

### Produção (Docker Compose)

1. Copie o arquivo `.env.template` para `.env` e ajuste variáveis conforme necessário.
2. Construa e suba os serviços:

```
docker compose up -d --build
```

- Nginx é configurado automaticamente a partir de `nginx/`.
- Variável `PORT` controla a porta externa (padrão `8080`).
- Opcional: `CLOUDFLARE_TUNNEL_TOKEN` para habilitar Cloudflare Tunnel.

## Apoie o projeto

Você pode apoiar este projeto de várias formas:

- **Financeiramente**: Acesse https://tabuamare.devtu.qzz.io/apoiar para contribuir e ajudar a pagar uma VPS melhor
- **Desenvolvimento**: Crie issues, pull requests ou contribua com código
- **Divulgação**: Compartilhe o projeto com outros desenvolvedores

## Contribuindo

- Issues e pull requests são bem-vindos.
- Mantenha o estilo do código e a organização existente.

## Licença

Este projeto está licenciado sob a MIT License. Consulte o arquivo `LICENSE` para os termos completos.
