cmake_minimum_required(VERSION 3.18.0)
set(CMAKE_CXX_STANDARD 17)
project(space VERSION 0.1.0)

option(SPACE_ENABLE_CCACHE "Use ccache to speed up rebuilds" ON)

if(SPACE_ENABLE_CCACHE)
    find_program(CCACHE_PROGRAM ccache)
    if(CCACHE_PROGRAM)
        get_filename_component(_ccache_base_dir "${CMAKE_SOURCE_DIR}" ABSOLUTE)
        if(NOT CMAKE_C_COMPILER_LAUNCHER)
            set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM};base_dir=${_ccache_base_dir}")
        endif()
        if(NOT CMAKE_CXX_COMPILER_LAUNCHER)
            set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM};base_dir=${_ccache_base_dir}")
        endif()
        message(STATUS "ccache found and enabled as compiler launcher (base_dir=${_ccache_base_dir})")
    endif()
endif()

set(OpenGL_GL_PREFERENCE "GLVND")
find_package(Python3 REQUIRED COMPONENTS Interpreter)

if(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
    message(STATUS "CMAKE_BUILD_TYPE not set, defaulting to Release")
endif()

set(SPACE_VERSION "" CACHE STRING "Override app/package version (defaults to git tag-derived version)")
set(SPACE_PACKAGE_VERSION "")

if(NOT SPACE_VERSION)
    find_package(Git QUIET)
    if(GIT_FOUND)
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" -C "${CMAKE_SOURCE_DIR}" describe --tags --match "v*" --abbrev=8 --dirty
            OUTPUT_VARIABLE SPACE_GIT_DESCRIBE
            RESULT_VARIABLE SPACE_GIT_DESCRIBE_RESULT
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(SPACE_GIT_DESCRIBE_RESULT EQUAL 0 AND SPACE_GIT_DESCRIBE)
            if(SPACE_GIT_DESCRIBE MATCHES "^v(.+)-([0-9]+)-g([0-9a-f]+)(-dirty)?$")
                set(_space_version_base "${CMAKE_MATCH_1}")
                set(_space_version_count "${CMAKE_MATCH_2}")
                set(_space_version_sha "${CMAKE_MATCH_3}")
                set(_space_version_dirty "${CMAKE_MATCH_4}")
                if(_space_version_dirty)
                    set(_space_version_dirty ".dirty")
                endif()
                set(SPACE_VERSION "${_space_version_base}+git.${_space_version_count}.g${_space_version_sha}${_space_version_dirty}")
            elseif(SPACE_GIT_DESCRIBE MATCHES "^v(.+)$")
                set(SPACE_VERSION "${CMAKE_MATCH_1}")
            else()
                set(SPACE_VERSION "${SPACE_GIT_DESCRIBE}")
            endif()
        endif()
    endif()
endif()

if(NOT SPACE_VERSION)
    set(SPACE_VERSION "${PROJECT_VERSION}+unknown")
endif()

set(SPACE_PACKAGE_VERSION "${SPACE_VERSION}")
string(REPLACE "-" "." SPACE_PACKAGE_VERSION "${SPACE_PACKAGE_VERSION}")
string(REGEX REPLACE "[^0-9A-Za-z.+~]" "." SPACE_PACKAGE_VERSION "${SPACE_PACKAGE_VERSION}")
if(NOT SPACE_PACKAGE_VERSION MATCHES "^[0-9]")
    set(SPACE_PACKAGE_VERSION "0.${SPACE_PACKAGE_VERSION}")
endif()

message(STATUS "space version: ${SPACE_VERSION} (package: ${SPACE_PACKAGE_VERSION})")

set(SPACE_PACKAGE_VENDOR "Humanity")
set(SPACE_PACKAGE_DESCRIPTION "space")

set(SPACE_WINDOWS_FILE_VERSION_MAJOR "${PROJECT_VERSION_MAJOR}")
set(SPACE_WINDOWS_FILE_VERSION_MINOR "${PROJECT_VERSION_MINOR}")
set(SPACE_WINDOWS_FILE_VERSION_PATCH "${PROJECT_VERSION_PATCH}")
set(SPACE_WINDOWS_FILE_VERSION_BUILD 0)
if(SPACE_PACKAGE_VERSION MATCHES "^([0-9]+)(\\.([0-9]+))?(\\.([0-9]+))?(\\.([0-9]+))?")
    set(SPACE_WINDOWS_FILE_VERSION_MAJOR "${CMAKE_MATCH_1}")
    if(DEFINED CMAKE_MATCH_3 AND NOT CMAKE_MATCH_3 STREQUAL "")
        set(SPACE_WINDOWS_FILE_VERSION_MINOR "${CMAKE_MATCH_3}")
    endif()
    if(DEFINED CMAKE_MATCH_5 AND NOT CMAKE_MATCH_5 STREQUAL "")
        set(SPACE_WINDOWS_FILE_VERSION_PATCH "${CMAKE_MATCH_5}")
    endif()
    if(DEFINED CMAKE_MATCH_7 AND NOT CMAKE_MATCH_7 STREQUAL "")
        set(SPACE_WINDOWS_FILE_VERSION_BUILD "${CMAKE_MATCH_7}")
    endif()
endif()
set(SPACE_WINDOWS_FILE_VERSION_COMMAS
    "${SPACE_WINDOWS_FILE_VERSION_MAJOR},${SPACE_WINDOWS_FILE_VERSION_MINOR},${SPACE_WINDOWS_FILE_VERSION_PATCH},${SPACE_WINDOWS_FILE_VERSION_BUILD}")

include(CTest)
enable_testing()
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/cef-defaults.cmake)

option(SPACE_BUILD_MATRIX "Build Matrix Rust library" ON)
option(SPACE_SUPPRESS_THIRD_PARTY_WARNINGS "Suppress warnings from third-party libraries" ON)
option(SPACE_ENABLE_WALLET_CORE "Build wallet-core integration" OFF)
option(SPACE_ENABLE_LIBTORRENT "Build libtorrent-rasterbar integration" ON)
option(SPACE_ENABLE_FFMPEG "Build FFmpeg-backed in-world video support" ON)
option(SPACE_ENABLE_CEF "Enable CEF embedded browser support" ${SPACE_DEFAULT_ENABLE_CEF})
set(SPACE_BUILD_PROFILE "full" CACHE STRING "Build profile (full|minimal)")
set_property(CACHE SPACE_BUILD_PROFILE PROPERTY STRINGS full minimal)
set(SPACE_MINIMAL_DISABLED_OPTIONS "SPACE_ENABLE_CEF" CACHE STRING
    "Semicolon-separated CMake option names forced OFF when SPACE_BUILD_PROFILE=minimal")
if(NOT SPACE_BUILD_PROFILE STREQUAL "full" AND NOT SPACE_BUILD_PROFILE STREQUAL "minimal")
    message(FATAL_ERROR "SPACE_BUILD_PROFILE must be one of: full, minimal")
endif()
if(SPACE_BUILD_PROFILE STREQUAL "minimal")
    foreach(_space_option IN LISTS SPACE_MINIMAL_DISABLED_OPTIONS)
        if(DEFINED ${_space_option})
            set(${_space_option} OFF CACHE BOOL
                "Disabled by SPACE_BUILD_PROFILE=minimal via SPACE_MINIMAL_DISABLED_OPTIONS" FORCE)
            message(STATUS "SPACE_BUILD_PROFILE=minimal: forcing ${_space_option}=OFF")
        else()
            message(WARNING
                "SPACE_BUILD_PROFILE=minimal requested disabling unknown option '${_space_option}'")
        endif()
    endforeach()
endif()
set(SPACE_CEF_VERSION "${SPACE_CEF_LINUX_VERSION_DEFAULT}" CACHE STRING "Pinned CEF build version")
set(SPACE_CEF_URL "${SPACE_CEF_LINUX_URL_DEFAULT}" CACHE STRING "Pinned CEF archive URL")
set(SPACE_CEF_SHA256 "${SPACE_CEF_LINUX_SHA256_DEFAULT}" CACHE STRING "Pinned CEF archive SHA256")
set(SPACE_CEF_DOWNLOAD_DIR "${CMAKE_BINARY_DIR}/_deps/cef" CACHE PATH "Directory used to cache downloaded CEF archives")
if(SPACE_ENABLE_CEF)
    set(CMAKE_CXX_STANDARD 20)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    if(NOT SPACE_CEF_VERSION)
        set(SPACE_CEF_VERSION "${SPACE_CEF_LINUX_VERSION_DEFAULT}" CACHE STRING "Pinned CEF build version" FORCE)
    endif()
    if(NOT SPACE_CEF_URL)
        set(SPACE_CEF_URL "${SPACE_CEF_LINUX_URL_DEFAULT}" CACHE STRING "Pinned CEF archive URL" FORCE)
    endif()
    if(NOT SPACE_CEF_SHA256)
        set(SPACE_CEF_SHA256 "${SPACE_CEF_LINUX_SHA256_DEFAULT}" CACHE STRING "Pinned CEF archive SHA256" FORCE)
    endif()
endif()

function(space_suppress_target_warnings target_name)
    if(TARGET ${target_name})
        get_target_property(target_type ${target_name} TYPE)
        if(target_type STREQUAL "INTERFACE_LIBRARY")
            if(MSVC)
                target_compile_options(${target_name} INTERFACE /W0)
            else()
                target_compile_options(${target_name} INTERFACE -w)
            endif()
        else()
            if(MSVC)
                target_compile_options(${target_name} PRIVATE /W0)
            else()
                target_compile_options(${target_name} PRIVATE -w)
            endif()
        endif()
    endif()
endfunction()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build static libraries")
add_subdirectory(external/lua)

add_subdirectory(external/sqlite)

add_subdirectory(external/tree-sitter)
if(WIN32)
    set(SPACE_ENABLE_WALLET_CORE OFF)
endif()
if(SPACE_ENABLE_WALLET_CORE)
    set(TW_UNIT_TESTS OFF CACHE BOOL "Disable wallet-core unit tests" FORCE)
    set(TW_BUILD_EXAMPLES OFF CACHE BOOL "Disable wallet-core examples" FORCE)
    set(TW_TREZOR_TESTS OFF CACHE BOOL "Disable trezor-crypto tests" FORCE)
    add_subdirectory(external/wallet-core)
endif()

set(MSDF_ATLAS_BUILD_STANDALONE OFF CACHE BOOL "Disable msdf-atlas-gen standalone build" FORCE)
set(MSDF_ATLAS_USE_VCPKG OFF CACHE BOOL "Disable msdf-atlas-gen vcpkg integration" FORCE)
set(MSDF_ATLAS_USE_SKIA OFF CACHE BOOL "Disable msdf-atlas-gen Skia integration" FORCE)
set(MSDF_ATLAS_INSTALL OFF CACHE BOOL "Disable msdf-atlas-gen install targets" FORCE)
set(MSDFGEN_BUILD_STANDALONE OFF CACHE BOOL "Disable msdfgen standalone build" FORCE)
set(MSDFGEN_USE_VCPKG OFF CACHE BOOL "Disable msdfgen vcpkg integration" FORCE)
set(MSDFGEN_USE_SKIA OFF CACHE BOOL "Disable msdfgen Skia integration" FORCE)
add_subdirectory(external/msdf-atlas-gen)

set(LIBJPEG_TURBO_ALLOW_SUBPROJECT ON CACHE BOOL "Allow libjpeg-turbo subproject" FORCE)
set(LIBJPEG_TURBO_BUILD_TOOLS OFF CACHE BOOL "Disable libjpeg-turbo tools" FORCE)
set(LIBJPEG_TURBO_BUILD_TESTS OFF CACHE BOOL "Disable libjpeg-turbo tests" FORCE)
set(ENABLE_SHARED OFF CACHE BOOL "Disable libjpeg-turbo shared build" FORCE)
set(ENABLE_STATIC ON CACHE BOOL "Enable libjpeg-turbo static build" FORCE)
set(WITH_TURBOJPEG OFF CACHE BOOL "Disable TurboJPEG API" FORCE)
set(WITH_JAVA OFF CACHE BOOL "Disable libjpeg-turbo Java" FORCE)
set(WITH_FUZZ OFF CACHE BOOL "Disable libjpeg-turbo fuzz targets" FORCE)
set(WITH_SIMD OFF CACHE BOOL "Disable libjpeg-turbo SIMD" FORCE)
add_subdirectory(external/libjpeg-turbo)

set(EFSW_BUILD_STATIC_LIBS OFF CACHE BOOL "Disable extra efsw-static library" FORCE)
set(EFSW_BUILD_TEST_APP OFF CACHE BOOL "Disable efsw test app" FORCE)
set(EFSW_INSTALL OFF CACHE BOOL "Disable efsw install targets" FORCE)
add_subdirectory(external/efsw)

include_directories(SYSTEM ${CMAKE_SOURCE_DIR}/external/sol2)

include_directories(SYSTEM ${CMAKE_SOURCE_DIR}/external/cgltf)
include_directories(SYSTEM ${CMAKE_SOURCE_DIR}/external/cppzmq)
find_package(PkgConfig REQUIRED)
set(SPACE_HAS_VTERM OFF)
if(UNIX AND NOT APPLE)
    pkg_check_modules(VTERM REQUIRED IMPORTED_TARGET vterm)
    set(SPACE_HAS_VTERM ON)
    pkg_check_modules(LIBGCCJIT IMPORTED_TARGET libgccjit)
    if(NOT LIBGCCJIT_FOUND)
        find_path(LIBGCCJIT_INCLUDE_DIR
            NAMES libgccjit.h
            PATHS
                /usr/lib/gcc/x86_64-linux-gnu/11/include
                /usr/lib/gcc/x86_64-linux-gnu/12/include
                /usr/lib/gcc/x86_64-linux-gnu/13/include
                /usr/include
        )
        find_library(LIBGCCJIT_LIBRARY
            NAMES gccjit libgccjit
            PATHS
                /usr/lib/gcc/x86_64-linux-gnu/11
                /usr/lib/gcc/x86_64-linux-gnu/12
                /usr/lib/gcc/x86_64-linux-gnu/13
                /usr/lib/x86_64-linux-gnu
                /usr/lib
        )
        if(NOT LIBGCCJIT_INCLUDE_DIR OR NOT LIBGCCJIT_LIBRARY)
            message(FATAL_ERROR "libgccjit not found. Install libgccjit-11-dev, libgccjit-devel, or equivalent.")
        endif()
        add_library(space_gccjit INTERFACE)
        target_include_directories(space_gccjit SYSTEM INTERFACE ${LIBGCCJIT_INCLUDE_DIR})
        target_link_libraries(space_gccjit INTERFACE ${LIBGCCJIT_LIBRARY})
    endif()
endif()
pkg_check_modules(ZMQ REQUIRED IMPORTED_TARGET libzmq)
pkg_check_modules(PORTAUDIO REQUIRED IMPORTED_TARGET portaudio-2.0)
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
pkg_check_modules(XAPIAN REQUIRED IMPORTED_TARGET xapian-core)
if(UNIX AND NOT APPLE)
    pkg_check_modules(LIBSECRET REQUIRED IMPORTED_TARGET libsecret-1)
endif()

set(SPACE_HAS_LIBTORRENT OFF)
set(SPACE_LIBTORRENT_TARGET "")
if(SPACE_ENABLE_LIBTORRENT)
    if(WIN32)
        find_package(LibtorrentRasterbar CONFIG QUIET)
        if(TARGET LibtorrentRasterbar::torrent-rasterbar)
            set(SPACE_HAS_LIBTORRENT ON)
            set(SPACE_LIBTORRENT_TARGET LibtorrentRasterbar::torrent-rasterbar)
        else()
            message(WARNING "LibtorrentRasterbar CMake target not found; libtorrent Lua module will be unavailable on Windows.")
        endif()
    else()
        pkg_check_modules(LIBTORRENT_RASTERBAR IMPORTED_TARGET libtorrent-rasterbar)
        if(LIBTORRENT_RASTERBAR_FOUND)
            set(SPACE_HAS_LIBTORRENT ON)
        else()
            message(WARNING "libtorrent-rasterbar-dev not found (pkg-config: libtorrent-rasterbar); libtorrent Lua module will be unavailable.")
        endif()
    endif()
endif()

set(SPACE_HAS_FFMPEG OFF)
if(SPACE_ENABLE_FFMPEG)
    pkg_check_modules(FFMPEG_AVFORMAT IMPORTED_TARGET libavformat)
    pkg_check_modules(FFMPEG_AVCODEC IMPORTED_TARGET libavcodec)
    pkg_check_modules(FFMPEG_AVUTIL IMPORTED_TARGET libavutil)
    pkg_check_modules(FFMPEG_SWSCALE IMPORTED_TARGET libswscale)
    pkg_check_modules(FFMPEG_SWRESAMPLE IMPORTED_TARGET libswresample)
    if(FFMPEG_AVFORMAT_FOUND AND FFMPEG_AVCODEC_FOUND AND FFMPEG_AVUTIL_FOUND AND FFMPEG_SWSCALE_FOUND AND FFMPEG_SWRESAMPLE_FOUND)
        set(SPACE_HAS_FFMPEG ON)
    else()
        message(WARNING "FFmpeg dev packages not found (need libavformat/libavcodec/libavutil/libswscale/libswresample); video module will be unavailable.")
    endif()
endif()

find_package(glm REQUIRED)

find_package(OpenGL REQUIRED COMPONENTS OpenGL)

find_package(OpenGL)

find_package(Bullet REQUIRED)
include_directories(${BULLET_INCLUDE_DIRS})

find_package(OpenAL REQUIRED)
include_directories(${OPENAL_INCLUDE_DIR})

find_package(PNG REQUIRED)

#find_package(Python3 REQUIRED COMPONENTS Interpreter Development)
#include_directories(Python3_INCLUDE_DIRS)

find_package(pybind11 CONFIG)

find_package(OpenMP REQUIRED)
find_package(CURL REQUIRED)
find_package(Aubio CONFIG QUIET)
if(TARGET Aubio::aubio)
    set(SPACE_AUBIO_TARGET Aubio::aubio)
else()
    pkg_check_modules(AUBIO REQUIRED IMPORTED_TARGET aubio)
    set(SPACE_AUBIO_TARGET PkgConfig::AUBIO)
endif()
set(SPDLOG_BUILD_SHARED OFF CACHE BOOL "Disable spdlog shared build" FORCE)
set(SPDLOG_BUILD_TESTS OFF CACHE BOOL "Disable spdlog tests" FORCE)
set(SPDLOG_BUILD_EXAMPLE OFF CACHE BOOL "Disable spdlog examples" FORCE)
set(SPDLOG_INSTALL OFF CACHE BOOL "Disable spdlog install" FORCE)
add_subdirectory(external/spdlog)

set(SENTRY_BUILD_TESTS OFF CACHE BOOL "Disable sentry-native tests" FORCE)
set(SENTRY_BUILD_EXAMPLES OFF CACHE BOOL "Disable sentry-native examples" FORCE)
set(SENTRY_BUILD_BENCHMARKS OFF CACHE BOOL "Disable sentry-native benchmarks" FORCE)
set(SENTRY_BUILD_SHARED_LIBS OFF CACHE BOOL "Build sentry-native statically" FORCE)
if(UNIX AND NOT APPLE)
    set(SENTRY_BACKEND crashpad CACHE STRING "Use crashpad backend for sentry-native" FORCE)
    set(SENTRY_TRANSPORT curl CACHE STRING "Use curl transport for sentry-native" FORCE)
endif()
add_subdirectory(external/sentry-native)
space_suppress_target_warnings(sentry)

option(SPACE_REQUIRE_NATIVE_LINUX_INPUT
    "Require native Linux desktop input backends (Wayland + XInput2) for SDL builds"
    ON)

if(UNIX AND NOT APPLE)
    pkg_check_modules(SPACE_WAYLAND wayland-client>=1.18 wayland-egl wayland-cursor egl xkbcommon>=0.5.0)
    pkg_check_modules(SPACE_XI xi)
    set(SPACE_HAS_NATIVE_WAYLAND_INPUT ${SPACE_WAYLAND_FOUND})
    set(SPACE_HAS_NATIVE_X11_INPUT ${SPACE_XI_FOUND})
    if(SPACE_REQUIRE_NATIVE_LINUX_INPUT)
        if(NOT SPACE_HAS_NATIVE_WAYLAND_INPUT)
            message(FATAL_ERROR
                "Missing Linux native Wayland input development packages for SDL. "
                "Install packages that provide pkg-config modules wayland-client>=1.18, wayland-egl, "
                "wayland-cursor, egl, and xkbcommon>=0.5.0, or configure with "
                "-DSPACE_REQUIRE_NATIVE_LINUX_INPUT=OFF to allow degraded input support.")
        endif()
        if(NOT SPACE_HAS_NATIVE_X11_INPUT)
            message(FATAL_ERROR
                "Missing Linux native X11 XInput2 development package for SDL. "
                "Install the package that provides pkg-config module xi, or configure with "
                "-DSPACE_REQUIRE_NATIVE_LINUX_INPUT=OFF to allow degraded input support.")
        endif()
    else()
        if(NOT SPACE_HAS_NATIVE_WAYLAND_INPUT)
            message(WARNING
                "Wayland native input dependencies missing. SDL may fall back to X11/Xwayland "
                "and native touch/stylus input may be unavailable.")
        endif()
        if(NOT SPACE_HAS_NATIVE_X11_INPUT)
            message(WARNING
                "X11 XInput2 dependency missing. Native X11 touch input may be unavailable.")
        endif()
    endif()
endif()

set(SDL_SHARED ON CACHE BOOL "Build SDL3 shared library" FORCE)
set(SDL_STATIC OFF CACHE BOOL "Disable SDL3 static library build" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "Disable SDL3 test helper library" FORCE)
set(SDL_TESTS OFF CACHE BOOL "Disable SDL3 tests" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "Disable SDL3 examples" FORCE)
set(SDL_INSTALL OFF CACHE BOOL "Disable SDL3 install rules" FORCE)
set(SDL_X11_XCURSOR OFF CACHE BOOL "Disable Xcursor (not available)" FORCE)
set(SDL_X11_XRANDR OFF CACHE BOOL "Disable Xrandr (not available)" FORCE)
set(SDL_X11_XSCRNSAVER OFF CACHE BOOL "Disable XScrnSaver (not available)" FORCE)
set(SDL_X11_XTEST OFF CACHE BOOL "Disable XTest (not available)" FORCE)
add_subdirectory(external/sdl)
if(UNIX AND NOT APPLE AND SPACE_REQUIRE_NATIVE_LINUX_INPUT)
    if(NOT SDL_WAYLAND)
        message(FATAL_ERROR
            "SDL configured without Wayland support even though SPACE_REQUIRE_NATIVE_LINUX_INPUT=ON. "
            "Install the missing SDL Wayland dependencies reported above, or configure with "
            "-DSPACE_REQUIRE_NATIVE_LINUX_INPUT=OFF to allow degraded input support.")
    endif()
    if(NOT SDL_X11_XINPUT)
        message(FATAL_ERROR
            "SDL configured without X11 XInput2 support even though SPACE_REQUIRE_NATIVE_LINUX_INPUT=ON. "
            "Install the missing SDL XInput2 dependencies reported above, or configure with "
            "-DSPACE_REQUIRE_NATIVE_LINUX_INPUT=OFF to allow degraded input support.")
    endif()
endif()
if(SPACE_SUPPRESS_THIRD_PARTY_WARNINGS)
    space_suppress_target_warnings(lua)
    space_suppress_target_warnings(lua-header)
    space_suppress_target_warnings(sqlite3)
    space_suppress_target_warnings(lsqlite3)
    space_suppress_target_warnings(tree_sitter_core)
    space_suppress_target_warnings(tree_sitter_cpp)
    space_suppress_target_warnings(tree_sitter_python)
    space_suppress_target_warnings(tree_sitter_fennel)
    space_suppress_target_warnings(tree_sitter_javascript)
    space_suppress_target_warnings(TrustWalletCore)
    space_suppress_target_warnings(msdf-atlas-gen)
    space_suppress_target_warnings(jpeg-static)
    space_suppress_target_warnings(efsw)
    space_suppress_target_warnings(spdlog)
    space_suppress_target_warnings(spdlog_header_only)
endif()

if(UNIX AND NOT APPLE)
    pkg_check_modules(GTK3 IMPORTED_TARGET gtk+-3.0)
    pkg_check_modules(APPINDICATOR IMPORTED_TARGET ayatana-appindicator3-0.1)
    pkg_check_modules(LIBNOTIFY IMPORTED_TARGET libnotify)
endif()
if(POLICY CMP0167)
    cmake_policy(SET CMP0167 NEW)
endif()
find_package(Boost CONFIG REQUIRED)

file( GLOB SOURCES src/*.cpp src/*.c src/realtime/*.cpp )
if(NOT SPACE_HAS_VTERM)
    list(REMOVE_ITEM SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/src/terminal.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/src/lua_terminal.cpp
    )
endif()
if(NOT SPACE_ENABLE_WALLET_CORE)
    list(REMOVE_ITEM SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/src/lua_wallet_core.cpp
    )
endif()
if(WIN32)
    list(REMOVE_ITEM SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/src/lua_process.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/src/lua_shell.cpp
    )
    list(APPEND SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/src/lua_process_windows.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/src/lua_shell_windows.cpp
    )
else()
    list(REMOVE_ITEM SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/src/lua_process_windows.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/src/lua_shell_windows.cpp
    )
endif()
add_library(${PROJECT_NAME}_lib ${SOURCES})
file(GLOB YOJIMBO_SOURCES
    external/yojimbo/source/*.cpp
)
add_library(space_yojimbo STATIC
    ${YOJIMBO_SOURCES}
    external/yojimbo/netcode/netcode.c
    external/yojimbo/reliable/reliable.c
    external/yojimbo/tlsf/tlsf.c
)
file(GLOB YOJIMBO_SODIUM_SOURCES external/yojimbo/sodium/*.c)
if(WIN32)
    file(GLOB YOJIMBO_SODIUM_ASM_SOURCES external/yojimbo/sodium/*.S)
    list(APPEND YOJIMBO_SODIUM_SOURCES ${YOJIMBO_SODIUM_ASM_SOURCES})
endif()
add_library(space_yojimbo_sodium STATIC ${YOJIMBO_SODIUM_SOURCES})
target_include_directories(space_yojimbo
    SYSTEM PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/external/yojimbo
    ${CMAKE_CURRENT_SOURCE_DIR}/external/yojimbo/include
    ${CMAKE_CURRENT_SOURCE_DIR}/external/yojimbo/netcode
    ${CMAKE_CURRENT_SOURCE_DIR}/external/yojimbo/reliable
    ${CMAKE_CURRENT_SOURCE_DIR}/external/yojimbo/serialize
    ${CMAKE_CURRENT_SOURCE_DIR}/external/yojimbo/tlsf
    ${CMAKE_CURRENT_SOURCE_DIR}/external/yojimbo/sodium
)
target_include_directories(space_yojimbo_sodium SYSTEM PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/external/yojimbo/sodium)
target_link_libraries(space_yojimbo PUBLIC space_yojimbo_sodium)
if(WIN32)
    target_link_libraries(space_yojimbo PRIVATE ws2_32 iphlpapi)
endif()
target_compile_definitions(${PROJECT_NAME}_lib PUBLIC GLM_ENABLE_EXPERIMENTAL=1)
if(SPACE_HAS_VTERM)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC SPACE_HAS_VTERM=1)
endif()
if(SPACE_ENABLE_CEF)
    if(NOT UNIX OR APPLE)
        message(FATAL_ERROR "SPACE_ENABLE_CEF currently supports Linux only")
    endif()
    include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/cef.cmake)
    target_compile_features(${PROJECT_NAME}_lib PUBLIC cxx_std_20)
    space_setup_cef_for_target(${PROJECT_NAME}_lib)
endif()
target_include_directories(${PROJECT_NAME}_lib
    PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/ffi/matrix/include
)
target_include_directories(${PROJECT_NAME}_lib
    SYSTEM PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/external/nlohmann
    ${CMAKE_CURRENT_SOURCE_DIR}/external/tomlplusplus/include
    ${CMAKE_CURRENT_SOURCE_DIR}/external/cpp-httplib
)
target_include_directories(${PROJECT_NAME}_lib
    SYSTEM PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/external/libjpeg-turbo
    ${CMAKE_CURRENT_BINARY_DIR}/external/libjpeg-turbo
)
target_link_libraries(${PROJECT_NAME}_lib
    SDL3::SDL3
    ${BULLET_LIBRARIES}
    ${OPENAL_LIBRARY}
    PNG::PNG
    jpeg-static
    msdf-atlas-gen::msdf-atlas-gen
    OpenGL::GL
    #Python3::Python
    glm::glm
    CURL::libcurl
    lua
    sqlite3
    lsqlite3
    PkgConfig::ZMQ
    PkgConfig::PORTAUDIO
    ${SPACE_AUBIO_TARGET}
    PkgConfig::XAPIAN
    tree_sitter_core
    tree_sitter_cpp
    tree_sitter_python
    tree_sitter_fennel
    tree_sitter_javascript
    OpenMP::OpenMP_CXX
    spdlog::spdlog
    efsw
    Boost::headers
    space_yojimbo
)
if(TARGET sentry::sentry)
    target_link_libraries(${PROJECT_NAME}_lib sentry::sentry)
elseif(TARGET sentry)
    # sentry::sentry is the expected upstream alias for sentry-native 0.16.6.
    target_link_libraries(${PROJECT_NAME}_lib sentry)
else()
    message(FATAL_ERROR "Required sentry-native target not found")
endif()
if(TARGET BulletInverseDynamics)
    target_link_libraries(${PROJECT_NAME}_lib BulletInverseDynamics)
endif()
if(TARGET Bullet3Common)
    target_link_libraries(${PROJECT_NAME}_lib Bullet3Common)
endif()
if(UNIX AND NOT APPLE)
    target_link_libraries(${PROJECT_NAME}_lib util)
endif()
if(SPACE_HAS_VTERM)
    target_link_libraries(${PROJECT_NAME}_lib PkgConfig::VTERM)
endif()
if(UNIX AND NOT APPLE)
    if(LIBGCCJIT_FOUND)
        target_link_libraries(${PROJECT_NAME}_lib PkgConfig::LIBGCCJIT)
    else()
        target_link_libraries(${PROJECT_NAME}_lib space_gccjit)
    endif()
endif()
target_link_libraries(${PROJECT_NAME}_lib PkgConfig::EPOXY)
if(SPACE_ENABLE_WALLET_CORE)
    target_link_libraries(${PROJECT_NAME}_lib TrustWalletCore)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC SPACE_ENABLE_WALLET_CORE=1)
endif()
if(SPACE_HAS_LIBTORRENT)
    if(SPACE_LIBTORRENT_TARGET)
        target_link_libraries(${PROJECT_NAME}_lib ${SPACE_LIBTORRENT_TARGET})
    else()
        target_link_libraries(${PROJECT_NAME}_lib PkgConfig::LIBTORRENT_RASTERBAR)
    endif()
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC SPACE_ENABLE_LIBTORRENT=1)
endif()
if(SPACE_HAS_FFMPEG)
    target_link_libraries(${PROJECT_NAME}_lib
        PkgConfig::FFMPEG_AVFORMAT
        PkgConfig::FFMPEG_AVCODEC
        PkgConfig::FFMPEG_AVUTIL
        PkgConfig::FFMPEG_SWSCALE
        PkgConfig::FFMPEG_SWRESAMPLE
    )
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC SPACE_HAS_FFMPEG=1)
endif()

if(WIN32)
    set(_space_bullet_relink_libs)
    if(TARGET BulletDynamics)
        list(APPEND _space_bullet_relink_libs BulletDynamics)
    elseif(BULLET_DYNAMICS_LIBRARY)
        list(APPEND _space_bullet_relink_libs ${BULLET_DYNAMICS_LIBRARY})
    endif()
    if(TARGET LinearMath)
        list(APPEND _space_bullet_relink_libs LinearMath)
    elseif(BULLET_MATH_LIBRARY)
        list(APPEND _space_bullet_relink_libs ${BULLET_MATH_LIBRARY})
    endif()
    if(_space_bullet_relink_libs)
        target_link_libraries(${PROJECT_NAME}_lib ${_space_bullet_relink_libs})
    endif()
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_WINAPI=1)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_NAME=\"winapi\")
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_REASON=\"\")
    target_link_libraries(${PROJECT_NAME}_lib user32 shell32 advapi32 psapi)
elseif(APPLE)
    find_library(APPKIT_FRAMEWORK AppKit)
    find_library(FOUNDATION_FRAMEWORK Foundation)
    find_library(OBJC_LIBRARY objc)
    if(APPKIT_FRAMEWORK AND FOUNDATION_FRAMEWORK AND OBJC_LIBRARY)
        target_link_libraries(${PROJECT_NAME}_lib ${APPKIT_FRAMEWORK} ${FOUNDATION_FRAMEWORK} ${OBJC_LIBRARY})
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_APPKIT=1)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_NAME=\"appkit\")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_REASON=\"\")
    else()
        message(WARNING "AppKit/Foundation/objc not found; tray support disabled on macOS builds.")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_NONE=1)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC "TRAY_BACKEND_NAME=\"none\"")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC "TRAY_BACKEND_REASON=\"AppKit/Foundation/objc frameworks not found during build.\"")
    endif()
elseif(UNIX AND NOT APPLE)
    if(GTK3_FOUND AND APPINDICATOR_FOUND)
        target_link_libraries(${PROJECT_NAME}_lib PkgConfig::GTK3 PkgConfig::APPINDICATOR)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC
            TRAY_APPINDICATOR=1
            TRAY_BACKEND_NAME="ayatana-appindicator"
            TRAY_BACKEND_REASON=""
        )
    else()
        message(WARNING "AppIndicator/GTK3 not found; tray support disabled on Linux builds.")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC
            TRAY_BACKEND_NONE=1
            TRAY_BACKEND_NAME="none"
        )
        if(NOT GTK3_FOUND)
            set(TRAY_BACKEND_REASON "GTK3 development files not found during build.")
        elseif(NOT APPINDICATOR_FOUND)
            set(TRAY_BACKEND_REASON "AppIndicator development files not found during build (install libayatana-appindicator3-dev on Debian/Ubuntu).")
        else()
            set(TRAY_BACKEND_REASON "Tray backend disabled during build.")
        endif()
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC TRAY_BACKEND_REASON="${TRAY_BACKEND_REASON}")
    endif()
    target_link_libraries(${PROJECT_NAME}_lib PkgConfig::LIBSECRET)
endif()

if(APPLE)
    find_library(APPLICATIONSERVICES_FRAMEWORK ApplicationServices)
    find_library(COREFOUNDATION_FRAMEWORK CoreFoundation)
    find_library(SECURITY_FRAMEWORK Security)
    if(APPLICATIONSERVICES_FRAMEWORK)
        target_link_libraries(${PROJECT_NAME}_lib ${APPLICATIONSERVICES_FRAMEWORK})
    else()
        message(WARNING "ApplicationServices framework not found; webbrowser support disabled on macOS builds.")
    endif()
    if(COREFOUNDATION_FRAMEWORK)
        target_link_libraries(${PROJECT_NAME}_lib ${COREFOUNDATION_FRAMEWORK})
    else()
        message(WARNING "CoreFoundation framework not found; webbrowser support disabled on macOS builds.")
    endif()
    if(SECURITY_FRAMEWORK)
        target_link_libraries(${PROJECT_NAME}_lib ${SECURITY_FRAMEWORK})
    else()
        message(WARNING "Security framework not found; keyring support may be unavailable on macOS builds.")
    endif()
endif()

if(WIN32)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NONE=1)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC "NOTIFY_BACKEND_NAME=\"none\"")
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC "NOTIFY_BACKEND_REASON=\"notifications not implemented on Windows builds.\"")
elseif(APPLE)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NONE=1)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC "NOTIFY_BACKEND_NAME=\"none\"")
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC "NOTIFY_BACKEND_REASON=\"notifications not implemented on macOS builds.\"")
elseif(UNIX AND NOT APPLE)
    if(LIBNOTIFY_FOUND)
        target_link_libraries(${PROJECT_NAME}_lib PkgConfig::LIBNOTIFY)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_LIBNOTIFY=1)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC "NOTIFY_BACKEND_NAME=\"libnotify\"")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC "NOTIFY_BACKEND_REASON=\"\"")
    else()
        message(WARNING "libnotify not found; notifications disabled on Linux builds.")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NONE=1)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC "NOTIFY_BACKEND_NAME=\"none\"")
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC "NOTIFY_BACKEND_REASON=\"libnotify development files not found during build.\"")
    endif()
else()
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC NOTIFY_BACKEND_NONE=1)
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC "NOTIFY_BACKEND_NAME=\"none\"")
    target_compile_definitions(${PROJECT_NAME}_lib PUBLIC "NOTIFY_BACKEND_REASON=\"notification backend unavailable on this platform.\"")
endif()

add_executable(${PROJECT_NAME} apps/space/main.cpp)
target_link_libraries(${PROJECT_NAME} ${PROJECT_NAME}_lib)
set_target_properties(${PROJECT_NAME} PROPERTIES
    INSTALL_RPATH "\$ORIGIN/../lib"
)
if(TARGET crashpad_handler)
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:crashpad_handler>
            $<TARGET_FILE_DIR:${PROJECT_NAME}>/crashpad_handler
        VERBATIM)
endif()
target_include_directories(${PROJECT_NAME} SYSTEM PRIVATE ${CMAKE_CURRENT_LIST_DIR}/external/CLI11/include)
if(WIN32)
    set(SPACE_WINDOWS_ICON_PNG "${CMAKE_CURRENT_SOURCE_DIR}/assets/pics/space.png")
    set(SPACE_WINDOWS_ICON_FILE "${CMAKE_CURRENT_BINARY_DIR}/space.ico")
    set(SPACE_WINDOWS_RC_FILE "${CMAKE_CURRENT_BINARY_DIR}/space-app.rc")
    set(SPACE_WINDOWS_COMPANY_NAME "${SPACE_PACKAGE_VENDOR}")
    set(SPACE_WINDOWS_FILE_DESCRIPTION "${SPACE_PACKAGE_DESCRIPTION}")
    set(SPACE_WINDOWS_INTERNAL_NAME "${PROJECT_NAME}")
    set(SPACE_WINDOWS_ORIGINAL_FILENAME "${PROJECT_NAME}.exe")
    set(SPACE_WINDOWS_PRODUCT_NAME "${PROJECT_NAME}")
    set(SPACE_WINDOWS_PRODUCT_VERSION "${SPACE_PACKAGE_VERSION}")

    add_custom_command(
        OUTPUT "${SPACE_WINDOWS_ICON_FILE}"
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/scripts/generate_windows_icon.py"
            --input "${SPACE_WINDOWS_ICON_PNG}"
            --output "${SPACE_WINDOWS_ICON_FILE}"
        DEPENDS
            "${SPACE_WINDOWS_ICON_PNG}"
            "${CMAKE_CURRENT_SOURCE_DIR}/scripts/generate_windows_icon.py"
        COMMENT "Generating Windows icon"
        VERBATIM
    )

    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/apps/space/windows_app.rc.in"
        "${SPACE_WINDOWS_RC_FILE}"
        @ONLY
    )

    set_source_files_properties("${SPACE_WINDOWS_ICON_FILE}" PROPERTIES GENERATED TRUE HEADER_FILE_ONLY TRUE)
    set_source_files_properties("${SPACE_WINDOWS_RC_FILE}" PROPERTIES OBJECT_DEPENDS "${SPACE_WINDOWS_ICON_FILE}")
    target_sources(${PROJECT_NAME} PRIVATE "${SPACE_WINDOWS_ICON_FILE}" "${SPACE_WINDOWS_RC_FILE}")
endif()
if(SPACE_ENABLE_CEF)
    target_compile_definitions(${PROJECT_NAME} PUBLIC SPACE_ENABLE_CEF=1)
    space_setup_cef_for_target(${PROJECT_NAME})
endif()

if(SPACE_ENABLE_CEF)
    add_executable(space_cef_helper
        apps/space/cef_subprocess_main.cpp
        src/cef_runtime.cpp
        src/executable_path.cpp
    )
    target_include_directories(space_cef_helper PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_compile_definitions(space_cef_helper PUBLIC SPACE_ENABLE_CEF=1)
    space_setup_cef_for_target(space_cef_helper)
endif()

add_test(NAME ${PROJECT_NAME}_fnl_tests
    COMMAND space -m tests.fast:main
)
set_tests_properties(${PROJECT_NAME}_fnl_tests PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    FIXTURES_REQUIRED space_constraints
    ENVIRONMENT "SKIP_KEYRING_TESTS=1;XDG_DATA_HOME=/tmp/space/tests/xdg-data;SPACE_DISABLE_AUDIO=1;SPACE_LOG_DIR=/tmp/space/tests/log;SPACE_ASSETS_PATH=${CMAKE_SOURCE_DIR}/assets;FENNEL_PATH=${CMAKE_SOURCE_DIR}/assets/lua/?.fnl\;${CMAKE_SOURCE_DIR}/assets/lua/?/init.fnl;FENNEL_MACRO_PATH=${CMAKE_SOURCE_DIR}/assets/lua/?.fnl\;${CMAKE_SOURCE_DIR}/assets/lua/?/init.fnl"
)

add_test(NAME ${PROJECT_NAME}_fnl_tests_integration
    COMMAND space -m tests.integration:main
)
set_tests_properties(${PROJECT_NAME}_fnl_tests_integration PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    FIXTURES_REQUIRED space_constraints
    ENVIRONMENT "SKIP_KEYRING_TESTS=1;XDG_DATA_HOME=/tmp/space/tests/xdg-data;SPACE_DISABLE_AUDIO=1;SPACE_LOG_DIR=/tmp/space/tests/log;SPACE_ASSETS_PATH=${CMAKE_SOURCE_DIR}/assets;FENNEL_PATH=${CMAKE_SOURCE_DIR}/assets/lua/?.fnl\;${CMAKE_SOURCE_DIR}/assets/lua/?/init.fnl;FENNEL_MACRO_PATH=${CMAKE_SOURCE_DIR}/assets/lua/?.fnl\;${CMAKE_SOURCE_DIR}/assets/lua/?/init.fnl"
)

add_test(NAME ${PROJECT_NAME}_constraints
    COMMAND space -m constraints.runner:main -- --output summary --target repo
)
set_tests_properties(${PROJECT_NAME}_constraints PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    FIXTURES_SETUP space_constraints
    ENVIRONMENT "SKIP_KEYRING_TESTS=1;XDG_DATA_HOME=/tmp/space/tests/xdg-data;SPACE_DISABLE_AUDIO=1;SPACE_LOG_DIR=/tmp/space/tests/log;SPACE_ASSETS_PATH=${CMAKE_SOURCE_DIR}/assets;FENNEL_PATH=${CMAKE_SOURCE_DIR}/assets/lua/?.fnl\;${CMAKE_SOURCE_DIR}/assets/lua/?/init.fnl;FENNEL_MACRO_PATH=${CMAKE_SOURCE_DIR}/assets/lua/?.fnl\;${CMAKE_SOURCE_DIR}/assets/lua/?/init.fnl"
)

add_test(NAME ${PROJECT_NAME}_runtime_fennel_paths
    COMMAND ${CMAKE_COMMAND} -E env --unset=FENNEL_PATH --unset=FENNEL_MACRO_PATH $<TARGET_FILE:space> -m tests.test-runtime-fennel-path:main
)
set_tests_properties(${PROJECT_NAME}_runtime_fennel_paths PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    ENVIRONMENT "SKIP_KEYRING_TESTS=1;XDG_DATA_HOME=/tmp/space/tests/xdg-data;SPACE_DISABLE_AUDIO=1;SPACE_LOG_DIR=/tmp/space/tests/log;SPACE_ASSETS_PATH=${CMAKE_SOURCE_DIR}/assets"
)

add_executable(test_vector_buffer
    tests/test_vector_buffer.cpp
)
target_include_directories(test_vector_buffer PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME test_vector_buffer COMMAND test_vector_buffer)
set_tests_properties(test_vector_buffer PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_error_reporting tests/test_error_reporting.cpp)
target_link_libraries(test_error_reporting ${PROJECT_NAME}_lib)
target_include_directories(test_error_reporting PRIVATE external/cpp-httplib)
add_test(NAME test_error_reporting COMMAND test_error_reporting)

add_executable(test_input_dial_type
    tests/test_input_dial_type.cpp
    src/dial_type.cpp
    src/input_dial_type.cpp
    src/input_state.cpp
    src/input_gamepad_state.cpp
)
target_include_directories(test_input_dial_type PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(test_input_dial_type SDL3::SDL3)
add_test(NAME test_input_dial_type COMMAND test_input_dial_type)
set_tests_properties(test_input_dial_type PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_input_touch_state
    tests/test_input_touch_state.cpp
    src/input_state.cpp
    src/input_gamepad_state.cpp
)
target_include_directories(test_input_touch_state PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(test_input_touch_state SDL3::SDL3)
add_test(NAME test_input_touch_state COMMAND test_input_touch_state)
set_tests_properties(test_input_touch_state PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_input_pen_state
    tests/test_input_pen_state.cpp
    src/input_state.cpp
    src/input_gamepad_state.cpp
)
target_include_directories(test_input_pen_state PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(test_input_pen_state SDL3::SDL3)
add_test(NAME test_input_pen_state COMMAND test_input_pen_state)
set_tests_properties(test_input_pen_state PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_dotenv
    tests/test_dotenv.cpp
    src/dotenv.cpp
)
target_include_directories(test_dotenv PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME test_dotenv COMMAND test_dotenv)
set_tests_properties(test_dotenv PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_dotenv_integration
    tests/test_dotenv_integration.cpp
)
add_test(NAME test_dotenv_integration COMMAND test_dotenv_integration)
set_tests_properties(test_dotenv_integration PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_audio_stream_clock
    tests/test_audio_stream_clock.cpp
    src/audio.cpp
)
target_include_directories(test_audio_stream_clock PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(test_audio_stream_clock
    ${OPENAL_LIBRARY}
    glm::glm
)
add_test(NAME test_audio_stream_clock COMMAND test_audio_stream_clock)
set_tests_properties(test_audio_stream_clock PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_video_telemetry
    tests/test_video_telemetry.cpp
)
target_include_directories(test_video_telemetry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME test_video_telemetry COMMAND test_video_telemetry)
set_tests_properties(test_video_telemetry PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_lua_gccjit_binding
    tests/test_lua_gccjit_binding.cpp
    src/lua_gccjit.cpp
)
target_include_directories(test_lua_gccjit_binding PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)
target_link_libraries(test_lua_gccjit_binding lua)
if(UNIX AND NOT APPLE)
    if(LIBGCCJIT_FOUND)
        target_link_libraries(test_lua_gccjit_binding PkgConfig::LIBGCCJIT)
    else()
        target_link_libraries(test_lua_gccjit_binding space_gccjit)
    endif()
endif()
add_test(NAME test_lua_gccjit_binding COMMAND test_lua_gccjit_binding)
set_tests_properties(test_lua_gccjit_binding PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_lua_module_error_integration
    tests/test_lua_module_error_integration.cpp
)
target_include_directories(test_lua_module_error_integration PRIVATE external/cpp-httplib)
add_test(NAME test_lua_module_error_integration COMMAND test_lua_module_error_integration)
set_tests_properties(test_lua_module_error_integration PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_realtime_core
    tests/test_realtime_core.cpp
    src/realtime/auth_ticket.cpp
    src/realtime/core.cpp
)
target_include_directories(test_realtime_core PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)
target_include_directories(test_realtime_core SYSTEM PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/external/nlohmann
)
target_link_libraries(test_realtime_core space_yojimbo space_yojimbo_sodium)
if(WIN32)
    target_include_directories(test_realtime_core SYSTEM PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/external/yojimbo/sodium)
    target_link_libraries(test_realtime_core ws2_32 iphlpapi)
endif()
add_test(NAME test_realtime_core COMMAND test_realtime_core)
set_tests_properties(test_realtime_core PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_executable_path
    tests/test_executable_path.cpp
    src/executable_path.cpp
)
target_include_directories(test_executable_path PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME test_executable_path COMMAND test_executable_path)
set_tests_properties(test_executable_path PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_asset_manager
    tests/test_asset_manager.cpp
    src/asset_manager.cpp
    src/appdirs.cpp
)
target_include_directories(test_asset_manager PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME test_asset_manager COMMAND test_asset_manager)
set_tests_properties(test_asset_manager PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_runtime_asset_discovery_integration
    tests/test_runtime_asset_discovery_integration.cpp
)
add_test(NAME test_runtime_asset_discovery_integration COMMAND test_runtime_asset_discovery_integration)
set_tests_properties(test_runtime_asset_discovery_integration PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_space_log_path
    tests/test_space_log_path.cpp
    src/space_log_path.cpp
    src/appdirs.cpp
)
target_include_directories(test_space_log_path PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME test_space_log_path COMMAND test_space_log_path)
set_tests_properties(test_space_log_path PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_executable(test_native_logging_integration
    tests/test_native_logging_integration.cpp
)
target_include_directories(test_native_logging_integration PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_test(NAME test_native_logging_integration COMMAND test_native_logging_integration)
set_tests_properties(test_native_logging_integration PROPERTIES
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

target_compile_options(${PROJECT_NAME} PRIVATE -O2 -g)
target_link_options(${PROJECT_NAME} PRIVATE -O2 -g)

set_target_properties(${PROJECT_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)

# Optional Rust Matrix bridge build.
if(SPACE_BUILD_MATRIX)
    find_program(CARGO_EXECUTABLE cargo)
    if(CARGO_EXECUTABLE)
        find_program(SCCACHE_PROGRAM sccache)
        set(MATRIX_DIR ${CMAKE_SOURCE_DIR}/ffi/matrix)
        set(SPACE_MATRIX_CARGO_TARGET_DIR "" CACHE PATH
            "Cargo target directory for ffi/matrix (empty uses a shared user cache)")
        if(SPACE_MATRIX_CARGO_TARGET_DIR)
            get_filename_component(MATRIX_CARGO_TARGET_ROOT "${SPACE_MATRIX_CARGO_TARGET_DIR}" ABSOLUTE)
        elseif(DEFINED ENV{CARGO_TARGET_DIR} AND NOT "$ENV{CARGO_TARGET_DIR}" STREQUAL "")
            get_filename_component(MATRIX_CARGO_TARGET_ROOT "$ENV{CARGO_TARGET_DIR}" ABSOLUTE)
        else()
            if(DEFINED ENV{XDG_CACHE_HOME} AND NOT "$ENV{XDG_CACHE_HOME}" STREQUAL "")
                set(_space_cache_home "$ENV{XDG_CACHE_HOME}")
            elseif(WIN32 AND DEFINED ENV{LOCALAPPDATA} AND NOT "$ENV{LOCALAPPDATA}" STREQUAL "")
                set(_space_cache_home "$ENV{LOCALAPPDATA}")
            elseif(DEFINED ENV{HOME} AND NOT "$ENV{HOME}" STREQUAL "")
                set(_space_cache_home "$ENV{HOME}/.cache")
            else()
                set(_space_cache_home "${CMAKE_BINARY_DIR}/_cache")
            endif()
            set(MATRIX_CARGO_TARGET_ROOT "${_space_cache_home}/space/cargo-target/matrix")
        endif()
        file(MAKE_DIRECTORY "${MATRIX_CARGO_TARGET_ROOT}")
        message(STATUS "Matrix Cargo target directory: ${MATRIX_CARGO_TARGET_ROOT}")

        set(_space_matrix_rust_target_default "")
        if(DEFINED ENV{RUST_TARGET} AND NOT "$ENV{RUST_TARGET}" STREQUAL "")
            set(_space_matrix_rust_target_default "$ENV{RUST_TARGET}")
        endif()
        set(SPACE_MATRIX_RUST_TARGET "${_space_matrix_rust_target_default}" CACHE STRING
            "Rust target triple for ffi/matrix (empty uses cargo host target)")

        set(MATRIX_RUST_TARGET "${SPACE_MATRIX_RUST_TARGET}")
        if(NOT MATRIX_RUST_TARGET)
            if(WIN32)
                if(MSVC)
                    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(ARM64|arm64|aarch64)$")
                        set(MATRIX_RUST_TARGET "aarch64-pc-windows-msvc")
                    elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
                        set(MATRIX_RUST_TARGET "x86_64-pc-windows-msvc")
                    else()
                        set(MATRIX_RUST_TARGET "i686-pc-windows-msvc")
                    endif()
                elseif(MINGW)
                    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
                        set(MATRIX_RUST_TARGET "x86_64-pc-windows-gnu")
                    else()
                        set(MATRIX_RUST_TARGET "i686-pc-windows-gnu")
                    endif()
                endif()
            endif()
        endif()

        set(MATRIX_CARGO_ARGS build --release)
        if(MATRIX_RUST_TARGET)
            list(APPEND MATRIX_CARGO_ARGS --target ${MATRIX_RUST_TARGET})
            set(MATRIX_TARGET_DIR ${MATRIX_CARGO_TARGET_ROOT}/${MATRIX_RUST_TARGET}/release)
        else()
            set(MATRIX_TARGET_DIR ${MATRIX_CARGO_TARGET_ROOT}/release)
        endif()

        if(MATRIX_RUST_TARGET MATCHES "windows")
            set(MATRIX_OUTPUT_NAME matrix.dll)
            if(MATRIX_RUST_TARGET MATCHES "msvc")
                set(MATRIX_LIB_NAME matrix.dll.lib)
            else()
                set(MATRIX_LIB_NAME libmatrix.dll.a)
            endif()
        elseif(MATRIX_RUST_TARGET MATCHES "apple|darwin")
            set(MATRIX_OUTPUT_NAME libmatrix.dylib)
            set(MATRIX_LIB_NAME ${MATRIX_OUTPUT_NAME})
        elseif(MATRIX_RUST_TARGET)
            set(MATRIX_OUTPUT_NAME libmatrix.so)
            set(MATRIX_LIB_NAME ${MATRIX_OUTPUT_NAME})
        elseif(WIN32)
            set(MATRIX_OUTPUT_NAME matrix${CMAKE_SHARED_LIBRARY_SUFFIX})
            if(MINGW)
                set(MATRIX_LIB_NAME libmatrix${CMAKE_SHARED_LIBRARY_SUFFIX}.a)
            else()
                set(MATRIX_LIB_NAME matrix${CMAKE_SHARED_LIBRARY_SUFFIX}.lib)
            endif()
        else()
            set(MATRIX_OUTPUT_NAME libmatrix${CMAKE_SHARED_LIBRARY_SUFFIX})
            set(MATRIX_LIB_NAME ${MATRIX_OUTPUT_NAME})
        endif()
        set(MATRIX_CARGO_OUTPUT ${MATRIX_TARGET_DIR}/${MATRIX_OUTPUT_NAME})
        set(MATRIX_BUILD_OUTPUT ${CMAKE_BINARY_DIR}/${MATRIX_OUTPUT_NAME})

        set(MATRIX_CARGO_COMMAND "${CARGO_EXECUTABLE}")
        set(_space_rustc_wrapper "")
        if(DEFINED ENV{RUSTC_WRAPPER} AND NOT "$ENV{RUSTC_WRAPPER}" STREQUAL "")
            set(_space_rustc_wrapper "$ENV{RUSTC_WRAPPER}")
        elseif(SCCACHE_PROGRAM)
            set(_space_rustc_wrapper "${SCCACHE_PROGRAM}")
        endif()
        if(_space_rustc_wrapper)
            set(MATRIX_CARGO_COMMAND "${CMAKE_COMMAND}" -E env
                "CARGO_TARGET_DIR=${MATRIX_CARGO_TARGET_ROOT}"
                "RUSTC_WRAPPER=${_space_rustc_wrapper}"
                "${CARGO_EXECUTABLE}")
            message(STATUS "Rust compiler cache enabled for Matrix build: RUSTC_WRAPPER=${_space_rustc_wrapper}")
        else()
            set(MATRIX_CARGO_COMMAND "${CMAKE_COMMAND}" -E env
                "CARGO_TARGET_DIR=${MATRIX_CARGO_TARGET_ROOT}"
                "${CARGO_EXECUTABLE}")
            message(STATUS "sccache not found; Matrix Rust build will run without a Rust compiler cache")
        endif()

        file(GLOB_RECURSE MATRIX_RUST_SOURCES CONFIGURE_DEPENDS ${MATRIX_DIR}/src/*.rs)

        if(MATRIX_OUTPUT_NAME STREQUAL MATRIX_LIB_NAME)
            add_custom_command(
                OUTPUT ${MATRIX_BUILD_OUTPUT}
                COMMAND ${MATRIX_CARGO_COMMAND} ${MATRIX_CARGO_ARGS}
                COMMAND ${CMAKE_COMMAND} -E copy "${MATRIX_CARGO_OUTPUT}" "${MATRIX_BUILD_OUTPUT}"
                WORKING_DIRECTORY ${MATRIX_DIR}
                DEPENDS ${MATRIX_DIR}/Cargo.toml ${MATRIX_DIR}/Cargo.lock ${MATRIX_RUST_SOURCES}
                COMMENT "---- Build matrix (Rust)"
            )
            set(MATRIX_BUILD_TARGETS ${MATRIX_BUILD_OUTPUT})
            target_link_libraries(${PROJECT_NAME}_lib "${MATRIX_BUILD_OUTPUT}")
        else()
            set(MATRIX_CARGO_LIB ${MATRIX_TARGET_DIR}/${MATRIX_LIB_NAME})
            set(MATRIX_BUILD_LIB ${CMAKE_BINARY_DIR}/${MATRIX_LIB_NAME})
            add_custom_command(
                OUTPUT ${MATRIX_BUILD_OUTPUT} ${MATRIX_BUILD_LIB}
                COMMAND ${MATRIX_CARGO_COMMAND} ${MATRIX_CARGO_ARGS}
                COMMAND ${CMAKE_COMMAND} -E copy "${MATRIX_CARGO_OUTPUT}" "${MATRIX_BUILD_OUTPUT}"
                COMMAND ${CMAKE_COMMAND} -E copy "${MATRIX_CARGO_LIB}" "${MATRIX_BUILD_LIB}"
                WORKING_DIRECTORY ${MATRIX_DIR}
                DEPENDS ${MATRIX_DIR}/Cargo.toml ${MATRIX_DIR}/Cargo.lock ${MATRIX_RUST_SOURCES}
                COMMENT "---- Build matrix (Rust)"
            )
            set(MATRIX_BUILD_TARGETS ${MATRIX_BUILD_OUTPUT} ${MATRIX_BUILD_LIB})
            target_link_libraries(${PROJECT_NAME}_lib "${MATRIX_BUILD_LIB}")
        endif()
        add_custom_target(matrix_build ALL DEPENDS ${MATRIX_BUILD_TARGETS})
        add_dependencies(${PROJECT_NAME}_lib matrix_build)
        add_dependencies(${PROJECT_NAME} matrix_build)
        target_compile_definitions(${PROJECT_NAME}_lib PUBLIC SPACE_MATRIX_ENABLED=1)
        set_property(TARGET ${PROJECT_NAME} APPEND PROPERTY BUILD_RPATH "${CMAKE_BINARY_DIR}")
        install(FILES ${MATRIX_BUILD_OUTPUT} DESTINATION lib)
    else()
        message(WARNING "cargo not found; matrix build disabled.")
    endif()
endif()

# Copying assets to the build folder
add_custom_command(
        TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_LIST_DIR}/assets
        $<TARGET_FILE_DIR:${PROJECT_NAME}>/assets
        COMMENT "---- Copy Assets"
)

set(CPACK_PROJECT_NAME ${PROJECT_NAME})
set(CPACK_PROJECT_VERSION ${SPACE_PACKAGE_VERSION})
set(CPACK_PACKAGE_VERSION ${SPACE_PACKAGE_VERSION})
set(CPACK_PACKAGE_VENDOR ${SPACE_PACKAGE_VENDOR})

# Install the executable to /usr/bin
install(TARGETS ${PROJECT_NAME}
    RUNTIME DESTINATION bin
)

# Install private runtime shared libraries used by the app.
if(TARGET SDL3-shared)
    install(TARGETS SDL3-shared
        LIBRARY DESTINATION lib
    )
endif()

if(SPACE_ENABLE_CEF)
    install(TARGETS space_cef_helper
        RUNTIME DESTINATION bin
    )

    set(_space_cef_required_runtime_files
        "${SPACE_CEF_ROOT}/Release/libcef.so"
        "${SPACE_CEF_ROOT}/Release/libEGL.so"
        "${SPACE_CEF_ROOT}/Release/libGLESv2.so"
        "${SPACE_CEF_ROOT}/Release/libvk_swiftshader.so"
        "${SPACE_CEF_ROOT}/Release/libvulkan.so.1"
        "${SPACE_CEF_ROOT}/Release/vk_swiftshader_icd.json"
        "${SPACE_CEF_ROOT}/Release/chrome_100_percent.pak"
        "${SPACE_CEF_ROOT}/Release/chrome_200_percent.pak"
        "${SPACE_CEF_ROOT}/Release/icudtl.dat"
        "${SPACE_CEF_ROOT}/Release/resources.pak"
        "${SPACE_CEF_ROOT}/Release/v8_context_snapshot.bin"
    )
    foreach(_space_cef_file IN LISTS _space_cef_required_runtime_files)
        if(NOT EXISTS "${_space_cef_file}")
            message(FATAL_ERROR "Required CEF runtime file not found: ${_space_cef_file}")
        endif()
        install(FILES "${_space_cef_file}" DESTINATION lib/space/cef)
    endforeach()
    if(EXISTS "${SPACE_CEF_ROOT}/Release/snapshot_blob.bin")
        install(FILES "${SPACE_CEF_ROOT}/Release/snapshot_blob.bin" DESTINATION lib/space/cef)
    endif()
    if(EXISTS "${SPACE_CEF_ROOT}/Release/locales")
        install(DIRECTORY "${SPACE_CEF_ROOT}/Release/locales" DESTINATION lib/space/cef)
    else()
        message(FATAL_ERROR "Required CEF locales directory not found: ${SPACE_CEF_ROOT}/Release/locales")
    endif()
endif()

# Install the assets folder to /usr/share/space/assets
install(DIRECTORY assets/ DESTINATION share/${PROJECT_NAME}/assets)

# Path where the generated desktop file will go
set(DESKTOP_FILE ${CMAKE_BINARY_DIR}/space.desktop)

# Generate the .desktop file
file(WRITE ${DESKTOP_FILE} 
"[Desktop Entry]\n"
"Name=${CPACK_PROJECT_NAME}\n"
"Comment=space\n"
"Exec=${CPACK_PROJECT_NAME} %U\n"
"Icon=${CPACK_PROJECT_NAME}\n"
"Terminal=false\n"
"Type=Application\n"
"Categories=Game;\n"
)

# Install the generated desktop file
install(FILES ${DESKTOP_FILE} DESTINATION share/applications)
install(FILES assets/pics/space.png DESTINATION share/icons/hicolor/256x256/apps)

set(CPACK_GENERATOR "DEB;RPM")
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "space")
set(CPACK_DEBIAN_PACKAGE_VERSION ${SPACE_PACKAGE_VERSION})
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS_PRIVATE_DIRS "/usr/lib")
#set(CPACK_DEBIAN_PACKAGE_DEPENDS
#"libsdl3-0, libepoxy0, libbullet-dev, libopenal1"
#)
set(CPACK_DEBIAN_PACKAGE_DESCRIPTION ${SPACE_PACKAGE_DESCRIPTION})
set(CPACK_DEBIAN_PACKAGE_SECTION "games")
set(CPACK_RPM_PACKAGE_VERSION ${SPACE_PACKAGE_VERSION})
set(CPACK_RPM_PACKAGE_LICENSE "GPLv3")
set(CPACK_RPM_PACKAGE_RELEASE "1")
set(CPACK_RPM_PACKAGE_GROUP "Amusements/Games")
set(CPACK_RPM_PACKAGE_DESCRIPTION ${SPACE_PACKAGE_DESCRIPTION})
set(CPACK_RPM_PACKAGE_AUTOREQ "0")
set(CPACK_RPM_PACKAGE_AUTOPROV "0")

include(CPack)
