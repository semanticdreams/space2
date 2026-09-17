#!/usr/bin/env bash
set -euo pipefail

ROOT=""
LAYOUT=""
APP_ID=""
ENTRYPOINT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            ROOT="${2:-}"
            shift 2
            ;;
        --layout)
            LAYOUT="${2:-}"
            shift 2
            ;;
        --app-id)
            APP_ID="${2:-}"
            shift 2
            ;;
        --entrypoint)
            ENTRYPOINT="${2:-}"
            shift 2
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "${ROOT}" ]]; then
    echo "error: --root is required" >&2
    exit 1
fi
if [[ "${LAYOUT}" != "package" && "${LAYOUT}" != "tarball" ]]; then
    echo "error: --layout must be 'package' or 'tarball'" >&2
    exit 1
fi
if [[ -z "${APP_ID}" ]]; then
    echo "error: --app-id is required" >&2
    exit 1
fi
if [[ -z "${ENTRYPOINT}" ]]; then
    echo "error: --entrypoint is required" >&2
    exit 1
fi

require_executable() {
    local path="$1"
    local description="$2"
    if [[ ! -x "${path}" ]]; then
        echo "error: missing executable ${description}: ${path}" >&2
        exit 1
    fi
}

require_file() {
    local path="$1"
    local description="$2"
    if [[ ! -f "${path}" ]]; then
        echo "error: missing ${description}: ${path}" >&2
        exit 1
    fi
}

require_directory() {
    local path="$1"
    local description="$2"
    if [[ ! -d "${path}" ]]; then
        echo "error: missing ${description}: ${path}" >&2
        exit 1
    fi
}

require_absent() {
    local path="$1"
    local description="$2"
    if [[ -e "${path}" ]]; then
        echo "error: unexpected ${description}: ${path}" >&2
        exit 1
    fi
}

require_launcher_contains() {
    local launcher="$1"
    local expected="$2"
    local description="$3"
    if ! grep -Fq -- "${expected}" "${launcher}"; then
        echo "error: ${description}: ${launcher}" >&2
        exit 1
    fi
}

if [[ "${LAYOUT}" == "package" ]]; then
    require_executable "${ROOT}/usr/bin/${APP_ID}" "app launcher"
    require_directory "${ROOT}/usr/share/${APP_ID}/assets" "app assets"
    require_file "${ROOT}/usr/share/applications/${APP_ID}.desktop" "desktop file"
    require_absent "${ROOT}/usr/share/space/assets" "bundled Space assets in app-only package"
    require_launcher_contains \
        "${ROOT}/usr/bin/${APP_ID}" \
        "SPACE_ASSETS_PATH=\"/usr/share/${APP_ID}/assets\${SPACE_ASSETS_PATH:+:\$SPACE_ASSETS_PATH}\" exec /usr/bin/space -m ${ENTRYPOINT} \"\$@\"" \
        "app package launcher must exec system Space with app assets first"
else
    require_executable "${ROOT}/${APP_ID}" "top-level app launcher"
    require_executable "${ROOT}/bin/space" "bundled Space binary"
    require_directory "${ROOT}/share/${APP_ID}/assets" "app assets"
    require_directory "${ROOT}/share/space/assets" "bundled Space assets"
    require_launcher_contains \
        "${ROOT}/${APP_ID}" \
        "share/${APP_ID}/assets" \
        "tarball launcher must include app assets"
    require_launcher_contains \
        "${ROOT}/${APP_ID}" \
        "share/space/assets" \
        "tarball launcher must include bundled Space assets"
    if ! python3 - "${ROOT}/${APP_ID}" "share/${APP_ID}/assets" "share/space/assets" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
app = text.find(sys.argv[2])
space = text.find(sys.argv[3])
if app == -1 or space == -1 or app > space:
    sys.exit(1)
PY
    then
        echo "error: app assets must precede bundled Space assets in launcher: ${ROOT}/${APP_ID}" >&2
        exit 1
    fi
    require_launcher_contains \
        "${ROOT}/${APP_ID}" \
        "exec \"\${APP_DIR}/bin/space\" -m ${ENTRYPOINT} \"\$@\"" \
        "tarball launcher must exec bundled Space"
fi
