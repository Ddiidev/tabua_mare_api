#!/bin/bash
set -euo pipefail

API1_PORT="3330"
API2_PORT="3340"
NGINX_PORT="9090"
DATA_DIR="${DATA_DIR:-/app/data}"
SQLITE_SOURCE="${SQLITE_SOURCE:-/app/taubinha.sqlite}"
DB_SQLITE_PATH="${DB_SQLITE_PATH:-${DATA_DIR}/taubinha.sqlite}"
SUPERVISOR_TEMPLATE="/app/dockerfiles/supervisord.single.conf"
SUPERVISOR_TARGET="/etc/supervisor/conf.d/tabua-mare.conf"

echo "[startup] API1_PORT=${API1_PORT}, API2_PORT=${API2_PORT}, NGINX_PORT=${NGINX_PORT}"

mkdir -p "${DATA_DIR}" /var/run/nginx /var/log/nginx /etc/supervisor/conf.d

if [ ! -f "${DB_SQLITE_PATH}" ]; then
  echo "[startup] Copiando SQLite inicial para ${DB_SQLITE_PATH}"
  cp "${SQLITE_SOURCE}" "${DB_SQLITE_PATH}"
fi

export DB_SQLITE_PATH
export URL_ENV="${URL_ENV:-http://localhost:${NGINX_PORT}}"

cp "${SUPERVISOR_TEMPLATE}" "${SUPERVISOR_TARGET}"

if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  cat <<EOF >> "${SUPERVISOR_TARGET}"

[program:cloudflared]
command=/usr/bin/cloudflared --no-autoupdate tunnel run --token ${CLOUDFLARE_TUNNEL_TOKEN}
autostart=true
autorestart=true
startsecs=3
priority=40
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF
  echo "[startup] Cloudflare Tunnel habilitado"
else
  echo "[startup] CLOUDFLARE_TUNNEL_TOKEN não definido; o tunnel não será iniciado."
fi

nginx -t

echo "[startup] Iniciando supervisord"
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
