# Temporal Recurrence Set Zoned Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Temporal.recurrence-set` for finite recurrence-set assembly, explicit-zone expansion, DST disambiguation, and compact UTC `UNTIL` support.

**Architecture:** Implement a focused Fennel facade that composes the existing `Temporal.recurrence` RRULE engine, local RDATE/EXDATE records, and core zoned conversion. Keep `Temporal.recurrence.occurrences` PlainDateTime-only and keep native temporal core independent from recurrence-set policy.

**Tech Stack:** Space Fennel, existing temporal core Lua bindings, existing `temporal/recurrence` modules, Space Fennel test runner, project-native Fennel compile and constraint tooling.

## Global Constraints

- no host-local timezone defaults;
- `Duration` remains exact nanoseconds-only and is not used for calendar policy;
- native temporal core stays independent from recurrence-set, ICS, provider, localization, and scheduler policy;
- canonical option keys only;
- unsupported semantics fail loudly.
- Do not implement ICS/VEVENT parsing or serialization, `VTIMEZONE`, recurrence overrides, cancellations, all-day events, or client interoperability in this track.
- Do not import or bind libical for recurrence sets.
- Do not add date-only RDATE/EXDATE values, fractional-second `UNTIL`, offset UNTIL forms other than compact UTC `Z`, or leap-second support.
- Do not add host-local timezone fallback or output-mode switches.
- `Temporal.recurrence.occurrences` must remain PlainDateTime-only and continue rejecting compact UTC `UNTIL`.
- Fennel validation order is compile check, constraints, focused tests, then broader suite when finishing the branch.
- Use project-native Fennel tooling only; do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e` as validation oracles.

---

### Task 1: Public `Temporal.recurrence-set` Facade and RDATE-Only Expansion

**Files:**
- Create: `assets/lua/temporal/recurrence-set.fnl`
- Modify: `assets/lua/temporal.fnl`
- Create: `assets/lua/tests/test-temporal-recurrence-set.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `Temporal.plain-date-time.parse(text)`, `Temporal.recurrence.from(options)`, `Temporal.zoned-date-time.from-plain(plain zone-id options)`.
- Produces: `Temporal.recurrence-set.from(options) -> RecurrenceSet` and `Temporal.recurrence-set.occurrences(set options) -> ZonedDateTime[]`.
- `RecurrenceSet` shape: `{:kind :temporal-recurrence-set :dtstart PlainDateTime :rrules [RecurrenceRule] :rdates [PlainDateTime] :exdates [PlainDateTime] :exrules [RecurrenceRule]}`.

- [ ] **Step 1: Write failing tests for the exported namespace, RDATE-only zoned expansion, and validation**

Create `assets/lua/tests/test-temporal-recurrence-set.fnl`:

```fennel
(local tests [])
(local Temporal (require :temporal))

(fn assert-error [f message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  err)

(fn assert-error-contains [f fragment message]
  (local err (assert-error f message))
  (assert (tostring err):find fragment 1 true)
  err)

(fn p [text]
  (Temporal.plain-date-time.parse text))

(fn assert-zoned-strings [actual expected]
  (assert (= (# actual) (# expected)))
  (each [index value (ipairs expected)]
    (local occurrence (. actual index))
    (assert (= (occurrence:to-string) value))
    (assert occurrence.instant)))

(fn exports-recurrence-set-and-expands-rdate-only []
  (assert Temporal.recurrence-set)
  (assert (= (type Temporal.recurrence-set.from) :function))
  (assert (= (type Temporal.recurrence-set.occurrences) :function))
  (local set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-03-06T01:30:00")
       :rdates [(p "2026-03-10T01:30:00")]}))
  (assert (= set.kind :temporal-recurrence-set))
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences set {:zone-id "America/New_York"})
    ["2026-03-10T01:30:00-04:00[America/New_York]"]))

(fn validates-constructor-and-occurrence-options []
  (assert-error-contains
    #(Temporal.recurrence-set.from {:rdates [(p "2026-01-01T09:00:00")]})
    "dtstart"
    "missing dtstart should identify dtstart")
  (assert-error-contains
    #(Temporal.recurrence-set.from {:dtstart (p "2026-01-01T09:00:00")})
    "inclusion"
    "missing inclusion source should identify inclusion")
  (assert-error-contains
    #(Temporal.recurrence-set.from {:dtstart (p "2026-01-01T09:00:00")
                                    :rrule []})
    "rrule"
    "singular rrule alias should be rejected")
  (assert-error-contains
    #(Temporal.recurrence-set.from {:dtstart (p "2026-01-01T09:00:00")
                                    :rdates (p "2026-01-01T09:00:00")})
    "rdates"
    "non-list rdates should identify rdates")
  (local set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-01-01T09:00:00")
       :rdates [(p "2026-01-01T09:00:00")]}))
  (assert-error-contains
    #(Temporal.recurrence-set.occurrences set {})
    "zone-id"
    "missing zone-id should identify zone-id")
  (assert-error-contains
    #(Temporal.recurrence-set.occurrences set {:zone-id "America/New_York"
                                               :timezone "America/New_York"})
    "timezone"
    "unknown occurrence option should identify the rejected key")
  (assert-error-contains
    #(Temporal.recurrence-set.occurrences set {:zone-id "America/New_York"
                                               :disambiguation :middle})
    "disambiguation"
    "invalid disambiguation should identify disambiguation"))

(table.insert tests {:name "exports recurrence-set and expands RDATE-only"
                     :fn exports-recurrence-set-and-expands-rdate-only})
(table.insert tests {:name "validates constructor and occurrence options"
                     :fn validates-constructor-and-occurrence-options})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-recurrence-set" :tests tests})))

{:name "temporal-recurrence-set" :tests tests :main main}
```

Register `:tests.test-temporal-recurrence-set` in `assets/lua/tests/fast.fnl` near the existing temporal tests.

- [ ] **Step 2: Run focused test and verify it fails**

```bash
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-set:main
```

Expected: FAIL because `Temporal.recurrence-set` is not exported.

- [ ] **Step 3: Implement the minimal facade**

Create `assets/lua/temporal/recurrence-set.fnl` with validation helpers and an RDATE-only `occurrences` path. The implementation must reject unknown keys, require `:dtstart`, require at least one inclusion source, normalize optional lists to vectors, require `options.zone-id`, default `:disambiguation` to `:reject`, and convert each RDATE with `deps.zoned-date-time.from-plain`.

```fennel
(local constructor-keys {:dtstart true :rrules true :rdates true :exdates true :exrules true})
(local occurrence-option-keys {:zone-id true :disambiguation true :limit true})
(local valid-disambiguation {:reject true :earliest true :latest true})

(fn positive-integer? [value]
  (and (= (type value) :number) (= value (math.floor value)) (> value 0)))

(fn validate-plain-date-time [value name]
  (when (not (and value value.compare value.to-string value.fields))
    (error (.. "invalid temporal recurrence-set " name)))
  value)

(fn copy-normalized-list [value name item-validator]
  (if (= value nil)
      []
      (do
        (when (not= (type value) :table)
          (error (.. "invalid temporal recurrence-set " name)))
        (local result [])
        (each [index item (ipairs value)]
          (table.insert result (item-validator item)))
        result)))
```

`create`, `from`, and `occurrences` should use those helpers directly. `from` returns the documented `RecurrenceSet` shape. `occurrences` validates `set.kind`, validates options, slices to `:limit` when supplied, and calls `(deps.zoned-date-time.from-plain candidate zone-id {:disambiguation policy})` for each surviving RDATE.

- [ ] **Step 4: Export the facade from `assets/lua/temporal.fnl`**

Add:

```fennel
(local create-recurrence-set (require :temporal/recurrence-set))
```

Instantiate after `recurrence`:

```fennel
(local recurrence-set
  (create-recurrence-set
    {:recurrence recurrence
     :standard standard
     :plain-date-time base.plain-date-time
     :instant base.instant
     :zoned-date-time base.zoned-date-time}))
```

Return it as:

```fennel
:recurrence-set recurrence-set
```

- [ ] **Step 5: Validate Task 1**

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence-set.fnl --file assets/lua/tests/test-temporal-recurrence-set.fnl --file assets/lua/tests/fast.fnl
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-set:main
```

Expected: PASS.

- [ ] **Step 6: Commit Task 1**

```bash
git add assets/lua/temporal/recurrence-set.fnl assets/lua/temporal.fnl assets/lua/tests/test-temporal-recurrence-set.fnl assets/lua/tests/fast.fnl
git commit -m "feat(lua): add temporal recurrence-set facade"
```

---

### Task 2: Inclusion, Exclusion, Deduplication, Sorting, and Finite Limit Semantics

**Files:**
- Modify: `assets/lua/temporal/recurrence-set.fnl`
- Modify: `assets/lua/tests/test-temporal-recurrence-set.fnl`

**Interfaces:**
- Consumes: Task 1 facade and `Temporal.recurrence.occurrences(rule dtstart options)`.
- Produces: local assembly that expands RRULEs and EXRULEs from `:dtstart`, merges RDATEs, removes EXDATE/EXRULE exclusions, dedupes by `PlainDateTime:to-string`, sorts by `PlainDateTime:compare`, and applies `:limit` without backfilling excluded generated instances.

- [ ] **Step 1: Add failing tests for set assembly**

Append helpers and tests:

```fennel
(fn r [text]
  (Temporal.recurrence.parse-rrule text))

(fn assembles-inclusions-exclusions-dedupes-and-orders []
  (local set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-01-01T09:00:00")
       :rrules [(r "RRULE:FREQ=DAILY;COUNT=3")
                (r "RRULE:FREQ=WEEKLY;COUNT=2")]
       :rdates [(p "2026-01-03T09:00:00") (p "2026-01-04T09:00:00")]
       :exdates [(p "2026-01-02T09:00:00")]
       :exrules [(r "RRULE:FREQ=DAILY;INTERVAL=7;COUNT=1")]}))
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences set {:zone-id "America/New_York"})
    ["2026-01-03T09:00:00-05:00[America/New_York]"
     "2026-01-04T09:00:00-05:00[America/New_York]"
     "2026-01-08T09:00:00-05:00[America/New_York]"]))

(fn allows-empty-results-after-exclusions []
  (local set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-01-01T09:00:00")
       :rdates [(p "2026-01-01T09:00:00")]
       :exdates [(p "2026-01-01T09:00:00")]}))
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences set {:zone-id "America/New_York"})
    []))

(fn applies-limit-without-backfill-after-exclusions []
  (local set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-01-01T09:00:00")
       :rrules [(r "RRULE:FREQ=DAILY;COUNT=5")]
       :exdates [(p "2026-01-01T09:00:00")]}))
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences set {:zone-id "America/New_York" :limit 2})
    ["2026-01-02T09:00:00-05:00[America/New_York]"]))

(fn enforces-finite-expansion []
  (local unbounded
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-01-01T09:00:00")
       :rrules [(r "RRULE:FREQ=DAILY")]}))
  (assert-error-contains
    #(Temporal.recurrence-set.occurrences unbounded {:zone-id "America/New_York"})
    "unbounded"
    "unbounded recurrence-set should throw")
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences unbounded {:zone-id "America/New_York" :limit 2})
    ["2026-01-01T09:00:00-05:00[America/New_York]"
     "2026-01-02T09:00:00-05:00[America/New_York]"]))
```

Register each test with `table.insert tests` using descriptive names.

- [ ] **Step 2: Run focused test and verify it fails**

```bash
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-set:main
```

Expected: FAIL because Task 1 only expands RDATEs.

- [ ] **Step 3: Implement local set assembly**

In `recurrence-set.fnl`, add helpers with these exact names and responsibilities:

```fennel
(fn local-key [plain]
  (plain:to-string))

(fn sorted-local [items]
  (table.sort items #(< ($1:compare $2) 0))
  items)

(fn bounded-rule? [rule options]
  (or rule.count rule.until options.limit))

(fn rule-occurrence-options [options]
  (if options.limit {:limit options.limit} {}))

(fn zoned-entry [deps candidate options]
  (local zdt
    (deps.zoned-date-time.from-plain
      candidate
      options.zone-id
      {:disambiguation options.disambiguation}))
  {:local candidate :zoned zdt :instant (zdt:instant)})
```

Also implement `add-local-once`, `assert-finite-rule`, `expand-rule-local`, `local-inclusions`, `local-exclusion-map`, `apply-exclusions`, `limited`, `sort-zoned-entries`, and `zoned-results` so `occurrences` validates input, gathers inclusions, gathers exclusions, removes excluded local candidates, applies `:limit`, converts to zoned entries, sorts by instant with local-time tie-breaker, and returns only `entry.zoned` values. Each helper should throw an explicit `temporal recurrence-set` error when its required precondition is violated.

- [ ] **Step 4: Validate Task 2**

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence-set.fnl --file assets/lua/tests/test-temporal-recurrence-set.fnl
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-set:main
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add assets/lua/temporal/recurrence-set.fnl assets/lua/tests/test-temporal-recurrence-set.fnl
git commit -m "feat(lua): assemble temporal recurrence sets"
```

---

### Task 3: DST Policy and Compact UTC `UNTIL` in Recurrence Sets

**Files:**
- Modify: `assets/lua/temporal/recurrence/rule.fnl`
- Modify: `assets/lua/temporal/recurrence-set.fnl`
- Modify: `assets/lua/tests/test-temporal-recurrence-set.fnl`

**Interfaces:**
- Consumes: Task 2 set assembly, `Temporal.instant.parse`, `Temporal.zoned-date-time.from-instant`, and existing recurrence rule parsing.
- Produces: exported rule helpers for compact UTC `UNTIL`, recurrence-set-only UTC `UNTIL` filtering by resolved instant, and regression coverage that standalone recurrence expansion still rejects UTC `UNTIL`.

- [ ] **Step 1: Add failing tests for DST and UTC `UNTIL`**

Append tests:

```fennel
(fn applies-dst-disambiguation-policy []
  (local overlap-set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-11-01T01:30:00")
       :rdates [(p "2026-11-01T01:30:00")]}))
  (assert-error-contains
    #(Temporal.recurrence-set.occurrences overlap-set {:zone-id "America/New_York"})
    "ambiguous or nonexistent"
    "default reject should reject overlap")
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences overlap-set {:zone-id "America/New_York" :disambiguation :earliest})
    ["2026-11-01T01:30:00-04:00[America/New_York]"])
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences overlap-set {:zone-id "America/New_York" :disambiguation :latest})
    ["2026-11-01T01:30:00-05:00[America/New_York]"])
  (local gap-set
    (Temporal.recurrence-set.from
      {:dtstart (p "2026-03-08T02:30:00")
       :rdates [(p "2026-03-08T02:30:00")]}))
  (assert-error-contains
    #(Temporal.recurrence-set.occurrences gap-set {:zone-id "America/New_York"})
    "ambiguous or nonexistent"
    "default reject should reject gap")
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences gap-set {:zone-id "America/New_York" :disambiguation :earliest})
    ["2026-03-08T03:00:00-04:00[America/New_York]"])
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences gap-set {:zone-id "America/New_York" :disambiguation :latest})
    ["2026-03-08T01:59:59.999999999-05:00[America/New_York]"]))

(fn supports-compact-utc-until-only-in-recurrence-set []
  (local dtstart (p "2026-01-01T09:00:00"))
  (local utc-rule (r "RRULE:FREQ=DAILY;UNTIL=20260103T140000Z"))
  (local set (Temporal.recurrence-set.from {:dtstart dtstart :rrules [utc-rule]}))
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences set {:zone-id "America/New_York"})
    ["2026-01-01T09:00:00-05:00[America/New_York]"
     "2026-01-02T09:00:00-05:00[America/New_York]"
     "2026-01-03T09:00:00-05:00[America/New_York]"])
  (local before-third
    (Temporal.recurrence-set.from
      {:dtstart dtstart
       :rrules [(r "RRULE:FREQ=DAILY;UNTIL=20260103T135959Z")]}))
  (assert-zoned-strings
    (Temporal.recurrence-set.occurrences before-third {:zone-id "America/New_York"})
    ["2026-01-01T09:00:00-05:00[America/New_York]"
     "2026-01-02T09:00:00-05:00[America/New_York]"])
  (assert-error-contains
    #(Temporal.recurrence.occurrences utc-rule dtstart {})
    "UTC UNTIL"
    "standalone recurrence must still reject UTC UNTIL"))
```

Register the tests with `table.insert tests`.

- [ ] **Step 2: Run focused tests and verify UTC `UNTIL` fails**

```bash
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-set:main
```

Expected: FAIL on compact UTC `UNTIL` support while standalone recurrence rejection remains present.

- [ ] **Step 3: Export compact UTC `UNTIL` helpers from `rule.fnl`**

`compact-utc-until?` and `parse-until` already exist in `assets/lua/temporal/recurrence/rule.fnl`. Add `parse-utc-until` and export it with `compact-utc-until?`:

```fennel
(fn compact-utc-until->iso [text]
  (.. (text:sub 1 4) "-" (text:sub 5 6) "-" (text:sub 7 8)
      "T" (text:sub 10 11) ":" (text:sub 12 13) ":" (text:sub 14 15) "Z"))

(fn parse-utc-until [instant text]
  (when (not (compact-utc-until? text))
    (error "invalid temporal recurrence UNTIL"))
  (local (ok value) (pcall instant.parse (compact-utc-until->iso text)))
  (when (not ok)
    (error "invalid temporal recurrence UNTIL"))
  value)
```

Keep standalone recurrence expansion behavior unchanged.

- [ ] **Step 4: Implement recurrence-set UTC `UNTIL` filtering**

In `recurrence-set.fnl`, require `:temporal/recurrence/rule`, validate unsupported `UNTIL` forms through the existing `parse-until`, clone UTC-UNTIL rules to a local bound for generation, then filter generated candidates by resolving each candidate to the explicit zone and checking `candidate-instant <= until-instant`.

```fennel
(local rule-utils (require :temporal/recurrence/rule))

(fn utc-until-instant [deps rule]
  (when (and rule.until (rule-utils.compact-utc-until? rule.until))
    (rule-utils.parse-utc-until deps.instant rule.until)))

(fn validate-until-form [deps rule]
  (when rule.until
    (if (rule-utils.compact-utc-until? rule.until)
        true
        (do
          (local (ok _value) (pcall rule-utils.parse-until deps.standard rule.until))
          (when (not ok) (error "invalid temporal recurrence UNTIL"))))))

(fn candidate-within-utc-until? [deps candidate options until-instant]
  (if (= until-instant nil)
      true
      (do
        (local zdt (deps.zoned-date-time.from-plain candidate options.zone-id {:disambiguation options.disambiguation}))
        (<= ((zdt:instant):compare until-instant) 0))))
```

Use `deps.zoned-date-time.from-instant` to derive the local compact bound for efficient generation, and require `deps.instant.parse` and `deps.zoned-date-time.from-instant` during module creation.

- [ ] **Step 5: Validate Task 3**

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/recurrence/rule.fnl --file assets/lua/temporal/recurrence-set.fnl --file assets/lua/tests/test-temporal-recurrence-set.fnl
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-set:main
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-rfc5545:main
```

Expected: PASS for recurrence-set tests and existing standalone recurrence tests.

- [ ] **Step 6: Commit Task 3**

```bash
git add assets/lua/temporal/recurrence/rule.fnl assets/lua/temporal/recurrence-set.fnl assets/lua/tests/test-temporal-recurrence-set.fnl
git commit -m "feat(lua): support zoned UTC until recurrence sets"
```

---

### Task 4: Temporal Docs, Acceptance Evidence, and Final Validation

**Files:**
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`
- Modify: `docs/dev/features/temporal-complete-acceptance.md`
- Modify: `docs/dev/features/temporal-complete-library.md`

**Interfaces:**
- Consumes: implemented `Temporal.recurrence-set.from`, implemented `Temporal.recurrence-set.occurrences`, and validation output from Tasks 1-3.
- Produces: docs for recurrence-set API, explicit zone requirement, DST policy, UTC `UNTIL`, and remaining ICS boundaries.

- [ ] **Step 1: Update `temporal-parsing-recurrence.md`**

Add a section after “Recurrence and RRULE”:

~~~~markdown
## Recurrence sets and zoned expansion

`temporal.recurrence-set` composes finite local recurrence sources and converts the surviving occurrences through an explicit IANA time zone:

```fennel
(local set
  (Temporal.recurrence-set.from
    {:dtstart (Temporal.plain-date-time.parse "2026-03-06T01:30:00")
     :rrules [(Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;COUNT=3")]
     :rdates [(Temporal.plain-date-time.parse "2026-03-10T01:30:00")]
     :exdates [(Temporal.plain-date-time.parse "2026-03-07T01:30:00")]
     :exrules [(Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;COUNT=1")]}))

(Temporal.recurrence-set.occurrences
  set
  {:zone-id "America/New_York"
   :disambiguation :earliest
   :limit 10})
```

Constructor keys are canonical: `:dtstart`, `:rrules`, `:rdates`, `:exdates`, and `:exrules`. Expansion option keys are canonical: `:zone-id`, `:disambiguation`, and `:limit`. Singular aliases, raw ICS property text, host-local timezone defaults, and output-mode switches are rejected.

Local assembly expands each RRULE from `:dtstart`, adds RDATEs, expands EXRULEs from `:dtstart`, adds EXDATEs, deduplicates local inclusions, removes local exclusions, and sorts by local plain date-time. Exclusions win over inclusions. `:limit` caps returned occurrences after exclusions and does not backfill additional generated instances.

Expansion requires `:zone-id` and returns `ZonedDateTime` values. `:disambiguation` defaults to `:reject`; accepted values are `:reject`, `:earliest`, and `:latest`. DST gaps and overlaps use the same core zoned conversion behavior as `Temporal.zoned-date-time.from-plain`.

Standalone `Temporal.recurrence.occurrences` remains PlainDateTime-only and rejects compact UTC `UNTIL`. `Temporal.recurrence-set.occurrences` supports compact UTC `UNTIL=YYYYMMDDTHHMMSSZ` because it has an explicit zone; unsupported date-only, fractional, non-compact offset, and leap-second forms still fail loudly.

Recurrence sets are not ICS parsing. `VEVENT`, `VTIMEZONE`, all-day events, overrides, cancellations, client interoperability, and serialization remain future `Temporal.ics` work.
~~~~

Update the existing deferred continuation paragraph so recurrence sets and explicit-zone expansion are no longer listed as deferred after this track lands.

- [ ] **Step 2: Update `temporal-complete-acceptance.md` and `temporal-complete-library.md`**

Replace the recurrence-set acceptance row with evidence for RDATE/EXDATE/EXRULE tests, duplicate dedupe, exclusion precedence, explicit `:zone-id`, DST gap/overlap policies, compact UTC `UNTIL`, standalone UTC `UNTIL` rejection regression, focused recurrence-set suite, recurrence regression suite, constraints, broader local suite, and PR CI.

Update current implementation status in `temporal-complete-library.md` to state that recurrence-set explicit-zone expansion has landed while later tracks remain unsupported and loud-failing.

- [ ] **Step 3: Validate docs and Fennel together**

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/recurrence-set.fnl --file assets/lua/temporal/recurrence/rule.fnl --file assets/lua/tests/test-temporal-recurrence-set.fnl --file assets/lua/tests/fast.fnl
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-set:main
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-rfc5545:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: all commands PASS. PR CI remains the full integration gate after push and PR creation.

- [ ] **Step 4: Commit Task 4**

```bash
git add docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/temporal-complete-acceptance.md docs/dev/features/temporal-complete-library.md
git commit -m "docs: document temporal recurrence-set expansion"
```
