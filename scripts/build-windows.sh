#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build/windows}"
VCPKG_ROOT="${VCPKG_ROOT:-${ROOT_DIR}/vcpkg}"
VCPKG_TRIPLET="${VCPKG_TARGET_TRIPLET:-x64-mingw-dynamic-posix}"
VCPKG_OVERLAY_TRIPLETS="${VCPKG_OVERLAY_TRIPLETS:-${ROOT_DIR}/scripts/vcpkg-triplets}"
VCPKG_OVERLAY_PORTS="${VCPKG_OVERLAY_PORTS:-${ROOT_DIR}/scripts/vcpkg-ports}"
VCPKG_BUILD_TYPE="${VCPKG_BUILD_TYPE:-release}"
VCPKG_PACKAGES="${VCPKG_PACKAGES:-sdl3 libepoxy bullet3 glm openal-soft curl zeromq cppzmq portaudio aubio xapian libpng freetype sqlite3 boost-headers boost-uuid ffmpeg[openssl] libtorrent}"
CROSS_CC="${CROSS_CC:-x86_64-w64-mingw32-gcc-posix}"
CROSS_CXX="${CROSS_CXX:-x86_64-w64-mingw32-g++-posix}"
RUST_TARGET="${RUST_TARGET:-x86_64-pc-windows-gnu}"
CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="${CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER:-x86_64-w64-mingw32-gcc-posix}"
SPACE_ENABLE_LIBTORRENT="${SPACE_ENABLE_LIBTORRENT:-ON}"
SPACE_ENABLE_FFMPEG="${SPACE_ENABLE_FFMPEG:-ON}"
WRAPPER_RESTORE_DIR=""
WRAPPER_RESTORE_MAP_FILE=""

if [ ! -d "${VCPKG_ROOT}" ]; then
    echo "VCPKG_ROOT not found: ${VCPKG_ROOT}" >&2
    echo "Set VCPKG_ROOT or clone vcpkg into ${ROOT_DIR}/vcpkg." >&2
    exit 1
fi

vcpkg_bin="${VCPKG_ROOT}/vcpkg"
if [ ! -x "${vcpkg_bin}" ] && [ -x "${vcpkg_bin}.exe" ]; then
    vcpkg_bin="${vcpkg_bin}.exe"
fi
if [ ! -x "${vcpkg_bin}" ]; then
    echo "vcpkg executable not found. Run bootstrap-vcpkg first." >&2
    exit 1
fi

triplet_file=""
for candidate in "${VCPKG_TRIPLET}" x64-mingw-dynamic-posix x64-mingw-dynamic x64-mingw-static; do
    for dir in "${VCPKG_OVERLAY_TRIPLETS}" "${VCPKG_ROOT}/triplets" "${VCPKG_ROOT}/triplets/community"; do
        if [ -f "${dir}/${candidate}.cmake" ]; then
            VCPKG_TRIPLET="${candidate}"
            triplet_file="${dir}/${candidate}.cmake"
            break
        fi
    done
    if [ -n "${triplet_file}" ]; then
        break
    fi
done
if [ -z "${triplet_file}" ]; then
    echo "Vcpkg triplet not found for mingw. Available mingw triplets:" >&2
    find "${VCPKG_ROOT}/triplets" "${VCPKG_ROOT}/triplets/community" -maxdepth 1 -name "*mingw*.cmake" -print >&2 || true
    exit 1
fi

export VCPKG_TARGET_TRIPLET="${VCPKG_TRIPLET}"
export VCPKG_BUILD_TYPE

cleanup_toolwrap() {
    if [ -n "${toolwrap_dir:-}" ] && [ -d "${toolwrap_dir}" ]; then
        rm -rf "${toolwrap_dir}"
    fi
}

cleanup_wrapper_overrides() {
    if [ -n "${WRAPPER_RESTORE_MAP_FILE}" ] && [ -f "${WRAPPER_RESTORE_MAP_FILE}" ]; then
        while IFS= read -r entry; do
            [ -z "${entry}" ] && continue
            wrapper_path="${entry%%|*}"
            backup_path="${entry#*|}"
            if [ -f "${backup_path}" ]; then
                cp "${backup_path}" "${wrapper_path}"
            fi
        done < "${WRAPPER_RESTORE_MAP_FILE}"
    fi
    if [ -n "${WRAPPER_RESTORE_DIR}" ] && [ -d "${WRAPPER_RESTORE_DIR}" ]; then
        rm -rf "${WRAPPER_RESTORE_DIR}"
    fi
}

cleanup_on_exit() {
    cleanup_wrapper_overrides
    cleanup_toolwrap
}

trap cleanup_on_exit EXIT

if command -v x86_64-w64-mingw32-gcc-posix >/dev/null 2>&1 && command -v x86_64-w64-mingw32-g++-posix >/dev/null 2>&1; then
    toolwrap_dir="$(mktemp -d)"
    ln -sf "$(command -v x86_64-w64-mingw32-gcc-posix)" "${toolwrap_dir}/x86_64-w64-mingw32-gcc"
    ln -sf "$(command -v x86_64-w64-mingw32-g++-posix)" "${toolwrap_dir}/x86_64-w64-mingw32-g++"
    for tool in dlltool ar nm ranlib strip windres; do
        prefixed_tool="x86_64-w64-mingw32-${tool}"
        if command -v "${prefixed_tool}" >/dev/null 2>&1; then
            ln -sf "$(command -v "${prefixed_tool}")" "${toolwrap_dir}/${tool}"
        fi
    done
    export PATH="${toolwrap_dir}:${PATH}"
fi

if [ -n "${VCPKG_PACKAGES}" ]; then
    "${vcpkg_bin}" install \
        --recurse \
        --triplet "${VCPKG_TRIPLET}" \
        --overlay-triplets "${VCPKG_OVERLAY_TRIPLETS}" \
        --overlay-ports "${VCPKG_OVERLAY_PORTS}" \
        ${VCPKG_PACKAGES}
fi

backup_wrapper_path() {
    local wrapper_path="$1"
    local backup_path
    if [ -z "${WRAPPER_RESTORE_DIR}" ]; then
        WRAPPER_RESTORE_DIR="$(mktemp -d)"
        WRAPPER_RESTORE_MAP_FILE="${WRAPPER_RESTORE_DIR}/map.txt"
        : > "${WRAPPER_RESTORE_MAP_FILE}"
    fi
    backup_path="${WRAPPER_RESTORE_DIR}/$(basename "${wrapper_path}").$$"
    cp "${wrapper_path}" "${backup_path}"
    printf '%s|%s\n' "${wrapper_path}" "${backup_path}" >> "${WRAPPER_RESTORE_MAP_FILE}"
}

patch_zlib_wrapper_for_mingw_import_libs() {
    local wrapper_path
    wrapper_path="${VCPKG_ROOT}/installed/${VCPKG_TRIPLET}/share/zlib/vcpkg-cmake-wrapper.cmake"
    if [ ! -f "${wrapper_path}" ]; then
        return
    fi
    backup_wrapper_path "${wrapper_path}"

    cat >"${wrapper_path}" <<'EOF'
find_path(ZLIB_INCLUDE_DIR NAMES zlib.h PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/include" NO_DEFAULT_PATH)
find_library(ZLIB_LIBRARY_RELEASE NAMES zlib z PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(ZLIB_LIBRARY_DEBUG   NAMES zlibd z PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/debug/lib" NO_DEFAULT_PATH)

if(NOT ZLIB_LIBRARY_RELEASE)
    find_file(
        ZLIB_LIBRARY_RELEASE
        NAMES libzlib.dll.a libzlib.a zlib.lib
        PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib"
        NO_DEFAULT_PATH
    )
endif()

if(NOT ZLIB_LIBRARY_DEBUG)
    find_file(
        ZLIB_LIBRARY_DEBUG
        NAMES libzlibd.dll.a libzlibd.a zlibd.lib
        PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/debug/lib"
        NO_DEFAULT_PATH
    )
endif()

if(NOT ZLIB_INCLUDE_DIR OR NOT (ZLIB_LIBRARY_RELEASE OR ZLIB_LIBRARY_DEBUG))
    message(FATAL_ERROR "Broken installation of vcpkg port zlib")
endif()
if(CMAKE_VERSION VERSION_LESS 3.4)
    include(SelectLibraryConfigurations)
    select_library_configurations(ZLIB)
    unset(ZLIB_FOUND)
endif()
_find_package(${ARGS})
EOF
}

patch_png_wrapper_for_mingw_import_libs() {
    local wrapper_path
    wrapper_path="${VCPKG_ROOT}/installed/${VCPKG_TRIPLET}/share/png/vcpkg-cmake-wrapper.cmake"
    if [ ! -f "${wrapper_path}" ]; then
        return
    fi
    backup_wrapper_path "${wrapper_path}"

    cat >"${wrapper_path}" <<'EOF'
find_library(PNG_LIBRARY_RELEASE NAMES png16 libpng16 NAMES_PER_DIR PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib" NO_DEFAULT_PATH)
find_library(PNG_LIBRARY_DEBUG NAMES png16d libpng16d NAMES_PER_DIR PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/debug/lib" NO_DEFAULT_PATH)

if(NOT PNG_LIBRARY_RELEASE)
    find_file(
        PNG_LIBRARY_RELEASE
        NAMES libpng16.dll.a libpng.dll.a libpng16.a libpng.a png16.lib
        PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib"
        NO_DEFAULT_PATH
    )
endif()

if(NOT PNG_LIBRARY_DEBUG)
    find_file(
        PNG_LIBRARY_DEBUG
        NAMES libpng16d.dll.a libpngd.dll.a libpng16d.a libpngd.a png16d.lib
        PATHS "${_VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/debug/lib"
        NO_DEFAULT_PATH
    )
endif()

_find_package(${ARGS})
EOF
}

patch_zlib_wrapper_for_mingw_import_libs
patch_png_wrapper_for_mingw_import_libs

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

export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER

pkgconfig_paths=(
    "${VCPKG_ROOT}/installed/${VCPKG_TRIPLET}/lib/pkgconfig"
    "${VCPKG_ROOT}/installed/${VCPKG_TRIPLET}/share/pkgconfig"
)
pkgconfig_libdirs=()
for path in "${pkgconfig_paths[@]}"; do
    if [ -d "${path}" ]; then
        pkgconfig_libdirs+=("${path}")
    fi
done
if [ "${#pkgconfig_libdirs[@]}" -gt 0 ]; then
    pkgconfig_joined=""
    for path in "${pkgconfig_libdirs[@]}"; do
        if [ -z "${pkgconfig_joined}" ]; then
            pkgconfig_joined="${path}"
        else
            pkgconfig_joined="${pkgconfig_joined}:${path}"
        fi
    done
    # Prefer triplet pkg-config entries first while keeping system metadata available
    # for transitive requirements such as epoxy -> gl.
    export PKG_CONFIG_PATH="${pkgconfig_joined}${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
fi
triplet_lib_dir="${VCPKG_ROOT}/installed/${VCPKG_TRIPLET}/lib"
if [ -d "${triplet_lib_dir}" ]; then
    export LIBRARY_PATH="${triplet_lib_dir}${LIBRARY_PATH:+:${LIBRARY_PATH}}"
    rust_native_flag="-Lnative=${triplet_lib_dir}"
    if [ -n "${CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUSTFLAGS:-}" ]; then
        export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUSTFLAGS="${CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUSTFLAGS} ${rust_native_flag}"
    else
        export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUSTFLAGS="${rust_native_flag}"
    fi
fi

if command -v pkg-config >/dev/null 2>&1; then
    required_pc_modules=(libzmq portaudio-2.0 epoxy xapian-core)
    for module in "${required_pc_modules[@]}"; do
        if ! pkg-config --exists "${module}"; then
            echo "Missing pkg-config module '${module}' for triplet '${VCPKG_TRIPLET}'." >&2
            echo "Install/update vcpkg dependencies (VCPKG_PACKAGES) before configuring CMake." >&2
            exit 1
        fi
    done
fi

cmake_args=(
    -S "${ROOT_DIR}"
    -B "${BUILD_DIR}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_SYSTEM_NAME=Windows
    -DCMAKE_SYSTEM_PROCESSOR=x86_64
    -DCMAKE_FIND_LIBRARY_PREFIXES:STRING=lib\;
    -DCMAKE_FIND_LIBRARY_SUFFIXES:STRING=.dll.a\;.a\;.lib
    -DCMAKE_TOOLCHAIN_FILE="${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"
    -DVCPKG_CHAINLOAD_TOOLCHAIN_FILE="${VCPKG_OVERLAY_TRIPLETS}/mingw-posix-toolchain.cmake"
    -DVCPKG_TARGET_TRIPLET="${VCPKG_TRIPLET}"
    -DVCPKG_OVERLAY_TRIPLETS="${VCPKG_OVERLAY_TRIPLETS}"
    -DVCPKG_OVERLAY_PORTS="${VCPKG_OVERLAY_PORTS}"
    -DSPACE_ENABLE_LIBTORRENT="${SPACE_ENABLE_LIBTORRENT}"
    -DSPACE_ENABLE_FFMPEG="${SPACE_ENABLE_FFMPEG}"
)
if [ -n "${CROSS_CC}" ]; then
    cmake_args+=(-DCMAKE_C_COMPILER="${CROSS_CC}")
fi
if [ -n "${CROSS_CXX}" ]; then
    cmake_args+=(-DCMAKE_CXX_COMPILER="${CROSS_CXX}")
fi
if [ -n "${CMAKE_C_COMPILER_LAUNCHER:-}" ]; then
    cmake_args+=(-DCMAKE_C_COMPILER_LAUNCHER="${CMAKE_C_COMPILER_LAUNCHER}")
fi
if [ -n "${CMAKE_CXX_COMPILER_LAUNCHER:-}" ]; then
    cmake_args+=(-DCMAKE_CXX_COMPILER_LAUNCHER="${CMAKE_CXX_COMPILER_LAUNCHER}")
fi
if [ -n "${CMAKE_ASM_MASM_COMPILER:-}" ]; then
    cmake_args+=(-DCMAKE_ASM_MASM_COMPILER="${CMAKE_ASM_MASM_COMPILER}")
fi
if [ -n "${CMAKE_ASM_MASM_FLAGS:-}" ]; then
    cmake_args+=(-DCMAKE_ASM_MASM_FLAGS="${CMAKE_ASM_MASM_FLAGS}")
fi

if [ -n "${CMAKE_GENERATOR:-}" ]; then
    cmake_args+=(-G "${CMAKE_GENERATOR}")
fi

cache_file="${BUILD_DIR}/CMakeCache.txt"
if [ -f "${cache_file}" ]; then
    needs_reset=0
    if ! grep -Eq '^CMAKE_SYSTEM_NAME:.*=Windows$' "${cache_file}"; then
        needs_reset=1
    fi
    if ! grep -Eq '^VCPKG_CHAINLOAD_TOOLCHAIN_FILE:.*=.+mingw-posix-toolchain\.cmake$' "${cache_file}"; then
        needs_reset=1
    fi
    if [ "${needs_reset}" -eq 1 ]; then
        echo "Resetting ${BUILD_DIR} due to stale CMake cache." >&2
        rm -rf "${BUILD_DIR}"
    fi
fi

cmake "${cmake_args[@]}"
cmake --build "${BUILD_DIR}" --config Release --target space space-cli
