#!/bin/bash
set -e

# Funcao para aguardar um servico ficar healthy usando docker compose
wait_healthy() {
  local service=$1
  local container_id
  container_id=$(docker compose ps -q "$service" 2>/dev/null)
  if [ -z "$container_id" ]; then
    echo "ERRO: container do servico $service nao encontrado!"
    return 1
  fi
  until [ "$(docker inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null)" = "healthy" ]; do
    sleep 2
  done
  echo "$service healthy!"
}

# Build nova imagem
docker compose build

# Verificar se nginx já esta rodando
NGINX_ID=$(docker compose ps -q nginx 2>/dev/null)
NGINX_RUNNING="false"
if [ -n "$NGINX_ID" ]; then
  NGINX_RUNNING=$(docker inspect --format='{{.State.Running}}' "$NGINX_ID" 2>/dev/null || echo "false")
fi

if [ "$NGINX_RUNNING" != "true" ]; then
    echo "Primeiro deploy detectado. Subindo todos os servicos..."
    docker compose up -d
    echo "Aguardando todos os containers ficarem healthy..."
    for service in tabua-mare1 tabua-mare2 tabua-mare3 tabua-mare4; do
      wait_healthy "$service"
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
for service in tabua-mare1 tabua-mare2; do
  wait_healthy "$service"
done

echo "Containers 1 e 2 healthy. Atualizando 3 e 4..."

# Segunda onda: restart containers 3 e 4
docker compose up -d --no-deps --build tabua-mare3 tabua-mare4

# Aguarda ficarem healthy
echo "Aguardando containers 3 e 4 ficarem healthy..."
for service in tabua-mare3 tabua-mare4; do
  wait_healthy "$service"
done

# Atualizar nginx e cloudflared (sem derrubar - apenas aplica config se mudou)
docker compose up -d --no-deps nginx cloudflared

echo "Deploy concluido!"
