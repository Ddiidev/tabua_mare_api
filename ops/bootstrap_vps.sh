#!/usr/bin/env bash
set -euo pipefail

readonly COOLIFY_VERSION='4.1.2'
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
	[[ "${CONFIRM_KEY_CONNECTION:-}" == yes ]] || \
		fail 'valide outra conexao por chave e execute com CONFIRM_KEY_CONNECTION=yes'
	install -d -m 0755 /etc/ssh/sshd_config.d
	cat >/etc/ssh/sshd_config.d/99-tabua-mare.conf <<'SSH'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
SSH
	sshd -t
	systemctl reload ssh
	log 'SSH endurecido: root somente por chave'
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

if [[ ! -f /swapfile ]]; then
	log 'Criando swap de 2 GiB'
	fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
	chmod 600 /swapfile
	mkswap /swapfile >/dev/null
fi
grep -qF '/swapfile none swap sw 0 0' /etc/fstab || \
	printf '/swapfile none swap sw 0 0\n' >>/etc/fstab
swapon /swapfile 2>/dev/null || true
printf 'vm.swappiness=10\n' >/etc/sysctl.d/99-tabua-mare.conf
sysctl --system >/dev/null

install -d -m 0700 /root/.config/tabua-mare

current_image=''
if command -v docker >/dev/null 2>&1 && docker inspect coolify >/dev/null 2>&1; then
	current_image="$(docker inspect coolify --format '{{.Config.Image}}')"
fi
if [[ "${current_image}" != *":${COOLIFY_VERSION}" ]]; then
	log "Instalando Coolify ${COOLIFY_VERSION} pelo instalador oficial"
	installer="$(mktemp)"
	trap 'rm -f "${installer:-}"' EXIT
	curl -fsSL https://cdn.coollabs.io/coolify/install.sh -o "${installer}"
	bash "${installer}" "${COOLIFY_VERSION}"
	rm -f "${installer}"
	trap - EXIT
fi

[[ -f "${coolify_source}/.env" ]] || fail 'Coolify nao criou .env de producao'
if grep -q '^AUTOUPDATE=' "${coolify_source}/.env"; then
	sed -i 's/^AUTOUPDATE=.*/AUTOUPDATE=false/' "${coolify_source}/.env"
else
	printf '\nAUTOUPDATE=false\n' >>"${coolify_source}/.env"
fi

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
[[ "${current_image}" == *":${COOLIFY_VERSION}" ]] || \
	fail "versao Coolify inesperada: ${current_image}"

firewall_source="${script_dir}/cloudflare-origin-firewall.sh"
[[ -f "${firewall_source}" ]] || fail 'cloudflare-origin-firewall.sh ausente ao lado do bootstrap'
install -m 0755 "${firewall_source}" /usr/local/sbin/tabuamare-cloudflare-firewall
/usr/local/sbin/tabuamare-cloudflare-firewall --install-systemd

log "Coolify ${COOLIFY_VERSION} pronto; cadastro inicial somente via tunnel SSH localhost:8000"
log 'Proximo: criar admin, token Cloudflare e duas aplicacoes; nao endurecer SSH antes de validar nova conexao por chave'
