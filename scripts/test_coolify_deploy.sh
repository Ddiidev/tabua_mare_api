#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deploy_script="${root_dir}/scripts/coolify_deploy.sh"
target_tag="sha-1111111111111111111111111111111111111111"
tmp_dir="$(mktemp -d)"
server_pid=''

cleanup() {
	if [[ -n "${server_pid}" ]]; then
		kill "${server_pid}" >/dev/null 2>&1 || true
		wait "${server_pid}" >/dev/null 2>&1 || true
	fi
	rm -rf "${tmp_dir}"
}
trap cleanup EXIT

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

[[ -x "${deploy_script}" ]] || fail 'scripts/coolify_deploy.sh ausente ou nao executavel'

mkdir -p "${tmp_dir}/bin"
cat >"${tmp_dir}/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 3 ]]
[[ "$1" == manifest ]]
[[ "$2" == inspect ]]
[[ "$3" == 'ghcr.io/ddiidev/tabua-mare-api:sha-1111111111111111111111111111111111111111' ]]
DOCKER
chmod +x "${tmp_dir}/bin/docker"

start_server() {
	local scenario="$1"
	local state_file="$2"
	local port_file="$3"
	python3 - "${state_file}" "${port_file}" "${scenario}" "${target_tag}" <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

state_path = Path(sys.argv[1])
port_path = Path(sys.argv[2])
scenario = sys.argv[3]
target_tag = sys.argv[4]
state = {
    "apps": {
        "app-a": {"docker_registry_image_tag": "sha-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "status": "running:healthy"},
        "app-b": {"docker_registry_image_tag": "sha-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "status": "running:healthy"},
    },
    "events": [],
}

def save():
    state_path.write_text(json.dumps(state), encoding="utf-8")

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def reply(self, code, body=None):
        payload = b"" if body is None else json.dumps(body).encode()
        self.send_response(code)
        if payload:
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if payload:
            self.wfile.write(payload)

    def authorized(self):
        return self.headers.get("Authorization") == "Bearer test-token"

    def app_uuid(self, suffix=""):
        path = urlparse(self.path).path
        prefix = "/api/v1/applications/"
        if not path.startswith(prefix) or not path.endswith(suffix):
            return None
        value = path[len(prefix):]
        if suffix:
            value = value[:-len(suffix)]
        return value if value in state["apps"] else None

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/state":
            self.reply(200, state)
            return
        if path in ("/health/ready", "/api/v2/states"):
            state["events"].append(f"smoke:{path}")
            if scenario == "fail-b" and state["apps"]["app-b"]["docker_registry_image_tag"] == target_tag:
                save()
                self.reply(503, {"message": "forced smoke failure"})
                return
            save()
            self.reply(204 if path == "/health/ready" else 200, {})
            return
        if not self.authorized():
            self.reply(401, {"message": "Unauthenticated."})
            return
        uuid = self.app_uuid()
        if uuid:
            state["events"].append(f"get:{uuid}")
            save()
            self.reply(200, state["apps"][uuid])
            return
        self.reply(404, {"message": "not found"})

    def do_PATCH(self):
        if not self.authorized():
            self.reply(401, {"message": "Unauthenticated."})
            return
        uuid = self.app_uuid()
        if not uuid:
            self.reply(404, {"message": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length) or b"{}")
        tag = body.get("docker_registry_image_tag", "")
        state["apps"][uuid]["docker_registry_image_tag"] = tag
        state["apps"][uuid]["status"] = "stopped"
        state["events"].append(f"patch:{uuid}:{tag}")
        save()
        self.reply(200, {"uuid": uuid})

    def do_POST(self):
        if not self.authorized():
            self.reply(401, {"message": "Unauthenticated."})
            return
        uuid = self.app_uuid("/start")
        if not uuid:
            self.reply(404, {"message": "not found"})
            return
        state["apps"][uuid]["status"] = "running:healthy"
        state["events"].append(f"start:{uuid}")
        save()
        self.reply(200, {"message": "Deployment request queued."})

save()
server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
port_path.write_text(str(server.server_port), encoding="utf-8")
server.serve_forever()
PY
	server_pid="$!"
	for _ in $(seq 1 100); do
		[[ -s "${port_file}" ]] && return 0
		sleep 0.02
	done
	fail 'servidor HTTP fake nao iniciou'
}

assert_state() {
	local scenario="$1"
	local state_file="$2"
	python3 - "${scenario}" "${state_file}" "${target_tag}" <<'PY'
import json
import sys

scenario, state_file, target = sys.argv[1:]
state = json.load(open(state_file, encoding="utf-8"))
apps = state["apps"]
events = state["events"]
if scenario == "success":
    assert apps["app-a"]["docker_registry_image_tag"] == target
    assert apps["app-b"]["docker_registry_image_tag"] == target
    required = [
        f"patch:app-a:{target}", "start:app-a", "smoke:/health/ready", "smoke:/api/v2/states",
        f"patch:app-b:{target}", "start:app-b",
    ]
else:
    assert apps["app-a"]["docker_registry_image_tag"] == "sha-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    assert apps["app-b"]["docker_registry_image_tag"] == "sha-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    assert apps["app-a"]["status"] == "running:healthy"
    assert apps["app-b"]["status"] == "running:healthy"
    required = [
        f"patch:app-a:{target}", f"patch:app-b:{target}",
        "patch:app-b:sha-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "patch:app-a:sha-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ]
positions = []
for item in required:
    positions.append(events.index(item, positions[-1] + 1 if positions else 0))
assert positions == sorted(positions), events
PY
}

run_case() {
	local scenario="$1"
	local expected_exit="$2"
	local state_file="${tmp_dir}/${scenario}.json"
	local port_file="${tmp_dir}/${scenario}.port"
	local log_file="${tmp_dir}/${scenario}.log"

	server_pid=''
	start_server "${scenario}" "${state_file}" "${port_file}"
	local port
	port="$(cat "${port_file}")"

	set +e
	PATH="${tmp_dir}/bin:${PATH}" \
		COOLIFY_URL="http://127.0.0.1:${port}" \
		COOLIFY_TOKEN='test-token' \
		COOLIFY_APP_A_UUID='app-a' \
		COOLIFY_APP_B_UUID='app-b' \
		PUBLIC_SMOKE_URL="http://127.0.0.1:${port}" \
		COOLIFY_ALLOW_HTTP=1 \
		COOLIFY_DEPLOY_TIMEOUT=2 \
		COOLIFY_POLL_SECONDS=0.02 \
		"${deploy_script}" "${target_tag}" >"${log_file}" 2>&1
	local exit_code="$?"
	set -e

	[[ "${exit_code}" -eq "${expected_exit}" ]] || {
		cat "${log_file}" >&2
		fail "cenario ${scenario}: exit ${exit_code}, esperado ${expected_exit}"
	}
	if grep -Fq 'test-token' "${log_file}"; then
		fail "cenario ${scenario}: token apareceu no log"
	fi
	assert_state "${scenario}" "${state_file}"

	kill "${server_pid}" >/dev/null 2>&1 || true
	wait "${server_pid}" >/dev/null 2>&1 || true
	server_pid=''
}

run_case success 0
run_case fail-b 1

printf 'PASS: deploy A/B sequencial, smoke e rollback preservam tags anteriores\n'
