#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/windows}"
CLI_EXE="${BUILD_DIR}/space-cli.exe"
TEST_MODULE="${SPACE_TEST_MODULE:-tests.fast:main}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"

resolve_wine_cmd() {
    if [ -n "${WINE_CMD:-}" ]; then
        printf '%s\n' "${WINE_CMD}"
        return 0
    fi

    if command -v wine64 >/dev/null 2>&1; then
        printf '%s\n' wine64
        return 0
    fi

    if command -v wine >/dev/null 2>&1; then
        printf '%s\n' wine
        return 0
    fi

    echo "Missing required command: wine64 or wine" >&2
    exit 1
}

WINE_CMD="$(resolve_wine_cmd)"

"${ROOT_DIR}/scripts/prepare-windows-wine-runtime.sh" "${CLI_EXE}"

exec timeout "${TIMEOUT_SECONDS}s" env \
    SKIP_KEYRING_TESTS=1 \
    XDG_DATA_HOME=/tmp/space/tests/xdg-data \
    PWD="${ROOT_DIR}" \
    SPACE_DISABLE_AUDIO=1 \
    SPACE_ASSETS_PATH="${ROOT_DIR}/assets" \
    FENNEL_PATH="${ROOT_DIR}/assets/lua/?.fnl;${ROOT_DIR}/assets/lua/?/init.fnl" \
    FENNEL_MACRO_PATH="${ROOT_DIR}/assets/lua/?.fnl;${ROOT_DIR}/assets/lua/?/init.fnl" \
    "${WINE_CMD}" "${CLI_EXE}" -m "${TEST_MODULE}"
