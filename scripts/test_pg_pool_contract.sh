#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
middleware="${root_dir}/shareds/rate_limit/middleware.v"
auth="${root_dir}/auth_controller.v"
api_v2="${root_dir}/api_v2.v"

grep -Fq 'pg_holder &infradb_pg.PgHolder' "${middleware}" || {
	echo 'FAIL: rate-limit sem holder PostgreSQL compartilhado' >&2
	exit 1
}
if grep -Fq 'pg.connect_with_conninfo(connstr)' "${middleware}"; then
	echo 'FAIL: rate-limit ainda abre PostgreSQL por request' >&2
	exit 1
fi
grep -Eq 'pg_holder[[:space:]]+\??&infradb_pg\.PgHolder' "${auth}" || {
	echo 'FAIL: AuthController sem holder PostgreSQL compartilhado' >&2
	exit 1
}
grep -Fq 'ac.close_db(mut db)' "${auth}" || {
	echo 'FAIL: AuthController pode fechar o pool compartilhado por request' >&2
	exit 1
}
if grep -Fq 'defer { db.close()' "${auth}"; then
	echo 'FAIL: AuthController ainda fecha PostgreSQL compartilhado diretamente' >&2
	exit 1
fi
grep -Fq 'pg_holder &infradb_pg.PgHolder' "${api_v2}" || {
	echo 'FAIL: APIControllerV2 sem holder PostgreSQL compartilhado' >&2
	exit 1
}
if grep -Fq 'pg.connect_with_conninfo(connstr)' "${api_v2}"; then
	echo 'FAIL: endpoint usage ainda abre PostgreSQL por request' >&2
	exit 1
fi
echo 'PASS: pool PostgreSQL compartilhado configurado'
