#!/usr/bin/env bash
set -euo pipefail

readonly image_name='ghcr.io/ddiidev/tabua-mare-api'
readonly target_tag="${1:-}"
readonly deploy_timeout="${COOLIFY_DEPLOY_TIMEOUT:-480}"
readonly poll_seconds="${COOLIFY_POLL_SECONDS:-5}"

log() {
	printf '%s\n' "$*" >&2
}

fail() {
	log "ERRO: $*"
	exit 1
}

require_env() {
	local name="$1"
	[[ -n "${!name:-}" ]] || fail "variavel ${name} obrigatoria"
}

require_env COOLIFY_URL
require_env COOLIFY_TOKEN
require_env COOLIFY_APP_A_UUID
require_env COOLIFY_APP_B_UUID
require_env PUBLIC_SMOKE_URL
require_env DEPLOY_SMOKE_SECRET

[[ "${target_tag}" =~ ^sha-[0-9a-f]{40}$ ]] || \
	fail 'uso: coolify_deploy.sh sha-<commit de 40 hex minusculos>'
[[ "${COOLIFY_APP_A_UUID}" != "${COOLIFY_APP_B_UUID}" ]] || fail 'UUIDs A/B devem ser diferentes'
[[ "${deploy_timeout}" =~ ^[1-9][0-9]*$ ]] || fail 'COOLIFY_DEPLOY_TIMEOUT deve ser inteiro positivo'
[[ "${poll_seconds}" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail 'COOLIFY_POLL_SECONDS invalido'
[[ "${#DEPLOY_SMOKE_SECRET}" -ge 32 ]] || fail 'DEPLOY_SMOKE_SECRET deve ter no minimo 32 caracteres'

coolify_origin="${COOLIFY_URL%/}"
smoke_origin="${PUBLIC_SMOKE_URL%/}"
if [[ "${COOLIFY_ALLOW_HTTP:-0}" != 1 ]]; then
	[[ "${coolify_origin}" == https://* ]] || fail 'COOLIFY_URL deve usar HTTPS'
	[[ "${smoke_origin}" == https://* ]] || fail 'PUBLIC_SMOKE_URL deve usar HTTPS'
fi
readonly api_base="${coolify_origin}/api/v1"

command -v curl >/dev/null 2>&1 || fail 'curl nao encontrado'
command -v python3 >/dev/null 2>&1 || fail 'python3 nao encontrado'
command -v docker >/dev/null 2>&1 || fail 'docker nao encontrado para validar manifesto GHCR'

log "Validando imagem ${image_name}:${target_tag}"
docker manifest inspect "${image_name}:${target_tag}" >/dev/null || fail 'imagem GHCR inexistente ou inacessivel'

api_request() {
	local method="$1"
	local path="$2"
	local body="${3:-}"
	local args=(
		--fail-with-body
		--silent
		--show-error
		--connect-timeout 10
		--max-time 30
		-X "${method}"
		-H "Authorization: Bearer ${COOLIFY_TOKEN}"
		-H 'Accept: application/json'
	)
	if [[ -n "${body}" ]]; then
		args+=( -H 'Content-Type: application/json' --data "${body}" )
	fi
	curl "${args[@]}" "${api_base}${path}"
}

json_field() {
	local field="$1"
	python3 -c 'import json,sys; value=json.load(sys.stdin).get(sys.argv[1], ""); print(value if value is not None else "")' "${field}"
}

get_app() {
	api_request GET "/applications/$1"
}

get_storages() {
	api_request GET "/applications/$1/storages"
}

validate_app_preflight() {
	local slot="$1"
	local app_json="$2"
	local storages_json="$3"
	python3 - "${slot}" "${app_json}" "${storages_json}" <<'PY'
import json
import re
import sys

slot, app_raw, storages_raw = sys.argv[1:]
app = json.loads(app_raw)
storages_payload = json.loads(storages_raw)

def fail(message):
    raise SystemExit(f"app {slot}: {message}")

def lookup(*paths):
    for path in paths:
        value = app
        for part in path.split("."):
            if not isinstance(value, dict) or part not in value:
                value = None
                break
            value = value[part]
        if value is not None:
            return value
    return None

if lookup("status") != "running:healthy":
    fail("status inicial deve ser running:healthy")

try:
    if float(str(lookup("limits_cpus"))) != 2.0:
        fail("limits_cpus deve ser 2")
except (TypeError, ValueError):
    fail("limits_cpus ausente ou invalido")

def bytes_value(value):
    text = str(value or "").strip().lower()
    match = re.fullmatch(r"(\d+(?:\.\d+)?)\s*(b|k|kb|kib|m|mb|mib|g|gb|gib)?", text)
    if not match:
        return None
    number = float(match.group(1))
    unit = match.group(2) or "b"
    multiplier = {
        "b": 1, "k": 1024, "kb": 1024, "kib": 1024,
        "m": 1024**2, "mb": 1024**2, "mib": 1024**2,
        "g": 1024**3, "gb": 1024**3, "gib": 1024**3,
    }[unit]
    return int(number * multiplier)

if bytes_value(lookup("limits_memory")) != 512 * 1024 * 1024:
    fail("limits_memory deve ser 512 MiB")
if bytes_value(lookup("limits_memory_reservation", "limits_reservation_memory")) != 256 * 1024 * 1024:
    fail("reserva de memoria deve ser 256 MiB")

exposes = [item.strip() for item in str(lookup("ports_exposes") or "").split(",") if item.strip()]
if exposes != ["3330"]:
    fail("ports_exposes deve conter somente 3330")
mappings = lookup("ports_mappings")
if mappings not in (None, "", [], {}):
    fail("ports_mappings deve estar vazio; host mapping e inseguro")

health_enabled = lookup("health_check_enabled")
if health_enabled is not True and str(health_enabled).lower() not in {"1", "true", "yes"}:
    fail("health_check_enabled deve estar habilitado")
if lookup("health_check_path") != "/health/ready":
    fail("health_check_path deve ser /health/ready")
health_port = str(lookup("health_check_port") or "3330")
if health_port != "3330":
    fail("health_check_port deve ser 3330")

storages = storages_payload.get("persistent_storages") if isinstance(storages_payload, dict) else storages_payload
if not isinstance(storages, list):
    fail("resposta de storages sem persistent_storages")
data_mounts = [item for item in storages if item.get("mount_path") == "/app/data"]
if len(data_mounts) != 1:
    fail("esperado exatamente um storage em /app/data")
storage = data_mounts[0]
host_path = str(storage.get("host_path") or "").strip()
name = str(storage.get("name") or "").strip()
identity = f"host:{host_path}" if host_path else f"volume:{name}"
if identity in {"host:", "volume:"}:
    fail("storage /app/data sem name ou host_path")
print(identity)
PY
}

patch_tag() {
	local uuid="$1"
	local tag="$2"
	api_request PATCH "/applications/${uuid}" \
		"{\"docker_registry_image_tag\":\"${tag}\"}" >/dev/null
}

start_app() {
	api_request POST "/applications/$1/start?force=true"
}

stop_app() {
	api_request POST "/applications/$1/stop" >/dev/null
}

wait_stopped() {
	local uuid="$1"
	local deadline="$2"
	local response status
	while (( $(date +%s) <= deadline )); do
		response="$(get_app "${uuid}" 2>/dev/null || true)"
		if [[ -n "${response}" ]]; then
			status="$(json_field status <<<"${response}" 2>/dev/null || true)"
			case "${status}" in
				exited|exited:*|stopped|stopped:*) return 0 ;;
			esac
		fi
		sleep "${poll_seconds}"
	done
	log "Timeout: ${uuid} nao ficou definitivamente parada"
	return 1
}

wait_deployment() {
	local deployment_uuid="$1"
	local deadline="$2"
	local response status
	while (( $(date +%s) <= deadline )); do
		response="$(api_request GET "/deployments/${deployment_uuid}" 2>/dev/null || true)"
		if [[ -n "${response}" ]]; then
			status="$(json_field status <<<"${response}" 2>/dev/null || true)"
			case "${status}" in
				finished) return 0 ;;
				failed|cancelled-by-user)
					log "Deployment ${deployment_uuid} terminou com ${status}"
					return 1
					;;
			esac
		fi
		sleep "${poll_seconds}"
	done
	log "Timeout: deployment ${deployment_uuid} nao terminou"
	return 1
}

wait_healthy() {
	local uuid="$1"
	local expected_tag="$2"
	local deadline="$3"
	local response status current_tag
	while (( $(date +%s) <= deadline )); do
		response="$(get_app "${uuid}" 2>/dev/null || true)"
		if [[ -n "${response}" ]]; then
			status="$(json_field status <<<"${response}" 2>/dev/null || true)"
			current_tag="$(json_field docker_registry_image_tag <<<"${response}" 2>/dev/null || true)"
			if [[ "${status}" == 'running:healthy' && "${current_tag}" == "${expected_tag}" ]]; then
				return 0
			fi
		fi
		sleep "${poll_seconds}"
	done
	log "Timeout: ${uuid} nao ficou running:healthy com ${expected_tag}"
	return 1
}

ensure_app_healthy() {
	local uuid="$1"
	local slot="$2"
	local response status
	response="$(get_app "${uuid}" 2>/dev/null || true)"
	[[ -n "${response}" ]] || {
		log "Peer ${slot} indisponivel antes do stop"
		return 1
	}
	status="$(json_field status <<<"${response}" 2>/dev/null || true)"
	[[ "${status}" == 'running:healthy' ]] || {
		log "Peer ${slot} nao esta running:healthy antes do stop"
		return 1
	}
}

public_smoke() {
	local slot="$1"
	local path code
	for path in /health/ready /api/v2/states; do
		code="$(curl --silent --show-error --connect-timeout 10 --max-time 20 \
			-H "X-Tabuamare-Deploy-Slot: ${slot}" \
			-H "X-Tabuamare-Deploy-Secret: ${DEPLOY_SMOKE_SECRET}" \
			-o /dev/null -w '%{http_code}' "${smoke_origin}${path}" || true)"
		if [[ "${path}" == /health/ready ]]; then
			[[ "${code}" == 204 ]] || {
				log "Smoke falhou: ${path} retornou ${code}"
				return 1
			}
		else
			[[ "${code}" == 200 ]] || {
				log "Smoke falhou: ${path} retornou ${code}"
				return 1
			}
		fi
	done
}

touched_a=0
touched_b=0
old_tag_a=''
old_tag_b=''

deploy_app() {
	local slot="$1"
	local uuid="$2"
	local peer_uuid peer_slot start_response deployment_uuid deadline
	deadline=$(( $(date +%s) + deploy_timeout ))
	log "Atualizando app ${slot} para ${target_tag}"
	if [[ "${slot}" == A ]]; then
		peer_uuid="${COOLIFY_APP_B_UUID}"
		peer_slot=B
	else
		peer_uuid="${COOLIFY_APP_A_UUID}"
		peer_slot=A
	fi
	ensure_app_healthy "${peer_uuid}" "${peer_slot}" || return 1
	if [[ "${slot}" == A ]]; then
		touched_a=1
	else
		touched_b=1
	fi
	stop_app "${uuid}" || return 1
	wait_stopped "${uuid}" "${deadline}" || return 1
	patch_tag "${uuid}" "${target_tag}" || return 1
	start_response="$(start_app "${uuid}")" || return 1
	deployment_uuid="$(json_field deployment_uuid <<<"${start_response}" 2>/dev/null || true)"
	[[ -n "${deployment_uuid}" ]] || {
		log "Coolify nao retornou deployment_uuid para app ${slot}"
		return 1
	}
	wait_deployment "${deployment_uuid}" "${deadline}" || return 1
	wait_healthy "${uuid}" "${target_tag}" "${deadline}" || return 1
	public_smoke "${slot}"
}

restore_app() {
	local slot="$1"
	local uuid="$2"
	local old_tag="$3"
	local peer_uuid="$4"
	local peer_slot="$5"
	local start_response deployment_uuid deadline
	deadline=$(( $(date +%s) + deploy_timeout ))
	log "Rollback app ${slot} para ${old_tag}"
	ensure_app_healthy "${peer_uuid}" "${peer_slot}" || return 1
	stop_app "${uuid}" || return 1
	wait_stopped "${uuid}" "${deadline}" || return 1
	patch_tag "${uuid}" "${old_tag}" || return 1
	start_response="$(start_app "${uuid}")" || return 1
	deployment_uuid="$(json_field deployment_uuid <<<"${start_response}" 2>/dev/null || true)"
	[[ -n "${deployment_uuid}" ]] || return 1
	wait_deployment "${deployment_uuid}" "${deadline}" && \
		wait_healthy "${uuid}" "${old_tag}" "${deadline}"
}

rollback() {
	[[ "${rollback_in_progress}" == 0 ]] || return 1
	rollback_in_progress=1
	local failed=0
	if [[ "${touched_b}" == 1 ]]; then
		if ! restore_app B "${COOLIFY_APP_B_UUID}" "${old_tag_b}" "${COOLIFY_APP_A_UUID}" A; then
			log 'ERRO CRITICO: rollback de B falhou; A mantida saudavel na tag atual'
			rollback_in_progress=0
			rollback_done=1
			return 1
		fi
	fi
	if [[ "${touched_a}" == 1 ]]; then
		restore_app A "${COOLIFY_APP_A_UUID}" "${old_tag_a}" "${COOLIFY_APP_B_UUID}" B || failed=1
	fi
	if [[ "${failed}" == 1 ]]; then
		log 'ERRO CRITICO: rollback incompleto; verificar Coolify imediatamente'
	fi
	rollback_in_progress=0
	rollback_done=1
	return "${failed}"
}

rollback_in_progress=0
rollback_done=0

app_a="$(get_app "${COOLIFY_APP_A_UUID}")" || fail 'nao foi possivel ler app A'
app_b="$(get_app "${COOLIFY_APP_B_UUID}")" || fail 'nao foi possivel ler app B'
storages_a="$(get_storages "${COOLIFY_APP_A_UUID}")" || fail 'nao foi possivel ler storages da app A'
storages_b="$(get_storages "${COOLIFY_APP_B_UUID}")" || fail 'nao foi possivel ler storages da app B'
storage_identity_a="$(validate_app_preflight A "${app_a}" "${storages_a}")" || fail 'preflight da app A falhou'
storage_identity_b="$(validate_app_preflight B "${app_b}" "${storages_b}")" || fail 'preflight da app B falhou'
[[ "${storage_identity_a}" != "${storage_identity_b}" ]] || \
	fail 'apps A/B compartilham o mesmo volume ou host_path em /app/data'
old_tag_a="$(json_field docker_registry_image_tag <<<"${app_a}")"
old_tag_b="$(json_field docker_registry_image_tag <<<"${app_b}")"
[[ "${old_tag_a}" =~ ^sha-[0-9a-f]{40}$ ]] || fail 'tag anterior invalida no app A'
[[ "${old_tag_b}" =~ ^sha-[0-9a-f]{40}$ ]] || fail 'tag anterior invalida no app B'

on_signal() {
	trap '' INT TERM
	log 'Deploy interrompido; tentando rollback antes de sair'
	rollback || true
	exit 130
}

on_exit() {
	local exit_code="$?"
	if [[ "${exit_code}" != 0 && "${rollback_done}" == 0 && "${rollback_in_progress}" == 0 ]]; then
		log 'Saida inesperada; tentando rollback'
		rollback || true
	fi
	return "${exit_code}"
}
trap on_signal INT TERM
trap on_exit EXIT

if ! deploy_app A "${COOLIFY_APP_A_UUID}"; then
	log 'Deploy A falhou; iniciando rollback'
	rollback || true
	exit 1
fi
if ! deploy_app B "${COOLIFY_APP_B_UUID}"; then
	log 'Deploy B falhou; iniciando rollback de B e A'
	rollback || true
	exit 1
fi

trap - INT TERM EXIT
log "Deploy concluido: A/B em ${target_tag}"
