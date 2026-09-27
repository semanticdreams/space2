# Temporal Expression Reference-Instant Projection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Temporal.expression.context` support `:reference-instant` by projecting it through the caller's explicit `:zone-id`.

**Architecture:** Implement projection privately inside `assets/lua/temporal/expression.fnl` using existing temporal-core bindings: `zoned-date-time.from-instant`, `zdt:fields`, and `plain-date-time.from-fields`. Normalize contexts to an effective `:reference-plain-date-time` so existing relative-date and next-weekday resolution logic remains unchanged.

**Tech Stack:** Space Fennel, native `temporal-core` Lua bindings, project-native Fennel validation through `tools.fennel-check`, constraints, and focused Fennel tests.

## Global Constraints

- `Temporal.expression.context` must support `:reference-instant` only when an explicit string `:zone-id` is provided.
- No host-local timezone defaults.
- No broader natural language maturity.
- No recurrence maturity changes.
- No public instant-to-plain helper/facade in this slice.
- No native C++ binding method in this slice.
- Preserve existing `:reference-plain-date-time` behavior and returned resolution shape.
- If both `:reference-plain-date-time` and `:reference-instant` are supplied, `:reference-plain-date-time` remains the effective reference for compatibility.
- Invalid zones or invalid temporal values must throw loudly through existing temporal-core behavior.
- Documentation must update the existing canonical page: `docs/dev/features/temporal-parsing-recurrence.md`; no new `docs/dev` page is needed because that page already owns `Temporal.expression`.

---

## File Structure

- `assets/lua/temporal/expression.fnl`
  - Owns structured temporal-expression context normalization and resolution.
  - Add private helpers for `:reference-instant` projection.
  - Keep exported table unchanged: `{:context context :resolve resolve}`.
- `assets/lua/tests/test-temporal-parsing-recurrence.fnl`
  - Owns focused tests for parsing, recurrence, natural expressions, and expression resolution.
  - Add a regression test proving the same instant maps to different local dates through different explicit zones.
- `docs/dev/features/temporal-parsing-recurrence.md`
  - Canonical feature documentation for `Temporal.expression`.
  - Document explicit-zone projection and the absence of host-local defaults.

---

### Task 1: Expression Reference-Instant Projection

**Files:**
- Modify: `assets/lua/temporal/expression.fnl`
- Modify: `assets/lua/tests/test-temporal-parsing-recurrence.fnl`
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`

**Interfaces:**
- Consumes:
  - `core.zoned-date-time.from-instant(instant, zone-id:string) -> TemporalZonedDateTime`
  - `zdt:fields() -> table`
  - `core.plain-date-time.from-fields(fields:table) -> TemporalPlainDateTime`
  - Existing `Temporal.expression.context(options:table) -> context-table`
  - Existing `Temporal.expression.resolve(expr:table, ctx:table) -> result-table`
- Produces:
  - Unchanged public API: `Temporal.expression.context(options:table) -> context-table`
  - Unchanged public API: `Temporal.expression.resolve(expr:table, ctx:table) -> result-table`
  - Contexts with only `:reference-instant` and `:zone-id` resolve supported relative expressions as `:plain-date-time` results.
  - No new exported function.

- [ ] **Step 1: Add the failing projection regression test.**

  In `assets/lua/tests/test-temporal-parsing-recurrence.fnl`, add this function after `natural-relative-resolution` and before `natural-next-weekday-and-recurrence`:

  ```fennel
  (fn expression-reference-instant-projects-through-zone []
    (local instant (Temporal.instant.parse "2026-09-25T00:30:00Z"))
    (local ny-ctx (Temporal.expression.context {:reference-instant instant
                                                :zone-id "America/New_York"}))
    (local tokyo-ctx (Temporal.expression.context {:reference-instant instant
                                                   :zone-id "Asia/Tokyo"}))
    (local ny-today (Temporal.expression.resolve (Temporal.natural.parse "today") ny-ctx))
    (local tokyo-today (Temporal.expression.resolve (Temporal.natural.parse "today") tokyo-ctx))
    (assert (= (ny-today.value:to-string) "2026-09-24T00:00:00"))
    (assert (= (tokyo-today.value:to-string) "2026-09-25T00:00:00")))
  ```

  Register it before the existing natural tests:

  ```fennel
  (table.insert tests {:name "expression reference instant projects through zone" :fn expression-reference-instant-projects-through-zone})
  ```

- [ ] **Step 2: Run the focused test and verify the failure.**

  If `./build/space` is missing or stale, first run:

  ```bash
  make build
  ```

  Then run the focused test:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected before implementation: failure containing `reference instant resolution requires projection support`.

- [ ] **Step 3: Implement private projection helpers.**

  In `assets/lua/temporal/expression.fnl`, add these helpers after `require-context` and before `reference-plain-date-time`:

  ```fennel
  (fn project-reference-instant [instant zone-id]
    (when (not= (type zone-id) :string)
      (error "temporal expression context requires zone id"))
    (local zdt (core.zoned-date-time.from-instant instant zone-id))
    (core.plain-date-time.from-fields (zdt:fields)))

  (fn normalized-reference-plain-date-time [ctx]
    (if (not= ctx.reference-plain-date-time nil)
        ctx.reference-plain-date-time
        (not= ctx.reference-instant nil)
        (project-reference-instant ctx.reference-instant ctx.zone-id)
        nil))
  ```

  Replace the existing `reference-plain-date-time` body with:

  ```fennel
  (fn reference-plain-date-time [ctx]
    (require-context ctx)
    (local reference (normalized-reference-plain-date-time ctx))
    (when (= reference nil)
      (error "temporal expression context requires reference plain date-time"))
    reference)
  ```

- [ ] **Step 4: Normalize contexts at creation time.**

  Replace the existing `context` function with:

  ```fennel
  (fn context [options]
    (when (not= (type options) :table)
      (error "temporal expression context options must be a table"))
    (when (not= (type options.zone-id) :string)
      (error "temporal expression context requires zone id"))
    (local reference (normalized-reference-plain-date-time options))
    (when (= reference nil)
      (error "temporal expression context requires reference"))
    {:zone-id options.zone-id
     :reference-plain-date-time reference
     :reference-instant options.reference-instant})
  ```

  This preserves the existing context table shape while ensuring downstream resolution sees an effective plain-date-time reference.

- [ ] **Step 5: Update the documentation.**

  In `docs/dev/features/temporal-parsing-recurrence.md`, update the structured-expression section to include this wording:

  ```markdown
  Expression contexts require an explicit `:zone-id` and either a
  `:reference-plain-date-time` or a `:reference-instant`. Plain references are
  used directly. Instant references are projected through the explicit zone id
  before relative expressions are resolved, so the same instant can produce
  different civil dates in different zones. Space never falls back to the host
  local timezone for expression resolution.
  ```

  Keep the existing description that supported relative-date and next-weekday expressions resolve to plain-date-time results.

- [ ] **Step 6: Run touched-file Fennel compile checks.**

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/expression.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Expected: command exits zero with no Fennel compile errors.

- [ ] **Step 7: Run constraints.**

  ```bash
  make constraints
  ```

  Expected: command exits zero. Constraint-impact note for the handoff: not applicable; this changes expression context behavior without adding or relaxing structural constraints.

- [ ] **Step 8: Run the focused Fennel test.**

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
  ```

  Expected: command exits zero and includes the new `expression reference instant projects through zone` test in the run.

- [ ] **Step 9: Run focused documentation/search checks.**

  ```bash
  rg "reference-instant|host-local timezone|Temporal.expression.context|zone-id" docs/dev/features/temporal-parsing-recurrence.md assets/lua/temporal/expression.fnl assets/lua/tests/test-temporal-parsing-recurrence.fnl
  ```

  Expected: output shows the docs, implementation, and test all mention the projection surface.

- [ ] **Step 10: Commit the reviewed task changes.**

  ```bash
  git add assets/lua/temporal/expression.fnl assets/lua/tests/test-temporal-parsing-recurrence.fnl docs/dev/features/temporal-parsing-recurrence.md
  git commit -m "feat(temporal): project expression reference instants"
  ```

  The implementer report must include:
  - Failing-test evidence from Step 2.
  - Compile-check evidence from Step 6.
  - Constraints evidence from Step 7.
  - Focused-test evidence from Step 8.
  - Documentation/search evidence from Step 9.
  - Constraint-impact note: not applicable.

---

## Final Review and Finishing Validation

After Task 1 passes reviewer gate, request a whole-branch reviewer pass against:

- `docs/specs/2026-09-27-temporal-expression-projection-design.md`
- `docs/plans/2026-09-27-temporal-expression-projection.md`
- `assets/lua/temporal/expression.fnl`
- `assets/lua/tests/test-temporal-parsing-recurrence.fnl`
- `docs/dev/features/temporal-parsing-recurrence.md`

Then invoke finishing-a-development-branch. Required final validation should include at least:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/expression.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl
make constraints
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
```

Broaden to the full suite during finishing if reviewer requests it, if final integration policy requires it, or if focused validation exposes cross-surface risk.
