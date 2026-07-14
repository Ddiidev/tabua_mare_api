#!/usr/bin/env bash
set -euo pipefail

readonly cf4_set='tabuamare_cf4'
readonly cf6_set='tabuamare_cf6'
readonly cf4_stage='tabuamare_cf4_stage'
readonly cf6_stage='tabuamare_cf6_stage'
readonly filter_chain='TABUAMARE-CF'
readonly admin_ports='8000,6001,6002'

log() {
	printf '[firewall] %s\n' "$*"
}

fail() {
	printf '[firewall] ERRO: %s\n' "$*" >&2
	exit 1
}

[[ "${EUID}" -eq 0 ]] || fail 'execute como root'

fetch_ranges() {
	local url="$1"
	local output="$2"
	curl -fsSL --retry 3 --connect-timeout 10 "${url}" -o "${output}"
	grep -Eq '^[0-9a-fA-F:.]+/[0-9]+$' "${output}" || fail "lista invalida: ${url}"
}

refresh_set() {
	local family="$1"
	local active="$2"
	local stage="$3"
	local ranges="$4"
	ipset create "${active}" hash:net family "${family}" -exist
	ipset create "${stage}" hash:net family "${family}" -exist
	ipset flush "${stage}"
	while IFS= read -r range; do
		[[ -n "${range}" ]] && ipset add "${stage}" "${range}"
	done <"${ranges}"
	[[ "$(ipset list "${stage}" | awk '/Number of entries:/ {print $4}')" -gt 0 ]] || \
		fail "set ${stage} vazio"
	ipset swap "${stage}" "${active}"
	ipset destroy "${stage}"
}

ensure_jump() {
	local tool="$1"
	"${tool}" -w -nL DOCKER-USER >/dev/null 2>&1 || "${tool}" -w -N DOCKER-USER
	"${tool}" -w -C FORWARD -j DOCKER-USER >/dev/null 2>&1 || \
		"${tool}" -w -I FORWARD 1 -j DOCKER-USER
	"${tool}" -w -nL "${filter_chain}" >/dev/null 2>&1 || "${tool}" -w -N "${filter_chain}"
	"${tool}" -w -C DOCKER-USER -j "${filter_chain}" >/dev/null 2>&1 || \
		"${tool}" -w -I DOCKER-USER 1 -j "${filter_chain}"
}

configure_rules() {
	local tool="$1"
	local cf_set="$2"
	ensure_jump "${tool}"
	"${tool}" -w -F "${filter_chain}"
	"${tool}" -w -A "${filter_chain}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
	"${tool}" -w -A "${filter_chain}" -i lo -j ACCEPT
	IFS=',' read -r -a ports <<<"${admin_ports}"
	for port in "${ports[@]}"; do
		"${tool}" -w -A "${filter_chain}" -p tcp -m conntrack \
			--ctdir ORIGINAL --ctorigdstport "${port}" -j DROP
	done
	"${tool}" -w -A "${filter_chain}" -p tcp -m multiport --dports 80,443 \
		-m set --match-set "${cf_set}" src -j ACCEPT
	"${tool}" -w -A "${filter_chain}" -p tcp -m multiport --dports 80,443 -j DROP
	"${tool}" -w -A "${filter_chain}" -p udp --dport 443 \
		-m set --match-set "${cf_set}" src -j ACCEPT
	"${tool}" -w -A "${filter_chain}" -p udp --dport 443 -j DROP
	"${tool}" -w -A "${filter_chain}" -j RETURN
}

ensure_input_jump() {
	local tool="$1"
	local cf_set="$2"
	local chain="${filter_chain}-IN"
	"${tool}" -w -nL "${chain}" >/dev/null 2>&1 || "${tool}" -w -N "${chain}"
	"${tool}" -w -C INPUT -j "${chain}" >/dev/null 2>&1 || "${tool}" -w -I INPUT 1 -j "${chain}"
	"${tool}" -w -F "${chain}"
	"${tool}" -w -A "${chain}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
	"${tool}" -w -A "${chain}" -i lo -j ACCEPT
	"${tool}" -w -A "${chain}" -p tcp -m multiport --dports "${admin_ports}" -j DROP
	"${tool}" -w -A "${chain}" -p tcp -m multiport --dports 80,443 \
		-m set --match-set "${cf_set}" src -j ACCEPT
	"${tool}" -w -A "${chain}" -p tcp -m multiport --dports 80,443 -j DROP
	"${tool}" -w -A "${chain}" -p udp --dport 443 \
		-m set --match-set "${cf_set}" src -j ACCEPT
	"${tool}" -w -A "${chain}" -p udp --dport 443 -j DROP
	"${tool}" -w -A "${chain}" -j RETURN
}

apply_firewall() {
	command -v ipset >/dev/null 2>&1 || fail 'ipset nao instalado'
	command -v iptables >/dev/null 2>&1 || fail 'iptables nao instalado'
	tmp_dir="$(mktemp -d)"
	trap 'rm -rf "${tmp_dir:-}"' EXIT
	fetch_ranges https://www.cloudflare.com/ips-v4 "${tmp_dir}/ips-v4"
	fetch_ranges https://www.cloudflare.com/ips-v6 "${tmp_dir}/ips-v6"
	refresh_set inet "${cf4_set}" "${cf4_stage}" "${tmp_dir}/ips-v4"
	refresh_set inet6 "${cf6_set}" "${cf6_stage}" "${tmp_dir}/ips-v6"
	configure_rules iptables "${cf4_set}"
	ensure_input_jump iptables "${cf4_set}"
	if command -v ip6tables >/dev/null 2>&1; then
		configure_rules ip6tables "${cf6_set}"
		ensure_input_jump ip6tables "${cf6_set}"
	fi
	rm -rf "${tmp_dir}"
	trap - EXIT
	log '80/443 limitadas a Cloudflare; 8000/6001/6002 bloqueadas externamente'
}

install_systemd() {
	cat >/etc/systemd/system/tabuamare-cloudflare-firewall.service <<'SERVICE'
[Unit]
Description=Atualiza ranges Cloudflare e protege origem Tábua de Marés
Wants=network-online.target docker.service
After=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/tabuamare-cloudflare-firewall --apply
SERVICE
	cat >/etc/systemd/system/tabuamare-cloudflare-firewall.timer <<'TIMER'
[Unit]
Description=Atualização diária dos ranges Cloudflare

[Timer]
OnBootSec=2min
OnUnitActiveSec=1d
RandomizedDelaySec=30min
Persistent=true
Unit=tabuamare-cloudflare-firewall.service

[Install]
WantedBy=timers.target
TIMER
	systemctl daemon-reload
	systemctl enable --now tabuamare-cloudflare-firewall.timer
}

case "${1:---apply}" in
	--apply)
		apply_firewall
		;;
	--install-systemd)
		apply_firewall
		install_systemd
		;;
	*)
		fail 'uso: cloudflare-origin-firewall.sh [--apply|--install-systemd]'
		;;
esac
