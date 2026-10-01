#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/windows}"
DIST_DIR="${1:-${ROOT_DIR}/build/dist/windows}"
TARGET_EXE="${BUILD_DIR}/space.exe"
CLI_EXE="${BUILD_DIR}/space-cli.exe"
TZDATA_SOURCE="${ROOT_DIR}/external/date/tzdata"
TEMPORAL_METADATA_SOURCE="${ROOT_DIR}/external/temporal"

if [ ! -d "${BUILD_DIR}" ]; then
    echo "Missing build directory: ${BUILD_DIR}" >&2
    exit 1
fi
if [ ! -f "${TARGET_EXE}" ]; then
    echo "Missing target executable: ${TARGET_EXE}" >&2
    exit 1
fi
if [ ! -f "${CLI_EXE}" ]; then
    echo "Missing CLI executable: ${CLI_EXE}" >&2
    exit 1
fi
if [ ! -d "${TZDATA_SOURCE}" ]; then
    echo "Missing bundled Windows temporal tzdata: ${TZDATA_SOURCE}" >&2
    exit 1
fi
if [ ! -d "${TEMPORAL_METADATA_SOURCE}" ]; then
    echo "Missing Windows temporal dependency metadata: ${TEMPORAL_METADATA_SOURCE}" >&2
    exit 1
fi
for required_tzdata_file in \
    africa \
    antarctica \
    asia \
    australasia \
    backward \
    etcetera \
    europe \
    northamerica \
    southamerica \
    leapseconds \
    version \
    windowsZones.xml \
    LICENSE \
    CLDR-LICENSE.txt
do
    if [ ! -f "${TZDATA_SOURCE}/${required_tzdata_file}" ]; then
        echo "Missing bundled Windows temporal tzdata file: ${TZDATA_SOURCE}/${required_tzdata_file}" >&2
        exit 1
    fi
done
for required_temporal_manifest in \
    icu/DEPENDENCY_MANIFEST.json \
    libical/DEPENDENCY_MANIFEST.json \
    holidays/DEPENDENCY_MANIFEST.json
do
    if [ ! -f "${TEMPORAL_METADATA_SOURCE}/${required_temporal_manifest}" ]; then
        echo "Missing Windows temporal dependency manifest: ${TEMPORAL_METADATA_SOURCE}/${required_temporal_manifest}" >&2
        exit 1
    fi
done

"${ROOT_DIR}/scripts/prepare-windows-runtime.sh" "${TARGET_EXE}"
"${ROOT_DIR}/scripts/prepare-windows-runtime.sh" "${CLI_EXE}"

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"
cp "${TARGET_EXE}" "${DIST_DIR}/"
cp "${CLI_EXE}" "${DIST_DIR}/"
cp -r "${ROOT_DIR}/assets" "${DIST_DIR}/assets"
cp -r "${TZDATA_SOURCE}" "${DIST_DIR}/tzdata"
mkdir -p "${DIST_DIR}/external"
cp -r "${TEMPORAL_METADATA_SOURCE}" "${DIST_DIR}/external/temporal"
find "${BUILD_DIR}" -maxdepth 1 -type f -name '*.dll' -exec cp {} "${DIST_DIR}/" \;

echo "Windows runtime package prepared in ${DIST_DIR}"
