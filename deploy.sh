#!/bin/bash
set -e

# Build nova imagem
docker compose build

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

echo "Deploy concluido!"
