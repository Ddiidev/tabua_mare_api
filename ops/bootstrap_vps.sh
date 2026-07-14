#!/usr/bin/env bash
set -euo pipefail

readonly COOLIFY_VERSION='4.1.2'
readonly coolify_image="docker.io/coollabsio/coolify:${COOLIFY_VERSION}"
readonly swap_size_bytes='2147483648'
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly coolify_source='/data/coolify/source'

log() {
	printf '[bootstrap] %s\n' "$*"
}

fail() {
	printf '[bootstrap] ERRO: %s\n' "$*" >&2
	exit 1
}

[[ "${EUID}" -eq 0 ]] || fail 'execute como root'

harden_ssh() {
	local sshd_effective
	local sshd_host
	[[ "${CONFIRM_KEY_CONNECTION:-}" == yes ]] || \
		fail 'valide outra conexao por chave e execute com CONFIRM_KEY_CONNECTION=yes'
	install -d -m 0755 /etc/ssh/sshd_config.d
	# OpenSSH usa o primeiro valor encontrado. 00- precede 50-cloud-init.
	cat >/etc/ssh/sshd_config.d/00-tabua-mare.conf <<'SSH'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
SSH
	rm -f /etc/ssh/sshd_config.d/99-tabua-mare.conf
	sshd -t
	sshd_host="$(hostname)"
	sshd_effective="$(sshd -T -C user=root,host="${sshd_host}",addr=127.0.0.1)"
	assert_sshd_value() {
		local key="$1"
		local expected="$2"
		printf '%s\n' "${sshd_effective}" | grep -Fqx "${key} ${expected}" || \
			fail "sshd efetivo inesperado: ${key} deve ser ${expected}"
	}
	assert_sshd_value passwordauthentication no
	assert_sshd_value kbdinteractiveauthentication no
	# sshd normaliza "prohibit-password" para o nome historico abaixo.
	assert_sshd_value permitrootlogin without-password
	systemctl reload ssh
	log 'SSH endurecido: root somente por chave'
}

swap_is_active() {
	swapon --show=NAME --noheadings | awk '$1 == "/swapfile" { found=1 } END { exit !found }'
}

configure_swap() {
	local needs_recreate=false
	local fstab_tmp

	if [[ ! -e /swapfile || ! -f /swapfile ]]; then
		needs_recreate=true
	elif [[ "$(stat -c %F /swapfile)" != 'regular file' || \
		"$(stat -c %s /swapfile)" != "${swap_size_bytes}" ]]; then
		needs_recreate=true
	fi

	if [[ "${needs_recreate}" == true ]]; then
		log 'Recriando swap regular de 2 GiB'
		if swap_is_active; then
			swapoff /swapfile
		fi
		rm -f /swapfile /swapfile.new
		fallocate -l "${swap_size_bytes}" /swapfile.new || \
			dd if=/dev/zero of=/swapfile.new bs=1M count=2048 status=progress
		[[ -f /swapfile.new && "$(stat -c %s /swapfile.new)" == "${swap_size_bytes}" ]] || \
			fail 'nao foi possivel criar swap regular de 2 GiB'
		chmod 600 /swapfile.new
		mkswap /swapfile.new >/dev/null
		mv /swapfile.new /swapfile
	elif ! swap_is_active && [[ "$(blkid -p -s TYPE -o value /swapfile 2>/dev/null || true)" != swap ]]; then
		chmod 600 /swapfile
		mkswap /swapfile >/dev/null
	fi

	chmod 600 /swapfile
	fstab_tmp="$(mktemp)"
	awk '$1 != "/swapfile"' /etc/fstab >"${fstab_tmp}"
	printf '/swapfile none swap sw 0 0\n' >>"${fstab_tmp}"
	cat "${fstab_tmp}" >/etc/fstab
	rm -f "${fstab_tmp}"

	if ! swap_is_active; then
		swapon /swapfile
	fi
	[[ -f /swapfile && "$(stat -c %F /swapfile)" == 'regular file' ]] || \
		fail '/swapfile nao e arquivo regular'
	[[ "$(stat -c %s /swapfile)" == "${swap_size_bytes}" ]] || \
		fail '/swapfile nao tem 2 GiB exatos'
	swap_is_active || fail '/swapfile nao ficou ativa'
}

verify_docker_firewall_dependencies() {
	local unit load_state requires after
	for unit in docker.service docker.socket; do
		load_state="$(systemctl show "${unit}" --property=LoadState --value)"
		if [[ "${unit}" == docker.socket && "${load_state}" == not-found ]]; then
			continue
		fi
		[[ "${load_state}" == loaded ]] || fail "unidade ${unit} nao carregada: ${load_state}"
		requires="$(systemctl show "${unit}" --property=Requires --value)"
		after="$(systemctl show "${unit}" --property=After --value)"
		grep -qw 'tabuamare-cloudflare-firewall.service' <<<"${requires}" || \
			fail "${unit} nao requer tabuamare-cloudflare-firewall.service"
		grep -qw 'tabuamare-cloudflare-firewall.service' <<<"${after}" || \
			fail "${unit} nao aguarda tabuamare-cloudflare-firewall.service"
	done
}

set_env_value() {
	local key="$1"
	local value="$2"
	local env_file="${coolify_source}/.env"
	if grep -q "^${key}=" "${env_file}"; then
		sed -i "s|^${key}=.*|${key}=${value}|" "${env_file}"
	else
		printf '\n%s=%s\n' "${key}" "${value}" >>"${env_file}"
	fi
}

if [[ "${1:-}" == --harden-ssh ]]; then
	harden_ssh
	exit 0
fi
[[ "$#" -eq 0 ]] || fail 'opcao desconhecida'

# Arquivo padrao do sistema alvo.
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID}" == ubuntu && "${VERSION_ID}" == 24.04 ]] || \
	fail "Ubuntu 24.04 obrigatorio; encontrado ${ID} ${VERSION_ID}"

export DEBIAN_FRONTEND=noninteractive
log 'Atualizando Ubuntu e instalando dependencias'
apt-get update
apt-get -y dist-upgrade
apt-get install -y --no-install-recommends \
	ca-certificates curl fail2ban ipset iptables jq openssl tzdata

# Protege a origem antes de qualquer instalador poder publicar portas.
firewall_source="${script_dir}/cloudflare-origin-firewall.sh"
[[ -f "${firewall_source}" ]] || fail 'cloudflare-origin-firewall.sh ausente ao lado do bootstrap'
install -m 0755 "${firewall_source}" /usr/local/sbin/tabuamare-cloudflare-firewall
/usr/local/sbin/tabuamare-cloudflare-firewall --install-systemd

timedatectl set-timezone America/Sao_Paulo

install -d -m 0755 /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/sshd.local <<'FAIL2BAN'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
FAIL2BAN
systemctl enable --now fail2ban
systemctl restart fail2ban

configure_swap
printf 'vm.swappiness=10\n' >/etc/sysctl.d/99-tabua-mare.conf
sysctl --system >/dev/null

install -d -m 0700 /root/.config/tabua-mare

current_image=''
if command -v docker >/dev/null 2>&1 && docker inspect coolify >/dev/null 2>&1; then
	current_image="$(docker inspect coolify --format '{{.Config.Image}}')"
fi
if [[ "${current_image}" != "${coolify_image}" ]]; then
	log "Instalando Coolify ${COOLIFY_VERSION} pelo instalador oficial"
	installer="$(mktemp)"
	trap 'rm -f "${installer:-}"' EXIT
	curl -fsSL https://cdn.coollabs.io/coolify/install.sh -o "${installer}"
	bash "${installer}" "${COOLIFY_VERSION}"
	rm -f "${installer}"
	trap - EXIT
fi

systemctl daemon-reload
verify_docker_firewall_dependencies

[[ -f "${coolify_source}/.env" ]] || fail 'Coolify nao criou .env de producao'
set_env_value LATEST_IMAGE "${COOLIFY_VERSION}"
set_env_value AUTOUPDATE false

log 'Aplicando AUTOUPDATE=false no Coolify'
docker compose \
	--env-file "${coolify_source}/.env" \
	-f "${coolify_source}/docker-compose.yml" \
	-f "${coolify_source}/docker-compose.prod.yml" \
	up -d --no-deps --force-recreate coolify

for _ in $(seq 1 60); do
	if [[ "$(docker inspect coolify --format '{{.State.Health.Status}}' 2>/dev/null || true)" == healthy ]]; then
		break
	fi
	sleep 2
done
[[ "$(docker inspect coolify --format '{{.State.Health.Status}}' 2>/dev/null || true)" == healthy ]] || \
	fail 'container Coolify nao ficou healthy'
docker exec coolify php artisan app:init >/dev/null

current_image="$(docker inspect coolify --format '{{.Config.Image}}')"
[[ "${current_image}" == "${coolify_image}" ]] || \
	fail "versao Coolify inesperada: ${current_image}"

log "Coolify ${COOLIFY_VERSION} pronto; cadastro inicial somente via tunnel SSH localhost:8000"
log 'Proximo: criar admin, token Cloudflare e duas aplicacoes; nao endurecer SSH antes de validar nova conexao por chave'
