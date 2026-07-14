#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
old_domain='tabuamare.devtu.qzz.io'
new_origin='https://tabuamare.api.br'
active_paths=(
	Dockerfile
	.env.template
	README.md
	pages
	shareds
	requirment-v_stripe.md
)

cd "${root_dir}"

matches="$(grep -RInsF --exclude='*.png' --exclude='*.jpg' --exclude='*.ico' \
	"${old_domain}" "${active_paths[@]}" || true)"
if [[ -n "${matches}" ]]; then
	printf 'FAIL: dominio antigo em superficie ativa:\n%s\n' "${matches}" >&2
	exit 1
fi

grep -Fq "${new_origin}" README.md
grep -Fq "${new_origin}" pages/og.html
grep -Fq "URL_ENV=${new_origin}" .env.template
grep -Fq "GOOGLE_REDIRECT_URI=${new_origin}/auth/google/callback" .env.template
grep -Fq "${new_origin}/auth/webhook" .env.template
grep -Fq "ENV PORT=3330" Dockerfile
grep -Fq "URL_ENV=${new_origin}" Dockerfile

printf 'PASS: superficie ativa usa %s\n' "${new_origin}"
