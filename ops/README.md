# Operacao da nova plataforma

## 1. Bootstrap da VPS

O script aceita somente Ubuntu 24.04 e instala atualizacoes, timezone `America/Sao_Paulo`, fail2ban, swap 2 GiB, `swappiness=10`, Docker/Coolify `4.1.2` e firewall da origem.

Use `ops/recover_vps.py` para uma VPS nova ou reconstruída. O wizard pede a chave SSH, caminhos dos backups, domínio e segredos sem gravá-los no Git, valida os arquivos locais e executa bootstrap/firewall. A importação do backup Coolify, env e SQLite continua com confirmação manual no painel/volumes, porque o formato e o destino dependem da instalação. `run_ssh.sh` é um atalho local ignorado pelo repositório.

Execução manual, se necessária:

```bash
tar -C ops -cf - bootstrap_vps.sh cloudflare-origin-firewall.sh \
  | ssh root@SEU_IP 'mkdir -p /root/tabuamare-ops && tar -C /root/tabuamare-ops -xf -'
ssh root@SEU_IP 'bash /root/tabuamare-ops/bootstrap_vps.sh'
```

O bootstrap fixa `AUTOUPDATE=false`. Atualizacoes futuras do Coolify ficam manuais.
O firewall entra antes de Docker/Coolify. No boot, restaura os ultimos ranges Cloudflare validos; sem cache, bloqueia 80/443 ate obter uma lista oficial valida. As portas 8000/6001/6002 permanecem acessiveis apenas via loopback/tunnel SSH.

## 2. Primeiro admin, sem expor porta 8000

```bash
ssh -N -L 8000:127.0.0.1:8000 root@SEU_IP
```

Abrir `http://localhost:8000` e criar imediatamente o primeiro admin. Nao criar conta no Let's Encrypt: o Nginx proprio (secao 5) registra e renova o certificado via DNS-01 Cloudflare.

## 3. Token Cloudflare e DNS-01

Criar token restrito a zona `tabuamare.api.br`:

- `Zone / DNS / Edit`;
- `Zone / Zone / Read`.

Na VPS, sem colocar o valor no repositorio:

```bash
install -d -m 700 /root/.config/tabua-mare
read -rsp 'CF_DNS_API_TOKEN: ' CF_DNS_API_TOKEN; echo
printf 'dns_cloudflare_api_token = %s\n' "$CF_DNS_API_TOKEN" \
  > /root/.config/tabua-mare/cloudflare-token.ini
chmod 600 /root/.config/tabua-mare/cloudflare-token.ini
unset CF_DNS_API_TOKEN
```

## 4. Aplicacoes A/B

Criar duas aplicacoes regulares baseadas em Docker Image:

- nomes `tabuamare-a` e `tabuamare-b`;
- imagem `ghcr.io/ddiidev/tabua-mare-api:sha-<commit>`;
- porta exposta `3330`, sem host mapping;
- health check `/health/ready`, intervalo 5s, timeout 2s;
- stop grace period `30s`; no Coolify `4.1.2` fixado, o default quando nao configurado usa `docker stop --time=30` em `app/Actions/Application/StopApplication.php`;
- limite `2` CPU, `512 MiB`; reserva `256 MiB`;
- volume exclusivo por app em `/app/data`.
- Network Alias na rede `coolify`: `tabuamare-app-a` para A e
  `tabuamare-app-b` para B. Configure em Advanced -> Network Alias e
  redeploy cada app antes de subir o Nginx.

Variaveis iguais nas duas apps: PostgreSQL, Google, `SESSION_SECRET`, Stripe e limites. Variaveis obrigatorias:

```text
URL_ENV=https://tabuamare.api.br
GOOGLE_REDIRECT_URI=https://tabuamare.api.br/auth/google/callback
DB_SQLITE_PATH=/app/data/taubinha.sqlite
```

Produção bloqueada com `sk_test_*`. Usar `sk_live_*`, prices live e webhook live em `https://tabuamare.api.br/auth/webhook`.

## 5. Nginx proprio (substitui Traefik na borda)

O Nginx proprio fica na borda da VPS, escutando 80/443 do host, e termina
TLS para todos os dominios: `tabuamare.api.br`, `www.tabuamare.api.br` e
`coolify-admin.tabuamare.api.br`. O `coolify-proxy` interno do Coolify deixa
de publicar 80/443 no host e fica acessivel somente pela rede Docker
`coolify:80`. O Nginx roteia `coolify-admin` para ele; o proxy continua
servindo o painel do Coolify (`coolify:8080`).

Por que substituir o Traefik na borda: o Traefik do Coolify nao tem
`proxy_next_upstream` (retry em falha de upstream), nao tem rate limit por
rota e o healthCheck ativo nao drena o server antes de devolver 503 ao
cliente. O Nginx faz retry automatico para o proximo upstream quando um
slot falha (timeout/502/503/504), eliminando o flap do 503 observado em
producao.

Provisionamento automatizado (faz tudo):

```bash
# Na VPS, com o repo clonado em /root/tabuamare-api (ou copie ops/nginx/):
export DEPLOY_SMOKE_SECRET='<seu secret do GitHub Actions, min 32 chars>'
export COOLIFY_APP_A_UUID='<uuid da app A>'
export COOLIFY_APP_B_UUID='<uuid da app B>'
bash ops/nginx/migrate-from-coolify.sh
```

O script:

1. Valida os aliases estaveis `tabuamare-app-a` e `tabuamare-app-b` nos
   containers correntes das apps A/B; sem alias, aborta antes de alterar a borda.
2. Valida que o `coolify-proxy` do Coolify NAO esta mais publicando 80/443 no host
   (se estiver, aborta com instrucoes de como remover via painel do
   Coolify: Servers -> localhost -> Proxy, remover portas 80/443 do host).
3. Renderiza `nginx.conf` somente com `DEPLOY_SMOKE_SECRET`; o vhost usa
   aliases fixos e DNS dinamico do Docker, nao nomes ou IPs efemeros de
   containers.
4. Valida a sintaxe da config do Nginx dentro de um container efemero na rede `coolify`.
5. Emite certificado Let's Encrypt via DNS-01 Cloudflare (se ainda nao
   existir em /etc/letsencrypt/live/tabuamare.api.br/).
6. Sobe Nginx + Certbot via docker compose up -d.
7. Aguarda o Nginx responder em https://tabuamare.api.br/health/ready.
8. Smoke por slot A e B via headers de deploy (bypassa o LB).

Apos o script, falta um passo manual no painel do Coolify: apagar os
routers/servicos do proxy para `tabuamare.api.br` e `www`
(`tabuamare-apex`, `tabuamare-www`, `tabuamare-ab`,
`tabuamare-deploy-slot-a/b`). Manter ou recriar um router simples para
`coolify-admin.tabuamare.api.br` apontando para `coolify:8080` (sem TLS,
HTTP plano -- o Nginx termina TLS na borda). O proprio script imprime
essas instrucoes no final.

Logs do Nginx:

```bash
ssh root@SEU_IP 'docker logs tabuamare-nginx --tail 100 -f'
```

O Nginx consulta o DNS embutido do Docker a cada poucos segundos. Assim, um
deploy/restart que troca o IP de A ou B nao exige reiniciar manualmente o Nginx.
O failover de conexao ao peer saudavel e limitado a 1 segundo.

Validacao real da Stripe dentro dos dois containers (testa rede, secret key e
os tres prices sem imprimir segredos):

```bash
COOLIFY_APP_A_UUID=... COOLIFY_APP_B_UUID=... \
  bash ops/check-stripe-production.sh
```

Diagnostico de flap por slot (bypass do LB):

```bash
curl -H 'X-Tabuamare-Deploy-Slot: A' -H "X-Tabuamare-Deploy-Secret: $DEPLOY_SMOKE_SECRET" \
  https://tabuamare.api.br/health/debug
curl -H 'X-Tabuamare-Deploy-Slot: B' -H "X-Tabuamare-Deploy-Secret: $DEPLOY_SMOKE_SECRET" \
  https://tabuamare.api.br/health/debug
# sem os dois headers corretos, /health/debug responde 404 e nao expoe estado.
```

Para reverter (voltar tudo para Traefik do Coolify):

```bash
ssh root@SEU_IP 'docker compose -f /root/tabuamare-ops/nginx/docker-compose.yml down'
# restaurar ports 80/443 no coolify-proxy e recriar routers no painel do Coolify
```

## 6. Cloudflare

- manter proxy laranja em `@`, `www` e `coolify-admin`;
- bypass de cache: `/api/*`, `/auth/*`, `/dashboard*`, `/health/*` e todo `coolify-admin`;
- cache somente para assets estaticos;
- confirmar que acesso direto ao IP em 80/443 falha e que 8000/6001/6002 nao abrem externamente.

## 7. GitHub e deploy

Secrets: `COOLIFY_TOKEN` e `DEPLOY_SMOKE_SECRET` (minimo 32 caracteres). Variables: `COOLIFY_URL`, `COOLIFY_APP_A_UUID`, `COOLIFY_APP_B_UUID`. Token Coolify somente com `read`, `write`, `deploy`.

No primeiro push, GitHub cria o pacote GHCR privado por padrao. Ir em `Ddiidev -> Packages -> tabua-mare-api -> Package settings -> Change visibility -> Public`. Essa mudanca e obrigatoria e irreversivel. Confirmar sem login:

```bash
docker logout ghcr.io
docker manifest inspect ghcr.io/ddiidev/tabua-mare-api:sha-<commit>
```

Tags `sha-*` existentes nunca sao sobrescritas; o CI falha se a tag ja existir.

O workflow `Deploy manual de producao A/B` recebe SHA completo. Atualiza A, smoke, B; falha restaura tags anteriores.

Antes de qualquer alteracao, o cliente valida as duas apps por `GET /api/v1/applications/{uuid}` e `GET /api/v1/applications/{uuid}/storages`. Campos oficiais usados: `ports_exposes`, `ports_mappings`, `health_check_enabled`, `health_check_path`, `health_check_port`, `limits_cpus`, `limits_memory`, `limits_memory_reservation`; storage usa `name`, `mount_path`, `host_path`. Invariantes exigidas:

- porta interna somente `3330`, sem `ports_mappings` para host;
- health check habilitado em `/health/ready` na porta `3330`;
- 2 CPU, 512 MiB de limite e 256 MiB de reserva;
- exatamente um storage em `/app/data`; identidade (`name` de volume ou `host_path`) diferente entre A/B;
- `custom_network_aliases` deve conter o alias estavel correspondente da app.

O deploy exige A e B inicialmente `running:healthy`. Deploy e rollback sao stop-first: antes de cada stop, consultam novamente o peer e exigem `running:healthy`; entao marcam o slot como tocado, chamam `POST /applications/{uuid}/stop`, aguardam o GET reportar `exited`/`stopped` e somente depois alteram tag e iniciam. No rollback B -> A, A so e parada depois que B foi restaurada e voltou a `running:healthy`. Se restaurar B falhar, A permanece saudavel na tag nova e o script reporta rollback incompleto. Antes do primeiro deploy, conferir manualmente na UI que stop grace esta vazio/default ou `30s`; nunca configurar abaixo de 30s. Referencia do default fixado: [StopApplication.php do Coolify](https://github.com/coollabsio/coolify/blob/4.1.2/app/Actions/Application/StopApplication.php).

O smoke publico envia o slot e `X-Tabuamare-Deploy-Secret`, sem registrar o segredo. O `map` no `ops/nginx/nginx.conf` exige ambos os headers para rotear ao upstream de slot; sem o secret correto a request cai no balanceador `tabuamare_ab`.

## 8. Endurecer SSH por ultimo

Abrir e manter uma segunda sessao funcionando por chave. So depois:

```bash
ssh root@SEU_IP \
  'CONFIRM_KEY_CONNECTION=yes bash /root/tabuamare-ops/bootstrap_vps.sh --harden-ssh'
```

Resultado: `PasswordAuthentication no` e `PermitRootLogin prohibit-password`.

## 9. Recovery bundle

Apos criar o admin, gerar o recovery/backup inicial do Coolify e guardar fora do repositorio e da VPS. Backup S3 e PostgreSQL externo continuam em ciclo separado.
