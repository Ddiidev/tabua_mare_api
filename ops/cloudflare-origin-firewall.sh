#!/usr/bin/env bash
set -euo pipefail

readonly cf4_set='tabuamare_cf4'
readonly cf6_set='tabuamare_cf6'
readonly cf4_stage='tabuamare_cf4_stage'
readonly cf6_stage='tabuamare_cf6_stage'
readonly filter_chain='TABUAMARE-CF'
readonly forward_chain="${filter_chain}-V2"
readonly input_chain="${filter_chain}-IN-V2"
readonly legacy_input_chain="${filter_chain}-IN"
readonly admin_ports='8000,6001,6002'
readonly cache_dir='/var/lib/tabuamare-cloudflare-firewall'
readonly cache_v4="${cache_dir}/ips-v4"
readonly cache_v6="${cache_dir}/ips-v6"
readonly public_iface='eth0'

log() {
	printf '[firewall] %s\n' "$*"
}

fail() {
	printf '[firewall] ERRO: %s\n' "$*" >&2
	exit 1
}

validate_ranges_file() {
	local file="$1"
	awk '
		BEGIN { valid=1; entries=0 }
		NF {
			entries++
			if ($0 !~ /^[0-9a-fA-F:.]+\/[0-9]+$/) valid=0
		}
		END { exit !(valid && entries > 0) }
	' "${file}"
}

fetch_ranges() {
	local url="$1"
	local output="$2"
	curl -fsSL --retry 3 --connect-timeout 10 "${url}" -o "${output}" || return 1
	validate_ranges_file "${output}"
}

ensure_sets() {
	ipset create "${cf4_set}" hash:net family inet -exist
	ipset create "${cf6_set}" hash:net family inet6 -exist
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

ensure_forward_parent() {
	local tool="$1"
	"${tool}" -w -nL DOCKER-USER >/dev/null 2>&1 || "${tool}" -w -N DOCKER-USER
	"${tool}" -w -C FORWARD -j DOCKER-USER >/dev/null 2>&1 || \
		"${tool}" -w -I FORWARD 1 -j DOCKER-USER
}

chain_is_referenced() {
	local tool="$1"
	local candidate="$2"
	local rules
	rules="$("${tool}" -w -S)" || fail "falha ao enumerar referencias da cadeia ${candidate}"
	grep -Fq -- "-j ${candidate}" <<<"${rules}"
}

reset_unreferenced_generation() {
	local tool="$1"
	local candidate="$2"
	if "${tool}" -w -nL "${candidate}" >/dev/null 2>&1; then
		# O chamador so chega aqui depois de provar que nao existe referencia ativa.
		if chain_is_referenced "${tool}" "${candidate}"; then
			fail "cadeia passou a ser referenciada; recusando flush: ${candidate}"
		fi
		"${tool}" -w -F "${candidate}"
		"${tool}" -w -X "${candidate}"
	fi
	"${tool}" -w -N "${candidate}"
}

activate_chain() {
	local tool="$1"
	local parent="$2"
	local candidate="$3"
	local legacy="$4"
	# Insere a nova cadeia completa primeiro. Falha posterior mantem as duas protecoes.
	"${tool}" -w -C "${parent}" -j "${candidate}" >/dev/null 2>&1 || \
		"${tool}" -w -I "${parent}" 1 -j "${candidate}"
	while "${tool}" -w -C "${parent}" -j "${legacy}" >/dev/null 2>&1; do
		"${tool}" -w -D "${parent}" -j "${legacy}"
	done
}

configure_rules() {
	local tool="$1"
	local cf_set="$2"
	local -a ports
	ensure_forward_parent "${tool}"
	if ! chain_is_referenced "${tool}" "${forward_chain}"; then
		reset_unreferenced_generation "${tool}" "${forward_chain}"
		"${tool}" -w -A "${forward_chain}" -i lo -j ACCEPT
		IFS=',' read -r -a ports <<<"${admin_ports}"
		for port in "${ports[@]}"; do
			"${tool}" -w -A "${forward_chain}" -p tcp -m conntrack \
				--ctdir ORIGINAL --ctorigdstport "${port}" -j DROP
		done
		"${tool}" -w -A "${forward_chain}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
		"${tool}" -w -A "${forward_chain}" -i "${public_iface}" -p tcp -m multiport --dports 80,443 \
			-m set --match-set "${cf_set}" src -j ACCEPT
		"${tool}" -w -A "${forward_chain}" -i "${public_iface}" -p tcp -m multiport --dports 80,443 -j DROP
		"${tool}" -w -A "${forward_chain}" -i "${public_iface}" -p udp --dport 443 \
			-m set --match-set "${cf_set}" src -j ACCEPT
		"${tool}" -w -A "${forward_chain}" -i "${public_iface}" -p udp --dport 443 -j DROP
		"${tool}" -w -A "${forward_chain}" -j RETURN
	fi
	activate_chain "${tool}" DOCKER-USER "${forward_chain}" "${filter_chain}"
}

configure_input_rules() {
	local tool="$1"
	local cf_set="$2"
	if ! chain_is_referenced "${tool}" "${input_chain}"; then
		reset_unreferenced_generation "${tool}" "${input_chain}"
		"${tool}" -w -A "${input_chain}" -i lo -j ACCEPT
		"${tool}" -w -A "${input_chain}" -p tcp -m multiport --dports "${admin_ports}" -j DROP
		"${tool}" -w -A "${input_chain}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
		"${tool}" -w -A "${input_chain}" -p tcp -m multiport --dports 80,443 \
			-m set --match-set "${cf_set}" src -j ACCEPT
		"${tool}" -w -A "${input_chain}" -p tcp -m multiport --dports 80,443 -j DROP
		"${tool}" -w -A "${input_chain}" -p udp --dport 443 \
			-m set --match-set "${cf_set}" src -j ACCEPT
		"${tool}" -w -A "${input_chain}" -p udp --dport 443 -j DROP
		"${tool}" -w -A "${input_chain}" -j RETURN
	fi
	activate_chain "${tool}" INPUT "${input_chain}" "${legacy_input_chain}"
}

configure_fail_closed_rules() {
	command -v ipset >/dev/null 2>&1 || fail 'ipset nao instalado'
	command -v iptables >/dev/null 2>&1 || fail 'iptables nao instalado'
	ensure_sets
	configure_rules iptables "${cf4_set}"
	configure_input_rules iptables "${cf4_set}"
	if command -v ip6tables >/dev/null 2>&1; then
		configure_rules ip6tables "${cf6_set}"
		configure_input_rules ip6tables "${cf6_set}"
	fi
}

cache_is_valid() {
	[[ -s "${cache_v4}" && -s "${cache_v6}" ]] || return 1
	validate_ranges_file "${cache_v4}" && validate_ranges_file "${cache_v6}"
}

load_range_files() {
	local ipv4_file="$1"
	local ipv6_file="$2"
	refresh_set inet "${cf4_set}" "${cf4_stage}" "${ipv4_file}"
	refresh_set inet6 "${cf6_set}" "${cf6_stage}" "${ipv6_file}"
}

restore_cache() {
	configure_fail_closed_rules
	if cache_is_valid; then
		load_range_files "${cache_v4}" "${cache_v6}"
		log 'ranges Cloudflare restaurados do cache last-known-good'
	else
		ipset flush "${cf4_set}"
		ipset flush "${cf6_set}"
		log 'cache ausente; 80/443 permanecem bloqueadas para todas as origens'
	fi
}

save_cache() {
	local ipv4_file="$1"
	local ipv6_file="$2"
	install -d -m 0700 "${cache_dir}"
	install -m 0600 "${ipv4_file}" "${cache_v4}.new"
	install -m 0600 "${ipv6_file}" "${cache_v6}.new"
	mv "${cache_v4}.new" "${cache_v4}"
	mv "${cache_v6}.new" "${cache_v6}"
}

refresh_firewall() {
	local tmp_dir
	restore_cache
	tmp_dir="$(mktemp -d)"
	trap 'rm -rf "${tmp_dir:-}"' EXIT
	if fetch_ranges https://www.cloudflare.com/ips-v4 "${tmp_dir}/ips-v4" && \
		fetch_ranges https://www.cloudflare.com/ips-v6 "${tmp_dir}/ips-v6"; then
		load_range_files "${tmp_dir}/ips-v4" "${tmp_dir}/ips-v6"
		save_cache "${tmp_dir}/ips-v4" "${tmp_dir}/ips-v6"
		log 'ranges Cloudflare atualizados e salvos no cache last-known-good'
	elif cache_is_valid; then
		log 'download falhou; mantendo ranges last-known-good' >&2
	else
		fail 'download dos ranges falhou; origem permanece bloqueada sem cache'
	fi
	rm -rf "${tmp_dir}"
	trap - EXIT
	log '80/443 limitadas a Cloudflare; 8000/6001/6002 bloqueadas externamente'
}

install_systemd() {
	cat >/etc/systemd/system/tabuamare-cloudflare-firewall.service <<'SERVICE'
[Unit]
Description=Protege origem Tábua de Marés antes dos serviços web
DefaultDependencies=no
After=local-fs.target
Before=docker.service docker.socket coolify.service
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/tabuamare-cloudflare-firewall --restore-cache
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE
	install -d -m 0755 \
		/etc/systemd/system/docker.service.d \
		/etc/systemd/system/docker.socket.d
	cat >/etc/systemd/system/docker.service.d/10-tabua-mare-firewall.conf <<'DROPIN'
[Unit]
Requires=tabuamare-cloudflare-firewall.service
After=tabuamare-cloudflare-firewall.service
DROPIN
	cat >/etc/systemd/system/docker.socket.d/10-tabua-mare-firewall.conf <<'DROPIN'
[Unit]
Requires=tabuamare-cloudflare-firewall.service
After=tabuamare-cloudflare-firewall.service
DROPIN
	cat >/etc/systemd/system/tabuamare-cloudflare-firewall-refresh.service <<'SERVICE'
[Unit]
Description=Atualiza ranges Cloudflare da origem Tábua de Marés
Wants=network-online.target
After=network-online.target tabuamare-cloudflare-firewall.service
Requires=tabuamare-cloudflare-firewall.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/tabuamare-cloudflare-firewall --refresh
SERVICE
	cat >/etc/systemd/system/tabuamare-cloudflare-firewall.timer <<'TIMER'
[Unit]
Description=Atualização diária dos ranges Cloudflare

[Timer]
OnBootSec=30s
OnUnitActiveSec=1d
RandomizedDelaySec=30min
Persistent=true
Unit=tabuamare-cloudflare-firewall-refresh.service

[Install]
WantedBy=timers.target
TIMER
	systemctl daemon-reload
	systemctl enable --now tabuamare-cloudflare-firewall.service
	/usr/local/sbin/tabuamare-cloudflare-firewall --refresh
	systemctl enable --now tabuamare-cloudflare-firewall.timer
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	[[ "${EUID}" -eq 0 ]] || fail 'execute como root'
	case "${1:---apply}" in
		--apply|--refresh)
			refresh_firewall
			;;
		--restore-cache)
			restore_cache
			;;
		--install-systemd)
			install_systemd
			;;
		*)
			fail 'uso: cloudflare-origin-firewall.sh [--restore-cache|--refresh|--install-systemd]'
			;;
	esac
fi
