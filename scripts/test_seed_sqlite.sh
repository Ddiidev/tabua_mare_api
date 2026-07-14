#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRYPOINT="${ENTRYPOINT:-${ROOT_DIR}/dockerfiles/entrypoint-alpine.sh}"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_eq() {
	local expected="$1"
	local actual="$2"
	local message="$3"
	[[ "${actual}" == "${expected}" ]] || fail "${message}: esperado=${expected}, atual=${actual}"
}

create_db() {
	local path="$1"
	local value="$2"
	python3 - "${path}" "${value}" <<'PY'
import sqlite3
import sys

path, value = sys.argv[1:]
connection = sqlite3.connect(path)
connection.execute("CREATE TABLE seed_info (value TEXT NOT NULL)")
connection.execute("INSERT INTO seed_info(value) VALUES (?)", (value,))
connection.commit()
connection.close()
PY
}

write_checksum() {
	local source="$1"
	local destination="$2"
	sha256sum "${source}" | awk '{ print $1 }' > "${destination}"
}

[[ -f "${ENTRYPOINT}" ]] || fail "entrypoint ausente: ${ENTRYPOINT}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

DATA_DIR="${TMP_DIR}/data"
SEED_DIR="${TMP_DIR}/seed"
BIN_DIR="${TMP_DIR}/bin"
mkdir -p "${DATA_DIR}" "${SEED_DIR}" "${BIN_DIR}"

SQLITE_WRAPPER="${BIN_DIR}/sqlite3-python"
cat > "${SQLITE_WRAPPER}" <<'PY'
#!/usr/bin/env python3
import sqlite3
import sys

if len(sys.argv) < 3:
    raise SystemExit("usage: sqlite3-python DATABASE SQL")

database = sys.argv[1]
statement = " ".join(sys.argv[2:])
try:
    connection = sqlite3.connect(f"file:{database}?mode=rw", uri=True)
    cursor = connection.execute(statement)
    rows = cursor.fetchall()
    connection.commit()
    for row in rows:
        print("|".join(str(value) for value in row))
    connection.close()
except sqlite3.Error as error:
    print(error, file=sys.stderr)
    raise SystemExit(1)
PY
chmod +x "${SQLITE_WRAPPER}"

SU_EXEC_MOCK="${BIN_DIR}/su-exec"
cat > "${SU_EXEC_MOCK}" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$1" > "${SU_EXEC_RECORD:?}"
shift
exec "$@"
SH
chmod +x "${SU_EXEC_MOCK}"

APP_MOCK="${BIN_DIR}/TabuaMareAPI"
cat > "${APP_MOCK}" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$@" > "${APP_RECORD:?}"
SH
chmod +x "${APP_MOCK}"

DB_PATH="${DATA_DIR}/taubinha.sqlite"
MARKER_PATH="${DATA_DIR}/.taubinha.sqlite.seed.sha256"
SEED_PATH="${SEED_DIR}/taubinha.sqlite"
CHECKSUM_PATH="${SEED_DIR}/taubinha.sqlite.sha256"
APP_RECORD="${TMP_DIR}/app-record"
SU_EXEC_RECORD="${TMP_DIR}/su-exec-record"
CURRENT_UID="$(id -u)"
CURRENT_GID="$(id -g)"

run_entrypoint() {
	env \
		DATA_DIR="${DATA_DIR}" \
		DB_SQLITE_PATH="${DB_PATH}" \
		SQLITE_SEED_PATH="${SEED_PATH}" \
		SQLITE_SEED_CHECKSUM_PATH="${CHECKSUM_PATH}" \
		SQLITE_SEED_MARKER_PATH="${MARKER_PATH}" \
		SQLITE3_BIN="${SQLITE_WRAPPER}" \
		SU_EXEC_BIN="${SU_EXEC_MOCK}" \
		APP_BINARY="${APP_MOCK}" \
		APP_UID="${CURRENT_UID}" \
		APP_GID="${CURRENT_GID}" \
		APP_RECORD="${APP_RECORD}" \
		SU_EXEC_RECORD="${SU_EXEC_RECORD}" \
		PORT=3330 \
		sh "${ENTRYPOINT}"
}

query_value() {
	"${SQLITE_WRAPPER}" "${DB_PATH}" 'SELECT value FROM seed_info LIMIT 1;'
}

# Volume vazio: instala seed validado e cria marcador.
create_db "${SEED_PATH}" 'seed-v1'
write_checksum "${SEED_PATH}" "${CHECKSUM_PATH}"
run_entrypoint
assert_eq 'seed-v1' "$(query_value)" 'volume vazio nao recebeu seed'
assert_eq "$(cat "${CHECKSUM_PATH}")" "$(cat "${MARKER_PATH}")" 'marcador inicial incorreto'
assert_eq "${CURRENT_UID}:${CURRENT_GID}" "$(cat "${SU_EXEC_RECORD}")" 'identidade enviada ao su-exec incorreta'
assert_eq '3330' "$(cat "${APP_RECORD}")" 'porta enviada ao binario incorreta'

# Seed igual: preserva dados locais e nao substitui o banco.
"${SQLITE_WRAPPER}" "${DB_PATH}" "CREATE TABLE local_state (value TEXT NOT NULL);" >/dev/null
"${SQLITE_WRAPPER}" "${DB_PATH}" "INSERT INTO local_state(value) VALUES ('preserve-me');" >/dev/null
run_entrypoint
assert_eq 'preserve-me' "$("${SQLITE_WRAPPER}" "${DB_PATH}" 'SELECT value FROM local_state LIMIT 1;')" 'seed igual substituiu banco existente'

# Seed novo valido: substitui atomicamente e limpa sidecars antigos.
rm -f "${SEED_PATH}"
create_db "${SEED_PATH}" 'seed-v2'
write_checksum "${SEED_PATH}" "${CHECKSUM_PATH}"
touch "${DB_PATH}-wal" "${DB_PATH}-shm"
run_entrypoint
assert_eq 'seed-v2' "$(query_value)" 'seed novo nao substituiu banco'
assert_eq "$(cat "${CHECKSUM_PATH}")" "$(cat "${MARKER_PATH}")" 'marcador nao acompanhou seed novo'
[[ ! -e "${DB_PATH}-wal" ]] || fail 'WAL antigo permaneceu apos substituicao validada'
[[ ! -e "${DB_PATH}-shm" ]] || fail 'SHM antigo permaneceu apos substituicao validada'

# Seed corrompido: falha antes de tocar no banco e no marcador atuais.
DB_HASH_BEFORE="$(sha256sum "${DB_PATH}" | awk '{ print $1 }')"
MARKER_BEFORE="$(cat "${MARKER_PATH}")"
printf 'not-a-sqlite-database\n' > "${SEED_PATH}"
write_checksum "${SEED_PATH}" "${CHECKSUM_PATH}"
if run_entrypoint >"${TMP_DIR}/corrupt-seed.log" 2>&1; then
	fail 'seed corrompido foi aceito'
fi
grep -Fq 'seed SQLite falhou no PRAGMA quick_check' "${TMP_DIR}/corrupt-seed.log" || \
	fail 'falha do seed corrompido nao foi explicita'
assert_eq "${DB_HASH_BEFORE}" "$(sha256sum "${DB_PATH}" | awk '{ print $1 }')" 'seed corrompido alterou banco atual'
assert_eq "${MARKER_BEFORE}" "$(cat "${MARKER_PATH}")" 'seed corrompido alterou marcador atual'

printf 'PASS: seed SQLite vazio, igual, novo valido e corrompido\n'
