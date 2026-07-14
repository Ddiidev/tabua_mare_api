#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ops/cloudflare-origin-firewall.sh
source "${root_dir}/ops/cloudflare-origin-firewall.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

printf '173.245.48.0/20\n2400:cb00::/32\n' >"${tmp_dir}/valid"
printf '173.245.48.0/20\nconteudo-invalido\n' >"${tmp_dir}/invalid"
: >"${tmp_dir}/empty"

validate_ranges_file "${tmp_dir}/valid"
if validate_ranges_file "${tmp_dir}/invalid"; then
	printf 'FAIL: lista malformada foi aceita\n' >&2
	exit 1
fi
if validate_ranges_file "${tmp_dir}/empty"; then
	printf 'FAIL: lista vazia foi aceita\n' >&2
	exit 1
fi

printf 'PASS: validacao de ranges Cloudflare\n'
