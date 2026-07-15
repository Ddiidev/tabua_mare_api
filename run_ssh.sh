#!/usr/bin/env bash
set -euo pipefail
set +x

readonly ssh_host="${SSH_VPS_HOST:-167.148.161.67}"
readonly ssh_user="${SSH_VPS_USER:-root}"
readonly ssh_port="${SSH_VPS_PORT:-22}"
readonly env_file="${SSH_ENV_FILE:-${HOME}/.config/tabua-mare/ssh.env}"
readonly windows_ssh="${SSH_WINDOWS_BIN:-/mnt/c/Windows/System32/OpenSSH/ssh.exe}"
readonly windows_key_wsl="${SSH_KEY_WINDOWS_WSL:-/mnt/c/Users/andre/.ssh/tabua-api}"
readonly windows_key="${SSH_KEY_WINDOWS:-C:\Users\andre\.ssh\tabua-api}"
readonly linux_key="${SSH_KEY_LINUX:-${HOME}/.ssh/tabua-api}"
readonly linux_ssh="${SSH_BIN:-ssh}"
readonly sshpass_bin="${SSHPASS_BIN:-sshpass}"
readonly target="${ssh_user}@${ssh_host}"

fail() {
	printf 'ERRO: %s\n' "$*" >&2
	exit 1
}

if [[ -f "${env_file}" ]]; then
	mode="$(stat -c '%a' "${env_file}")"
	[[ "${mode}" =~ ^[0-7]00$ ]] || fail "permissao insegura em ${env_file}; use chmod 600"
	# Caminho configuravel, fora do repositorio.
	# shellcheck disable=SC1090
	source "${env_file}"
fi

common_options=(
	-p "${ssh_port}"
	-o ConnectTimeout=15
	-o ServerAliveInterval=30
	-o ServerAliveCountMax=3
	-o StrictHostKeyChecking=accept-new
)

method=''
if [[ -x "${windows_ssh}" && -f "${windows_key_wsl}" ]]; then
	method='windows-key'
elif command -v "${linux_ssh}" >/dev/null 2>&1 && [[ -f "${linux_key}" ]]; then
	key_mode="$(stat -c '%a' "${linux_key}")"
	[[ "${key_mode}" =~ ^[0-7]00$ ]] || fail "permissao insegura em ${linux_key}; use chmod 600"
	method='linux-key'
elif [[ -n "${SSH_PASS_VPS:-}" ]] && { [[ -x "${sshpass_bin}" ]] || command -v "${sshpass_bin}" >/dev/null 2>&1; }; then
	method='password-fallback'
else
	fail 'nenhuma chave utilizavel e fallback SSH_PASS_VPS/sshpass indisponivel'
fi

if [[ "${1:-}" == --dry-run ]]; then
	case "${method}" in
		windows-key) printf 'method=windows-key host=%s identity=%s\n' "${target}" "${windows_key}" ;;
		linux-key) printf 'method=linux-key host=%s identity=%s\n' "${target}" "${linux_key}" ;;
		password-fallback) printf 'method=password-fallback host=%s env=%s\n' "${target}" "${env_file}" ;;
	esac
	exit 0
fi

ssh_extra=()
remote_command=()
parsing_remote=0
for arg in "$@"; do
	if [[ "${arg}" == -- && "${parsing_remote}" == 0 ]]; then
		parsing_remote=1
		continue
	fi
	if [[ "${parsing_remote}" == 0 ]]; then
		ssh_extra+=("${arg}")
	else
		remote_command+=("${arg}")
	fi
done

case "${method}" in
	windows-key)
		exec "${windows_ssh}" "${common_options[@]}" -i "${windows_key}" \
			"${ssh_extra[@]}" "${target}" "${remote_command[@]}"
		;;
	linux-key)
		exec "${linux_ssh}" "${common_options[@]}" -i "${linux_key}" \
			"${ssh_extra[@]}" "${target}" "${remote_command[@]}"
		;;
	password-fallback)
		SSHPASS="${SSH_PASS_VPS}" exec "${sshpass_bin}" -e "${linux_ssh}" \
			"${common_options[@]}" "${ssh_extra[@]}" "${target}" "${remote_command[@]}"
		;;
esac
