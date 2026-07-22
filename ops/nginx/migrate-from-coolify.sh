#!/usr/bin/env bash
# Migra o fluxo publico de tabuamare.api.br do proxy do Coolify para um
# Nginx proprio. As apps A/B continuam sendo aplicacoes regulares do Coolify.
#
#   1. Valida os aliases de rede estaveis das apps A/B.
#   2. Renderiza nginx.conf com __DEPLOY_SMOKE_SECRET__.
#   3. Emite certificado Let's Encrypt via DNS-01 Cloudflare.
#   4. Sobe Nginx + Certbot (docker compose up -d).
#   5. Valida que o Nginx responde e que os dois slots passam no smoke.
#   6. Nao remove rotas do proxy do Coolify automaticamente.
#
# Pre-requisitos na VPS:
#   - /root/.config/tabua-mare/cloudflare-token.ini com:
#       dns_cloudflare_api_token = TOKEN...
#   - DEPLOY_SMOKE_SECRET exportado (igual ao secret do GitHub Actions).
#   - Docker + Docker Compose instalados.
#   - Apps A e B rodando no Coolify com Network Alias configurado:
#       tabuamare-app-a e tabuamare-app-b
#
# Uso:
#   DEPLOY_SMOKE_SECRET=... bash ops/nginx/migrate-from-coolify.sh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "${script_dir}/nginx.conf" ]]; then
	nginx_dir="${script_dir}"
else
	nginx_dir="$(cd "${script_dir}/../.." && pwd)/ops/nginx"
fi
token_file="/root/.config/tabua-mare/cloudflare-token.ini"
remote_dir="/root/tabuamare-ops/nginx"
app_alias_a="${COOLIFY_APP_A_ALIAS:-tabuamare-app-a}"
app_alias_b="${COOLIFY_APP_B_ALIAS:-tabuamare-app-b}"

log() { printf '[migrate] %s\n' "$*"; }
fail() { printf '[migrate] ERRO: %s\n' "$*" >&2; exit 1; }

[[ -f "${nginx_dir}/nginx.conf" ]] || fail "nao encontrei nginx.conf em ${nginx_dir}"
[[ -f "${nginx_dir}/conf.d/tabuamare.conf" ]] || fail "nao encontrei vhost do Nginx em ${nginx_dir}"
[[ -f "${token_file}" ]] || fail "${token_file} nao encontrado. Crie com:
  install -d -m 700 /root/.config/tabua-mare
  printf 'dns_cloudflare_api_token = TOKEN\n' > ${token_file}
  chmod 600 ${token_file}"

[[ -n "${DEPLOY_SMOKE_SECRET:-}" ]] || \
	fail 'DEPLOY_SMOKE_SECRET nao definido. Exporte com o mesmo valor do secret do GitHub Actions.'
[[ "${#DEPLOY_SMOKE_SECRET}" -ge 32 ]] || \
	fail 'DEPLOY_SMOKE_SECRET deve ter no minimo 32 caracteres'
[[ "${DEPLOY_SMOKE_SECRET}" =~ ^[A-Za-z0-9._-]+$ ]] || \
	fail 'DEPLOY_SMOKE_SECRET deve usar somente A-Z, a-z, 0-9, ponto, underscore ou hifen'

command -v docker >/dev/null 2>&1 || fail 'docker nao encontrado'
docker compose version >/dev/null 2>&1 || fail 'docker compose nao encontrado'
command -v curl >/dev/null 2>&1 || fail 'curl nao encontrado'

log 'Sanity check: coolify-admin.tabuamare.api.br respondendo...'
admin_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 \
	'https://coolify-admin.tabuamare.api.br/' 2>/dev/null || true)"
[[ "${admin_code}" != "000" ]] || \
	fail 'coolify-admin.tabuamare.api.br nao responde. Verifique o coolify-proxy antes de migrar.'
log "  coolify-admin respondeu ${admin_code} (ok, nao precisa ser 200)"

if [[ -z "${COOLIFY_APP_A_UUID:-}" ]]; then
	read -rp 'COOLIFY_APP_A_UUID: ' COOLIFY_APP_A_UUID
fi
if [[ -z "${COOLIFY_APP_B_UUID:-}" ]]; then
	read -rp 'COOLIFY_APP_B_UUID: ' COOLIFY_APP_B_UUID
fi
[[ -n "${COOLIFY_APP_A_UUID}" && -n "${COOLIFY_APP_B_UUID}" ]] || \
	fail 'UUIDs das apps A/B obrigatorios'
[[ "${COOLIFY_APP_A_UUID}" != "${COOLIFY_APP_B_UUID}" ]] || \
	fail 'UUIDs A e B devem ser diferentes'

assert_network_alias() {
	local uuid="$1"
	local alias="$2"
	local slot="$3"
	local container
	# Coolify 4.1.2 usa coolify.applicationId para o ID numerico interno
	# (por exemplo 1/2). O UUID publico da API fica em coolify.name e tambem
	# identifica o projeto gerado pelo Docker Compose.
	container="$(docker ps \
		--filter 'label=coolify.type=application' \
		--filter "label=coolify.name=${uuid}" \
		--format '{{.Names}}' | head -n1 || true)"
	if [[ -z "${container}" ]]; then
		container="$(docker ps \
			--filter "label=com.docker.compose.project=${uuid}" \
			--format '{{.Names}}' | head -n1 || true)"
	fi
	[[ -n "${container}" ]] || \
		fail "nenhum container running encontrado para app ${slot} (${uuid})"

	if ! docker inspect --format '{{range $network, $data := .NetworkSettings.Networks}}{{if eq $network "coolify"}}{{range $data.Aliases}}{{println .}}{{end}}{{end}}{{end}}' "${container}" \
		| grep -Fxq "${alias}"; then
		fail "app ${slot} precisa do Network Alias ${alias}; configure-o no Coolify e redeploy antes de continuar"
	fi
	log "  app ${slot}: alias ${alias} confirmado (${container})"
}

log 'Validando aliases estaveis das apps A e B...'
assert_network_alias "${COOLIFY_APP_A_UUID}" "${app_alias_a}" A
assert_network_alias "${COOLIFY_APP_B_UUID}" "${app_alias_b}" B

docker network inspect tabuamare-nginx >/dev/null 2>&1 || {
	log 'Criando rede tabuamare-nginx...'
	docker network create tabuamare-nginx
}
docker network inspect coolify >/dev/null 2>&1 || \
	fail 'rede coolify nao existe. Coolify esta instalado?'

docker inspect coolify-proxy >/dev/null 2>&1 || fail 'container coolify-proxy nao encontrado'
published_proxy_ports=''
for container_port in 80/tcp 443/tcp; do
	mappings="$(docker port coolify-proxy "${container_port}" 2>/dev/null || true)"
	if [[ -n "${mappings}" ]]; then
		published_proxy_ports+="${container_port}: ${mappings}"$'\n'
	fi
done
if [[ -n "${published_proxy_ports}" ]]; then
	fail "O coolify-proxy ainda publica 80/443 no host:
${published_proxy_ports}

Remova as portas publicadas no painel do Coolify:
  Servers -> localhost -> Proxy -> editar coolify-proxy
Deixe o proxy acessivel somente pela rede interna e rode este script novamente."
fi

log 'Renderizando configuracao do Nginx...'
render_dir="$(mktemp -d)"
trap 'rm -rf "${render_dir}"' EXIT
mkdir -p "${render_dir}/conf.d" "${render_dir}/certbot"
sed -e "s|__DEPLOY_SMOKE_SECRET__|${DEPLOY_SMOKE_SECRET}|g" \
	"${nginx_dir}/nginx.conf" >"${render_dir}/nginx.conf"
cp "${nginx_dir}/conf.d/tabuamare.conf" "${render_dir}/conf.d/tabuamare.conf"
cp "${nginx_dir}/docker-compose.yml" "${render_dir}/docker-compose.yml"
cp "${nginx_dir}/certbot/issue.sh" "${render_dir}/certbot/issue.sh"
chmod +x "${render_dir}/certbot/issue.sh"

cert_dir="/etc/letsencrypt/live/tabuamare.api.br"
if [[ -d "${cert_dir}" ]]; then
	log "Certificado ja existe em ${cert_dir}, pulando emissao."
else
	log "Emitindo certificado Let's Encrypt (DNS-01 Cloudflare)..."
	bash "${render_dir}/certbot/issue.sh" admin@tabuamare.api.br
fi

log 'Validando sintaxe da config do Nginx...'
docker run --rm \
	--network coolify \
	-v "${render_dir}/nginx.conf:/etc/nginx/nginx.conf:ro" \
	-v "${render_dir}/conf.d:/etc/nginx/conf.d:ro" \
	-v /etc/letsencrypt:/etc/letsencrypt:ro \
	nginx:1.30.4-alpine nginx -t

log 'Instalando config em /root/tabuamare-ops/nginx/...'
mkdir -p "${remote_dir}/conf.d" "${remote_dir}/certbot"
cp "${render_dir}/nginx.conf" "${remote_dir}/nginx.conf"
cp "${render_dir}/conf.d/tabuamare.conf" "${remote_dir}/conf.d/tabuamare.conf"
cp "${render_dir}/docker-compose.yml" "${remote_dir}/docker-compose.yml"
cp "${render_dir}/certbot/issue.sh" "${remote_dir}/certbot/issue.sh"
chmod +x "${remote_dir}/certbot/issue.sh"

mkdir -p /var/log/nginx /var/www/certbot

log 'Subindo Nginx + Certbot via docker compose...'
docker compose -f "${remote_dir}/docker-compose.yml" up -d

log 'Aguardando Nginx responder em https://tabuamare.api.br/health/ready...'
deadline=$(( $(date +%s) + 30 ))
ok=false
while (( $(date +%s) <= deadline )); do
	code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
		'https://tabuamare.api.br/health/ready' 2>/dev/null || true)"
	if [[ "${code}" == "204" || "${code}" == "200" ]]; then
		ok=true
		break
	fi
	sleep 2
done
[[ "${ok}" == true ]] || fail 'Nginx subiu mas /health/ready nao respondeu em 30s.'
log 'Nginx respondendo em https://tabuamare.api.br/health/ready'

log 'Smoke por slot...'
for slot in A B; do
	code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
		-H "X-Tabuamare-Deploy-Slot: ${slot}" \
		-H "X-Tabuamare-Deploy-Secret: ${DEPLOY_SMOKE_SECRET}" \
		'https://tabuamare.api.br/health/debug' 2>/dev/null || true)"
	log "  slot ${slot}: /health/debug -> ${code}"
	[[ "${code}" == "200" ]] || fail "smoke do slot ${slot} falhou com HTTP ${code}"
done

cat <<INSTRUCTIONS

==============================================================================
MIGRACAO CONCLUIDA. REVISE OS ROUTERS ANTIGOS NO COOLIFY.
==============================================================================

O Nginx responde por tabuamare.api.br, www e coolify-admin em 80/443.
O coolify-proxy deve permanecer somente na rede interna; o Nginx roteia
coolify-admin para coolify-proxy:80.

No painel do Coolify:

  1. Confirme que o coolify-proxy nao publica 80/443 no host.

  2. Apague os routers/servicos antigos do proxy para tabuamare.api.br e www:
     - tabuamare-apex
     - tabuamare-www
     - tabuamare-ab
     - tabuamare-deploy-slot-a
     - tabuamare-deploy-slot-b

  3. MANTENHA o router coolify-admin, sem TLS no proxy interno.
     O Nginx termina TLS e repassa HTTP para coolify:8080.

Apos salvar, aguarde o proxy recarregar. Teste:

  curl -I https://tabuamare.api.br/health/ready
  curl -I https://coolify-admin.tabuamare.api.br/

Logs do Nginx:
  docker logs tabuamare-nginx --tail 100 -f

Para reverter:
  docker compose -f /root/tabuamare-ops/nginx/docker-compose.yml down
  # restaurar ports 80/443 no coolify-proxy e recriar routers no painel
==============================================================================
INSTRUCTIONS
