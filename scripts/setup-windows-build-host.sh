#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VCPKG_ROOT="${VCPKG_ROOT:-${ROOT_DIR}/vcpkg}"
RUST_TARGET="${RUST_TARGET:-x86_64-pc-windows-gnu}"

install_powershell_core() {
    if command -v pwsh >/dev/null 2>&1; then
        return 0
    fi

    if [ ! -r /etc/os-release ]; then
        echo "PowerShell Core (pwsh) is required by vcpkg." >&2
        echo "Unable to detect Ubuntu VERSION_ID from /etc/os-release; install PowerShell Core manually and re-run setup." >&2
        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release
    if [ "${ID:-}" != "ubuntu" ] || [ -z "${VERSION_ID:-}" ]; then
        echo "PowerShell Core (pwsh) is required by vcpkg." >&2
        echo "Automatic PowerShell Core setup is only supported on Ubuntu with VERSION_ID; install pwsh manually and re-run setup." >&2
        exit 1
    fi

    local microsoft_package
    microsoft_package="$(mktemp --tmpdir packages-microsoft-prod.XXXXXX.deb)"
    curl -fsSL \
        "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb" \
        -o "${microsoft_package}" || {
        rm -f "${microsoft_package}"
        echo "PowerShell Core (pwsh) is required by vcpkg." >&2
        echo "Could not download Microsoft's Ubuntu ${VERSION_ID} package repo configuration; install pwsh manually and re-run setup." >&2
        exit 1
    }
    sudo dpkg -i "${microsoft_package}"
    rm -f "${microsoft_package}"
    sudo apt-get update
    sudo apt-get install -y powershell

    if ! command -v pwsh >/dev/null 2>&1; then
        echo "PowerShell Core (pwsh) is required by vcpkg." >&2
        echo "PowerShell installation completed but pwsh is still unavailable on PATH." >&2
        exit 1
    fi
}

sudo apt-get update
sudo apt-get install -y \
    mingw-w64 \
    gcc-mingw-w64-x86-64-posix \
    g++-mingw-w64-x86-64-posix \
    binutils-mingw-w64-x86-64 \
    wine64 \
    winbind \
    cmake \
    ninja-build \
    ccache \
    git \
    pkg-config \
    nasm \
    llvm-14 \
    curl \
    python3 \
    python3-pil \
    ripgrep \
    zip

sudo apt-get install -y sccache || true
install_powershell_core

if command -v ninja >/dev/null 2>&1 && [ ! -x /usr/local/bin/ninja ]; then
    sudo mkdir -p /usr/local/bin
    sudo ln -sf "$(command -v ninja)" /usr/local/bin/ninja
fi

if ! command -v ccache >/dev/null 2>&1; then
    echo "Missing ccache after setup." >&2
    exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
    echo "Missing ripgrep after setup." >&2
    exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
    echo "Missing zip after setup." >&2
    exit 1
fi

if ! command -v pwsh >/dev/null 2>&1; then
    echo "PowerShell Core (pwsh) is required by vcpkg." >&2
    echo "Missing pwsh after setup." >&2
    exit 1
fi

if ! command -v x86_64-w64-mingw32-gcc-posix >/dev/null 2>&1 \
    || ! command -v x86_64-w64-mingw32-g++-posix >/dev/null 2>&1; then
    echo "Missing posix MinGW compiler variants after install." >&2
    echo "Ensure packages gcc-mingw-w64-x86-64-posix and g++-mingw-w64-x86-64-posix are available." >&2
    exit 1
fi

if [ ! -d "${VCPKG_ROOT}" ]; then
    git clone --branch 2025.03.19 https://github.com/microsoft/vcpkg "${VCPKG_ROOT}"
fi

if [ ! -x "${VCPKG_ROOT}/vcpkg" ]; then
    "${VCPKG_ROOT}/bootstrap-vcpkg.sh"
fi

if ! command -v rustc >/dev/null 2>&1; then
    curl -fsSL https://sh.rustup.rs | sh -s -- -y
fi
if [ -f "${HOME}/.cargo/env" ]; then
    # shellcheck disable=SC1090
    source "${HOME}/.cargo/env"
fi
if command -v rustup >/dev/null 2>&1; then
    rustup target add "${RUST_TARGET}"
fi

cat <<'EOF'
Windows build host setup complete.
Next step (no sudo): scripts/build-windows-from-linux.sh
Then run Windows tests under Wine: scripts/test-windows-under-wine.sh
EOF
