#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="${root_dir}/docker-compose.yml"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

grep -Eq '^  tabuamare-a:$' "${compose_file}" || fail 'servico tabuamare-a ausente'
grep -Eq '^  tabuamare-b:$' "${compose_file}" || fail 'servico tabuamare-b ausente'
mapfile -t services < <(awk '
	/^services:$/ { in_services = 1; next }
	/^volumes:$/ { in_services = 0 }
	in_services && /^  [a-zA-Z0-9_-]+:$/ {
		name = $1
		sub(/:$/, "", name)
		print name
	}
' "${compose_file}")
[[ "${#services[@]}" -eq 2 ]] || fail "Compose deve ter apenas A/B; encontrou ${services[*]}"
grep -Fq -- '- sqlite-a:/app/data' "${compose_file}" || fail 'volume sqlite-a ausente'
grep -Fq -- '- sqlite-b:/app/data' "${compose_file}" || fail 'volume sqlite-b ausente'
grep -Eq '^  sqlite-a:$' "${compose_file}" || fail 'declaracao sqlite-a ausente'
grep -Eq '^  sqlite-b:$' "${compose_file}" || fail 'declaracao sqlite-b ausente'
grep -Fq '/health/ready' "${compose_file}" || fail 'healthcheck readiness ausente'
grep -Fq 'stop_grace_period: 30s' "${compose_file}" || fail 'stop grace de 30s ausente'
grep -Fq 'mem_limit: 512m' "${compose_file}" || fail 'limite de RAM ausente'
grep -Fq 'mem_reservation: 256m' "${compose_file}" || fail 'reserva de RAM ausente'

if grep -Eqi 'cloudflared|CLOUDFLARE_TUNNEL|^[[:space:]]+nginx:' "${compose_file}"; then
	fail 'nginx/cloudflared ainda presente no Compose ativo'
fi
if grep -Fq -- '- sqlite-data:/app/data' "${compose_file}"; then
	fail 'volume SQLite compartilhado ainda presente'
fi
for legacy_file in \
	deploy.sh \
	start.sh \
	dockerfiles/Dockerfile.compose \
	dockerfiles/Dockerfile.tabuamare \
	dockerfiles/entrypoint.sh \
	dockerfiles/nginx.single.conf \
	dockerfiles/supervisord.single.conf \
	nginx/nginx.conf \
	nginx/conf.d/maisfoco.conf; do
	[[ ! -e "${root_dir}/${legacy_file}" ]] || fail "artefato legado ainda ativo: ${legacy_file}"
done

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
	printf 'PASS: topologia A/B estatica; Docker indisponivel, runtime adiado\n'
	exit 0
fi

cd "${root_dir}"
docker compose config --quiet

if [[ "${COMPOSE_RUNTIME:-0}" != 1 ]]; then
	printf 'PASS: topologia A/B e docker compose config\n'
	exit 0
fi

project="tabuamare-smoke-${RANDOM}-${RANDOM}"
cleanup() {
	docker compose -p "${project}" down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker compose -p "${project}" up -d --build

wait_http() {
	local url="$1"
	local expected="$2"
	local code='000'
	for _ in $(seq 1 180); do
		code="$(curl -sS -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"
		[[ "${code}" == "${expected}" ]] && return 0
		sleep 1
	done
	fail "${url} retornou ${code}, esperado ${expected}"
}

wait_http 'http://127.0.0.1:3330/health/ready' 204
wait_http 'http://127.0.0.1:3340/health/ready' 204
wait_http 'http://127.0.0.1:3330/api/v2/states' 200
wait_http 'http://127.0.0.1:3340/api/v2/states' 200

a_id="$(docker compose -p "${project}" ps -q tabuamare-a)"
b_id="$(docker compose -p "${project}" ps -q tabuamare-b)"
a_volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Name}}{{end}}{{end}}' "${a_id}")"
b_volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Name}}{{end}}{{end}}' "${b_id}")"

[[ -n "${a_volume}" ]] || fail 'mount SQLite A nao encontrado'
[[ -n "${b_volume}" ]] || fail 'mount SQLite B nao encontrado'
[[ "${a_volume}" != "${b_volume}" ]] || fail 'A e B compartilham o mesmo volume SQLite'

printf 'PASS: A/B saudaveis, API v2 200, volumes distintos %s != %s\n' "${a_volume}" "${b_volume}"
