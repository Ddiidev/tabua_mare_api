#!/bin/bash
set -euo pipefail

# Configurações e defaults
PORT="${PORT:-8080}"
API1_PORT="${API1_PORT:-4048}"
API2_PORT="${API2_PORT:-4049}"
NGINX_CONF="/etc/nginx/conf.d/maisfoco.conf"

echo "[startup] PORT=${PORT}, API1_PORT=${API1_PORT}, API2_PORT=${API2_PORT}"

# Ajustar a porta de escuta do Nginx: garantir listen 80; e adicionar listen $PORT se necessário
if [ -f "$NGINX_CONF" ]; then
  # Garantir que exista 'listen 80;'
  if ! grep -qE 'listen\s+80;' "$NGINX_CONF"; then
    sed -ri 's/(server\s*\{)/\1\n    listen 80;/' "$NGINX_CONF"
  fi
  # Adicionar também 'listen ${PORT};' se for diferente de 80 e ainda não existir
  if [ "$PORT" != "80" ] && ! grep -qE "listen\s+${PORT};" "$NGINX_CONF"; then
    sed -ri "s/(server\\s*\\{)/\\1\\n    listen ${PORT};/" "$NGINX_CONF"
  fi
fi

# Iniciar as instâncias da aplicação (em background)
echo "[startup] Iniciando TabuaMareAPI nas portas ${API1_PORT} e ${API2_PORT}"
./TabuaMareAPI "${API1_PORT}" &
API1_PID=$!
./TabuaMareAPI "${API2_PORT}" &
API2_PID=$!

# Iniciar Cloudflare Tunnel (opcional) se token estiver disponível
if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
  echo "[startup] Iniciando Cloudflare Tunnel"
  cloudflared --no-autoupdate tunnel run --token "${CLOUDFLARE_TUNNEL_TOKEN}" &
  CF_PID=$!
else
  echo "[startup] CLOUDFLARE_TUNNEL_TOKEN não definido; o tunnel não será iniciado."
fi

# Preparar diretórios do Nginx e validar configuração
mkdir -p /var/run/nginx
nginx -t

echo "[startup] Iniciando Nginx escutando em 80 e (se aplicável) em ${PORT}"
# Executa o Nginx em foreground como PID 1
exec nginx -g 'daemon off;'