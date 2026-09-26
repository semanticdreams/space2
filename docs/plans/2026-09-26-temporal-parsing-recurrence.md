# Temporal Parsing and Recurrence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a layered parsing, formatting, structured-expression, and recurrence foundation above the existing temporal core while keeping core temporal semantics independent.

**Architecture:** The native C++ temporal core remains the primitive semantic layer and only gains dependency-free civil helpers needed by higher layers. Strict standard parsing/formatting, explicit patterns, RRULE recurrence, structured expression resolution, and the small deterministic natural grammar live in focused Fennel modules under the public `temporal` umbrella.

**Tech Stack:** C++17, Howard Hinnant `date/tz`, sol2 Lua bindings, Space Fennel modules/tests, CMake/CTest, Space-native Fennel check/constraints/test tooling.

## Global Constraints

- Keep `src/temporal.h` / `src/temporal.cpp` clean and independent from Lua, Fennel, natural language, recurrence, ICU, CLDR, and localization dependencies.
- Higher-level parsers must translate external representations into typed temporal concepts; they must not make raw Unix timestamps the API boundary.
- Natural parsing must return structured temporal expressions first; timestamp-like resolution is context-dependent and explicit.
- Recurrence is its own semantic subsystem, separate from standard parsing and natural-language parsing.
- Natural-language recurrence is only a frontend that emits recurrence expressions/rules.
- Do not add ICU, CLDR, locale data, broad natural-language parsing, non-Gregorian calendars, host-local timezone defaults, persisted timestamp migrations, or runtime timer redesign in this slice.
- No new third-party runtime dependency is allowed in this slice.
- Existing public temporal APIs must remain compatible: `duration`, `instant`, `plain-date-time`, `zoned-date-time`, `clock`, and `tzdb` keep their current names and behavior.
- Zoned conversion must continue to require explicit IANA zone ids; no API may silently default to the host-local timezone.
- Errors must be loud: invalid fields, invalid patterns, invalid parses, unsupported recurrence expansion, invalid RRULE, and missing context must throw.
- Use canonical option keys only; do not add legacy aliases or compatibility shims.
- Fennel-facing validation order is compile check first, constraints second, focused Fennel tests third.
- `make build` is the runtime/freshness prerequisite before using `./build/space` when the binary may be missing or stale.
- Future broad localized parsing/formatting must choose an ICU/CLDR/data-packaging strategy before implementation.
- Future broad natural-language coverage must choose supported languages/locales and ambiguity UX before implementation.

---

## File Structure

- `src/temporal.h` / `src/temporal.cpp` — add dependency-free `PlainDateTime` civil helpers.
- `src/lua_temporal_core.cpp` — expose native civil helpers to Lua userdata.
- `tests/test_temporal_core.cpp` — native helper tests.
- `tests/test_lua_temporal_core_binding.cpp` — Lua binding helper tests.
- `assets/lua/temporal/standard.fnl` — strict standard parse/format facade.
- `assets/lua/temporal/pattern.fnl` — deterministic explicit pattern compiler/parser/formatter.
- `assets/lua/temporal/recurrence.fnl` — normalized recurrence rules, RRULE parser/serializer, bounded daily/weekly expansion.
- `assets/lua/temporal/expression.fnl` — structured expression context and resolution.
- `assets/lua/temporal/natural.fnl` — small deterministic English natural parser.
- `assets/lua/temporal.fnl` — export new namespaces without breaking existing API.
- `assets/lua/tests/test-temporal-parsing-recurrence.fnl` — focused public Fennel tests for the new layers.
- `assets/lua/tests/fast.fnl` — register focused test.
- `docs/dev/features/temporal.md` — link to the new feature page and core independence note.
- `docs/dev/features/temporal-parsing-recurrence.md` — document APIs, examples, boundaries, and deferred continuation path.
- `docs/dev/features/index.md` — feature page link.

## Public API Additions

Existing `Temporal.duration`, `Temporal.instant`, `Temporal.plain-date-time`, `Temporal.zoned-date-time`, `Temporal.clock`, and `Temporal.tzdb` stay compatible.

New public namespaces:

```fennel
Temporal.standard.parse-instant
Temporal.standard.format-instant
Temporal.standard.parse-plain-date-time
Temporal.standard.format-plain-date-time
Temporal.standard.parse-zoned-date-time
Temporal.standard.format-zoned-date-time

Temporal.pattern.compile
Temporal.pattern.parse
Temporal.pattern.format

Temporal.recurrence.from
Temporal.recurrence.parse-rrule
Temporal.recurrence.to-rrule
Temporal.recurrence.occurrences

Temporal.expression.context
Temporal.expression.resolve

Temporal.natural.parse
```

---

### Task 1: Native Civil Helper Boundary

**Files:**
- Modify: `src/temporal.h`
- Modify: `src/temporal.cpp`
- Modify: `src/lua_temporal_core.cpp`
- Modify: `tests/test_temporal_core.cpp`
- Modify: `tests/test_lua_temporal_core_binding.cpp`

**Interfaces:**
- Consumes: existing `space::temporal::PlainDateTime`.
- Produces:
  - `PlainDateTime PlainDateTime::add_days(int days) const`
  - `int PlainDateTime::iso_weekday() const`
  - Lua methods `TemporalPlainDateTime:add-days(days)` and `TemporalPlainDateTime:iso-weekday()`.

- [ ] **Step 1: Add failing native tests.**
  In `tests/test_temporal_core.cpp`, add tests equivalent to:

  ```cpp
  void test_plain_date_time_add_days()
  {
      expect_eq(PlainDateTime::parse("2028-02-28T10:11:12")
                    .add_days(1)
                    .to_string(),
                std::string("2028-02-29T10:11:12"));
      expect_eq(PlainDateTime::parse("2026-12-31T23:00:00")
                    .add_days(1)
                    .to_string(),
                std::string("2027-01-01T23:00:00"));
      expect_eq(PlainDateTime::parse("2026-01-01T00:00:00")
                    .add_days(-1)
                    .to_string(),
                std::string("2025-12-31T00:00:00"));
  }

  void test_plain_date_time_iso_weekday()
  {
      expect_eq(PlainDateTime::parse("2026-09-28T00:00:00").iso_weekday(), 1);
      expect_eq(PlainDateTime::parse("2026-10-04T00:00:00").iso_weekday(), 7);
  }
  ```

  Register both tests in `main()`.

- [ ] **Step 2: Add failing Lua binding assertions.**
  In `tests/test_lua_temporal_core_binding.cpp`, add Lua script assertions:

  ```lua
  local leap_plain = core["plain-date-time"].parse("2028-02-28T10:11:12")
  local leap_next = leap_plain["add-days"](leap_plain, 1)
  assert(leap_next["to-string"](leap_next) == "2028-02-29T10:11:12")
  assert(leap_next["iso-weekday"](leap_next) == 2)
  ```

- [ ] **Step 3: Verify the native/binding tests fail before implementation.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
  ```

  Expected before implementation: compile failure for missing `PlainDateTime::add_days` / `iso_weekday` or Lua method failure.

- [ ] **Step 4: Add native declarations.**
  In `src/temporal.h`, add to `PlainDateTime` public methods:

  ```cpp
  PlainDateTime add_days(int days) const;
  int iso_weekday() const;
  ```

- [ ] **Step 5: Implement native helpers.**
  In `src/temporal.cpp`, implement using `date::floor<date::days>(value_)`, `date::weekday`, and existing checked nanosecond/local-time construction paths. `iso_weekday()` must return Monday `1` through Sunday `7`. `add_days` must preserve the local time-of-day and throw on representable-range overflow.

- [ ] **Step 6: Bind Lua methods.**
  In `src/lua_temporal_core.cpp`, add methods to `TemporalPlainDateTime`:

  ```cpp
  "add-days", [](const PlainDateTime& self, int days) { return self.add_days(days); },
  "iso-weekday", &PlainDateTime::iso_weekday,
  ```

- [ ] **Step 7: Validate focused native surface.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
  ```

  Expected: both tests pass.

- [ ] **Step 8: Commit this task after review approval.**
  Commit message:

  ```bash
  git commit -m "feat(temporal): add civil date helpers"
  ```

---

### Task 2: Standard Parse/Format Facade and Test Harness

**Files:**
- Create: `assets/lua/temporal/standard.fnl`
- Modify: `assets/lua/temporal.fnl`
- Create: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: existing `Temporal.instant`, `Temporal.plain-date-time`, `Temporal.zoned-date-time`.
- Produces:
  - `Temporal.standard.parse-instant(text)`
  - `Temporal.standard.format-instant(instant)`
  - `Temporal.standard.parse-plain-date-time(text)`
  - `Temporal.standard.format-plain-date-time(plain)`
  - `Temporal.standard.parse-zoned-date-time(text)`
  - `Temporal.standard.format-zoned-date-time(zdt)`

- [ ] **Step 1: Add focused test harness.**
  Create `assets/lua/tests/test-temporal-parsing-recurrence.fnl` with:

  ```fennel
  (local tests [])
  (local Temporal (require :temporal))

  (fn assert-error [f message]
    (local (ok err) (pcall f))
    (assert (not ok) message)
    err)

  (fn standard-instant-round-trip []
    (local instant (Temporal.standard.parse-instant "2026-09-25T08:34:56-04:00"))
    (assert (= (Temporal.standard.format-instant instant) "2026-09-25T12:34:56Z"))
    (assert-error #(Temporal.standard.parse-instant "2026-09-25T12:34:56")
                  "standard instant requires explicit offset"))

  (fn standard-plain-round-trip []
    (local plain (Temporal.standard.parse-plain-date-time "2026-09-25T12:34:56"))
    (assert (= (Temporal.standard.format-plain-date-time plain)
               "2026-09-25T12:34:56")))

  (fn standard-zoned-round-trip []
    (local zdt (Temporal.standard.parse-zoned-date-time
                 "2026-11-01T01:30:00-04:00[America/New_York]"))
    (assert (= ((zdt:instant):to-string) "2026-11-01T05:30:00Z"))
    (assert (= (Temporal.standard.format-zoned-date-time zdt)
               "2026-11-01T01:30:00-04:00[America/New_York]"))
    (assert-error #(Temporal.standard.parse-zoned-date-time
                     "2026-11-01T01:30:00-03:00[America/New_York]")
                  "mismatched offset should throw"))

  (table.insert tests {:name "standard instant round trip" :fn standard-instant-round-trip})
  (table.insert tests {:name "standard plain round trip" :fn standard-plain-round-trip})
  (table.insert tests {:name "standard zoned round trip" :fn standard-zoned-round-trip})

  (local main
    (fn []
      (local runner (require :tests/runner))
      (runner.run-tests {:name "temporal-parsing-recurrence"
                         :tests tests})))

  {:name "temporal-parsing-recurrence"
   :tests tests
   :main main}
  ```

- [ ] **Step 2: Verify the test fails before implementation.**
  Run:

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected before implementation: compile check passes for the new test file, then the focused test fails because `Temporal.standard` is missing.

- [ ] **Step 3: Implement `assets/lua/temporal/standard.fnl`.**
  Required implementation details:
  - `parse-instant` delegates to `Temporal.instant.parse`.
  - `format-instant` calls `(instant:to-string)`.
  - `parse-plain-date-time` delegates to `Temporal.plain-date-time.parse`.
  - `format-plain-date-time` calls `(plain:to-string)`.
  - `parse-zoned-date-time` accepts only `local + numeric offset + [zone]` in the strict shape from the spec.
  - Build an instant by parsing `local-with-offset` through `Temporal.instant.parse`.
  - Build zoned value with `Temporal.zoned-date-time.from-instant`.
  - Verify `(zdt:offset-string)` equals the input offset and `(zdt:to-string)` projects the same local fields; throw `"temporal zoned offset does not match zone"` otherwise.
  - `format-zoned-date-time` delegates to `(zdt:to-string)`.

- [ ] **Step 4: Export the namespace.**
  In `assets/lua/temporal.fnl`, require `:temporal/standard` after building the base table or pass the base table into the module. The public return table must include `:standard standard` without changing existing namespaces.

- [ ] **Step 5: Register focused test in fast suite.**
  Add `:tests.test-temporal-parsing-recurrence` to `assets/lua/tests/fast.fnl` near `:tests.test-temporal`.

- [ ] **Step 6: Validate Fennel surface.**
  Run:

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/standard.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: compile check, constraints, and focused test pass.

- [ ] **Step 7: Commit this task after review approval.**
  Commit message:

  ```bash
  git commit -m "feat(temporal): add standard parse format facade"
  ```

---

### Task 3: Explicit Pattern API Shape

**Files:**
- Create: `assets/lua/temporal/pattern.fnl`
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes: `Temporal.plain-date-time.from-fields`, `plain:fields()`.
- Produces:
  - `Temporal.pattern.compile(pattern-text)`
  - `Temporal.pattern.parse(compiled, text, {:type :plain-date-time})`
  - `Temporal.pattern.format(compiled, value)`

- [ ] **Step 1: Add failing pattern tests.**
  Append tests:

  ```fennel
  (fn pattern-plain-date-time-round-trip []
    (local pattern (Temporal.pattern.compile "yyyy/MM/dd HH:mm:ss"))
    (local plain (Temporal.pattern.parse pattern "2026/09/25 12:34:56"
                                         {:type :plain-date-time}))
    (assert (= (plain:to-string) "2026-09-25T12:34:56"))
    (assert (= (Temporal.pattern.format pattern plain) "2026/09/25 12:34:56")))

  (fn pattern-literals-and-rejections []
    (local pattern (Temporal.pattern.compile "yyyy-MM-dd'T'HH:mm:ss"))
    (local plain (Temporal.pattern.parse pattern "2026-09-25T12:34:56"
                                         {:type :plain-date-time}))
    (assert (= (plain:to-string) "2026-09-25T12:34:56"))
    (assert-error #(Temporal.pattern.compile "yyyy MMM dd")
                  "unsupported pattern token should throw")
    (assert-error #(Temporal.pattern.parse pattern "2026-09-25X12:34:56"
                                          {:type :plain-date-time})
                  "literal mismatch should throw"))

  (table.insert tests {:name "pattern plain date time round trip" :fn pattern-plain-date-time-round-trip})
  (table.insert tests {:name "pattern literals and rejections" :fn pattern-literals-and-rejections})
  ```

- [ ] **Step 2: Implement pattern compiler.**
  Create `assets/lua/temporal/pattern.fnl` with a deterministic scanner that emits parts:
  - `{:kind :field :token :yyyy :width 4}`
  - `{:kind :literal :text "/"}`
  - Supported tokens: `yyyy`, `MM`, `dd`, `HH`, `mm`, `ss`.
  - Single-quoted text is literal; malformed quote throws `"invalid temporal pattern quote"`.
  - Any alphabetic run outside the supported tokens throws `"unsupported temporal pattern token: <token>"`.

- [ ] **Step 3: Implement pattern parse.**
  `parse(compiled, text, opts)` must require `opts.type == :plain-date-time`, match literals exactly, parse fixed-width digits for fields, reject trailing characters, and call `Temporal.plain-date-time.from-fields`.

- [ ] **Step 4: Implement pattern format.**
  `format(compiled, value)` must use `(value:fields)` and zero-pad fields to token width.

- [ ] **Step 5: Export pattern namespace.**
  Update `assets/lua/temporal.fnl` to return `:pattern pattern`.

- [ ] **Step 6: Validate touched Fennel files.**
  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/pattern.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: compile check, constraints, and focused tests pass.

- [ ] **Step 7: Commit this task after review approval.**
  Commit message:

  ```bash
  git commit -m "feat(temporal): add explicit pattern parsing"
  ```

---

### Task 4: Recurrence Model, RRULE Parser, and Occurrence Expansion

**Files:**
- Create: `assets/lua/temporal/recurrence.fnl`
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes: `plain:add-days(days)`, `plain:iso-weekday()`.
- Produces:
  - `Temporal.recurrence.from(options)`
  - `Temporal.recurrence.parse-rrule(text)`
  - `Temporal.recurrence.to-rrule(rule)`
  - `Temporal.recurrence.occurrences(rule, dtstart, options)`

- [ ] **Step 1: Add failing recurrence tests.**
  Append tests:

  ```fennel
  (fn recurrence-rrule-round-trip []
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=TU"))
    (assert (= rule.freq :weekly))
    (assert (= rule.count 3))
    (assert (= (. rule.by-day 1) :tu))
    (assert (= (Temporal.recurrence.to-rrule rule)
               "RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=TU"))
    (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;FREQ=DAILY")
                  "duplicate RRULE key should throw")
    (assert-error #(Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;BYHOUR=9")
                  "unknown RRULE key should throw"))

  (fn recurrence-weekly-occurrences []
    (local dtstart (Temporal.plain-date-time.parse "2026-09-22T09:00:00"))
    (local rule (Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=TU"))
    (local occ (Temporal.recurrence.occurrences rule dtstart {}))
    (assert (= (# occ) 3))
    (assert (= ((. occ 1):to-string) "2026-09-22T09:00:00"))
    (assert (= ((. occ 2):to-string) "2026-09-29T09:00:00"))
    (assert (= ((. occ 3):to-string) "2026-10-06T09:00:00")))

  (table.insert tests {:name "recurrence RRULE round trip" :fn recurrence-rrule-round-trip})
  (table.insert tests {:name "recurrence weekly occurrences" :fn recurrence-weekly-occurrences})
  ```

- [ ] **Step 2: Implement normalized rule creation.**
  `from(options)` must accept canonical keys `:freq`, `:interval`, `:count`, `:until`, `:by-day`. Default `:interval` to `1`. Reject unknown keys. Valid `:freq` values: `:daily`, `:weekly`, `:monthly`, `:yearly`. Valid `:by-day` values: `:mo`, `:tu`, `:we`, `:th`, `:fr`, `:sa`, `:su`.

- [ ] **Step 3: Implement strict RRULE parser.**
  `parse-rrule(text)` must require prefix `RRULE:`, split semicolon pairs, reject duplicates/unknown keys/empty values, map `FREQ=DAILY|WEEKLY|MONTHLY|YEARLY`, parse positive integer `INTERVAL`/`COUNT`, parse comma-separated `BYDAY`, and preserve `UNTIL` as raw text for this slice.

- [ ] **Step 4: Implement deterministic RRULE serialization.**
  `to-rrule(rule)` must output keys in this order when present: `FREQ`, `INTERVAL` when not `1`, `COUNT`, `UNTIL`, `BYDAY`.

- [ ] **Step 5: Implement bounded occurrences.**
  `occurrences(rule, dtstart, options)` must require `rule.count` or `options.limit`, cap generated values at that count/limit, support `:daily` and `:weekly`, and throw `"unsupported temporal recurrence expansion"` for `:monthly` and `:yearly`.

- [ ] **Step 6: Export recurrence namespace.**
  Update `assets/lua/temporal.fnl` to return `:recurrence recurrence`.

- [ ] **Step 7: Validate touched Fennel files.**
  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: compile check, constraints, and focused tests pass.

- [ ] **Step 8: Commit this task after review approval.**
  Commit message:

  ```bash
  git commit -m "feat(temporal): add recurrence RRULE foundation"
  ```

---

### Task 5: Structured Expressions and Small Natural Grammar

**Files:**
- Create: `assets/lua/temporal/expression.fnl`
- Create: `assets/lua/temporal/natural.fnl`
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`

**Interfaces:**
- Consumes: `Temporal.recurrence`, `plain:add-days(days)`, `plain:iso-weekday()`.
- Produces:
  - `Temporal.expression.context(options)`
  - `Temporal.expression.resolve(expression, context)`
  - `Temporal.natural.parse(text)`

- [ ] **Step 1: Add failing expression/natural tests.**
  Append tests:

  ```fennel
  (fn natural-relative-resolution []
    (local reference (Temporal.plain-date-time.parse "2026-09-25T15:30:00"))
    (local ctx (Temporal.expression.context {:reference-plain-date-time reference
                                             :zone-id "America/New_York"}))
    (local today-result (Temporal.expression.resolve (Temporal.natural.parse "today") ctx))
    (local tomorrow-result (Temporal.expression.resolve (Temporal.natural.parse "tomorrow") ctx))
    (local in-two-weeks-result (Temporal.expression.resolve (Temporal.natural.parse "in 2 weeks") ctx))
    (assert (= (today-result.value:to-string) "2026-09-25T00:00:00"))
    (assert (= (tomorrow-result.value:to-string) "2026-09-26T00:00:00"))
    (assert (= (in-two-weeks-result.value:to-string) "2026-10-09T00:00:00")))

  (fn natural-next-weekday-and-recurrence []
    (local reference (Temporal.plain-date-time.parse "2026-09-25T15:30:00"))
    (local ctx (Temporal.expression.context {:reference-plain-date-time reference
                                             :zone-id "America/New_York"}))
    (local next-tu (Temporal.expression.resolve (Temporal.natural.parse "next Tuesday") ctx))
    (assert (= (next-tu.value:to-string) "2026-09-29T00:00:00"))
    (local recurring (Temporal.natural.parse "every Tuesday"))
    (assert (= recurring.kind :recurrence))
    (assert (= recurring.rule.freq :weekly))
    (assert (= (. recurring.rule.by-day 1) :tu))
    (assert-error #(Temporal.natural.parse "around lunch sometime")
                  "unsupported natural expression should throw"))

  (table.insert tests {:name "natural relative resolution" :fn natural-relative-resolution})
  (table.insert tests {:name "natural next weekday and recurrence" :fn natural-next-weekday-and-recurrence})
  ```

- [ ] **Step 2: Implement expression records/resolution.**
  `expression.context(options)` must require `:zone-id` and either `:reference-plain-date-time` or `:reference-instant`. For this slice, resolution requires `:reference-plain-date-time`; if only `:reference-instant` is passed, throw `"reference instant resolution requires projection support"` as explicit first-slice unsupported behavior. Default time is midnight.

  `resolve(expr, ctx)` must return:
  - `{:kind :plain-date-time :value plain}` for `:relative-date` and `:next-weekday`.
  - `{:kind :recurrence :rule rule}` for `:recurrence`.

- [ ] **Step 3: Implement natural parser.**
  `natural.parse(text)` must trim and lowercase text, support exactly:
  - `today` -> `{:kind :relative-date :amount 0 :unit :day}`
  - `tomorrow` -> `{:kind :relative-date :amount 1 :unit :day}`
  - `in N days` / `in N day`
  - `in N weeks` / `in N week`
  - `next Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday`
  - `every Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday` -> recurrence expression

  Unsupported text throws `"unsupported temporal natural expression"`.

- [ ] **Step 4: Export expression and natural namespaces.**
  Update `assets/lua/temporal.fnl` to return `:expression expression` and `:natural natural`.

- [ ] **Step 5: Validate touched Fennel files.**
  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/expression.fnl --file assets/lua/temporal/natural.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: compile check, constraints, and focused tests pass.

- [ ] **Step 6: Commit this task after review approval.**
  Commit message:

  ```bash
  git commit -m "feat(temporal): add structured natural expressions"
  ```

---

### Task 6: Developer Documentation and Final Validation

**Files:**
- Modify: `docs/dev/features/temporal.md`
- Create: `docs/dev/features/temporal-parsing-recurrence.md`
- Modify: `docs/dev/features/index.md`

**Interfaces:**
- Consumes: all public APIs from Tasks 1-5.
- Produces: documented feature boundaries, examples, validation commands, and deferred continuation map.

- [ ] **Step 1: Update the core temporal page.**
  In `docs/dev/features/temporal.md`, add a short section after `Future layers`:

  ```markdown
  ## Parsing, formatting, and recurrence layers

  Higher-level parsing, pattern formatting, natural expressions, and recurrence live above the core. See [Temporal Parsing and Recurrence](./temporal-parsing-recurrence). The core remains independent from natural language, recurrence, ICU, CLDR, and localization dependencies.
  ```

- [ ] **Step 2: Create the parsing/recurrence feature page.**
  Create `docs/dev/features/temporal-parsing-recurrence.md` with these sections:
  - `# Temporal Parsing and Recurrence`
  - `## Layering model`
  - `## Standard parse and format`
  - `## Explicit patterns`
  - `## Recurrence and RRULE`
  - `## Structured expressions`
  - `## Natural grammar subset`
  - `## Deferred continuation map`
  - `## Validation`

  The deferred continuation map must explicitly cover ICU/CLDR localization, broad natural language, full RFC5545, ISO intervals/repeating intervals, calendar periods, non-Gregorian calendars, and parser providers/plugins.

- [ ] **Step 3: Link the feature page from the index.**
  Add to `docs/dev/features/index.md` near the Temporal Core entry:

  ```markdown
  - [Temporal Parsing and Recurrence](./temporal-parsing-recurrence)
  ```

- [ ] **Step 4: Validate documentation terms.**
  Run:

  ```bash
  rg "Temporal Parsing and Recurrence|temporal.standard|temporal.pattern|temporal.recurrence|temporal.expression|temporal.natural|ICU|CLDR|RFC5545|non-Gregorian|parser providers" docs/dev/features/temporal.md docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/index.md
  ```

  Expected: all terms are present.

- [ ] **Step 5: Run focused native validation.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
  ```

  Expected: build and both CTests pass.

- [ ] **Step 6: Run focused Fennel validation in required order.**
  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/standard.fnl --file assets/lua/temporal/pattern.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/temporal/expression.fnl --file assets/lua/temporal/natural.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: compile check, constraints, and focused Fennel tests pass. Constraint impact note: not applicable unless constraints are changed.

- [ ] **Step 7: Run broader final local suite.**
  This work touches C++, Lua bindings, public Fennel APIs, fast-suite registration, and docs. Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: full suite passes.

- [ ] **Step 8: Commit this task after review approval.**
  Commit message:

  ```bash
  git commit -m "docs(temporal): document parsing recurrence layers"
  ```

---

## Final Acceptance

- `require :temporal` exposes the five new namespaces without breaking existing namespaces.
- Core remains independent from natural language, recurrence, localization, ICU, and CLDR.
- Standard facade, pattern API, recurrence/RRULE, expression resolution, and small natural grammar have focused tests.
- Deferred work is documented in enough detail for follow-up specs and plans.
- Required local validation passes, and PR CI remains the full integration gate.
