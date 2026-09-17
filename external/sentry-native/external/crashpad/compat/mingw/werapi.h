// Copyright 2015 The Crashpad Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef CRASHPAD_COMPAT_MINGW_WERAPI_H_
#define CRASHPAD_COMPAT_MINGW_WERAPI_H_

typedef HANDLE HREPORT;

#ifndef WER_MAX_PREFERRED_MODULES_BUFFER
#define WER_MAX_PREFERRED_MODULES_BUFFER 256
#endif

// Ubuntu 22.04/Jammy's MinGW-w64 8.0.0 and MinGW-w64 11.0.1 werapi.h declare
// WER_SUBMIT_RESULT but omit the PWER_SUBMIT_RESULT pointer typedef while
// still using PWER_SUBMIT_RESULT in WerReportSubmit(). Define the missing name
// before include_next so that the affected headers can parse their own prototype.
// Newer MinGW headers include *PWER_SUBMIT_RESULT in the enum typedef, so limit
// this workaround to detected affected MinGW versions; predefining it for fixed
// headers would corrupt that typedef.
#if defined(__MINGW64_VERSION_MAJOR) && __MINGW64_VERSION_MAJOR <= 11
#ifndef PWER_SUBMIT_RESULT
#define PWER_SUBMIT_RESULT WER_SUBMIT_RESULT*
#endif
#endif

#include_next <werapi.h>

#ifndef PWER_SUBMIT_RESULT
#define PWER_SUBMIT_RESULT WER_SUBMIT_RESULT*
#endif

// MinGW's WER_RUNTIME_EXCEPTION_INFORMATION declaration is gated on
// _WIN32_WINNT >= 0x0601. Crashpad uses the pointer type even when the build's
// target version is lower, so provide the same base fields from MinGW's Win7+
// declaration when the system header intentionally omitted it. Crashpad carries
// its own Windows 10 19041 extension for bIsFatal.
#if !defined(_WIN32_WINNT) || _WIN32_WINNT < 0x0601
typedef struct _WER_RUNTIME_EXCEPTION_INFORMATION {
  DWORD dwSize;
  HANDLE hProcess;
  HANDLE hThread;
  EXCEPTION_RECORD exceptionRecord;
  CONTEXT context;
  PCWSTR pwszReportId;
} WER_RUNTIME_EXCEPTION_INFORMATION, *PWER_RUNTIME_EXCEPTION_INFORMATION;

#ifdef __cplusplus
extern "C" {
#endif

HRESULT WINAPI WerRegisterRuntimeExceptionModule(
    PCWSTR pwszOutOfProcessCallbackDll,
    PVOID pContext);
HRESULT WINAPI WerUnregisterRuntimeExceptionModule(
    PCWSTR pwszOutOfProcessCallbackDll,
    PVOID pContext);

#ifdef __cplusplus
}
#endif
#endif

#endif  // CRASHPAD_COMPAT_MINGW_WERAPI_H_
