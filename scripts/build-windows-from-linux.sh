#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VCPKG_ROOT="${VCPKG_ROOT:-${ROOT_DIR}/vcpkg}"
RUST_TARGET="${RUST_TARGET:-x86_64-pc-windows-gnu}"
CMAKE_ASM_MASM_COMPILER="${CMAKE_ASM_MASM_COMPILER:-llvm-ml-14}"

require_cmd() {
    local cmd="$1"
    local install_hint="$2"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "Missing required command: ${cmd}" >&2
        echo "Hint: ${install_hint}" >&2
        exit 1
    fi
}

require_cmd cmake "Run scripts/setup-windows-build-host.sh"
require_cmd git "Run scripts/setup-windows-build-host.sh"
require_cmd pkg-config "Run scripts/setup-windows-build-host.sh"
require_cmd nasm "Run scripts/setup-windows-build-host.sh"
require_cmd "${CMAKE_ASM_MASM_COMPILER}" "Run scripts/setup-windows-build-host.sh"
require_cmd curl "Run scripts/setup-windows-build-host.sh"
require_cmd x86_64-w64-mingw32-gcc-posix "Run scripts/setup-windows-build-host.sh"
require_cmd x86_64-w64-mingw32-g++-posix "Run scripts/setup-windows-build-host.sh"

if [ ! -d "${VCPKG_ROOT}" ]; then
    echo "VCPKG_ROOT not found: ${VCPKG_ROOT}" >&2
    echo "Run scripts/setup-windows-build-host.sh first." >&2
    exit 1
fi

if [ ! -x "${VCPKG_ROOT}/vcpkg" ]; then
    echo "vcpkg executable missing under ${VCPKG_ROOT}." >&2
    echo "Run scripts/setup-windows-build-host.sh first." >&2
    exit 1
fi

if ! command -v rustc >/dev/null 2>&1; then
    echo "rustc not found." >&2
    echo "Run scripts/setup-windows-build-host.sh first." >&2
    exit 1
fi
if [ -f "${HOME}/.cargo/env" ]; then
    # shellcheck disable=SC1090
    source "${HOME}/.cargo/env"
fi
if command -v rustup >/dev/null 2>&1 && ! rustup target list --installed | grep -q "^${RUST_TARGET}$"; then
    echo "Rust target '${RUST_TARGET}' is not installed." >&2
    echo "Run scripts/setup-windows-build-host.sh first." >&2
    exit 1
fi

export VCPKG_ROOT
export VCPKG_TARGET_TRIPLET="${VCPKG_TARGET_TRIPLET:-x64-mingw-dynamic-posix}"
export CROSS_CC="${CROSS_CC:-x86_64-w64-mingw32-gcc-posix}"
export CROSS_CXX="${CROSS_CXX:-x86_64-w64-mingw32-g++-posix}"
export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="${CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER:-x86_64-w64-mingw32-gcc-posix}"
export CMAKE_ASM_MASM_COMPILER
export CMAKE_ASM_MASM_FLAGS="${CMAKE_ASM_MASM_FLAGS:--m64}"

"${ROOT_DIR}/scripts/build-windows.sh"

cat <<'EOF'
Windows build complete.
To prepare and run the Windows fast tests under Wine:
  scripts/test-windows-under-wine.sh
EOF
