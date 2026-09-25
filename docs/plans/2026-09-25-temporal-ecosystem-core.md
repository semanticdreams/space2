# Temporal Ecosystem Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first production temporal core for Space: native C++17 temporal semantics, a Lua `temporal-core` binding, a Fennel `temporal` wrapper, conformance tests, and developer docs.

**Architecture:** C++ owns correctness-critical temporal machinery: exact instants and durations, strict ISO/RFC3339 parsing and formatting, ISO proleptic Gregorian civil date-times, IANA timezone lookup, DST disambiguation, and clock implementations. Lua exposes immutable native userdata through a small `temporal-core` module; Fennel exposes the ergonomic public `temporal` API while keeping timezone and calendar logic out of Fennel.

**Tech Stack:** C++17, Howard Hinnant `date/tz`, sol2 Lua bindings, Space Fennel modules, CMake/CTest, Space-native Fennel compile and constraints validation.

## Global Constraints

- Use a native C++ temporal core with Lua/Fennel ergonomics; do not build the production core in pure Fennel.
- Vendor Howard Hinnant `date/tz` under `external/date` and configure it for OS tzdb use with remote timezone downloading disabled.
- Keep the public modules named `temporal-core` for the native Lua binding and `temporal` for the canonical Fennel/Lua API.
- C++ code must remain compatible with the repository's C++17 baseline; do not depend on C++20 chrono timezone/calendar APIs.
- `Instant` is an absolute Unix/POSIX timeline point.
- Leap seconds are rejected explicitly in the first implementation.
- `Duration` is an exact elapsed time with nanosecond precision; it is not a calendar period.
- `PlainDateTime` is an ISO proleptic Gregorian civil date-time without zone or offset.
- `ZonedDateTime` pairs an `Instant` with an explicit IANA timezone id.
- Zoned conversion never defaults to the host local timezone; callers must pass a zone id.
- Disambiguation policies are `:reject`, `:earliest`, and `:latest`; `:reject` is the default.
- Provide `clock.system()` for real time and `clock.fixed(instant)` for deterministic tests and replay.
- Do not implement natural-language parsing, recurrence, localization, CLDR/ICU formatting, non-Gregorian calendars, host-local timezone defaults, persisted timestamp migrations, or runtime timer redesign in this PR.
- Do not change existing `engine.now-ms`, `sysinfo.now-ms`, media clocks, profiling clocks, or runtime timer behavior.
- Use canonical option keys only; do not add legacy aliases or compatibility shims.
- Errors must be loud: invalid fields, invalid parses, leap seconds, invalid zones, missing tzdb, and rejected DST gaps/overlaps throw.
- For Fennel-facing validation, run compile check before constraints before focused Fennel tests.

---

## File Structure

- `external/date/` — vendored Howard Hinnant `date/tz` source, license, version note, and local CMake target.
- `src/temporal.h` / `src/temporal.cpp` — native semantic model and timezone logic with no Lua dependency.
- `src/lua_temporal_core.h` / `src/lua_temporal_core.cpp` — sol2 binding that exposes `require("temporal-core")`.
- `src/lua_runtime.cpp` — runtime registration for `temporal-core`.
- `tests/test_temporal_core.cpp` — native core conformance tests.
- `tests/test_lua_temporal_core_binding.cpp` — direct Lua binding smoke/conformance tests.
- `assets/lua/temporal.fnl` — canonical ergonomic Fennel API.
- `assets/lua/tests/test-temporal.fnl` — Fennel public API tests.
- `assets/lua/tests/fast.fnl` — fast-suite registration for the public API tests.
- `docs/dev/features/temporal.md` — developer-facing temporal semantics and API guide.
- `docs/dev/features/index.md` — link to the temporal feature page.
- `CMakeLists.txt` — dependency, library, and CTest registration.

## Public Native Interfaces

Implement these C++ interfaces in `namespace space::temporal`:

```cpp
enum class Disambiguation { Reject, Earliest, Latest };

struct CivilFields {
    int year;
    int month;
    int day;
    int hour;
    int minute;
    int second;
    int nanosecond;
};

class Duration {
public:
    static Duration from_nanoseconds(std::int64_t nanoseconds);
    static Duration from_seconds(std::int64_t seconds);
    static Duration from_parts(std::int64_t seconds,
                               std::int64_t milliseconds,
                               std::int64_t microseconds,
                               std::int64_t nanoseconds);
    std::int64_t nanoseconds() const;
    std::string to_string() const;
};

class Instant {
public:
    static Instant parse(const std::string& text);
    static Instant from_unix(std::int64_t epoch_seconds, std::int32_t nanosecond);
    std::int64_t epoch_seconds() const;
    std::int32_t nanosecond() const;
    std::string to_string() const;
    Instant add(const Duration& duration) const;
    Duration since(const Instant& earlier) const;
    bool operator==(const Instant& other) const;
    bool operator<(const Instant& other) const;
};

class PlainDateTime {
public:
    static PlainDateTime parse(const std::string& text);
    static PlainDateTime from_fields(int year,
                                     int month,
                                     int day,
                                     int hour,
                                     int minute,
                                     int second,
                                     int nanosecond);
    CivilFields fields() const;
    std::string to_string() const;
};

class ZonedDateTime {
public:
    static ZonedDateTime from_plain(const PlainDateTime& local,
                                    const std::string& zone_id,
                                    Disambiguation disambiguation);
    static ZonedDateTime from_instant(const Instant& instant,
                                      const std::string& zone_id);
    Instant instant() const;
    std::string zone_id() const;
    CivilFields fields() const;
    std::string offset_string() const;
    std::string to_string() const;
};

class Clock {
public:
    static Clock system();
    static Clock fixed(const Instant& instant);
    Instant now() const;
};

Disambiguation parse_disambiguation(const std::string& value);
std::string tzdb_version();
```

## Public Fennel API

`assets/lua/temporal.fnl` returns:

```fennel
{:duration {:from from-duration
            :from-nanoseconds core.duration.from-nanoseconds
            :from-seconds core.duration.from-seconds}
 :instant {:parse core.instant.parse
           :from-unix core.instant.from-unix}
 :plain-date-time {:parse core.plain-date-time.parse
                   :from-fields core.plain-date-time.from-fields}
 :zoned-date-time {:from-plain from-zoned-plain
                   :from-instant core.zoned-date-time.from-instant}
 :clock {:system core.clock.system
         :fixed core.clock.fixed}
 :tzdb {:version core.tzdb.version}}
```

---

### Task 1: Vendor `date/tz` and Wire Build Targets

**Files:**
- Create: `external/date/CMakeLists.txt`
- Create: `external/date/LICENSE.txt`
- Create: `external/date/VENDORED_VERSION.md`
- Create: `external/date/include/date/date.h`
- Create: `external/date/include/date/tz.h`
- Create: `external/date/include/date/tz_private.h`
- Create: `external/date/src/tz.cpp`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Consumes: Howard Hinnant `date/tz` release `v3.0.1` source files.
- Produces: CMake targets `date::date` and `date::date-tz` linked into `${PROJECT_NAME}_lib`.

- [ ] **Step 1: Add the vendored source snapshot.**
  Copy upstream `v3.0.1` files into the exact paths listed above. Preserve the upstream license text in `external/date/LICENSE.txt`.

- [ ] **Step 2: Record the vendored source policy.**
  Create `external/date/VENDORED_VERSION.md` with:

  ```markdown
  # Howard Hinnant date/tz vendored snapshot

  Source: https://github.com/HowardHinnant/date
  Version: v3.0.1
  Purpose: C++17 Gregorian calendar, RFC3339 parsing support, and IANA timezone handling for Space temporal core.
  Local policy: build against the OS timezone database; remote timezone database download/update paths are disabled.
  ```

- [ ] **Step 3: Create the local dependency CMake target.**
  Create `external/date/CMakeLists.txt`:

  ```cmake
  cmake_minimum_required(VERSION 3.18)

  add_library(date_date INTERFACE)
  target_include_directories(date_date INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/include)
  add_library(date::date ALIAS date_date)

  find_package(Threads REQUIRED)

  add_library(date_tz STATIC src/tz.cpp)
  target_include_directories(date_tz PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_compile_features(date_tz PUBLIC cxx_std_17)
  target_compile_definitions(date_tz PUBLIC
      USE_OS_TZDB=1
      HAS_REMOTE_API=0
      AUTO_DOWNLOAD=0
  )
  target_link_libraries(date_tz PUBLIC date_date Threads::Threads)
  add_library(date::date-tz ALIAS date_tz)
  ```

- [ ] **Step 4: Register the dependency in the top-level build.**
  Modify `CMakeLists.txt`:
  - add `add_subdirectory(external/date)` beside the other `external/*` dependency registrations;
  - add `space_suppress_target_warnings(date_tz)` inside the third-party warning suppression block if that block exists for the current configuration;
  - add `date::date-tz` to `target_link_libraries(${PROJECT_NAME}_lib ...)`.

- [ ] **Step 5: Validate configure and build.**
  Run with explicit timeouts:

  ```bash
  make cmake
  make build
  ```

  Expected: both commands complete successfully. Use timeout `600000` for `make cmake` and timeout `14400000` for `make build`.

- [ ] **Step 6: Commit this task.**
  Stage only this task's dependency/build files and commit with:

  ```bash
  git commit -m "build(temporal): vendor date timezone dependency"
  ```

---

### Task 2: Native Temporal Core and C++ Conformance Tests

**Files:**
- Create: `src/temporal.h`
- Create: `src/temporal.cpp`
- Create: `tests/test_temporal_core.cpp`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Consumes: `date::date-tz` from Task 1.
- Produces: the `space::temporal` C++ API declared in the Public Native Interfaces section.

- [ ] **Step 1: Register the native CTest target.**
  Add near existing C++ tests in `CMakeLists.txt`:

  ```cmake
  add_executable(test_temporal_core
      tests/test_temporal_core.cpp
      src/temporal.cpp
  )
  target_include_directories(test_temporal_core PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
  target_link_libraries(test_temporal_core date::date-tz)
  add_test(NAME test_temporal_core COMMAND test_temporal_core)
  set_tests_properties(test_temporal_core PROPERTIES
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  )
  ```

- [ ] **Step 2: Write failing tests for the native API.**
  Create `tests/test_temporal_core.cpp` with small helper functions `expect_true`, `expect_eq`, and `expect_throws`. Include checks named:
  - `test_instant_parse_format_requires_offset`
  - `test_instant_rejects_leap_second`
  - `test_duration_arithmetic_and_overflow`
  - `test_plain_date_time_field_validation`
  - `test_zoned_from_plain_requires_valid_zone`
  - `test_new_york_spring_gap_disambiguation`
  - `test_new_york_fall_overlap_disambiguation`
  - `test_fixed_clock_is_deterministic`
  - `test_tzdb_version_is_available`

  The tests must assert these exact visible results:

  ```cpp
  expect_eq(Instant::parse("2026-09-25T12:34:56Z").to_string(),
            "2026-09-25T12:34:56Z");
  expect_eq(Instant::parse("2026-09-25T08:34:56-04:00").to_string(),
            "2026-09-25T12:34:56Z");
  expect_throws([] { Instant::parse("2026-09-25T12:34:56"); });
  expect_throws([] { Instant::parse("2026-12-31T23:59:60Z"); });
  expect_eq(Instant::parse("2026-09-25T12:34:56Z")
                .add(Duration::from_parts(90, 500, 0, 0))
                .to_string(),
            "2026-09-25T12:36:26.5Z");
  expect_throws([] { PlainDateTime::parse("2026-02-29T00:00:00"); });
  expect_throws([] { PlainDateTime::from_fields(2026, 13, 1, 0, 0, 0, 0); });
  expect_throws([] { PlainDateTime::from_fields(2026, 1, 1, 24, 0, 0, 0); });
  expect_eq(ZonedDateTime::from_plain(PlainDateTime::parse("2026-11-01T01:30:00"),
                                      "America/New_York",
                                      Disambiguation::Earliest)
                .instant()
                .to_string(),
            "2026-11-01T05:30:00Z");
  expect_eq(ZonedDateTime::from_plain(PlainDateTime::parse("2026-11-01T01:30:00"),
                                      "America/New_York",
                                      Disambiguation::Latest)
                .instant()
                .to_string(),
            "2026-11-01T06:30:00Z");
  expect_throws([] {
      ZonedDateTime::from_plain(PlainDateTime::parse("2026-11-01T01:30:00"),
                                "America/New_York",
                                Disambiguation::Reject);
  });
  expect_throws([] {
      ZonedDateTime::from_plain(PlainDateTime::parse("2026-03-08T02:30:00"),
                                "America/New_York",
                                Disambiguation::Reject);
  });
  expect_eq(ZonedDateTime::from_plain(PlainDateTime::parse("2026-03-08T02:30:00"),
                                      "America/New_York",
                                      Disambiguation::Earliest)
                .instant()
                .to_string(),
            "2026-03-08T07:00:00Z");
  expect_eq(ZonedDateTime::from_plain(PlainDateTime::parse("2026-03-08T02:30:00"),
                                      "America/New_York",
                                      Disambiguation::Latest)
                .instant()
                .to_string(),
            "2026-03-08T06:59:59.999999999Z");
  expect_throws([] {
      ZonedDateTime::from_plain(PlainDateTime::parse("2026-01-01T00:00:00"),
                                "Mars/Base",
                                Disambiguation::Reject);
  });
  expect_eq(Clock::fixed(Instant::parse("2026-09-25T12:34:56Z")).now().to_string(),
            "2026-09-25T12:34:56Z");
  expect_true(!tzdb_version().empty(), "tzdb version should not be empty");
  ```

- [ ] **Step 3: Verify the test fails before implementation.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R '^test_temporal_core$' --output-on-failure
  ```

  Expected before implementation: build or test failure due to missing temporal symbols.

- [ ] **Step 4: Implement `src/temporal.h`.**
  Add declarations exactly matching the Public Native Interfaces section. Use `#pragma once`, include `<cstdint>` and `<string>`, and keep Lua/sol headers out of this file.

- [ ] **Step 5: Implement `src/temporal.cpp`.**
  Requirements:
  - store `Instant` as `date::sys_time<std::chrono::nanoseconds>`;
  - store `PlainDateTime` as `date::local_time<std::chrono::nanoseconds>`;
  - store `ZonedDateTime` as `Instant` plus `std::string zone_id`;
  - parse instants only in `YYYY-MM-DDTHH:MM:SS[.fraction](Z|+HH:MM|-HH:MM)` form;
  - parse plain date-times only in `YYYY-MM-DDTHH:MM:SS[.fraction]` form;
  - accept fractional seconds of 1 through 9 digits and right-pad to nanoseconds;
  - format canonical UTC instants with `Z` and no fractional part when nanosecond is zero;
  - trim trailing zeroes in fractional seconds;
  - throw `std::invalid_argument` for invalid fields, invalid parses, leap seconds, unknown zones, and rejected ambiguous/nonexistent local times;
  - throw `std::overflow_error` for duration arithmetic overflow;
  - throw `std::runtime_error` with prefix `temporal timezone database unavailable:` when tzdb access fails;
  - implement `Disambiguation::Reject` by throwing on `date::local_info::ambiguous` and `date::local_info::nonexistent`;
  - implement `Disambiguation::Earliest` for overlaps as `local - info.first.offset` and for gaps as `info.second.begin`;
  - implement `Disambiguation::Latest` for overlaps as `local - info.second.offset` and for gaps as `info.first.end - std::chrono::nanoseconds(1)`.

- [ ] **Step 6: Validate native core behavior.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R '^test_temporal_core$' --output-on-failure
  ```

  Expected: `test_temporal_core` passes.

- [ ] **Step 7: Commit this task.**
  Stage only `src/temporal.h`, `src/temporal.cpp`, `tests/test_temporal_core.cpp`, and the related `CMakeLists.txt` test changes. Commit with:

  ```bash
  git commit -m "feat(temporal): add native temporal core"
  ```

---

### Task 3: Lua `temporal-core` Binding

**Files:**
- Create: `src/lua_temporal_core.h`
- Create: `src/lua_temporal_core.cpp`
- Create: `tests/test_lua_temporal_core_binding.cpp`
- Modify: `src/lua_runtime.cpp`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Consumes: `space::temporal` C++ API from Task 2.
- Produces: Lua module `require("temporal-core")` with userdata types `TemporalDuration`, `TemporalInstant`, `TemporalPlainDateTime`, `TemporalZonedDateTime`, and `TemporalClock`.

- [ ] **Step 1: Register the Lua binding test target.**
  Add near existing Lua binding tests in `CMakeLists.txt`:

  ```cmake
  add_executable(test_lua_temporal_core_binding
      tests/test_lua_temporal_core_binding.cpp
      src/temporal.cpp
      src/lua_temporal_core.cpp
  )
  target_include_directories(test_lua_temporal_core_binding PRIVATE
      ${CMAKE_CURRENT_SOURCE_DIR}/src
  )
  target_link_libraries(test_lua_temporal_core_binding lua date::date-tz)
  add_test(NAME test_lua_temporal_core_binding COMMAND test_lua_temporal_core_binding)
  set_tests_properties(test_lua_temporal_core_binding PROPERTIES
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
  )
  ```

- [ ] **Step 2: Write the failing Lua binding test.**
  Create `tests/test_lua_temporal_core_binding.cpp` that opens Lua base/package/table/string/math libraries, calls `lua_bind_temporal_core(lua)`, and runs a script with these assertions:

  ```lua
  local core = require("temporal-core")

  local instant = core.instant.parse("2026-09-25T08:34:56-04:00")
  assert(instant["to-string"](instant) == "2026-09-25T12:34:56Z")

  local duration = core.duration["from-parts"]({
      seconds = 90,
      milliseconds = 500,
      microseconds = 0,
      nanoseconds = 0
  })
  local added = instant.add(instant, duration)
  assert(added["to-string"](added) == "2026-09-25T12:36:26.5Z")

  local plain = core["plain-date-time"].parse("2026-11-01T01:30:00")
  assert(plain.fields(plain).year == 2026)

  local earliest = core["zoned-date-time"]["from-plain"](plain, "America/New_York", "earliest")
  local earliest_instant = earliest.instant(earliest)
  assert(earliest_instant["to-string"](earliest_instant) == "2026-11-01T05:30:00Z")

  local clock = core.clock.fixed(instant)
  local now = clock.now(clock)
  assert(now["to-string"](now) == "2026-09-25T12:34:56Z")

  assert(type(core.tzdb.version()) == "string")
  assert(core.tzdb.version() ~= "")

  local ok = pcall(function()
      core.instant.parse("2026-09-25T12:34:56")
  end)
  assert(ok == false)

  ok = pcall(function()
      core["zoned-date-time"]["from-plain"](plain, "Mars/Base", "reject")
  end)
  assert(ok == false)
  ```

- [ ] **Step 3: Verify the binding test fails before implementation.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R '^test_lua_temporal_core_binding$' --output-on-failure
  ```

  Expected before implementation: build or Lua require failure.

- [ ] **Step 4: Implement the binding header.**
  Create `src/lua_temporal_core.h`:

  ```cpp
  #pragma once

  #include <sol/sol.hpp>

  void lua_bind_temporal_core(sol::state& lua);
  ```

- [ ] **Step 5: Implement `src/lua_temporal_core.cpp`.**
  Requirements:
  - register userdata with `sol::no_constructor`;
  - expose factory tables under `package.preload["temporal-core"]`;
  - expose `duration.from-nanoseconds`, `duration.from-seconds`, and `duration.from-parts`;
  - expose `instant.parse` and `instant.from-unix`;
  - expose `plain-date-time.parse` and `plain-date-time.from-fields`;
  - expose `zoned-date-time.from-plain` and `zoned-date-time.from-instant`;
  - expose `clock.system`, `clock.fixed`, and `tzdb.version`;
  - convert `CivilFields` to tables with `year`, `month`, `day`, `hour`, `minute`, `second`, and `nanosecond` keys;
  - accept disambiguation strings exactly `"reject"`, `"earliest"`, and `"latest"`;
  - for `duration.from-parts`, missing `seconds`, `milliseconds`, `microseconds`, and `nanoseconds` default to `0`;
  - for `plain-date-time.from-fields`, require `year`, `month`, and `day`; default `hour`, `minute`, `second`, and `nanosecond` to `0`.

- [ ] **Step 6: Register the binding in `src/lua_runtime.cpp`.**
  Add `#include "lua_temporal_core.h"` with the other binding includes/declarations and call `lua_bind_temporal_core(lua);` in `LuaRuntime::install_base_bindings()` before `lua_bind_engine(lua);`.

- [ ] **Step 7: Validate native and binding tests.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
  ```

  Expected: both tests pass.

- [ ] **Step 8: Commit this task.**
  Stage only the Lua binding, binding test, runtime registration, and related CMake changes. Commit with:

  ```bash
  git commit -m "feat(temporal): expose native temporal Lua core"
  ```

---

### Task 4: Fennel `temporal` API and Public Tests

**Files:**
- Create: `assets/lua/temporal.fnl`
- Create: `assets/lua/tests/test-temporal.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `require("temporal-core")` from Task 3.
- Produces: public `(require :temporal)` API described in the Public Fennel API section.

- [ ] **Step 1: Create the Fennel wrapper.**
  Create `assets/lua/temporal.fnl`. It must:
  - `(local core (require :temporal-core))`;
  - expose exactly the namespaces listed in the Public Fennel API section;
  - implement `duration.from` by passing canonical keys to `core.duration.from-parts`;
  - implement `zoned-date-time.from-plain` with default `:reject` disambiguation;
  - convert `:reject`, `:earliest`, and `:latest` to `"reject"`, `"earliest"`, and `"latest"`;
  - assert that zone ids are strings;
  - expose no `.new` constructors;
  - not catch or convert native errors to nil.

- [ ] **Step 2: Create focused public API tests.**
  Create `assets/lua/tests/test-temporal.fnl` with a `tests` array and `{:main main}` return matching other fast tests. Include this helper:

  ```fennel
  (fn assert-error [f message]
    (local (ok err) (pcall f))
    (assert (not ok) message)
    err)
  ```

  Add tests named:
  - `temporal module loads`;
  - `instant parse and format require explicit offset`;
  - `duration factories and instant arithmetic`;
  - `plain date time parses fields`;
  - `zoned date time handles New York overlap`;
  - `zoned date time rejects gaps by default`;
  - `zoned date time resolves New York spring gap`;
  - `fixed clock returns deterministic instant`;
  - `invalid inputs throw loudly`.

  The tests must include these exact assertions:

  ```fennel
  (local Temporal (require :temporal))

  (local instant (Temporal.instant.parse "2026-09-25T08:34:56-04:00"))
  (assert (= (instant:to-string) "2026-09-25T12:34:56Z"))
  (assert-error #(Temporal.instant.parse "2026-09-25T12:34:56")
                "instant parse without offset should fail")
  (assert-error #(Temporal.instant.parse "2026-12-31T23:59:60Z")
                "leap second should fail")

  (local base (Temporal.instant.parse "2026-09-25T12:34:56Z"))
  (local duration (Temporal.duration.from {:seconds 90 :milliseconds 500}))
  (local added (base:add duration))
  (assert (= (added:to-string) "2026-09-25T12:36:26.5Z"))

  (local plain (Temporal.plain-date-time.parse "2026-11-01T01:30:00"))
  (assert (= (plain:to-string) "2026-11-01T01:30:00"))
  (local plain-fields (plain:fields))
  (assert (= plain-fields.year 2026))

  (local earliest
    (Temporal.zoned-date-time.from-plain
      plain
      "America/New_York"
      {:disambiguation :earliest}))
  (local latest
    (Temporal.zoned-date-time.from-plain
      plain
      "America/New_York"
      {:disambiguation :latest}))
  (local earliest-instant (earliest:instant))
  (local latest-instant (latest:instant))
  (assert (= (earliest-instant:to-string) "2026-11-01T05:30:00Z"))
  (assert (= (latest-instant:to-string) "2026-11-01T06:30:00Z"))
  (assert-error #(Temporal.zoned-date-time.from-plain plain "America/New_York")
                "ambiguous overlap should reject by default")

  (local gap (Temporal.plain-date-time.parse "2026-03-08T02:30:00"))
  (assert-error #(Temporal.zoned-date-time.from-plain gap "America/New_York")
                "nonexistent gap should reject by default")
  (local gap-earliest
    (Temporal.zoned-date-time.from-plain
      gap
      "America/New_York"
      {:disambiguation :earliest}))
  (local gap-latest
    (Temporal.zoned-date-time.from-plain
      gap
      "America/New_York"
      {:disambiguation :latest}))
  (local gap-earliest-instant (gap-earliest:instant))
  (local gap-latest-instant (gap-latest:instant))
  (assert (= (gap-earliest-instant:to-string) "2026-03-08T07:00:00Z"))
  (assert (= (gap-latest-instant:to-string) "2026-03-08T06:59:59.999999999Z"))

  (local clock (Temporal.clock.fixed base))
  (local fixed-now-a (clock:now))
  (local fixed-now-b (clock:now))
  (assert (= (fixed-now-a:to-string) "2026-09-25T12:34:56Z"))
  (assert (= (fixed-now-b:to-string) "2026-09-25T12:34:56Z"))
  (assert-error #(Temporal.zoned-date-time.from-plain plain "Mars/Base")
                "invalid zone should throw")
  ```

- [ ] **Step 3: Register the public test in the fast suite.**
  Add `:tests.test-temporal` to `assets/lua/tests/fast.fnl` near other non-UI utility tests.

- [ ] **Step 4: Run Fennel compile check first.**
  Run after `make build` if `./build/space` may be stale:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/tests/test-temporal.fnl --file assets/lua/tests/fast.fnl
  ```

  Expected: pass.

- [ ] **Step 5: Run constraints second.**
  Run:

  ```bash
  make constraints
  ```

  Expected: pass.

- [ ] **Step 6: Run focused public tests third.**
  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal:main
  ```

  Expected: pass.

- [ ] **Step 7: Commit this task.**
  Stage only `assets/lua/temporal.fnl`, `assets/lua/tests/test-temporal.fnl`, and `assets/lua/tests/fast.fnl`. Commit with:

  ```bash
  git commit -m "feat(temporal): add Fennel temporal API"
  ```

---

### Task 5: Developer Documentation

**Files:**
- Create: `docs/dev/features/temporal.md`
- Modify: `docs/dev/features/index.md`

**Interfaces:**
- Consumes: public API and semantics from Tasks 2-4.
- Produces: canonical developer documentation for the first temporal core.

- [ ] **Step 1: Create the temporal feature page.**
  Create `docs/dev/features/temporal.md` with sections:
  - `# Temporal Core`
  - `## Public modules`
  - `## Values`
  - `## Timezone policy`
  - `## Disambiguation`
  - `## Parsing and formatting`
  - `## Clocks`
  - `## Future layers`
  - `## Validation`

  The page must explicitly state:
  - `require :temporal` is the public Fennel/Lua API;
  - `require "temporal-core"` is the lower-level native binding;
  - instants are Unix/POSIX timeline values;
  - leap seconds are rejected;
  - `Duration` is exact elapsed time, not a calendar period;
  - `PlainDateTime` has no zone or offset;
  - `ZonedDateTime` requires an explicit IANA zone id;
  - the API does not silently use host-local timezone defaults;
  - natural-language parsing, recurrence, localization, ICU formatting, CLDR data, non-Gregorian calendars, and persisted timestamp migrations are future layers.

- [ ] **Step 2: Document validation commands.**
  Add these commands to the page:

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/tests/test-temporal.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal:main
  ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

- [ ] **Step 3: Link the feature page from the feature index.**
  Add this line to `docs/dev/features/index.md` in alphabetical order:

  ```markdown
  - [Temporal Core](./temporal)
  ```

- [ ] **Step 4: Validate documentation content.**
  Run:

  ```bash
  rg "Temporal Core|temporal-core|America/New_York|natural-language|recurrence|ICU|non-Gregorian" docs/dev/features/temporal.md docs/dev/features/index.md
  ```

  Expected: all terms are present in the new docs or index link.

- [ ] **Step 5: Commit this task.**
  Stage only the docs files and commit with:

  ```bash
  git commit -m "docs(temporal): document temporal core semantics"
  ```

---

### Task 6: Final Validation and Compatibility Review

**Files:**
- Validate: `external/date/**`
- Validate: `src/temporal.h`
- Validate: `src/temporal.cpp`
- Validate: `src/lua_temporal_core.h`
- Validate: `src/lua_temporal_core.cpp`
- Validate: `src/lua_runtime.cpp`
- Validate: `tests/test_temporal_core.cpp`
- Validate: `tests/test_lua_temporal_core_binding.cpp`
- Validate: `assets/lua/temporal.fnl`
- Validate: `assets/lua/tests/test-temporal.fnl`
- Validate: `assets/lua/tests/fast.fnl`
- Validate: `docs/dev/features/temporal.md`
- Validate: `docs/dev/features/index.md`
- Validate: `CMakeLists.txt`

**Interfaces:**
- Consumes: completed Tasks 1-5.
- Produces: local validation evidence for finishing and PR creation.

- [ ] **Step 1: Run configure and full build.**
  Run with explicit timeouts:

  ```bash
  make cmake
  make build
  ```

  Expected: both pass. Use timeout `600000` for `make cmake` and timeout `14400000` for `make build`.

- [ ] **Step 2: Run focused native tests.**
  Run:

  ```bash
  ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
  ```

  Expected: both focused native tests pass.

- [ ] **Step 3: Run Fennel compile check.**
  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/tests/test-temporal.fnl --file assets/lua/tests/fast.fnl
  ```

  Expected: pass.

- [ ] **Step 4: Run constraints.**
  Run:

  ```bash
  make constraints
  ```

  Expected: pass.

- [ ] **Step 5: Run focused Fennel temporal tests.**
  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal:main
  ```

  Expected: pass.

- [ ] **Step 6: Run broader suite.**
  This work touches C++, CMake, native bindings, Fennel modules, and fast-suite registration, so run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: pass.

- [ ] **Step 7: Review compatibility invariants.**
  Run:

  ```bash
  git diff -- src/lua_engine.cpp src/lua_sysinfo.cpp assets/lua/runtime-timers.fnl src/lua_runtime.cpp CMakeLists.txt
  rg "now-ms|sysinfo.now-ms|current_zone|local timezone|os.time|os.date" src assets/lua docs/dev/features/temporal.md
  ```

  Expected:
  - no changes to `engine.now-ms`;
  - no changes to `sysinfo.now-ms`;
  - no changes to `assets/lua/runtime-timers.fnl`;
  - no public zoned conversion API defaults to host-local timezone;
  - `current_zone` is not used as a public default.

- [ ] **Step 8: Leave final integration to the finishing workflow.**
  Do not claim ready-to-merge until reviewed changes are committed, the worktree is clean, the branch is evaluated against current `origin/main`, required validation passes, and PR CI is green.
