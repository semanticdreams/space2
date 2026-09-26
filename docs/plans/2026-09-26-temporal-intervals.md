# Temporal Intervals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add production-ready half-open temporal intervals and bounded repeating intervals above the existing temporal foundation.

**Architecture:** Use a hybrid design: native C++ adds only dependency-free comparison and exact plain-date-time duration primitives, while Fennel modules own interval records, strict start/end parsing, repeating interval syntax, and expansion policy. This preserves the clean temporal core boundary and keeps ISO grammar/product decisions in the higher layer.

**Tech Stack:** C++17 temporal core, Howard Hinnant `date/tz`, sol2 Lua bindings, Space Fennel modules/tests, CMake/CTest, Space-native Fennel check/constraints/test tooling.

## Global Constraints

- Add explicit half-open temporal interval records above the temporal core.
- Add bounded repeating interval records and ISO-style repeat parsing for start/end intervals.
- Keep native core changes small, dependency-free, and semantic: comparisons and exact plain-date-time duration arithmetic only.
- Keep interval parsing, formatting, validation policy, and repeating syntax in Fennel layers beside the existing temporal facade modules.
- Support intervals over `Instant` and `PlainDateTime` endpoints in the first slice.
- Make all invalid or unsupported forms fail loudly.
- Preserve existing `duration`, `instant`, `plain-date-time`, `zoned-date-time`, `standard`, `pattern`, `recurrence`, `expression`, and `natural` APIs.
- Do not add native C++ `Interval` or `RepeatingInterval` userdata.
- Do not implement the full ISO 8601 interval grammar.
- Do not support duration/start or duration/end interval forms.
- Do not support zoned-date-time intervals or DST-aware interval expansion.
- Do not add calendar periods containing years, months, business days, or locale calendars.
- Do not add interval set algebra, overlap merging, gap queries, or scheduler UX.
- Do not add broad natural-language interval parsing.
- Do not add ICU, CLDR, localization data, or new third-party runtime dependencies.
- All intervals are half-open: `[start, end)`.
- Start and end endpoints must have the same type. Mixed endpoints throw.
- `Temporal.interval.duration(interval)` returns an exact `Duration`.
- `Temporal.interval.shift(interval, duration)` shifts both endpoints by an exact duration and returns another half-open interval of the same endpoint type.
- `R<count>` means the total number of interval occurrences returned.
- `R/` means an unbounded repeating interval record. Expansion requires a canonical `{:limit n}` option.
- If both a record count and expansion limit are present, expansion returns the smaller number.
- Count and limit must be positive integers. `R0`, negative counts, unknown options, missing bounds, and malformed repeat prefixes throw.
- No API may silently default to host-local timezone behavior.
- Direct Fennel test runs must use the project-native runtime with `SPACE_ASSETS_PATH`, `FENNEL_PATH`, and `FENNEL_MACRO_PATH` set as documented in `AGENTS.md`; system `fennel` or system `lua` are not validation oracles.

---

## File Structure

- `src/temporal.h` / `src/temporal.cpp` — add comparison and exact plain-date-time duration primitives.
- `src/lua_temporal_core.cpp` — expose native primitives to Lua userdata.
- `tests/test_temporal_core.cpp` — native primitive coverage.
- `tests/test_lua_temporal_core_binding.cpp` — Lua binding coverage for primitives.
- `assets/lua/temporal/interval.fnl` — half-open interval records, parse/format, duration, contains, shift.
- `assets/lua/temporal/repeating-interval.fnl` — repeating interval records, parse/format, bounded occurrence expansion.
- `assets/lua/temporal.fnl` — export `interval` and `repeating-interval` namespaces.
- `assets/lua/tests/test-temporal-intervals.fnl` — focused public Fennel tests.
- `assets/lua/tests/fast.fnl` — register focused interval tests.
- `docs/dev/features/temporal-intervals.md` — developer guide for interval APIs and deferred scope.
- `docs/dev/features/index.md` — feature guide link.
- `docs/dev/features/temporal.md` — core temporal page link.
- `docs/dev/features/temporal-parsing-recurrence.md` — update deferred continuation map to point at bounded interval slice.

## Public API Additions

Existing temporal public namespaces keep their current names and behavior.

New native-bound methods:

```fennel
(duration:compare other-duration) ; => -1, 0, or 1
(instant:compare other-instant) ; => -1, 0, or 1
(plain:compare other-plain) ; => -1, 0, or 1
(plain:add duration) ; => shifted plain date-time
(plain:since earlier-plain) ; => exact local Duration
```

New Fennel namespaces:

```fennel
Temporal.interval.from
Temporal.interval.parse
Temporal.interval.format
Temporal.interval.duration
Temporal.interval.contains
Temporal.interval.shift

Temporal.repeating-interval.from
Temporal.repeating-interval.parse
Temporal.repeating-interval.format
Temporal.repeating-interval.occurrences
```

Interval record shape:

```fennel
{:kind :interval
 :type :instant|:plain-date-time
 :start value
 :end value
 :bounds :half-open}
```

Repeating interval record shape:

```fennel
{:kind :repeating-interval
 :interval interval
 :count positive-integer-or-nil}
```

---

### Task 1: Native Comparison and Plain Duration Primitives

**Files:**
- Modify: `src/temporal.h`
- Modify: `src/temporal.cpp`
- Modify: `src/lua_temporal_core.cpp`
- Modify: `tests/test_temporal_core.cpp`
- Modify: `tests/test_lua_temporal_core_binding.cpp`

**Interfaces:**
- Consumes: existing `space::temporal::Duration`, `Instant`, and `PlainDateTime`.
- Produces:
  - `int Duration::compare(const Duration& other) const`
  - `int Instant::compare(const Instant& other) const`
  - `int PlainDateTime::compare(const PlainDateTime& other) const`
  - `PlainDateTime PlainDateTime::add(const Duration& duration) const`
  - `Duration PlainDateTime::since(const PlainDateTime& earlier) const`
  - Lua methods `duration:compare`, `instant:compare`, `plain:compare`, `plain:add`, `plain:since`.

- [ ] **Step 1: Add failing native tests.**
  In `tests/test_temporal_core.cpp`, add tests equivalent to:

  ```cpp
  void test_temporal_value_comparison()
  {
      const auto one = Duration::from_seconds(1);
      const auto two = Duration::from_seconds(2);
      expect_eq(one.compare(two), -1);
      expect_eq(two.compare(one), 1);
      expect_eq(one.compare(Duration::from_seconds(1)), 0);

      const auto first = Instant::parse("2026-09-25T12:00:00Z");
      const auto second = Instant::parse("2026-09-25T12:00:01Z");
      expect_eq(first.compare(second), -1);
      expect_eq(second.compare(first), 1);
      expect_eq(first.compare(Instant::parse("2026-09-25T12:00:00Z")), 0);

      const auto plain = PlainDateTime::parse("2026-09-25T12:00:00");
      const auto later = PlainDateTime::parse("2026-09-25T12:00:01");
      expect_eq(plain.compare(later), -1);
      expect_eq(later.compare(plain), 1);
      expect_eq(plain.compare(PlainDateTime::parse("2026-09-25T12:00:00")), 0);
  }

  void test_plain_date_time_exact_duration_math()
  {
      const auto start = PlainDateTime::parse("2026-09-25T12:00:00");
      const auto shifted = start.add(Duration::from_seconds(90));
      expect_eq(shifted.to_string(), std::string("2026-09-25T12:01:30"));
      expect_eq(shifted.since(start).to_string(), std::string("PT1M30S"));
      expect_eq(start.since(shifted).to_string(), std::string("-PT1M30S"));
  }
  ```

  Register both tests in `main()`.

- [ ] **Step 2: Add failing Lua binding assertions.**
  In `tests/test_lua_temporal_core_binding.cpp`, add Lua assertions equivalent to:

  ```lua
  local one = core.duration["from-seconds"](1)
  local two = core.duration["from-seconds"](2)
  assert(one.compare(one, two) == -1)
  assert(two.compare(two, one) == 1)
  assert(one.compare(one, core.duration["from-seconds"](1)) == 0)

  local instant_a = core.instant.parse("2026-09-25T12:00:00Z")
  local instant_b = core.instant.parse("2026-09-25T12:00:01Z")
  assert(instant_a.compare(instant_a, instant_b) == -1)
  assert(instant_b.compare(instant_b, instant_a) == 1)

  local plain = core["plain-date-time"].parse("2026-09-25T12:00:00")
  local shifted = plain.add(plain, core.duration["from-seconds"](90))
  assert(shifted["to-string"](shifted) == "2026-09-25T12:01:30")
  local elapsed = shifted.since(shifted, plain)
  assert(elapsed["to-string"](elapsed) == "PT1M30S")
  assert(plain.compare(plain, shifted) == -1)
  ```

- [ ] **Step 3: Verify tests fail before implementation.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
  ```

  Expected before implementation: compile or Lua method failure for missing comparison/add/since APIs.

- [ ] **Step 4: Add native declarations.**
  In `src/temporal.h`, add public methods to the matching classes:

  ```cpp
  int compare(const Duration& other) const;
  int compare(const Instant& other) const;
  int compare(const PlainDateTime& other) const;
  PlainDateTime add(const Duration& duration) const;
  Duration since(const PlainDateTime& earlier) const;
  ```

- [ ] **Step 5: Implement native methods.**
  In `src/temporal.cpp`, implement comparisons with a shared `-1/0/1` pattern. Implement `PlainDateTime::add` and `PlainDateTime::since` using existing nanosecond range helpers so overflow throws with an explicit temporal range error rather than wrapping.

- [ ] **Step 6: Bind Lua methods.**
  In `src/lua_temporal_core.cpp`, expose:

  ```cpp
  "compare", &Duration::compare
  "compare", &Instant::compare
  "compare", &PlainDateTime::compare
  "add", [](const PlainDateTime& self, const Duration& duration) { return self.add(duration); }
  "since", [](const PlainDateTime& self, const PlainDateTime& earlier) { return self.since(earlier); }
  ```

- [ ] **Step 7: Validate focused native/binding surface.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
  ```

  Expected: build and both CTests pass.

- [ ] **Step 8: Commit this task after review approval.**
  Commit message:

  ```bash
  git commit -m "feat(temporal): add interval primitive helpers"
  ```

---

### Task 2: Half-Open Interval Facade

**Files:**
- Create: `assets/lua/temporal/interval.fnl`
- Modify: `assets/lua/temporal.fnl`
- Create: `assets/lua/tests/test-temporal-intervals.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `Temporal.standard`, native methods from Task 1.
- Produces:
  - `Temporal.interval.from(options)`
  - `Temporal.interval.parse(text, options)`
  - `Temporal.interval.format(interval)`
  - `Temporal.interval.duration(interval)`
  - `Temporal.interval.contains(interval, value)`
  - `Temporal.interval.shift(interval, duration)`

- [ ] **Step 1: Add focused interval test module.**
  Create `assets/lua/tests/test-temporal-intervals.fnl` with this harness and initial tests:

  ```fennel
  (local tests [])
  (local Temporal (require :temporal))

  (fn assert-error [f message]
    (local (ok err) (pcall f))
    (assert (not ok) message)
    err)

  (fn instant-interval-basic-behavior []
    (local start (Temporal.standard.parse-instant "2026-09-25T12:00:00Z"))
    (local end (Temporal.standard.parse-instant "2026-09-25T13:00:00Z"))
    (local interval (Temporal.interval.from {:type :instant :start start :end end}))
    (assert (= interval.kind :interval))
    (assert (= interval.type :instant))
    (assert (= interval.bounds :half-open))
    (assert (Temporal.interval.contains interval start))
    (assert (not (Temporal.interval.contains interval end)))
    (local elapsed (Temporal.interval.duration interval))
    (assert (= (elapsed:to-string) "PT1H"))
    (assert (= (Temporal.interval.format interval)
               "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z")))

  (fn plain-interval-parse-shift []
    (local interval (Temporal.interval.parse "2026-09-25T12:00:00/2026-09-25T13:00:00"
                                             {:type :plain-date-time}))
    (local shifted (Temporal.interval.shift interval (Temporal.duration.from {:seconds 7200})))
    (local elapsed (Temporal.interval.duration interval))
    (assert (= (Temporal.interval.format shifted)
               "2026-09-25T14:00:00/2026-09-25T15:00:00"))
    (assert (= (elapsed:to-string) "PT1H")))

  (fn invalid-intervals-throw []
    (local start (Temporal.standard.parse-instant "2026-09-25T12:00:00Z"))
    (assert-error #(Temporal.interval.from {:type :instant :start start :end start})
                  "zero-length interval should throw")
    (assert-error #(Temporal.interval.from {:type :instant :start start})
                  "missing end should throw")
    (assert-error #(Temporal.interval.parse "2026-09-25T12:00:00Z/PT1H" {:type :instant})
                  "start/duration form should throw")
    (assert-error #(Temporal.interval.parse "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z" {:kind :instant})
                  "unknown option key should throw"))

  (table.insert tests {:name "instant interval basic behavior" :fn instant-interval-basic-behavior})
  (table.insert tests {:name "plain interval parse shift" :fn plain-interval-parse-shift})
  (table.insert tests {:name "invalid intervals throw" :fn invalid-intervals-throw})

  (local main
    (fn []
      (local runner (require :tests/runner))
      (runner.run-tests {:name "temporal-intervals" :tests tests})))

  {:name "temporal-intervals" :tests tests :main main}
  ```

- [ ] **Step 2: Verify the focused test fails before implementation.**
  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-temporal-intervals.fnl
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-intervals:main
  ```

  Expected before implementation: compile check passes for the new test file, then focused test fails because `Temporal.interval` is missing.

- [ ] **Step 3: Implement interval module.**
  Create `assets/lua/temporal/interval.fnl` as a factory receiving the base `Temporal` table. Requirements:
  - Validate option keys are exactly `:type`, `:start`, and `:end` for `from`.
  - Accept only `:instant` and `:plain-date-time` endpoint types.
  - Use endpoint `:compare` methods to enforce `start < end`.
  - Return `{:kind :interval :type type :start start :end end :bounds :half-open}`.
  - `parse` accepts one `/` separator and `opts.type` only; it rejects `/P`, `P.../`, repeating prefixes, missing endpoint text, and unknown option keys.
  - `format` uses `Temporal.standard.format-instant` or `format-plain-date-time`.
  - `contains` returns true for `start <= value < end` and throws if value lacks compatible comparison.
  - `duration` calls `end:since start` for both endpoint types.
  - `shift` calls endpoint `:add duration` for both endpoints and returns a validated interval.

- [ ] **Step 4: Export interval namespace.**
  Update `assets/lua/temporal.fnl` to require `:temporal/interval` and return `:interval (create-interval base)` without changing existing namespaces.

- [ ] **Step 5: Register focused test in fast suite.**
  Add `:tests.test-temporal-intervals` to `assets/lua/tests/fast.fnl` near other temporal tests.

- [ ] **Step 6: Validate Fennel surface.**
  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/interval.fnl --file assets/lua/tests/test-temporal-intervals.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-intervals:main
  ```

  Expected: compile check, constraints, and focused tests pass.

- [ ] **Step 7: Commit this task after review approval.**
  Commit message:

  ```bash
  git commit -m "feat(temporal): add interval facade"
  ```

---

### Task 3: Repeating Interval Facade

**Files:**
- Create: `assets/lua/temporal/repeating-interval.fnl`
- Modify: `assets/lua/temporal.fnl`
- Modify: `assets/lua/tests/test-temporal-intervals.fnl`

**Interfaces:**
- Consumes: `Temporal.interval` from Task 2.
- Produces:
  - `Temporal.repeating-interval.from(options)`
  - `Temporal.repeating-interval.parse(text, options)`
  - `Temporal.repeating-interval.format(repeating)`
  - `Temporal.repeating-interval.occurrences(repeating, options)`

- [ ] **Step 1: Add repeating interval tests.**
  Append tests to `assets/lua/tests/test-temporal-intervals.fnl`:

  ```fennel
  (fn repeating-interval-counted-occurrences []
    (local repeating (Temporal.repeating-interval.parse
                       "R3/2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
                       {:type :instant}))
    (assert (= repeating.kind :repeating-interval))
    (assert (= repeating.count 3))
    (assert (= (Temporal.repeating-interval.format repeating)
               "R3/2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"))
    (local occ (Temporal.repeating-interval.occurrences repeating {}))
    (assert (= (# occ) 3))
    (assert (= (Temporal.interval.format (. occ 1))
               "2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"))
    (assert (= (Temporal.interval.format (. occ 2))
               "2026-09-25T13:00:00Z/2026-09-25T14:00:00Z"))
    (assert (= (Temporal.interval.format (. occ 3))
               "2026-09-25T14:00:00Z/2026-09-25T15:00:00Z")))

  (fn repeating-interval-unbounded-limit []
    (local repeating (Temporal.repeating-interval.parse
                       "R/2026-09-25T12:00:00/2026-09-25T13:00:00"
                       {:type :plain-date-time}))
    (assert (= repeating.count nil))
    (assert-error #(Temporal.repeating-interval.occurrences repeating {})
                  "unbounded repeating interval requires limit")
    (local occ (Temporal.repeating-interval.occurrences repeating {:limit 2}))
    (assert (= (# occ) 2))
    (assert (= (Temporal.interval.format (. occ 2))
               "2026-09-25T13:00:00/2026-09-25T14:00:00")))

  (fn repeating-interval-rejections []
    (assert-error #(Temporal.repeating-interval.parse
                     "R0/2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
                     {:type :instant})
                  "R0 should throw")
    (assert-error #(Temporal.repeating-interval.parse
                     "RX/2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
                     {:type :instant})
                  "malformed repeat prefix should throw")
    (local repeating (Temporal.repeating-interval.parse
                       "R3/2026-09-25T12:00:00Z/2026-09-25T13:00:00Z"
                       {:type :instant}))
    (assert-error #(Temporal.repeating-interval.occurrences repeating {:limt 2})
                  "unknown occurrence option should throw")
    (assert (= (# (Temporal.repeating-interval.occurrences repeating {:limit 2})) 2)))

  (table.insert tests {:name "repeating interval counted occurrences" :fn repeating-interval-counted-occurrences})
  (table.insert tests {:name "repeating interval unbounded limit" :fn repeating-interval-unbounded-limit})
  (table.insert tests {:name "repeating interval rejections" :fn repeating-interval-rejections})
  ```

- [ ] **Step 2: Implement repeating interval module.**
  Create `assets/lua/temporal/repeating-interval.fnl` as a factory receiving base `Temporal`. Requirements:
  - `from` accepts exactly `:interval` and optional `:count`.
  - `count`, when present, must be a positive integer.
  - `parse` requires text beginning with `R`, supports `R<count>/start/end` and `R/start/end`, and delegates the remainder to `Temporal.interval.parse`.
  - `format` emits `R<count>/` or `R/` plus `Temporal.interval.format`.
  - `occurrences` accepts only optional `:limit`; limit must be a positive integer.
  - Expansion count is `count`, `limit`, or the smaller of both. If neither exists, throw `"temporal repeating interval expansion requires limit"`.
  - Each occurrence is produced by repeatedly shifting the previous interval by the base interval's exact duration; do not invent duration multiplication unless a native helper exists.

- [ ] **Step 3: Export repeating interval namespace.**
  Update `assets/lua/temporal.fnl` to require `:temporal/repeating-interval` and return `:repeating-interval (create-repeating-interval base)`.

- [ ] **Step 4: Validate focused Fennel surface.**
  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/interval.fnl --file assets/lua/temporal/repeating-interval.fnl --file assets/lua/tests/test-temporal-intervals.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-intervals:main
  ```

  Expected: compile check, constraints, and focused tests pass.

- [ ] **Step 5: Commit this task after review approval.**
  Commit message:

  ```bash
  git commit -m "feat(temporal): add repeating intervals"
  ```

---

### Task 4: Developer Documentation

**Files:**
- Create: `docs/dev/features/temporal-intervals.md`
- Modify: `docs/dev/features/index.md`
- Modify: `docs/dev/features/temporal.md`
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`

**Interfaces:**
- Consumes: public APIs from Tasks 2 and 3.
- Produces: canonical developer docs for intervals and repeating intervals.

- [ ] **Step 1: Create interval developer guide.**
  Create `docs/dev/features/temporal-intervals.md` with sections:
  - `# Temporal Intervals`
  - `## Layering model`
  - `## Half-open interval semantics`
  - `## Temporal.interval`
  - `## Temporal.repeating-interval`
  - `## Unsupported forms and deferred scope`
  - `## Validation`

  Include examples for `Temporal.interval.parse`, `Temporal.interval.contains`, `Temporal.interval.shift`, `Temporal.repeating-interval.parse`, and `Temporal.repeating-interval.occurrences`.

- [ ] **Step 2: Document deferred scope explicitly.**
  The deferred section must name native interval userdata, full ISO interval grammar, duration/start forms, duration/end forms, zoned intervals, DST-aware interval expansion, calendar periods, localization, broad natural-language intervals, and interval algebra.

- [ ] **Step 3: Link docs from feature index.**
  Add to `docs/dev/features/index.md` near temporal entries:

  ```markdown
  - [Temporal Intervals](./temporal-intervals)
  ```

- [ ] **Step 4: Link from core temporal docs.**
  In `docs/dev/features/temporal.md`, add one short paragraph linking to `./temporal-intervals` and stating that interval parsing remains above the core.

- [ ] **Step 5: Update parsing/recurrence deferred map.**
  In `docs/dev/features/temporal-parsing-recurrence.md`, replace the broad `ISO intervals/repeating intervals` deferred bullet with a statement that bounded start/end intervals and repeating intervals are covered by `Temporal Intervals`, while full ISO forms and calendar periods remain deferred.

- [ ] **Step 6: Validate documentation terms.**
  Run:

  ```bash
  rg "Temporal Intervals|Temporal.interval|Temporal.repeating-interval|half-open|duration/start|duration/end|zoned intervals|calendar periods|interval algebra" docs/dev/features/temporal-intervals.md docs/dev/features/temporal.md docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/index.md
  ```

  Expected: all terms are present.

- [ ] **Step 7: Commit this task after review approval.**
  Commit message:

  ```bash
  git commit -m "docs(temporal): document interval layers"
  ```

---

### Task 5: Final Local Validation

**Files:**
- No source files expected unless validation reveals a reviewed fix is required.

**Interfaces:**
- Consumes: all previous task deliverables.
- Produces: validation evidence for final review and finishing.

- [ ] **Step 1: Run build and focused native validation.**
  Run:

  ```bash
  make build
  ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
  ```

  Expected: build and both CTests pass.

- [ ] **Step 2: Run Fennel compile check.**
  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/interval.fnl --file assets/lua/temporal/repeating-interval.fnl --file assets/lua/tests/test-temporal-intervals.fnl --file assets/lua/tests/fast.fnl
  ```

  Expected: pass with no diagnostics.

- [ ] **Step 3: Run constraints.**
  Run:

  ```bash
  make constraints
  ```

  Expected: pass. Constraint impact note: not applicable unless constraints are changed.

- [ ] **Step 4: Run focused interval tests.**
  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-intervals:main
  ```

  Expected: all focused interval tests pass with pristine output.

- [ ] **Step 5: Run full local suite.**
  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: full suite passes.

- [ ] **Step 6: Report coverage rationale.**
  The task report must state that validation covers native primitives, Lua bindings, Fennel public APIs, fast-suite registration, docs, and broad project regression risk. PR CI remains the full integration gate.

---

## Final Acceptance

- `require :temporal` exposes `interval` and `repeating-interval` namespaces.
- Existing temporal APIs remain compatible.
- Native core changes remain limited to comparison and exact local duration helpers.
- Intervals are half-open, typed, and reject zero-length, reversed, mixed-type, and unsupported forms.
- Repeating intervals support counted and limit-bounded expansion with explicit errors for unbounded expansion.
- Documentation explains supported behavior and deferred continuation paths.
- Focused validation and full local validation pass before finishing.
