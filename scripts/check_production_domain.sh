#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
old_domain='tabuamare.devtu.qzz.io'
new_origin='https://tabuamare.api.br'

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

cd "${root_dir}"

mapfile -t active_files < <(git ls-files | grep -Ev \
	'^(\.plans/|docs/superpowers/|scripts/check_production_domain\.sh$)')
matches="$(grep -InsIF "${old_domain}" "${active_files[@]}" || true)"
if [[ -n "${matches}" ]]; then
	printf 'FAIL: dominio antigo em superficie ativa:\n%s\n' "${matches}" >&2
	exit 1
fi

grep -Fq "${new_origin}" README.md || fail 'README sem nova origem'
grep -Fq "<meta property=\"og:url\" content=\"${new_origin}\" />" pages/og.html || fail 'og:url incorreto'
grep -Fq "<link rel=\"canonical\" href=\"${new_origin}\" />" pages/og.html || fail 'canonical incorreto'
grep -Fq "\"url\": \"${new_origin}\"" pages/og.html || fail 'JSON-LD url incorreta'
grep -Fxq "URL_ENV=${new_origin}" .env.template || fail 'URL_ENV de producao nao esta ativo'
grep -Fxq "GOOGLE_REDIRECT_URI=${new_origin}/auth/google/callback" .env.template || \
	fail 'callback Google de producao nao esta ativo'
grep -Fxq 'DB_SQLITE_PATH=/app/data/taubinha.sqlite' .env.template || fail 'SQLite de producao nao esta ativo'
grep -Fq "${new_origin}/auth/webhook" .env.template || fail 'webhook Stripe de producao ausente'
grep -Fq "ENV PORT=3330" Dockerfile || fail 'porta de producao ausente na imagem'
grep -Fq "URL_ENV=${new_origin}" Dockerfile || fail 'URL_ENV de producao ausente na imagem'

printf 'PASS: superficie ativa usa %s\n' "${new_origin}"
