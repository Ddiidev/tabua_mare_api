#!/usr/bin/env bash
# Ajusta a config dinamica do Traefik do Coolify para funcionar com o
# Nginx na borda. O Nginx termina TLS e manda HTTP plano para o Traefik
# na rede coolify (porta 80 do container). O Traefik nao deve mais:
#   - redirecionar HTTP -> HTTPS (causa loop infinito)
#   - ter routers na entrada https (TLS ja terminado no Nginx)
#   - ter routers para tabuamare.api.br (Nginx cuida do fluxo publico)
set -euo pipefail

dyn_dir="/data/coolify/proxy/dynamic"

log() { printf '[fix-traefik] %s\n' "$*"; }
fail() { printf '[fix-traefik] ERRO: %s\n' "$*" >&2; exit 1; }

[[ -d "${dyn_dir}" ]] || fail "${dyn_dir} nao encontrado"

# 1. Apagar tabuamare-loadbalance.yml (Nginx cuida do fluxo publico).
if [[ -f "${dyn_dir}/tabuamare-loadbalance.yml" ]]; then
	log 'Apagando tabuamare-loadbalance.yml (Nginx cuida do fluxo publico)'
	rm -f "${dyn_dir}/tabuamare-loadbalance.yml"
fi

# 2. Apagar tabuamare.yaml se existir (legacy).
if [[ -f "${dyn_dir}/tabuamare.yaml" ]]; then
	log 'Apagando tabuamare.yaml (legacy)'
	rm -f "${dyn_dir}/tabuamare.yaml"
fi

# 3. Reescrever coolify.yaml sem redirect HTTPS e sem routers na entrada
# https. O Nginx termina TLS na borda e manda HTTP plano para o Traefik.
# O Coolify regenera este arquivo se mexer no painel -- aceitar o risco
# e re-rodar este script se necessario.
log 'Reescrevendo coolify.yaml (sem redirect HTTPS, sem routers https)'
cat >"${dyn_dir}/coolify.yaml" <<'YAML'
# This file was adjusted by ops/nginx/fix-traefik-for-nginx-edge.sh
# to work with Nginx on the edge (Nginx terminates TLS, Traefik serves
# HTTP internally). Coolify may overwrite this file; re-run the script
# if that happens.

http:
  middlewares:
    gzip:
      compress: true
  routers:
    coolify-http:
      entryPoints:
        - http
      service: coolify
      rule: Host(`coolify-admin.tabuamare.api.br`)
    coolify-realtime-ws:
      entryPoints:
        - http
      service: coolify-realtime
      rule: 'Host(`coolify-admin.tabuamare.api.br`) && PathPrefix(`/app`)'
    coolify-terminal-ws:
      entryPoints:
        - http
      service: coolify-terminal
      rule: 'Host(`coolify-admin.tabuamare.api.br`) && PathPrefix(`/terminal/ws`)'
  services:
    coolify:
      loadBalancer:
        servers:
          -
            url: 'http://coolify:8080'
    coolify-realtime:
      loadBalancer:
        servers:
          -
            url: 'http://coolify-realtime:6001'
    coolify-terminal:
      loadBalancer:
        servers:
          -
            url: 'http://coolify-realtime:6002'
YAML

log 'Arquivos ajustados. Traefik recarrega automaticamente (file provider watch=true).'

# 4. Validar que o Traefik responde sem redirect.
log 'Testando Traefik sem redirect...'
sleep 2
code="$(docker exec coolify-proxy wget -S -O /dev/null --header 'Host: coolify-admin.tabuamare.api.br' http://localhost:80/ 2>&1 | grep 'HTTP/' | head -1 || true)"
log "  Traefik respondeu: ${code}"

log 'Pronto. Teste pelo Nginx:'
log '  curl -I https://coolify-admin.tabuamare.api.br/'