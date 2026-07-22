#!/usr/bin/env bash
# Valida, dentro de cada container Coolify A/B, o mesmo DNS/TLS/egress e as
# credenciais Stripe configuradas na aplicacao. Nenhum segredo e' impresso.
set -euo pipefail

fail() { printf '[stripe-check] ERRO: %s\n' "$*" >&2; exit 1; }
log() { printf '[stripe-check] %s\n' "$*"; }

[[ -n "${COOLIFY_APP_A_UUID:-}" ]] || fail 'COOLIFY_APP_A_UUID obrigatorio'
[[ -n "${COOLIFY_APP_B_UUID:-}" ]] || fail 'COOLIFY_APP_B_UUID obrigatorio'
[[ "${COOLIFY_APP_A_UUID}" != "${COOLIFY_APP_B_UUID}" ]] || fail 'UUIDs A/B devem ser diferentes'
command -v docker >/dev/null 2>&1 || fail 'docker nao encontrado'

container_for_app() {
	local uuid="$1"
	local container
	container="$(docker ps \
		--filter 'label=coolify.type=application' \
		--filter "label=coolify.name=${uuid}" \
		--format '{{.Names}}' | head -n1 || true)"
	if [[ -z "${container}" ]]; then
		container="$(docker ps \
			--filter "label=com.docker.compose.project=${uuid}" \
			--format '{{.Names}}' | head -n1 || true)"
	fi
	printf '%s\n' "${container}"
}

check_slot() {
	local slot="$1"
	local uuid="$2"
	local container
	container="$(container_for_app "${uuid}")"
	[[ -n "${container}" ]] || fail "slot ${slot}: container running nao encontrado"

	log "slot ${slot}: testando ${container}"
	docker exec "${container}" sh -ceu '
		for required in STRIPE_SECRET_KEY STRIPE_PRICE_PLAN5 STRIPE_PRICE_PLAN10 STRIPE_PRICE_PLANANNUAL; do
			value="$(printenv "${required}" || true)"
			[ -n "${value}" ] || { printf "variavel %s ausente\n" "${required}" >&2; exit 1; }
		done

		public_result="$(curl -sS --connect-timeout 3 --max-time 8 -o /dev/null \
			-w "%{http_code} %{time_total} %{remote_ip}" https://api.stripe.com/v1/account)"
		set -- ${public_result}
		[ "$1" = 401 ] || { printf "probe publica inesperada: HTTP %s\n" "$1" >&2; exit 1; }
		printf "  DNS/TLS/egress: HTTP %s em %ss via %s\n" "$1" "$2" "$3"

		account_code="$(curl -sS --connect-timeout 3 --max-time 8 -o /dev/null -w "%{http_code}" \
			-H "Authorization: Bearer ${STRIPE_SECRET_KEY}" https://api.stripe.com/v1/account)"
		[ "${account_code}" = 200 ] || { printf "credencial Stripe: HTTP %s\n" "${account_code}" >&2; exit 1; }
		printf "  credencial Stripe: HTTP 200\n"

		for price_var in STRIPE_PRICE_PLAN5 STRIPE_PRICE_PLAN10 STRIPE_PRICE_PLANANNUAL; do
			price_id="$(printenv "${price_var}")"
			price_code="$(curl -sS --connect-timeout 3 --max-time 8 -o /dev/null -w "%{http_code}" \
				-H "Authorization: Bearer ${STRIPE_SECRET_KEY}" \
				"https://api.stripe.com/v1/prices/${price_id}")"
			[ "${price_code}" = 200 ] || {
				printf "%s: HTTP %s (key/price podem estar em modos ou contas diferentes)\n" \
					"${price_var}" "${price_code}" >&2
				exit 1
			}
			printf "  %s: HTTP 200\n" "${price_var}"
		done
	'
}

check_slot A "${COOLIFY_APP_A_UUID}"
check_slot B "${COOLIFY_APP_B_UUID}"
log 'Stripe acessivel e configurada corretamente nos dois slots.'
