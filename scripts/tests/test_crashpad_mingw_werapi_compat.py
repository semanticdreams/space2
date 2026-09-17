from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WERAPI_COMPAT = REPO_ROOT / "external/sentry-native/external/crashpad/compat/mingw/werapi.h"
MINI_CHROMIUM_RAND_UTIL = REPO_ROOT / "external/sentry-native/external/crashpad/third_party/mini_chromium/mini_chromium/base/rand_util.cc"


def read_werapi_compat() -> str:
    return WERAPI_COMPAT.read_text(encoding="utf-8")


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
