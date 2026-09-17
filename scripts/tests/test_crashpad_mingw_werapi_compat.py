from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WERAPI_COMPAT = REPO_ROOT / "external/sentry-native/external/crashpad/compat/mingw/werapi.h"
DBGHELP_COMPAT = REPO_ROOT / "external/sentry-native/external/crashpad/compat/mingw/dbghelp.h"
WINNT_COMPAT = REPO_ROOT / "external/sentry-native/external/crashpad/compat/mingw/winnt.h"
PROCESSTHREADSAPI_COMPAT = REPO_ROOT / "external/sentry-native/external/crashpad/compat/mingw/processthreadsapi.h"
COMPAT_CMAKE = REPO_ROOT / "external/sentry-native/external/crashpad/compat/CMakeLists.txt"
SNAPSHOT_CMAKE = REPO_ROOT / "external/sentry-native/external/crashpad/snapshot/CMakeLists.txt"
MINI_CHROMIUM_RAND_UTIL = REPO_ROOT / "external/sentry-native/external/crashpad/third_party/mini_chromium/mini_chromium/base/rand_util.cc"


def read_werapi_compat() -> str:
    return WERAPI_COMPAT.read_text(encoding="utf-8")


def read_dbghelp_compat() -> str:
    return DBGHELP_COMPAT.read_text(encoding="utf-8")


def read_winnt_compat() -> str:
    return WINNT_COMPAT.read_text(encoding="utf-8")


def read_processthreadsapi_compat() -> str:
    assert PROCESSTHREADSAPI_COMPAT.exists()
    return PROCESSTHREADSAPI_COMPAT.read_text(encoding="utf-8")


def read_compat_cmake() -> str:
    return COMPAT_CMAKE.read_text(encoding="utf-8")


def read_snapshot_cmake() -> str:
    return SNAPSHOT_CMAKE.read_text(encoding="utf-8")


def read_mini_chromium_rand_util() -> str:
    return MINI_CHROMIUM_RAND_UTIL.read_text(encoding="utf-8")


def test_old_mingw_pwer_submit_result_workaround_precedes_system_header() -> None:
    header = read_werapi_compat()

    workaround = "#define PWER_SUBMIT_RESULT WER_SUBMIT_RESULT*"
    assert "__MINGW64_VERSION_MAJOR" in header
    assert header.index(workaround) < header.index("#include_next <werapi.h>")
    assert "__MINGW64_VERSION_MAJOR <= 8" in header


def test_runtime_exception_information_fallback_is_available_after_system_header() -> None:
    header = read_werapi_compat()
    fallback = "typedef struct _WER_RUNTIME_EXCEPTION_INFORMATION"

    assert header.index(fallback) > header.index("#include_next <werapi.h>")
    assert "DWORD dwSize;" in header
    assert "HANDLE hProcess;" in header
    assert "HANDLE hThread;" in header
    assert "EXCEPTION_RECORD exceptionRecord;" in header
    assert "CONTEXT context;" in header
    assert "PCWSTR pwszReportId;" in header
    assert "PWER_RUNTIME_EXCEPTION_INFORMATION" in header


def test_runtime_exception_module_fallbacks_are_available_after_system_header_with_c_linkage() -> None:
    header = read_werapi_compat()
    include_next = header.index("#include_next <werapi.h>")
    type_fallback = header.index("typedef struct _WER_RUNTIME_EXCEPTION_INFORMATION")
    register_fallback = "HRESULT WINAPI WerRegisterRuntimeExceptionModule("
    unregister_fallback = "HRESULT WINAPI WerUnregisterRuntimeExceptionModule("

    assert header.index(register_fallback) > include_next
    assert header.index(unregister_fallback) > include_next
    assert header.index(register_fallback) > type_fallback
    assert header.index(unregister_fallback) > type_fallback
    assert "#ifdef __cplusplus\nextern \"C\" {\n#endif" in header
    assert "#ifdef __cplusplus\n}\n#endif" in header
    assert "PCWSTR pwszOutOfProcessCallbackDll" in header
    assert "PVOID pContext" in header
    assert "#ifndef WerRegisterRuntimeExceptionModule" not in header


def test_mini_chromium_windows_sdk_includes_use_mingw_case_sensitive_names() -> None:
    source = read_mini_chromium_rand_util()

    assert "#include <ntsecapi.h>" in source
    assert "#include <NTSecAPI.h>" not in source


def test_old_mingw_dbghelp_thread_names_stream_fallback_precedes_thread_name_structs() -> None:
    header = read_dbghelp_compat()
    include_next = header.index("#include_next <dbghelp.h>")
    thread_name_comment = header.index("//! \\brief Contains the name of the thread")
    fallback = "#define ThreadNamesStream 24"

    assert "__MINGW64_VERSION_MAJOR" in header
    assert "__MINGW64_VERSION_MAJOR <= 8" in header
    assert header.index(fallback) > include_next
    assert header.index(fallback) < thread_name_comment


def test_old_mingw_winnt_cet_xstate_fallbacks_follow_system_header_before_sdk_fallbacks() -> None:
    header = read_winnt_compat()
    include_next = header.index("#include_next <winnt.h>")
    sdk_fallbacks = header.index("// 10.0.10240.0 SDK")
    context_xstate = header.index("#define CONTEXT_XSTATE")
    xstate_cet_u = header.index("#define XSTATE_CET_U 11")
    xstate_mask = header.index("#define XSTATE_MASK_CET_U (1ull << XSTATE_CET_U)")
    cet_format = header.index("typedef struct _XSAVE_CET_U_FORMAT")

    assert include_next < context_xstate < sdk_fallbacks
    assert include_next < xstate_cet_u < sdk_fallbacks
    assert include_next < xstate_mask < sdk_fallbacks
    assert include_next < cet_format < sdk_fallbacks
    assert "(CONTEXT_AMD64 | 0x40)" in header or "0x00100040" in header
    assert "(CONTEXT_i386 | 0x40)" in header or "0x00010040" in header
    assert "__MINGW64_VERSION_MAJOR <= 8" in header
    assert "ULONG64 Ia32CetUMsr;" in header
    assert "ULONG64 Ia32Pl3SspMsr;" in header
    assert "} XSAVE_CET_U_FORMAT" in header


def test_old_mingw_winnt_xstate_compaction_fallbacks_follow_system_header_before_cet_fallbacks() -> None:
    header = read_winnt_compat()
    include_next = header.index("#include_next <winnt.h>")
    xstate_cet_u = header.index("#define XSTATE_CET_U 11")
    compaction_enable_guard = header.index("#ifndef XSTATE_COMPACTION_ENABLE")
    compaction_enable = header.index("#define XSTATE_COMPACTION_ENABLE 63")
    compaction_mask_guard = header.index("#ifndef XSTATE_COMPACTION_ENABLE_MASK")
    compaction_mask = header.index(
        "#define XSTATE_COMPACTION_ENABLE_MASK (1ull << XSTATE_COMPACTION_ENABLE)"
    )

    assert include_next < compaction_enable_guard < compaction_enable < xstate_cet_u
    assert include_next < compaction_mask_guard < compaction_mask < xstate_cet_u


def test_process_reader_initialize_context2_sdk_definitions_do_not_apply_to_mingw() -> None:
    cmake = read_snapshot_cmake()
    definitions = "WINVER=0x0A00 _WIN32_WINNT=0x0A00 NTDDI_VERSION=0x0A000006"
    cmake_before_definitions = cmake[: cmake.index(definitions)]
    lines_before_definitions = cmake_before_definitions.splitlines()
    condition = next(line.strip() for line in reversed(lines_before_definitions) if line.strip().startswith("if") and "(" in line)

    assert "if(NOT MINGW)" in cmake_before_definitions
    assert "MINGW" not in condition
    assert "CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION" in condition
    assert "CMAKE_SYSTEM_VERSION LESS 10" in condition


def test_old_mingw_initialize_context2_fallback_is_available_after_system_header_with_c_linkage() -> None:
    header = read_processthreadsapi_compat()
    include_next = header.index("#include_next <processthreadsapi.h>")
    guard = "#if defined(__MINGW64_VERSION_MAJOR) && __MINGW64_VERSION_MAJOR <= 8"
    declaration = (
        "WINBASEAPI WINBOOL WINAPI InitializeContext2(PVOID Buffer,\n"
        "                                             DWORD ContextFlags,\n"
        "                                             PCONTEXT* Context,\n"
        "                                             PDWORD ContextLength,\n"
        "                                             ULONG64 XStateCompactionMask);"
    )

    assert header.index(guard) > include_next
    assert header.index(declaration) > header.index(guard)
    assert "#ifdef __cplusplus\nextern \"C\" {\n#endif" in header
    assert "#ifdef __cplusplus\n}\n#endif" in header


def test_mingw_processthreadsapi_compat_header_is_in_compat_source_list() -> None:
    cmake = read_compat_cmake()

    assert "mingw/processthreadsapi.h" in cmake
