#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dockerfile="${root_dir}/Dockerfile"
entrypoint="${root_dir}/dockerfiles/entrypoint-alpine.sh"
dockerignore="${root_dir}/.dockerignore"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

grep -Fq 'VOLUME ["/app/data"]' "${dockerfile}" || fail '/app/data sem VOLUME declarado'
grep -Fq 'ENV V_COMMIT=45ae01d23168b6372f734eeb38a77360bbcf184a' "${dockerfile}" || \
	fail 'commit V nao esta fixado por ENV no builder'
grep -Fq 'VC_COMMIT=7eb8c54a3843e5107d5af06d7a8c3e928f322475' "${dockerfile}" || \
	fail 'commit VC correspondente nao esta fixado por ENV no builder'
if grep -Eq '^ARG (V|VC|VEEMARKER|DOTENV|V_STRIPE)_COMMIT=' "${dockerfile}"; then
	fail 'pin de dependencia pode ser sobrescrito por build-arg'
fi
if grep -Eq 'chown (app:app|10001:10001).* /app/seed' "${dockerfile}"; then
	fail '/app/seed nao pode pertencer ao usuario da aplicacao'
fi
grep -Fq 'chown -R root:root /app/seed' "${dockerfile}" || fail '/app/seed nao esta root-owned'
grep -Fq 'trap cleanup EXIT' "${entrypoint}" || fail 'cleanup EXIT ausente'
grep -Fq "trap 'exit 143' TERM" "${entrypoint}" || fail 'SIGTERM nao encerra preparacao'
grep -Fxq '!/taubinha.sqlite' "${dockerignore}" || fail 'excecao do seed deve ser ancorada na raiz'

printf 'PASS: pin imutavel, volume, seed root-only e traps\n'
