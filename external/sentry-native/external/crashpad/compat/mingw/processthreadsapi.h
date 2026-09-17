// Copyright 2026 The Crashpad Authors. All rights reserved.
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

#ifndef CRASHPAD_COMPAT_MINGW_PROCESSTHREADSAPI_H_
#define CRASHPAD_COMPAT_MINGW_PROCESSTHREADSAPI_H_

#include_next <processthreadsapi.h>

#if defined(__MINGW64_VERSION_MAJOR) && __MINGW64_VERSION_MAJOR <= 8

#ifdef __cplusplus
extern "C" {
#endif

WINBASEAPI WINBOOL WINAPI InitializeContext2(PVOID Buffer,
                                             DWORD ContextFlags,
                                             PCONTEXT* Context,
                                             PDWORD ContextLength,
                                             ULONG64 XStateCompactionMask);

#ifdef __cplusplus
}
#endif

#endif

#endif  // CRASHPAD_COMPAT_MINGW_PROCESSTHREADSAPI_H_
