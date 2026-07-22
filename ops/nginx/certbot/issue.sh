#!/bin/sh
# Emite (ou re-emite) o certificado Let's Encrypt para tabuamare.api.br
# usando DNS-01 via Cloudflare. Nao precisa expor 80 para ACME.
#
# Pre-requisitos:
#   - /root/.config/tabua-mare/cloudflare-token.ini com:
#       dns_cloudflare_api_token = TOKEN...
#   - Docker + Docker Compose instalados.
#
# Uso: ops/nginx/certbot/issue.sh [email]
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE="${ROOT_DIR}/ops/nginx/docker-compose.yml"
TOKEN_FILE="/root/.config/tabua-mare/cloudflare-token.ini"

[ -f "${TOKEN_FILE}" ] || {
    echo "ERRO: ${TOKEN_FILE} nao encontrado." >&2
    echo "Crie com:" >&2
    echo "  install -d -m 700 /root/.config/tabua-mare" >&2
    echo "  printf 'dns_cloudflare_api_token = SEU_TOKEN\\n' > ${TOKEN_FILE}" >&2
    echo "  chmod 600 ${TOKEN_FILE}" >&2
    exit 1
}

DOMAIN="tabuamare.api.br"
EMAIL="${1:-admin@tabuamare.api.br}"

# Plugin Cloudflare do certbot. Usa a imagem oficial com plugins.
CERTBOT_IMAGE="certbot/dns-cloudflare:latest"

echo "Emitindo certificado Let's Encrypt para ${DOMAIN} via DNS-01 Cloudflare"

docker run --rm \
    -v /etc/letsencrypt:/etc/letsencrypt \
    -v /var/www/certbot:/var/www/certbot \
    -v "${TOKEN_FILE}:/run/secrets/cloudflare-token.ini:ro" \
    "${CERTBOT_IMAGE}" certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /run/secrets/cloudflare-token.ini \
    --dns-cloudflare-propagation-seconds 30 \
    --non-interactive \
    --agree-tos \
    --email "${EMAIL}" \
    -d "${DOMAIN}" \
    -d "www.${DOMAIN}" \
    -d "coolify-admin.${DOMAIN}"

echo "Certificado emitido em /etc/letsencrypt/live/${DOMAIN}/"

# Sinaliza nginx para recarregar certificados. Esta emissao inicial roda no
# host, portanto o Docker CLI esta disponivel aqui.
docker kill -s HUP tabuamare-nginx 2>/dev/null || true
echo "Nginx recarregado (se estava rodando). Pronto."
