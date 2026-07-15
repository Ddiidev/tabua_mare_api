#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
middleware="${root_dir}/shareds/rate_limit/middleware.v"
auth="${root_dir}/auth_controller.v"
api_v2="${root_dir}/api_v2.v"
pool="${root_dir}/shareds/infradb_pg/infradb_pg.v"
main="${root_dir}/main.v"

grep -Fq 'max_open_conns:    5' "${pool}" || {
	echo 'FAIL: max_open_conns do pool PostgreSQL nao e 5' >&2
	exit 1
}
grep -Fq 'max_idle_conns:    2' "${pool}" || {
	echo 'FAIL: max_idle_conns do pool PostgreSQL nao e 2' >&2
	exit 1
}
grep -Fq 'conn_max_lifetime: 30 * time.minute' "${pool}" || {
	echo 'FAIL: conn_max_lifetime do pool PostgreSQL nao e 30 minutos' >&2
	exit 1
}
grep -Fq 'pg_holder.close()' "${main}" || {
	echo 'FAIL: pool PostgreSQL nao e fechado no shutdown' >&2
	exit 1
}
grep -Fq 'PostgreSQL pool inicializado: max_open_conns=5 max_idle_conns=2 conn_max_lifetime=30m' "${main}" || {
	echo 'FAIL: log seguro de inicializacao do pool ausente' >&2
	exit 1
}

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
if grep -Fq 'ac.close_db(mut db)' "${auth}"; then
	echo 'FAIL: AuthController ainda fecha o pool compartilhado por request' >&2
	exit 1
fi
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
for request_file in "${middleware}" "${auth}" "${api_v2}"; do
	if grep -Fq 'db.close()' "${request_file}"; then
		echo "FAIL: ${request_file} fecha PostgreSQL por request" >&2
		exit 1
	fi
done
echo 'PASS: pool PostgreSQL compartilhado configurado'
