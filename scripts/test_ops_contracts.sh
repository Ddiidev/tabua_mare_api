#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap="${root_dir}/ops/bootstrap_vps.sh"
firewall="${root_dir}/ops/cloudflare-origin-firewall.sh"
traefik="${root_dir}/ops/traefik/dynamic/tabuamare.yaml"
readme="${root_dir}/ops/README.md"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

for file in "${bootstrap}" "${firewall}" "${traefik}" "${readme}"; do
	[[ -f "${file}" ]] || fail "arquivo ausente: ${file#"${root_dir}/"}"
done

grep -Fq "COOLIFY_VERSION='4.1.2'" "${bootstrap}" || fail 'Coolify nao fixado em 4.1.2'
grep -Fq 'America/Sao_Paulo' "${bootstrap}" || fail 'timezone ausente'
grep -Fq 'fail2ban' "${bootstrap}" || fail 'fail2ban ausente'
grep -Fq 'swapfile' "${bootstrap}" || fail 'swap ausente'
grep -Fq 'vm.swappiness=10' "${bootstrap}" || fail 'swappiness ausente'
grep -Fq 'AUTOUPDATE=false' "${bootstrap}" || fail 'auto-update nao desativado'

grep -Fq 'https://www.cloudflare.com/ips-v4' "${firewall}" || fail 'ranges IPv4 nao oficiais'
grep -Fq 'https://www.cloudflare.com/ips-v6' "${firewall}" || fail 'ranges IPv6 nao oficiais'
grep -Fq 'DOCKER-USER' "${firewall}" || fail 'cadeia DOCKER-USER ausente'
grep -Fq 'ipset swap' "${firewall}" || fail 'atualizacao de ranges nao atomica'
grep -Fq '8000,6001,6002' "${firewall}" || fail 'portas administrativas nao bloqueadas'
grep -Fq 'tabuamare-cloudflare-firewall.timer' "${firewall}" || fail 'timer de atualizacao ausente'

grep -Fq '__APP_A_CONTAINER__' "${traefik}" || fail 'placeholder A ausente'
grep -Fq '__APP_B_CONTAINER__' "${traefik}" || fail 'placeholder B ausente'
grep -Fq 'path: /health/ready' "${traefik}" || fail 'healthcheck Traefik ausente'
grep -Fq 'interval: 5s' "${traefik}" || fail 'intervalo healthcheck incorreto'
grep -Fq 'timeout: 2s' "${traefik}" || fail 'timeout healthcheck incorreto'
grep -Fq 'certResolver: letsencrypt' "${traefik}" || fail 'resolver TLS ausente'
grep -Fq 'coolify-admin.tabuamare.api.br' "${traefik}" || fail 'router admin ausente'
grep -Fq 'www.tabuamare.api.br' "${traefik}" || fail 'router www ausente'

if grep -RIEq '(sk_(live|test)_[A-Za-z0-9]{12,}|whsec_[A-Za-z0-9]{12,}|CF_DNS_API_TOKEN=[A-Za-z0-9_-]{12,}|SSH_PASS_VPS=.{8,})' \
	"${root_dir}/ops" "${root_dir}/run_ssh.sh"; then
	fail 'possivel segredo em artefato versionado'
fi

printf 'PASS: contratos de bootstrap, firewall e Traefik\n'
