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

Abrir `http://localhost:8000` e criar imediatamente o primeiro admin. Nao criar conta no Let's Encrypt: o Traefik registra e renova o certificado automaticamente.

## 3. Token Cloudflare e DNS-01

Criar token restrito a zona `tabuamare.api.br`:

- `Zone / DNS / Edit`;
- `Zone / Zone / Read`.

Na VPS, sem colocar o valor no repositorio:

```bash
install -d -m 700 /root/.config/tabua-mare
read -rsp 'CF_DNS_API_TOKEN: ' CF_DNS_API_TOKEN; echo
printf 'CF_DNS_API_TOKEN=%q\n' "$CF_DNS_API_TOKEN" \
  > /root/.config/tabua-mare/cloudflare.env
chmod 600 /root/.config/tabua-mare/cloudflare.env
unset CF_DNS_API_TOKEN
```

Em `Servers -> localhost -> Proxy`, manter a configuracao Traefik da versao instalada e alterar:

```yaml
services:
  traefik:
    env_file:
      - /root/.config/tabua-mare/cloudflare.env
    command:
      - --certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare
      - --certificatesresolvers.letsencrypt.acme.dnschallenge.delaybeforecheck=30
      - --certificatesresolvers.letsencrypt.acme.storage=/traefik/acme.json
```

Remover as duas flags `httpchallenge`. Reiniciar o proxy. Cloudflare deve ficar `Full (strict)`; `526` so e aceitavel antes da primeira emissao.

## 4. Aplicacoes A/B

Criar duas aplicacoes regulares baseadas em Docker Image:

- nomes `tabuamare-a` e `tabuamare-b`;
- imagem `ghcr.io/ddiidev/tabua-mare-api:sha-<commit>`;
- porta exposta `3330`, sem host mapping;
- health check `/health/ready`, intervalo 5s, timeout 2s;
- stop grace period `30s`; no Coolify `4.1.2` fixado, o default quando nao configurado usa `docker stop --time=30` em `app/Actions/Application/StopApplication.php`;
- limite `2` CPU, `512 MiB`; reserva `256 MiB`;
- volume exclusivo por app em `/app/data`.

Variaveis iguais nas duas apps: PostgreSQL, Google, `SESSION_SECRET`, Stripe e limites. Variaveis obrigatorias:

```text
URL_ENV=https://tabuamare.api.br
GOOGLE_REDIRECT_URI=https://tabuamare.api.br/auth/google/callback
DB_SQLITE_PATH=/app/data/taubinha.sqlite
```

Produção bloqueada com `sk_test_*`. Usar `sk_live_*`, prices live e webhook live em `https://tabuamare.api.br/auth/webhook`.

## 5. Traefik dinamico

Copiar `ops/traefik/dynamic/tabuamare.yaml` para `/data/coolify/proxy/dynamic/tabuamare.yaml`. Antes, substituir:

- `__APP_A_CONTAINER__`: nome consistente/UUID do container A;
- `__APP_B_CONTAINER__`: nome consistente/UUID do container B.
- `__DEPLOY_SMOKE_SECRET__`: segredo aleatorio de no minimo 32 caracteres, igual ao secret GitHub `DEPLOY_SMOKE_SECRET`.

Gerar o valor fora de logs de CI:

```bash
openssl rand -hex 32
```

O arquivo cria apex, redirect `www -> apex`, painel admin e balanceamento A/B com health check.

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
- exatamente um storage em `/app/data`; identidade (`name` de volume ou `host_path`) diferente entre A/B.

O deploy exige A e B inicialmente `running:healthy`. Deploy e rollback sao stop-first: antes de cada stop, consultam novamente o peer e exigem `running:healthy`; entao marcam o slot como tocado, chamam `POST /applications/{uuid}/stop`, aguardam o GET reportar `exited`/`stopped` e somente depois alteram tag e iniciam. No rollback B -> A, A so e parada depois que B foi restaurada e voltou a `running:healthy`. Se restaurar B falhar, A permanece saudavel na tag nova e o script reporta rollback incompleto. Antes do primeiro deploy, conferir manualmente na UI que stop grace esta vazio/default ou `30s`; nunca configurar abaixo de 30s. Referencia do default fixado: [StopApplication.php do Coolify](https://github.com/coollabsio/coolify/blob/4.1.2/app/Actions/Application/StopApplication.php).

O smoke publico envia o slot e `X-Tabuamare-Deploy-Secret`, sem registrar o segredo. Routers Traefik de prioridade 100 exigem ambos os headers; requisicoes normais continuam no balanceador `tabuamare-ab`.

## 8. Endurecer SSH por ultimo

Abrir e manter uma segunda sessao funcionando por chave. So depois:

```bash
ssh root@SEU_IP \
  'CONFIRM_KEY_CONNECTION=yes bash /root/tabuamare-ops/bootstrap_vps.sh --harden-ssh'
```

Resultado: `PasswordAuthentication no` e `PermitRootLogin prohibit-password`.

## 9. Recovery bundle

Apos criar o admin, gerar o recovery/backup inicial do Coolify e guardar fora do repositorio e da VPS. Backup S3 e PostgreSQL externo continuam em ciclo separado.
