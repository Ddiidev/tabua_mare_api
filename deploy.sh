#!/bin/bash
set -e

# Build nova imagem
docker compose build

# Verificar se nginx e cloudflared já estão rodando
NGINX_RUNNING=$(docker inspect --format='{{.State.Running}}' tabua-mare-nginx 2>/dev/null || echo "false")

if [ "$NGINX_RUNNING" != "true" ]; then
    echo "Primeiro deploy detectado. Subindo todos os servicos..."
    docker compose up -d
    echo "Aguardando todos os containers ficarem healthy..."
    for service in tabua-mare-app1 tabua-mare-app2 tabua-mare-app3 tabua-mare-app4; do
      until [ "$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null)" = "healthy" ]; do
        sleep 2
      done
      echo "$service healthy!"
    done
    echo "Deploy concluido!"
    exit 0
fi

# Rolling deploy: nginx e cloudflared continuam rodando

# Primeira onda: restart containers 1 e 2
echo "Atualizando containers 1 e 2..."
docker compose up -d --no-deps --build tabua-mare1 tabua-mare2

# Aguarda ficarem healthy
echo "Aguardando containers 1 e 2 ficarem healthy..."
for service in tabua-mare-app1 tabua-mare-app2; do
  until [ "$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null)" = "healthy" ]; do
    sleep 2
  done
  echo "$service healthy!"
done

echo "Containers 1 e 2 healthy. Atualizando 3 e 4..."

# Segunda onda: restart containers 3 e 4
docker compose up -d --no-deps --build tabua-mare3 tabua-mare4

# Aguarda ficarem healthy
echo "Aguardando containers 3 e 4 ficarem healthy..."
for service in tabua-mare-app3 tabua-mare-app4; do
  until [ "$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null)" = "healthy" ]; do
    sleep 2
  done
  echo "$service healthy!"
done

# Atualizar nginx e cloudflared (sem derrubar - apenas aplica config se mudou)
docker compose up -d --no-deps nginx cloudflared

echo "Deploy concluido!"
