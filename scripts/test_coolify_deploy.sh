#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deploy_script="${root_dir}/scripts/coolify_deploy.sh"
target_tag="sha-1111111111111111111111111111111111111111"
smoke_secret='test-deploy-smoke-secret-32-bytes-value'
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
        "app-a": {
            "docker_registry_image_tag": "sha-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "status": "running:healthy",
            "ports_exposes": "3330",
            "ports_mappings": "",
            "health_check_enabled": True,
            "health_check_path": "/health/ready",
            "health_check_port": "3330",
            "limits_cpus": "2",
            "limits_memory": "512M",
            "limits_memory_reservation": "256M",
            "custom_network_aliases": ["tabuamare-app-a"],
        },
        "app-b": {
            "docker_registry_image_tag": "sha-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "status": "running:healthy",
            "ports_exposes": "3330",
            "ports_mappings": "",
            "health_check_enabled": True,
            "health_check_path": "/health/ready",
            "health_check_port": "3330",
            "limits_cpus": "2.0",
            "limits_memory": "536870912",
            "limits_memory_reservation": "268435456",
            "custom_network_aliases": ["tabuamare-app-b"],
        },
    },
    "storages": {
        "app-a": [{"name": "tabuamare-a-data", "mount_path": "/app/data", "host_path": None}],
        "app-b": [{"name": "tabuamare-b-data", "mount_path": "/app/data", "host_path": None}],
    },
    "deployments": {},
    "stop_polls": {},
    "stop_attempts": {},
    "events": [],
}
if scenario == "bad-config":
    state["apps"]["app-a"]["limits_cpus"] = "1"
if scenario == "shared-storage":
    state["storages"]["app-b"] = [{"name": "tabuamare-a-data", "mount_path": "/app/data", "host_path": None}]
if scenario == "peer-down":
    state["apps"]["app-b"]["status"] = "exited"
if scenario == "network-alias":
    state["apps"]["app-a"]["custom_network_aliases"] = []

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
            slot = self.headers.get("X-Tabuamare-Deploy-Slot", "")
            secret = self.headers.get("X-Tabuamare-Deploy-Secret", "")
            if secret != "test-deploy-smoke-secret-32-bytes-value":
                self.reply(403, {"message": "invalid deploy smoke secret"})
                return
            state["events"].append(f"smoke:{slot}:{path}")
            if scenario in ("fail-b", "fail-restore-b") and slot == "B":
                save()
                self.reply(503, {"message": "forced smoke failure"})
                return
            save()
            self.reply(204 if path == "/health/ready" else 200, {})
            return
        if not self.authorized():
            self.reply(401, {"message": "Unauthenticated."})
            return
        deployment_prefix = "/api/v1/deployments/"
        if path.startswith(deployment_prefix):
            deployment_uuid = path[len(deployment_prefix):]
            deployment = state["deployments"].get(deployment_uuid)
            if not deployment:
                self.reply(404, {"message": "not found"})
                return
            deployment["polls"] += 1
            if deployment["polls"] >= 2:
                deployment["status"] = "finished"
                state["apps"][deployment["app"]]["status"] = "running:healthy"
            state["events"].append(f"deployment:{deployment_uuid}:{deployment['status']}")
            save()
            self.reply(200, {"deployment_uuid": deployment_uuid, "status": deployment["status"]})
            return
        uuid = self.app_uuid()
        if uuid:
            if state["apps"][uuid]["status"] == "stopping":
                state["stop_polls"][uuid] = state["stop_polls"].get(uuid, 0) + 1
                if state["stop_polls"][uuid] >= 2:
                    state["apps"][uuid]["status"] = "exited"
            state["events"].append(f"get:{uuid}:{state['apps'][uuid]['status']}")
            save()
            self.reply(200, state["apps"][uuid])
            return
        storage_prefix = "/api/v1/applications/"
        storage_suffix = "/storages"
        if path.startswith(storage_prefix) and path.endswith(storage_suffix):
            uuid = path[len(storage_prefix):-len(storage_suffix)]
            if uuid in state["storages"]:
                state["events"].append(f"storages:{uuid}")
                save()
                self.reply(200, state["storages"][uuid])
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
        if state["apps"][uuid]["status"] != "exited":
            self.reply(409, {"message": "application must be stopped before patch"})
            return
        other = "app-b" if uuid == "app-a" else "app-a"
        if state["apps"][other]["status"] != "running:healthy":
            self.reply(409, {"message": "other slot must stay healthy"})
            return
        state["events"].append(f"patch-precondition:{uuid}:exited:{other}:healthy")
        state["apps"][uuid]["docker_registry_image_tag"] = tag
        # O container antigo pode continuar healthy enquanto o novo deploy esta na fila.
        state["apps"][uuid]["status"] = "running:healthy"
        state["events"].append(f"patch:{uuid}:{tag}")
        save()
        self.reply(200, {"uuid": uuid})

    def do_POST(self):
        if not self.authorized():
            self.reply(401, {"message": "Unauthenticated."})
            return
        uuid = self.app_uuid("/stop")
        if uuid:
            state["stop_attempts"][uuid] = state["stop_attempts"].get(uuid, 0) + 1
            if scenario == "fail-stop-a" and uuid == "app-a" and state["stop_attempts"][uuid] == 1:
                state["events"].append("stop-failed:app-a")
                save()
                self.reply(500, {"message": "forced stop failure"})
                return
            if scenario == "fail-restore-b" and uuid == "app-b" and state["stop_attempts"][uuid] == 2:
                state["events"].append("stop-restore-failed:app-b")
                save()
                self.reply(500, {"message": "forced restore stop failure"})
                return
            state["apps"][uuid]["status"] = "stopping"
            state["stop_polls"][uuid] = 0
            state["events"].append(f"stop:{uuid}")
            save()
            self.reply(200, {"message": "Stop request queued."})
            return
        uuid = self.app_uuid("/start")
        if not uuid:
            self.reply(404, {"message": "not found"})
            return
        deployment_uuid = f"deployment-{len(state['deployments']) + 1}"
        state["deployments"][deployment_uuid] = {
            "app": uuid,
            "status": "queued",
            "polls": 0,
        }
        state["events"].append(f"start:{uuid}")
        save()
        self.reply(200, {"message": "Deployment request queued.", "deployment_uuid": deployment_uuid})

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
		"stop:app-a", "get:app-a:exited", "patch-precondition:app-a:exited:app-b:healthy",
        f"patch:app-a:{target}", "start:app-a", "deployment:deployment-1:finished",
        "smoke:A:/health/ready", "smoke:A:/api/v2/states",
		"stop:app-b", "get:app-b:exited", "patch-precondition:app-b:exited:app-a:healthy",
        f"patch:app-b:{target}", "start:app-b", "deployment:deployment-2:finished",
        "smoke:B:/health/ready", "smoke:B:/api/v2/states",
    ]
elif scenario == "fail-b":
    assert apps["app-a"]["docker_registry_image_tag"] == "sha-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    assert apps["app-b"]["docker_registry_image_tag"] == "sha-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    assert apps["app-a"]["status"] == "running:healthy"
    assert apps["app-b"]["status"] == "running:healthy"
    required = [
        f"patch:app-a:{target}", f"patch:app-b:{target}",
		"stop:app-b", "get:app-b:exited", "patch-precondition:app-b:exited:app-a:healthy",
        "patch:app-b:sha-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
		"stop:app-a", "get:app-a:exited", "patch-precondition:app-a:exited:app-b:healthy",
        "patch:app-a:sha-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ]
elif scenario == "fail-stop-a":
    assert apps["app-a"]["docker_registry_image_tag"] == "sha-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    assert apps["app-b"]["docker_registry_image_tag"] == "sha-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    required = [
        "stop-failed:app-a", "stop:app-a", "get:app-a:exited",
        "patch-precondition:app-a:exited:app-b:healthy",
        "patch:app-a:sha-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ]
elif scenario == "fail-restore-b":
    assert apps["app-a"]["docker_registry_image_tag"] == target
    assert apps["app-b"]["docker_registry_image_tag"] == target
    assert events.count("stop:app-a") == 1, events
    assert "stop-restore-failed:app-b" in events
    assert "patch:app-a:sha-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" not in events
    required = [f"patch:app-a:{target}", f"patch:app-b:{target}", "stop-restore-failed:app-b"]
elif scenario == "peer-down":
    assert apps["app-a"]["docker_registry_image_tag"] == "sha-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    assert apps["app-b"]["docker_registry_image_tag"] == "sha-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    assert not any(event.startswith("stop:") for event in events), events
    required = ["get:app-a:running:healthy", "get:app-b:exited", "storages:app-a", "storages:app-b"]
else:
    assert apps["app-a"]["docker_registry_image_tag"] == "sha-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    assert apps["app-b"]["docker_registry_image_tag"] == "sha-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    assert not any(event.startswith("patch:") for event in events), events
    required = ["get:app-a:running:healthy", "get:app-b:running:healthy", "storages:app-a", "storages:app-b"]
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
		DEPLOY_SMOKE_SECRET="${smoke_secret}" \
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
	if grep -Fq "${smoke_secret}" "${log_file}"; then
		fail "cenario ${scenario}: segredo do smoke apareceu no log"
	fi
	assert_state "${scenario}" "${state_file}"

	kill "${server_pid}" >/dev/null 2>&1 || true
	wait "${server_pid}" >/dev/null 2>&1 || true
	server_pid=''
}

run_weak_secret_case() {
	local weak_secret='too-short'
	local log_file="${tmp_dir}/weak-secret.log"
	set +e
	PATH="${tmp_dir}/bin:${PATH}" \
		COOLIFY_URL='https://coolify.invalid' \
		COOLIFY_TOKEN='test-token' \
		COOLIFY_APP_A_UUID='app-a' \
		COOLIFY_APP_B_UUID='app-b' \
		DEPLOY_SMOKE_SECRET="${weak_secret}" \
		PUBLIC_SMOKE_URL='https://tabuamare.api.br' \
		"${deploy_script}" "${target_tag}" >"${log_file}" 2>&1
	local exit_code="$?"
	set -e
	[[ "${exit_code}" -eq 1 ]] || fail 'DEPLOY_SMOKE_SECRET curto foi aceito'
	grep -Fq 'DEPLOY_SMOKE_SECRET deve ter no minimo 32 caracteres' "${log_file}" || \
		fail 'erro de DEPLOY_SMOKE_SECRET curto nao foi explicito'
	! grep -Fq "${weak_secret}" "${log_file}" || fail 'segredo curto apareceu no log'
}

run_weak_secret_case
run_case success 0
run_case fail-b 1
run_case fail-stop-a 1
run_case fail-restore-b 1
run_case bad-config 1
run_case shared-storage 1
run_case peer-down 1
run_case network-alias 1

nginx_vhost="${root_dir}/ops/nginx/conf.d/tabuamare.conf"
nginx_conf="${root_dir}/ops/nginx/nginx.conf"
grep -Fq 'tabuamare_ab' "${nginx_vhost}" || fail 'upstream tabuamare_ab ausente'
grep -Fq 'tabuamare_slot_a' "${nginx_vhost}" || fail 'upstream de slot A ausente'
grep -Fq 'tabuamare_slot_b' "${nginx_vhost}" || fail 'upstream de slot B ausente'
grep -Fq 'tabuamare-app-a:3330' "${nginx_vhost}" || fail 'alias estavel A ausente no vhost'
grep -Fq 'tabuamare-app-b:3330' "${nginx_vhost}" || fail 'alias estavel B ausente no vhost'
grep -Fq 'server coolify-proxy:80' "${nginx_vhost}" || fail 'proxy interno coolify-proxy ausente'
grep -Fq 'location = /health/debug' "${nginx_vhost}" || fail 'health/debug sem location exata'
grep -Fq 'return 404' "${nginx_vhost}" || fail 'health/debug sem bloqueio sem secret'
grep -Fq 'proxy_next_upstream' "${nginx_vhost}" || fail 'nginx sem proxy_next_upstream'
grep -Fq '"A:__DEPLOY_SMOKE_SECRET__"' "${nginx_conf}" || fail 'map de deploy slot A sem secret'
grep -Fq '"B:__DEPLOY_SMOKE_SECRET__"' "${nginx_conf}" || fail 'map de deploy slot B sem secret'
# shellcheck disable=SC2016
grep -Fq 'DEPLOY_SMOKE_SECRET: ${{ secrets.DEPLOY_SMOKE_SECRET }}' \
	"${root_dir}/.github/workflows/deploy-production.yml" || fail 'workflow sem secret do smoke'

printf 'PASS: stop-first, preflight, smoke secreto A/B e rollback preservam disponibilidade\n'
