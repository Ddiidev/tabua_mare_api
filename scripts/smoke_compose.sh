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

service_data_volume() {
	local service="$1"
	awk -v service="${service}" '
		$0 == "  " service ":" { in_service = 1; next }
		in_service && /^  [a-zA-Z0-9_-]+:$/ { exit }
		in_service && /^      - [^:]+:\/app\/data$/ {
			mount = $2
			sub(/:\/app\/data$/, "", mount)
			print mount
			exit
		}
	' "${compose_file}"
}

a_static_volume="$(service_data_volume tabuamare-a)"
b_static_volume="$(service_data_volume tabuamare-b)"
[[ "${a_static_volume}" == sqlite-a ]] || fail "A usa volume inesperado: ${a_static_volume:-ausente}"
[[ "${b_static_volume}" == sqlite-b ]] || fail "B usa volume inesperado: ${b_static_volume:-ausente}"
[[ "${a_static_volume}" != "${b_static_volume}" ]] || fail 'A e B compartilham volume no Compose fonte'
grep -Eq '^  sqlite-a:$' "${compose_file}" || fail 'declaracao sqlite-a ausente'
grep -Eq '^  sqlite-b:$' "${compose_file}" || fail 'declaracao sqlite-b ausente'
# Contrato literal do Compose, nao expansao shell.
# shellcheck disable=SC2016
grep -Fq 'path: ${TABUAMARE_ENV_FILE:-.env}' "${compose_file}" || fail 'env_file nao aceita arquivo isolado'
grep -Fq 'required: false' "${compose_file}" || fail '.env continua obrigatorio em checkout limpo'
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
config_json="$(TABUAMARE_ENV_FILE=/dev/null docker compose config --format json)"
python3 -c '
import json
import sys

config = json.load(sys.stdin)
sources = {}
for service in ("tabuamare-a", "tabuamare-b"):
    matches = [item.get("source") for item in config["services"][service].get("volumes", [])
               if item.get("target") == "/app/data"]
    if len(matches) != 1:
        raise SystemExit(f"{service}: esperado um mount /app/data, recebido {matches}")
    sources[service] = matches[0]
if sources["tabuamare-a"] == sources["tabuamare-b"]:
    raise SystemExit(f"volumes efetivos compartilhados: {sources}")
' <<<"${config_json}"

if [[ "${COMPOSE_RUNTIME:-0}" != 1 ]]; then
	printf 'PASS: topologia A/B e docker compose config\n'
	exit 0
fi

[[ -n "${COMPOSE_TEST_ENV_FILE:-}" ]] || fail 'COMPOSE_TEST_ENV_FILE obrigatorio para runtime'
[[ -f "${COMPOSE_TEST_ENV_FILE}" ]] || fail 'arquivo de ambiente de teste inexistente'
test_env_file="$(realpath "${COMPOSE_TEST_ENV_FILE}")"
[[ "${test_env_file}" != "$(realpath -m "${root_dir}/.env")" ]] || fail 'runtime smoke nao pode usar .env local'
[[ "${COMPOSE_TEST_ALLOW_DB_MUTATIONS:-}" == yes ]] || \
	fail 'defina COMPOSE_TEST_ALLOW_DB_MUTATIONS=yes para confirmar DB isolado'
grep -Eq '^POSTGRESQL_CONN_STR=.+$' "${test_env_file}" || fail 'POSTGRESQL_CONN_STR ausente no ambiente de teste'

project="tabuamare-smoke-${RANDOM}-${RANDOM}"
cleanup() {
	TABUAMARE_ENV_FILE="${test_env_file}" docker compose -p "${project}" down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

up_args=(up -d)
if [[ "${COMPOSE_BUILD:-1}" == 1 ]]; then
	up_args+=(--build)
else
	up_args+=(--no-build)
fi
TABUAMARE_ENV_FILE="${test_env_file}" docker compose -p "${project}" "${up_args[@]}"

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

a_id="$(TABUAMARE_ENV_FILE="${test_env_file}" docker compose -p "${project}" ps -q tabuamare-a)"
b_id="$(TABUAMARE_ENV_FILE="${test_env_file}" docker compose -p "${project}" ps -q tabuamare-b)"
a_volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Name}}{{end}}{{end}}' "${a_id}")"
b_volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Name}}{{end}}{{end}}' "${b_id}")"

[[ -n "${a_volume}" ]] || fail 'mount SQLite A nao encontrado'
[[ -n "${b_volume}" ]] || fail 'mount SQLite B nao encontrado'
[[ "${a_volume}" != "${b_volume}" ]] || fail 'A e B compartilham o mesmo volume SQLite'

app_uid() {
	local container_id="$1"
	docker exec "${container_id}" sh -eu -c '
		pid="$(pidof TabuaMareAPI)"
		[ -n "${pid}" ]
		awk "/^Uid:/ { print \$2 }" "/proc/${pid}/status"
	'
}

a_uid="$(app_uid "${a_id}")"
b_uid="$(app_uid "${b_id}")"
[[ "${a_uid}" == 10001 ]] || fail "processo A usa UID ${a_uid}, esperado 10001"
[[ "${b_uid}" == 10001 ]] || fail "processo B usa UID ${b_uid}, esperado 10001"

printf 'PASS: A/B saudaveis, API v2 200, UID 10001, volumes distintos %s != %s\n' "${a_volume}" "${b_volume}"
