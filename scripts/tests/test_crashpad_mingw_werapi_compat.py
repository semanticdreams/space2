from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WERAPI_COMPAT = REPO_ROOT / "external/sentry-native/external/crashpad/compat/mingw/werapi.h"


def read_werapi_compat() -> str:
    return WERAPI_COMPAT.read_text(encoding="utf-8")


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
