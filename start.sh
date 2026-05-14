#!/bin/bash
set -euo pipefail

API1_PORT="3330"
API2_PORT="3340"
NGINX_PORT="${PORT:-9090}"
DATA_DIR="${DATA_DIR:-/app/data}"
SQLITE_SOURCE="${SQLITE_SOURCE:-/app/taubinha.sqlite}"
DB_SQLITE_PATH="${DB_SQLITE_PATH:-${DATA_DIR}/taubinha.sqlite}"
SUPERVISOR_TEMPLATE="/app/dockerfiles/supervisord.single.conf"
SUPERVISOR_TARGET="/app/supervisor-conf/tabua-mare.conf"
NGINX_TEMPLATE="/app/dockerfiles/nginx.single.conf"
NGINX_TARGET="/app/nginx-conf/tabua-mare.conf"
SUPERVISORD_CONF="/app/supervisor-conf/supervisord.conf"

echo "[startup] API1_PORT=${API1_PORT}, API2_PORT=${NGINX_PORT}, NGINX_PORT=${NGINX_PORT}"

mkdir -p "${DATA_DIR}" /tmp/nginx/client_temp /tmp/nginx/client_body_temp /tmp/nginx/proxy_temp /tmp/nginx/fastcgi_temp /tmp/nginx/uwsgi_temp /tmp/nginx/scgi_temp /app/supervisor-conf /app/nginx-conf

if [ -d /var/log/nginx ]; then
  ln -sf /dev/stderr /var/log/nginx/error.log 2>/dev/null || true
  ln -sf /dev/stdout /var/log/nginx/access.log 2>/dev/null || true
fi

if [ ! -f "${DB_SQLITE_PATH}" ]; then
  echo "[startup] Copiando SQLite inicial para ${DB_SQLITE_PATH}"
  cp "${SQLITE_SOURCE}" "${DB_SQLITE_PATH}"
fi

export DB_SQLITE_PATH
export URL_ENV="${URL_ENV:-http://localhost:${NGINX_PORT}}"

cp "${SUPERVISOR_TEMPLATE}" "${SUPERVISOR_TARGET}"
sed "s/__PUBLIC_PORT__/${NGINX_PORT}/g" "${NGINX_TEMPLATE}" > "${NGINX_TARGET}"

cat > "${SUPERVISORD_CONF}" << 'SUPERVISORD_EOF'
[supervisord]
nodaemon=true
logfile=/dev/null
logfile_maxbytes=0
pidfile=/tmp/supervisord.pid

[include]
files = /app/supervisor-conf/tabua-mare.conf
SUPERVISORD_EOF

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
exec /usr/bin/supervisord -n -c /app/supervisor-conf/supervisord.conf
