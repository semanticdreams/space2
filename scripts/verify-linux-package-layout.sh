#!/usr/bin/env bash
set -euo pipefail

ROOT=""
PROFILE=""
LAYOUT="package"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            ROOT="${2:-}"
            shift 2
            ;;
        --profile)
            PROFILE="${2:-}"
            shift 2
            ;;
        --layout)
            LAYOUT="${2:-}"
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
if [[ "${PROFILE}" != "full" && "${PROFILE}" != "minimal" ]]; then
    echo "error: --profile must be 'full' or 'minimal'" >&2
    exit 1
fi
if [[ "${LAYOUT}" != "tarball" && "${LAYOUT}" != "package" ]]; then
    echo "error: --layout must be 'tarball' or 'package'" >&2
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

require_sdl3_runtime() {
    local root="$1"
    local matches=("${root}"/lib/libSDL3.so*)

    if [[ ! -e "${matches[0]}" ]]; then
        echo "error: missing bundled SDL3 runtime library under ${root}/lib" >&2
        exit 1
    fi
}

require_matrix_runtime_if_needed() {
    local root="$1"
    local binary="${root}/bin/space"

    if ! command -v readelf >/dev/null 2>&1; then
        return 0
    fi

    if readelf -d "${binary}" 2>/dev/null | grep -q 'NEEDED.*libmatrix\.so'; then
        if [[ ! -f "${root}/lib/libmatrix.so" ]]; then
            echo "error: missing bundled Matrix runtime library under ${root}/lib/libmatrix.so" >&2
            exit 1
        fi
    fi
}

require_executable "${ROOT}/bin/space" "installed binary"
require_file "${ROOT}/share/space/assets/lua/main.fnl" "main Fennel asset"

if [[ "${LAYOUT}" == "tarball" ]]; then
    require_executable "${ROOT}/space" "top-level launcher"
    require_directory "${ROOT}/lib" "bundled library directory"
    require_sdl3_runtime "${ROOT}"
    require_matrix_runtime_if_needed "${ROOT}"
fi

if [[ "${PROFILE}" == "full" ]]; then
    require_executable "${ROOT}/bin/space_cef_helper" "CEF helper"
    require_file "${ROOT}/lib/space/cef/libcef.so" "CEF libcef.so"
    require_file "${ROOT}/lib/space/cef/libEGL.so" "CEF libEGL.so"
    require_file "${ROOT}/lib/space/cef/libGLESv2.so" "CEF libGLESv2.so"
    require_file "${ROOT}/lib/space/cef/libvk_swiftshader.so" "CEF libvk_swiftshader.so"
    require_file "${ROOT}/lib/space/cef/libvulkan.so.1" "CEF libvulkan.so.1"
    require_file "${ROOT}/lib/space/cef/vk_swiftshader_icd.json" "CEF vk_swiftshader_icd.json"
    require_file "${ROOT}/lib/space/cef/icudtl.dat" "CEF icudtl.dat"
    require_file "${ROOT}/lib/space/cef/chrome_100_percent.pak" "CEF chrome_100_percent.pak"
    require_file "${ROOT}/lib/space/cef/chrome_200_percent.pak" "CEF chrome_200_percent.pak"
    require_file "${ROOT}/lib/space/cef/resources.pak" "CEF resources.pak"
    require_file "${ROOT}/lib/space/cef/v8_context_snapshot.bin" "CEF v8_context_snapshot.bin"
    require_directory "${ROOT}/lib/space/cef/locales" "CEF locales directory"
else
    require_absent "${ROOT}/bin/space_cef_helper" "CEF helper in minimal profile"
    require_absent "${ROOT}/lib/space/cef" "CEF runtime directory in minimal profile"
    require_absent "${ROOT}/lib/libcef.so" "top-level CEF library in minimal profile"
fi
