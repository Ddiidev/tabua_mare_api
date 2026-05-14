#!/bin/bash
set -euo pipefail

API1_PORT="3330"
API2_PORT="3340"
NGINX_PORT="${PORT:-9090}"
DATA_DIR="${DATA_DIR:-/app/data}"
SQLITE_SOURCE="${SQLITE_SOURCE:-/app/taubinha.sqlite}"
DB_SQLITE_PATH="${DB_SQLITE_PATH:-${DATA_DIR}/taubinha.sqlite}"
RUNTIME_DIR="/tmp/tabua-mare"
NGINX_TEMP_DIR="/tmp/nginx"
SUPERVISOR_TEMPLATE="/app/dockerfiles/supervisord.single.conf"
SUPERVISOR_CONF_DIR="${RUNTIME_DIR}/supervisor-conf"
SUPERVISOR_TARGET="${SUPERVISOR_CONF_DIR}/tabua-mare.conf"
NGINX_TEMPLATE="/app/dockerfiles/nginx.single.conf"
NGINX_CONF_DIR="${RUNTIME_DIR}/nginx-conf"
NGINX_TARGET="${NGINX_CONF_DIR}/tabua-mare.conf"
SUPERVISORD_CONF="${SUPERVISOR_CONF_DIR}/supervisord.conf"

echo "[startup] API1_PORT=${API1_PORT}, API2_PORT=${API2_PORT}, NGINX_PORT=${NGINX_PORT}"

mkdir -p \
  "${DATA_DIR}" \
  "${SUPERVISOR_CONF_DIR}" \
  "${NGINX_CONF_DIR}" \
  "${NGINX_TEMP_DIR}/client_body_temp" \
  "${NGINX_TEMP_DIR}/proxy_temp" \
  "${NGINX_TEMP_DIR}/fastcgi_temp" \
  "${NGINX_TEMP_DIR}/uwsgi_temp" \
  "${NGINX_TEMP_DIR}/scgi_temp"

if [ ! -f "${DB_SQLITE_PATH}" ]; then
  echo "[startup] Copiando SQLite inicial para ${DB_SQLITE_PATH}"
  cp "${SQLITE_SOURCE}" "${DB_SQLITE_PATH}"
fi

export DB_SQLITE_PATH
export URL_ENV="${URL_ENV:-http://localhost:${NGINX_PORT}}"

cp "${SUPERVISOR_TEMPLATE}" "${SUPERVISOR_TARGET}"
sed "s/__PUBLIC_PORT__/${NGINX_PORT}/g" "${NGINX_TEMPLATE}" > "${NGINX_TARGET}"

cat > "${SUPERVISORD_CONF}" << EOF
[supervisord]
nodaemon=true
logfile=/dev/null
logfile_maxbytes=0
pidfile=/tmp/supervisord.pid
childlogdir=/tmp

[include]
files = ${SUPERVISOR_TARGET}
EOF

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
exec /usr/bin/supervisord -n -c "${SUPERVISORD_CONF}"
