#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap="${root_dir}/ops/bootstrap_vps.sh"
firewall="${root_dir}/ops/cloudflare-origin-firewall.sh"
traefik="${root_dir}/ops/traefik/dynamic/tabuamare.yaml"
readme="${root_dir}/ops/README.md"

bash "${root_dir}/scripts/test_pg_pool_contract.sh"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

line_number() {
	local needle="$1"
	local file="$2"
	grep -nF -- "${needle}" "${file}" | head -n1 | cut -d: -f1
}

assert_before() {
	local first="$1"
	local second="$2"
	local file="$3"
	local first_line second_line
	first_line="$(line_number "${first}" "${file}")"
	second_line="$(line_number "${second}" "${file}")"
	[[ -n "${first_line}" && -n "${second_line}" && "${first_line}" -lt "${second_line}" ]] || \
		fail "ordem insegura em ${file#"${root_dir}/"}: ${first} deve vir antes de ${second}"
}

assert_last_before() {
	local first="$1"
	local second="$2"
	local file="$3"
	local first_line second_line
	first_line="$(grep -nF -- "${first}" "${file}" | tail -n1 | cut -d: -f1)"
	second_line="$(line_number "${second}" "${file}")"
	[[ -n "${first_line}" && -n "${second_line}" && "${first_line}" -lt "${second_line}" ]] || \
		fail "ordem insegura em ${file#"${root_dir}/"}: ultima chamada ${first} deve vir antes de ${second}"
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
grep -Fq "readonly coolify_image=\"docker.io/coollabsio/coolify:\${COOLIFY_VERSION}\"" "${bootstrap}" || \
	fail 'imagem Coolify esperada nao e exata'
grep -Fq "set_env_value LATEST_IMAGE \"\${COOLIFY_VERSION}\"" "${bootstrap}" || \
	fail 'LATEST_IMAGE fixada nao e persistida no .env'
grep -Fq 'set_env_value AUTOUPDATE false' "${bootstrap}" || \
	fail 'AUTOUPDATE nao usa atualizacao idempotente compartilhada'
grep -Fq "[[ \"\${current_image}\" == \"\${coolify_image}\" ]]" "${bootstrap}" || \
	fail 'imagem Coolify instalada nao e comparada exatamente'
assert_last_before "set_env_value LATEST_IMAGE \"\${COOLIFY_VERSION}\"" \
	'docker compose' "${bootstrap}"
grep -Fq '/etc/ssh/sshd_config.d/00-tabua-mare.conf' "${bootstrap}" || \
	fail 'hardening SSH nao tem precedencia sobre 50-cloud-init'
grep -Fq "assert_sshd_value passwordauthentication no" "${bootstrap}" || \
	fail 'PasswordAuthentication efetivo nao validado'
grep -Fq "assert_sshd_value kbdinteractiveauthentication no" "${bootstrap}" || \
	fail 'KbdInteractiveAuthentication efetivo nao validado'
grep -Fq "assert_sshd_value permitrootlogin without-password" "${bootstrap}" || \
	fail 'PermitRootLogin efetivo nao validado'
grep -Fq "readonly swap_size_bytes='2147483648'" "${bootstrap}" || \
	fail 'swap nao valida tamanho exato de 2 GiB'
grep -Fq 'stat -c %s /swapfile' "${bootstrap}" || fail 'swap nao valida tamanho real'
grep -Fq "stat -c %F /swapfile" "${bootstrap}" || fail 'swap nao valida arquivo regular'
grep -Fq "swapon --show=NAME --noheadings" "${bootstrap}" || fail 'swap ativa nao validada'
if grep -Eq 'swapon .*(\|\| true|2>/dev/null)' "${bootstrap}"; then
	fail 'falha de swapon ainda ignorada'
fi
assert_before '/usr/local/sbin/tabuamare-cloudflare-firewall --install-systemd' \
	"Instalando Coolify \${COOLIFY_VERSION}" "${bootstrap}"
grep -Fq 'verify_docker_firewall_dependencies()' "${bootstrap}" || \
	fail 'verificacao efetiva das dependencias Docker ausente'
grep -Fq "systemctl show \"\${unit}\" --property=Requires --value" "${bootstrap}" || \
	fail 'Requires efetivo do Docker nao validado'
grep -Fq "systemctl show \"\${unit}\" --property=After --value" "${bootstrap}" || \
	fail 'After efetivo do Docker nao validado'
assert_last_before 'verify_docker_firewall_dependencies' \
	"log 'Aplicando AUTOUPDATE=false no Coolify'" "${bootstrap}"

grep -Fq 'https://www.cloudflare.com/ips-v4' "${firewall}" || fail 'ranges IPv4 nao oficiais'
grep -Fq 'https://www.cloudflare.com/ips-v6' "${firewall}" || fail 'ranges IPv6 nao oficiais'
grep -Fq 'DOCKER-USER' "${firewall}" || fail 'cadeia DOCKER-USER ausente'
grep -Fq "readonly public_iface='eth0'" "${firewall}" || fail 'interface publica do firewall nao definida'
grep -Fq ' -i "${public_iface}" -p tcp -m multiport --dports 80,443' "${firewall}" || \
	fail 'regras Docker nao limitadas ao trafego de entrada'
grep -Fq 'ipset swap' "${firewall}" || fail 'atualizacao de ranges nao atomica'
grep -Fq '8000,6001,6002' "${firewall}" || fail 'portas administrativas nao bloqueadas'
grep -Fq 'tabuamare-cloudflare-firewall.timer' "${firewall}" || fail 'timer de atualizacao ausente'
grep -Fq "cache_dir='/var/lib/tabuamare-cloudflare-firewall'" "${firewall}" || \
	fail 'cache last-known-good ausente'
grep -Fq -- '--restore-cache' "${firewall}" || fail 'restauracao fail-closed no boot ausente'
grep -Fq -- '--refresh' "${firewall}" || fail 'refresh separado do boot ausente'
grep -Fq 'Before=docker.service docker.socket coolify.service traefik.service' "${firewall}" || \
	fail 'firewall nao ordenado antes de Docker/Coolify/Traefik'
grep -Fq 'ExecStart=/usr/local/sbin/tabuamare-cloudflare-firewall --restore-cache' "${firewall}" || \
	fail 'servico de boot nao restaura cache em modo fail-closed'
grep -Fq '/etc/systemd/system/docker.service.d/10-tabua-mare-firewall.conf' "${firewall}" || \
	fail 'drop-in de dependencia do docker.service ausente'
grep -Fq '/etc/systemd/system/docker.socket.d/10-tabua-mare-firewall.conf' "${firewall}" || \
	fail 'drop-in de dependencia do docker.socket ausente'
grep -Fq 'Requires=tabuamare-cloudflare-firewall.service' "${firewall}" || \
	fail 'Docker nao requer firewall de boot'
grep -Fq 'After=tabuamare-cloudflare-firewall.service' "${firewall}" || \
	fail 'Docker nao aguarda firewall de boot'
if grep -Fq 'OnBootSec=2min' "${firewall}"; then
	fail 'timer mantem janela de exposicao de dois minutos'
fi
assert_before 'systemctl enable --now tabuamare-cloudflare-firewall.service' \
	'systemctl enable --now tabuamare-cloudflare-firewall.timer' "${firewall}"

if grep -Fq -- "-F \"\${filter_chain}\"" "${firewall}" || \
	grep -Fq -- "-F \"\${chain}\"" "${firewall}"; then
	fail 'firewall ainda esvazia cadeia ativa referenciada'
fi
if grep -Fq 'if generation_needs_build' "${firewall}"; then
	fail 'mutacao de cadeia roda em condicional que desativa errexit do Bash'
fi
grep -Fq 'readonly forward_chain=' "${firewall}" || fail 'cadeia restritiva geracional FORWARD ausente'
grep -Fq 'readonly input_chain=' "${firewall}" || fail 'cadeia restritiva geracional INPUT ausente'
grep -Fq 'activate_chain' "${firewall}" || fail 'troca segura de cadeia ausente'
grep -Fq "rules=\"\$(\"\${tool}\" -w -S)\"" "${firewall}" || \
	fail 'deteccao de referencia pode falhar por SIGPIPE com pipefail'
grep -Fq 'falha ao enumerar referencias da cadeia' "${firewall}" || \
	fail 'erro do iptables -S nao aborta explicitamente'
reset_body="$(sed -n '/^reset_unreferenced_generation()/,/^}/p' "${firewall}")"
recheck_line="$(printf '%s\n' "${reset_body}" | grep -nF "chain_is_referenced \"\${tool}\" \"\${candidate}\"" | tail -n1 | cut -d: -f1)"
flush_line="$(printf '%s\n' "${reset_body}" | grep -nF -- "-F \"\${candidate}\"" | head -n1 | cut -d: -f1)"
[[ -n "${recheck_line}" && -n "${flush_line}" && "${recheck_line}" -lt "${flush_line}" ]] || \
	fail 'referencia da geracao nao e revalidada imediatamente antes do flush'
grep -Fq 'cadeia passou a ser referenciada; recusando flush' <<<"${reset_body}" || \
	fail 'recheck antes do flush nao aborta quando encontra referencia'

for function_name in configure_rules configure_input_rules; do
	function_body="$(sed -n "/^${function_name}()/,/^}/p" "${firewall}")"
	admin_line="$(printf '%s\n' "${function_body}" | grep -nF 'admin_ports' | tail -n1 | cut -d: -f1)"
	established_line="$(printf '%s\n' "${function_body}" | grep -nF 'ESTABLISHED,RELATED' | head -n1 | cut -d: -f1)"
	[[ -n "${admin_line}" && -n "${established_line}" && "${admin_line}" -lt "${established_line}" ]] || \
		fail "${function_name}: portas administrativas devem ser bloqueadas antes de ESTABLISHED"
done

grep -Fq '__APP_A_CONTAINER__' "${traefik}" || fail 'placeholder A ausente'
grep -Fq '__APP_B_CONTAINER__' "${traefik}" || fail 'placeholder B ausente'
grep -Fq 'path: /health/ready' "${traefik}" || fail 'healthcheck Traefik ausente'
grep -Fq 'interval: 5s' "${traefik}" || fail 'intervalo healthcheck incorreto'
grep -Fq 'timeout: 2s' "${traefik}" || fail 'timeout healthcheck incorreto'
grep -Fq 'certResolver: letsencrypt' "${traefik}" || fail 'resolver TLS ausente'
grep -Fq 'coolify-admin.tabuamare.api.br' "${traefik}" || fail 'router admin ausente'
grep -Fq 'www.tabuamare.api.br' "${traefik}" || fail 'router www ausente'

if grep -RIEq '(sk_(live|test)_[A-Za-z0-9]{12,}|whsec_[A-Za-z0-9]{12,}|CF_DNS_API_TOKEN=[A-Za-z0-9_-]{12,}|SSH_PASS_VPS=.{8,})' \
	"${root_dir}/ops"; then
	fail 'possivel segredo em artefato versionado'
fi

printf 'PASS: contratos de bootstrap, firewall e Traefik\n'
