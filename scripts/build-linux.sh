#!/usr/bin/env bash
set -euo pipefail

PROFILE="full"
BUILD_DIR="build"
PACKAGE_MODE="all"
DEB_FLAVOR=""
RPM_FLAVOR=""
NO_MATRIX=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            PROFILE="${2:-}"
            shift 2
            ;;
        --build-dir)
            BUILD_DIR="${2:-}"
            shift 2
            ;;
        --package-mode)
            PACKAGE_MODE="${2:-}"
            shift 2
            ;;
        --deb-flavor)
            DEB_FLAVOR="${2:-}"
            shift 2
            ;;
        --rpm-flavor)
            RPM_FLAVOR="${2:-}"
            shift 2
            ;;
        --no-matrix)
            NO_MATRIX=true
            shift
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            echo "usage: $0 [--profile full|minimal] [--build-dir <path>] [--package-mode all|deb-appimage|deb|appimage|rpm] [--deb-flavor <name>] [--rpm-flavor <name>] [--no-matrix]" >&2
            exit 1
            ;;
    esac
done

if [[ "${PROFILE}" != "full" && "${PROFILE}" != "minimal" ]]; then
    echo "error: invalid profile '${PROFILE}', expected 'full' or 'minimal'" >&2
    exit 1
fi
if [[ "${PACKAGE_MODE}" != "all" && "${PACKAGE_MODE}" != "deb-appimage" && "${PACKAGE_MODE}" != "deb" && "${PACKAGE_MODE}" != "appimage" && "${PACKAGE_MODE}" != "rpm" ]]; then
    echo "error: invalid package mode '${PACKAGE_MODE}', expected 'all', 'deb-appimage', 'deb', 'appimage', or 'rpm'" >&2
    exit 1
fi
if [[ -n "${DEB_FLAVOR}" && ! "${DEB_FLAVOR}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: invalid DEB flavor '${DEB_FLAVOR}', expected only letters, numbers, '.', '_', or '-'" >&2
    exit 1
fi
if [[ -n "${RPM_FLAVOR}" && ! "${RPM_FLAVOR}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "error: invalid RPM flavor '${RPM_FLAVOR}', expected only letters, numbers, '.', '_', or '-'" >&2
    exit 1
fi

builds_deb=false
builds_appimage=false
builds_rpm=false
if [[ "${PACKAGE_MODE}" == "all" || "${PACKAGE_MODE}" == "deb-appimage" || "${PACKAGE_MODE}" == "deb" ]]; then
    builds_deb=true
fi
if [[ "${PACKAGE_MODE}" == "all" || "${PACKAGE_MODE}" == "deb-appimage" || "${PACKAGE_MODE}" == "appimage" ]]; then
    builds_appimage=true
fi
if [[ "${PACKAGE_MODE}" == "all" || "${PACKAGE_MODE}" == "rpm" ]]; then
    builds_rpm=true
fi

CMAKE_ARGS=(
    -DCMAKE_BUILD_TYPE=Release
    "-DSPACE_BUILD_PROFILE=${PROFILE}"
)
if [[ "${PROFILE}" == "minimal" ]]; then
    CMAKE_ARGS+=(-DSPACE_ENABLE_CEF=OFF)
else
    CMAKE_ARGS+=(-DSPACE_ENABLE_CEF=ON)
fi
if [[ "${NO_MATRIX}" == true ]]; then
    CMAKE_ARGS+=(-DSPACE_BUILD_MATRIX=OFF)
fi

cmake -B "${BUILD_DIR}" "${CMAKE_ARGS[@]}"
cmake --build "${BUILD_DIR}" --config Release

PACKAGE_MARKER="${BUILD_DIR}/.package-build-start"
rm -f "${PACKAGE_MARKER}"
touch "${PACKAGE_MARKER}"
(
    cd "${BUILD_DIR}"
    if [[ "${builds_deb}" == true ]]; then
        cpack -G DEB
    fi
    if [[ "${builds_rpm}" == true ]]; then
        cpack -G RPM
    fi
)

mkdir -p "${BUILD_DIR}/dist"
TARBALL_ROOT="${BUILD_DIR}/dist/tar-root"

VARIANT_SUFFIX=""
APPIMAGE_BASE="space"
if [[ "${PROFILE}" == "minimal" ]]; then
    VARIANT_SUFFIX="-minimal"
    APPIMAGE_BASE="space-minimal"
fi

DEB_FLAVOR_SUFFIX=""
RPM_FLAVOR_SUFFIX=""
if [[ -n "${DEB_FLAVOR}" ]]; then
    DEB_FLAVOR_SUFFIX="-${DEB_FLAVOR}"
fi
if [[ -n "${RPM_FLAVOR}" ]]; then
    RPM_FLAVOR_SUFFIX="-${RPM_FLAVOR}"
fi

BIN_TAR_NAME="space-linux-x86_64${VARIANT_SUFFIX}.tar.gz"
STABLE_APPIMAGE_NAME="space-linux-x86_64${VARIANT_SUFFIX}.AppImage"
STABLE_DEB_NAME="space-linux-amd64${DEB_FLAVOR_SUFFIX}${VARIANT_SUFFIX}.deb"
STABLE_RPM_NAME="space-linux-x86_64${RPM_FLAVOR_SUFFIX}${VARIANT_SUFFIX}.rpm"

RELEASE_MANIFEST="${BUILD_DIR}/release-artifacts-${PROFILE}.txt"
RELEASE_DEB_PATH="${BUILD_DIR}/${STABLE_DEB_NAME}"
RELEASE_RPM_PATH="${BUILD_DIR}/${STABLE_RPM_NAME}"
RELEASE_APPIMAGE_PATH="${BUILD_DIR}/${STABLE_APPIMAGE_NAME}"
RELEASE_TAR_PATH="${BUILD_DIR}/dist/${BIN_TAR_NAME}"

if [[ "${builds_appimage}" == true ]]; then
    rm -rf "${TARBALL_ROOT}"
    cmake --install "${BUILD_DIR}" --prefix "${TARBALL_ROOT}"
    cat > "${TARBALL_ROOT}/space" <<'LAUNCHER'
#!/bin/sh
set -eu
HERE="$(dirname "$(readlink -f "$0")")"
export SPACE_ASSETS_PATH="${SPACE_ASSETS_PATH:-$HERE/share/space/assets}"
exec "$HERE/bin/space" "$@"
LAUNCHER
    chmod +x "${TARBALL_ROOT}/space"
    tar -czf "${RELEASE_TAR_PATH}" -C "${TARBALL_ROOT}" space bin lib share
    SPACE_BUILD_DIR="${BUILD_DIR}" SPACE_APPIMAGE_BASENAME="${APPIMAGE_BASE}" SPACE_INSTALL_PREFIX="${TARBALL_ROOT}" scripts/build-appimage.sh
fi

APPIMAGE_SRC=""
if [[ "${builds_appimage}" == true ]]; then
    APPIMAGE_SRC="$(
        find "${BUILD_DIR}" -maxdepth 1 -type f -name "${APPIMAGE_BASE}-*-x86_64.AppImage" -newer "${PACKAGE_MARKER}" -print \
            | sort \
            | head -n1
    )"
fi
DEB_SRC="$(
    find "${BUILD_DIR}" -maxdepth 1 -type f -name 'space-*-Linux.deb' -newer "${PACKAGE_MARKER}" -print \
        | sort \
        | head -n1
)"
RPM_SRC="$(
    find "${BUILD_DIR}" -maxdepth 1 -type f -name 'space-*-Linux.rpm' -newer "${PACKAGE_MARKER}" -print \
        | sort \
        | head -n1
)"
rm -f "${PACKAGE_MARKER}"

if [[ "${builds_deb}" == true && -z "${DEB_SRC}" ]]; then
    echo "error: failed to locate generated DEB package in ${BUILD_DIR}" >&2
    exit 1
fi
if [[ "${builds_rpm}" == true && -z "${RPM_SRC}" ]]; then
    echo "error: failed to locate generated RPM package in ${BUILD_DIR}" >&2
    exit 1
fi
if [[ "${builds_appimage}" == true && -z "${APPIMAGE_SRC}" ]]; then
    echo "error: failed to locate generated AppImage in ${BUILD_DIR}" >&2
    exit 1
fi

if [[ "${builds_deb}" == true ]]; then
    cp "${DEB_SRC}" "${RELEASE_DEB_PATH}"
fi
if [[ "${builds_appimage}" == true ]]; then
    cp "${APPIMAGE_SRC}" "${RELEASE_APPIMAGE_PATH}"
fi
if [[ "${builds_rpm}" == true ]]; then
    cp "${RPM_SRC}" "${RELEASE_RPM_PATH}"
fi

EXPECTED_ARTIFACTS=()
if [[ "${builds_deb}" == true ]]; then
    EXPECTED_ARTIFACTS+=("${RELEASE_DEB_PATH}")
fi
if [[ "${builds_appimage}" == true ]]; then
    EXPECTED_ARTIFACTS+=(
        "${RELEASE_APPIMAGE_PATH}"
        "${RELEASE_TAR_PATH}"
    )
fi
if [[ "${builds_rpm}" == true ]]; then
    EXPECTED_ARTIFACTS+=("${RELEASE_RPM_PATH}")
fi

for artifact in "${EXPECTED_ARTIFACTS[@]}"; do
    if [[ ! -f "${artifact}" ]]; then
        echo "error: expected release artifact missing: ${artifact}" >&2
        exit 1
    fi
done

printf '%s\n' "${EXPECTED_ARTIFACTS[@]}" > "${RELEASE_MANIFEST}"
