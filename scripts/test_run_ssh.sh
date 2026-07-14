#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner="${root_dir}/run_ssh.sh"
tmp_dir="$(mktemp -d)"
secret='segredo-que-nao-pode-aparecer'

cleanup() {
	rm -rf "${tmp_dir}"
}
trap cleanup EXIT

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

[[ -x "${runner}" ]] || fail 'run_ssh.sh ausente ou nao executavel'

mkdir -p "${tmp_dir}/config" "${tmp_dir}/bin"
printf 'SSH_PASS_VPS=%q\n' "${secret}" >"${tmp_dir}/config/ssh.env"
chmod 600 "${tmp_dir}/config/ssh.env"
cat >"${tmp_dir}/bin/ssh.exe" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${SSH_CAPTURE_FILE:-/dev/null}"
SSH
printf '#!/usr/bin/env bash\nexit 0\n' >"${tmp_dir}/bin/sshpass"
chmod +x "${tmp_dir}/bin/ssh.exe" "${tmp_dir}/bin/sshpass"
touch "${tmp_dir}/tabua-api"
chmod 600 "${tmp_dir}/tabua-api"

output="$(
	SSH_ENV_FILE="${tmp_dir}/config/ssh.env" \
	SSH_WINDOWS_BIN="${tmp_dir}/bin/ssh.exe" \
	SSH_KEY_WINDOWS_WSL="${tmp_dir}/tabua-api" \
	SSH_KEY_WINDOWS='C:\Users\andre\.ssh\tabua-api' \
	"${runner}" --dry-run
)"
grep -Fq 'method=windows-key' <<<"${output}" || fail 'chave Windows nao foi priorizada'
if grep -Fq "${secret}" <<<"${output}"; then
	fail 'senha apareceu no dry-run com chave'
fi

SSH_CAPTURE_FILE="${tmp_dir}/ssh-args" \
	SSH_ENV_FILE="${tmp_dir}/config/ssh.env" \
	SSH_WINDOWS_BIN="${tmp_dir}/bin/ssh.exe" \
	SSH_KEY_WINDOWS_WSL="${tmp_dir}/tabua-api" \
	SSH_KEY_WINDOWS='C:\Users\andre\.ssh\tabua-api' \
	"${runner}" -N -L 8000:127.0.0.1:8000 -- printf connected
python3 - "${tmp_dir}/ssh-args" <<'PY'
import sys
args = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert args.index("-L") < args.index("root@167.148.161.67")
assert args.index("root@167.148.161.67") < args.index("printf")
PY

output="$(
	SSH_ENV_FILE="${tmp_dir}/config/ssh.env" \
	SSH_WINDOWS_BIN="${tmp_dir}/ausente" \
	SSH_KEY_LINUX="${tmp_dir}/ausente" \
	SSHPASS_BIN="${tmp_dir}/bin/sshpass" \
	"${runner}" --dry-run
)"
grep -Fq 'method=password-fallback' <<<"${output}" || fail 'fallback sshpass nao selecionado'
if grep -Fq "${secret}" <<<"${output}"; then
	fail 'senha apareceu no dry-run do fallback'
fi

printf 'PASS: SSH prioriza chave e fallback nao expoe senha\n'
