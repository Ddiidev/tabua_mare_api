#!/usr/bin/env bash
set -euo pipefail

readonly image_name='ghcr.io/ddiidev/tabua-mare-api'
readonly target_tag="${1:-}"
readonly deploy_timeout="${COOLIFY_DEPLOY_TIMEOUT:-600}"
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

[[ "${target_tag}" =~ ^sha-[0-9a-f]{40}$ ]] || \
	fail 'uso: coolify_deploy.sh sha-<commit de 40 hex minusculos>'
[[ "${COOLIFY_APP_A_UUID}" != "${COOLIFY_APP_B_UUID}" ]] || fail 'UUIDs A/B devem ser diferentes'
[[ "${deploy_timeout}" =~ ^[1-9][0-9]*$ ]] || fail 'COOLIFY_DEPLOY_TIMEOUT deve ser inteiro positivo'
[[ "${poll_seconds}" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail 'COOLIFY_POLL_SECONDS invalido'

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

patch_tag() {
	local uuid="$1"
	local tag="$2"
	api_request PATCH "/applications/${uuid}" \
		"{\"docker_registry_image_tag\":\"${tag}\"}" >/dev/null
}

start_app() {
	api_request POST "/applications/$1/start?force=true" >/dev/null
}

wait_healthy() {
	local uuid="$1"
	local expected_tag="$2"
	local deadline=$(( $(date +%s) + deploy_timeout ))
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

public_smoke() {
	local path code
	for path in /health/ready /api/v2/states; do
		code="$(curl --silent --show-error --connect-timeout 10 --max-time 20 \
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
	log "Atualizando app ${slot} para ${target_tag}"
	patch_tag "${uuid}" "${target_tag}" || return 1
	if [[ "${slot}" == A ]]; then
		touched_a=1
	else
		touched_b=1
	fi
	start_app "${uuid}" || return 1
	wait_healthy "${uuid}" "${target_tag}" || return 1
	public_smoke
}

restore_app() {
	local slot="$1"
	local uuid="$2"
	local old_tag="$3"
	log "Rollback app ${slot} para ${old_tag}"
	patch_tag "${uuid}" "${old_tag}" && \
		start_app "${uuid}" && \
		wait_healthy "${uuid}" "${old_tag}"
}

rollback() {
	local failed=0
	if [[ "${touched_b}" == 1 ]]; then
		restore_app B "${COOLIFY_APP_B_UUID}" "${old_tag_b}" || failed=1
	fi
	if [[ "${touched_a}" == 1 ]]; then
		restore_app A "${COOLIFY_APP_A_UUID}" "${old_tag_a}" || failed=1
	fi
	if [[ "${failed}" == 1 ]]; then
		log 'ERRO CRITICO: rollback incompleto; verificar Coolify imediatamente'
	fi
	return "${failed}"
}

app_a="$(get_app "${COOLIFY_APP_A_UUID}")" || fail 'nao foi possivel ler app A'
app_b="$(get_app "${COOLIFY_APP_B_UUID}")" || fail 'nao foi possivel ler app B'
old_tag_a="$(json_field docker_registry_image_tag <<<"${app_a}")"
old_tag_b="$(json_field docker_registry_image_tag <<<"${app_b}")"
[[ "${old_tag_a}" =~ ^sha-[0-9a-f]{40}$ ]] || fail 'tag anterior invalida no app A'
[[ "${old_tag_b}" =~ ^sha-[0-9a-f]{40}$ ]] || fail 'tag anterior invalida no app B'

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

log "Deploy concluido: A/B em ${target_tag}"
