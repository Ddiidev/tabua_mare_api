#!/bin/sh
set -eu

DATA_DIR="${DATA_DIR:-/app/data}"
DB_SQLITE_PATH="${DB_SQLITE_PATH:-${DATA_DIR}/taubinha.sqlite}"
SQLITE_SEED_PATH="${SQLITE_SEED_PATH:-/app/seed/taubinha.sqlite}"
SQLITE_SEED_CHECKSUM_PATH="${SQLITE_SEED_CHECKSUM_PATH:-/app/seed/taubinha.sqlite.sha256}"
SQLITE_SEED_MARKER_PATH="${SQLITE_SEED_MARKER_PATH:-${DATA_DIR}/.taubinha.sqlite.seed.sha256}"
SQLITE3_BIN="${SQLITE3_BIN:-sqlite3}"
SU_EXEC_BIN="${SU_EXEC_BIN:-su-exec}"
APP_BINARY="${APP_BINARY:-/app/TabuaMareAPI}"
APP_UID="${APP_UID:-10001}"
APP_GID="${APP_GID:-10001}"
PORT="${PORT:-3330}"

DB_DIR="$(dirname "${DB_SQLITE_PATH}")"
MARKER_DIR="$(dirname "${SQLITE_SEED_MARKER_PATH}")"
TEMP_DB=''
TEMP_MARKER=''

cleanup() {
	if [ -n "${TEMP_DB}" ]; then
		rm -f "${TEMP_DB}"
	fi
	if [ -n "${TEMP_MARKER}" ]; then
		rm -f "${TEMP_MARKER}"
	fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
	printf '[entrypoint] ERROR: %s\n' "$*" >&2
	exit 1
}

quick_check() {
	database="$1"
	result="$("${SQLITE3_BIN}" "${database}" 'PRAGMA quick_check;' 2>/dev/null)" || return 1
	[ "${result}" = 'ok' ]
}

[ -r "${SQLITE_SEED_PATH}" ] || fail "seed SQLite ausente: ${SQLITE_SEED_PATH}"
[ -r "${SQLITE_SEED_CHECKSUM_PATH}" ] || fail "checksum do seed ausente: ${SQLITE_SEED_CHECKSUM_PATH}"
[ -x "${APP_BINARY}" ] || fail "binario da aplicacao nao executavel: ${APP_BINARY}"
command -v "${SQLITE3_BIN}" >/dev/null 2>&1 || fail "sqlite3 indisponivel: ${SQLITE3_BIN}"
command -v "${SU_EXEC_BIN}" >/dev/null 2>&1 || fail "su-exec indisponivel: ${SU_EXEC_BIN}"

EXPECTED_CHECKSUM="$(awk 'NR == 1 { print $1 }' "${SQLITE_SEED_CHECKSUM_PATH}")"
printf '%s\n' "${EXPECTED_CHECKSUM}" | grep -Eq '^[0-9a-fA-F]{64}$' || \
	fail "checksum do seed invalido: ${SQLITE_SEED_CHECKSUM_PATH}"
ACTUAL_CHECKSUM="$(sha256sum "${SQLITE_SEED_PATH}" | awk '{ print $1 }')"
[ "${ACTUAL_CHECKSUM}" = "${EXPECTED_CHECKSUM}" ] || fail 'checksum do seed SQLite nao confere'
quick_check "${SQLITE_SEED_PATH}" || fail 'seed SQLite falhou no PRAGMA quick_check'

mkdir -p "${DATA_DIR}" "${DB_DIR}" "${MARKER_DIR}"
chown "${APP_UID}:${APP_GID}" "${DATA_DIR}" "${DB_DIR}" "${MARKER_DIR}"

INSTALLED_CHECKSUM=''
if [ -r "${SQLITE_SEED_MARKER_PATH}" ]; then
	INSTALLED_CHECKSUM="$(awk 'NR == 1 { print $1 }' "${SQLITE_SEED_MARKER_PATH}")"
fi

if [ ! -f "${DB_SQLITE_PATH}" ] || [ "${INSTALLED_CHECKSUM}" != "${EXPECTED_CHECKSUM}" ]; then
	printf '[entrypoint] instalando seed SQLite %s\n' "${EXPECTED_CHECKSUM}"
	TEMP_DB="$(mktemp "${DB_SQLITE_PATH}.seed.XXXXXX")"
	TEMP_MARKER="$(mktemp "${SQLITE_SEED_MARKER_PATH}.tmp.XXXXXX")"
	cp "${SQLITE_SEED_PATH}" "${TEMP_DB}"
	quick_check "${TEMP_DB}" || fail 'copia temporaria do seed falhou no PRAGMA quick_check'
	printf '%s\n' "${EXPECTED_CHECKSUM}" > "${TEMP_MARKER}"
	chown "${APP_UID}:${APP_GID}" "${TEMP_DB}" "${TEMP_MARKER}"

	mv -f "${TEMP_DB}" "${DB_SQLITE_PATH}"
	TEMP_DB=''
	rm -f "${DB_SQLITE_PATH}-wal" "${DB_SQLITE_PATH}-shm"
	mv -f "${TEMP_MARKER}" "${SQLITE_SEED_MARKER_PATH}"
	TEMP_MARKER=''
fi

quick_check "${DB_SQLITE_PATH}" || fail 'banco SQLite instalado falhou no PRAGMA quick_check'
chown "${APP_UID}:${APP_GID}" "${DB_SQLITE_PATH}" "${SQLITE_SEED_MARKER_PATH}"

trap - EXIT HUP INT TERM
cleanup
exec "${SU_EXEC_BIN}" "${APP_UID}:${APP_GID}" "${APP_BINARY}" "${PORT}"
