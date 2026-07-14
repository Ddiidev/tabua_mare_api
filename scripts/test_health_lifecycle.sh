#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
port=${HEALTH_TEST_PORT:-39119}
pid=''

cleanup() {
	if [ -n "$pid" ]; then
		kill -KILL "$pid" 2>/dev/null || true
	fi
	rm -rf "$tmp_dir"
}
trap cleanup EXIT

cd "$repo_dir"
cp taubinha.sqlite "$tmp_dir/taubinha.sqlite"
v -d new_veb -o "$tmp_dir/TabuaMareAPI" .

DB_SQLITE_PATH="$tmp_dir/taubinha.sqlite" \
	POSTGRESQL_CONN_STR='postgresql://health:health@127.0.0.1:1/health?connect_timeout=1' \
	"$tmp_dir/TabuaMareAPI" "$port" >"$tmp_dir/stdout.log" 2>"$tmp_dir/stderr.log" &
pid=$!

request_code() {
	local method=$1
	local path=$2
	if [ "$method" = HEAD ]; then
		curl -sSI -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}${path}" 2>/dev/null || true
	else
		curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}${path}" 2>/dev/null || true
	fi
}

ready_code=000
for _ in $(seq 1 300); do
	ready_code=$(request_code GET /health/ready)
	[ "$ready_code" = 204 ] && break
	sleep 0.05
done
[ "$ready_code" = 204 ]

live_get=$(request_code GET /health/live)
ready_get=$(request_code GET /health/ready)
live_head=$(request_code HEAD /health/live)
ready_head=$(request_code HEAD /health/ready)
ping_get=$(request_code GET /ping)

[ "$live_get" = 204 ]
[ "$ready_get" = 204 ]
[ "$live_head" = 204 ]
[ "$ready_head" = 204 ]
[ "$ping_get" = 204 ]

started=$(date +%s)
kill -TERM "$pid"

draining_ready=000
for _ in $(seq 1 100); do
	draining_ready=$(request_code GET /health/ready)
	[ "$draining_ready" = 503 ] && break
	sleep 0.05
done
[ "$draining_ready" = 503 ]

draining_live=$(request_code GET /health/live)
[ "$draining_live" = 204 ]

for _ in $(seq 1 300); do
	if ! kill -0 "$pid" 2>/dev/null; then
		break
	fi
	sleep 0.1
done
if kill -0 "$pid" 2>/dev/null; then
	printf 'server did not exit within 30 seconds\n' >&2
	exit 1
fi

set +e
wait "$pid"
exit_code=$?
set -e
pid=''
elapsed=$(($(date +%s) - started))

[ "$exit_code" -eq 0 ]
[ "$elapsed" -ge 6 ]
[ "$elapsed" -le 30 ]

printf 'health lifecycle ok: live=%s ready=%s head=%s/%s drain=%s/%s shutdown=%ss exit=%s\n' \
	"$live_get" "$ready_get" "$live_head" "$ready_head" "$draining_ready" "$draining_live" \
	"$elapsed" "$exit_code"
