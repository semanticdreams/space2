# Temporal Complete Library Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the executable roadmap and acceptance contract that turns the approved complete temporal-library design into autonomous PR-sized implementation tracks.

**Architecture:** This plan is a documentation and coordination checkpoint, not the whole implementation. It creates the developer-facing roadmap, acceptance matrix, and updated temporal docs that later track-specific specs and plans must reference. Runtime code, dependency vendoring, Fennel modules, C++ adapters, migrations, and scheduler changes are implemented by follow-up track specs after this roadmap PR merges.

**Tech Stack:** Markdown docs, existing temporal docs under `docs/dev/features/`, focused text validation with `rg`, git-reviewed PR workflow.

## Global Constraints

- No API silently defaults to the host-local timezone. Zone-sensitive operations require explicit zone context.
- Exact `Duration` remains nanoseconds-only. Calendar periods, business days, months, years, and localized calendar arithmetic remain separate types/policies.
- The existing native temporal core remains the primitive semantic layer for `Instant`, `Duration`, `PlainDateTime`, `ZonedDateTime`, clock, and tzdb behavior.
- Higher-risk domains live in separate adapters and Fennel-facing modules: `temporal_ical`, `temporal_localization`, `Temporal.providers`, `Temporal.ics`, `Temporal.business-calendar`, `Temporal.natural`, `Temporal.migrations`, and `RuntimeScheduler`.
- Runtime parsing, formatting, scheduling, and migration must not perform network fetches.
- Third-party standards/data dependencies are pinned, reviewed, packaged, and tested.
- "Nothing deferred" means every temporal capability category has production API/docs/tests/data/fixtures/extension path; future corpus additions are maintenance, not missing architecture.
- This plan may edit docs only. Source, tests, build scripts, vendored dependencies, assets, and runtime behavior belong to follow-up track-specific specs/plans.

---

## File Structure

- Create `docs/dev/features/temporal-complete-library.md`: canonical developer roadmap for the complete temporal platform program, including architecture boundaries, program tracks, dependency policy, autonomy contract, and track-level spec gates.
- Create `docs/dev/features/temporal-complete-acceptance.md`: acceptance matrix mapping every in-scope category to required APIs/docs/tests/fixtures/validation evidence.
- Modify `docs/dev/features/index.md`: link the new roadmap and acceptance pages near existing temporal docs.
- Modify `docs/dev/features/temporal.md`: keep core invariants and point future-layer language to the complete roadmap.
- Modify `docs/dev/features/temporal-parsing-recurrence.md`: replace open-ended deferred wording with roadmap-owned categories while preserving current implemented subset and loud-failure behavior until follow-up tracks land.
- Modify `docs/dev/features/temporal-intervals.md`: point unsupported interval items to the roadmap tracks and preserve current loud rejection semantics.
- Modify `docs/dev/features/temporal-calendar-periods.md`: point business calendars, non-Gregorian calendars, localization, and timezone-aware period arithmetic to the roadmap tracks while preserving current period semantics.
- Reference `docs/specs/2026-09-28-temporal-complete-library-design.md`: committed source of truth for approved scope and invariants.

---

### Task 1: Publish Complete Temporal Roadmap Docs

**Files:**
- Create: `docs/dev/features/temporal-complete-library.md`
- Modify: `docs/dev/features/index.md`
- Modify: `docs/dev/features/temporal.md`
- Modify: `docs/dev/features/temporal-parsing-recurrence.md`
- Modify: `docs/dev/features/temporal-intervals.md`
- Modify: `docs/dev/features/temporal-calendar-periods.md`

**Interfaces:**
- Consumes: `docs/specs/2026-09-28-temporal-complete-library-design.md`
- Produces: `docs/dev/features/temporal-complete-library.md` as the developer-facing roadmap that all follow-up temporal track specs reference.

- [ ] **Step 1: Create the roadmap page with these exact sections**

Create `docs/dev/features/temporal-complete-library.md` with:

```markdown
# Temporal Complete Library Roadmap

## Completion definition

Space treats the temporal library as complete when every temporal capability category has a production API, public docs, focused tests, deterministic packaged data when needed, fixture or conformance coverage, and an extension path. Future additions of more locales, holiday jurisdictions, natural-language phrases, or calendar-client quirks are maintenance corpus expansion, not missing architecture.

## Non-negotiable invariants

- No host-local timezone defaulting.
- Exact `Duration` remains nanoseconds-only.
- Calendar periods, business days, localized calendars, and exact durations remain separate concepts.
- Native temporal primitives stay independent from natural-language parsing, recurrence policy, ICU/CLDR presentation, holiday policy, provider loading, and scheduler product semantics.
- Runtime temporal work does not fetch network data.

## Architecture boundaries

- Native core: `Instant`, `Duration`, `PlainDateTime`, `ZonedDateTime`, clock, timezone database, and small primitive helpers only when standards interoperability requires them.
- Native standards adapters: isolated modules such as `temporal_ical` and `temporal_localization` for libical and ICU/CLDR integration.
- Fennel facades: public policy and option shapes under `Temporal.recurrence`, `Temporal.recurrence-set`, `Temporal.interval`, `Temporal.repeating-interval`, `Temporal.ics`, `Temporal.localization`, `Temporal.calendar`, `Temporal.business-calendar`, `Temporal.providers`, `Temporal.natural`, `Temporal.migrations`, and `RuntimeScheduler`.

## Program tracks

1. Roadmap documentation and acceptance contract.
2. Dependency and data packaging foundation.
3. Provider/plugin registry.
4. Full RFC5545 recurrence engine.
5. Recurrence sets and explicit-zone/DST expansion.
6. Full ISO intervals and repeating intervals.
7. ICS/iCalendar interoperability.
8. ICU/CLDR localization and non-Gregorian calendars.
9. Business and holiday calendars.
10. Broad natural-language parsing.
11. Persisted timestamp migrations.
12. Runtime timer and scheduler redesign.
13. Final conformance and closeout.

## Dependency policy

ICU4C/CLDR and libical or an equivalent vetted iCalendar library are acceptable when selected by a track spec. Holiday data and natural-language corpora must be deterministic local data with source, license, version, and update process documented.

## Autonomy contract

After this roadmap and its plan are committed and reviewed, temporal implementation proceeds through PR-sized track specs and plans. The supervisor continues from track to track after each PR merges and stops only for semantic ambiguity not resolved by the active track spec, dependency or data license incompatibility, nondeterministic packaging, unavailable infrastructure, unsafe git history actions, validation failures without establishable root cause, PR CI or merge-queue blockers requiring human access, or material scope change.

## Track-level spec gates

Track specs must resolve the finite choices they introduce, including initial locale lists, non-Gregorian calendar lists, holiday jurisdictions and data source, iCalendar interoperability corpus, persisted timestamp schema inventory, scheduler catch-up semantics, and provider trust policy.

## Current implementation status

The current implementation remains the documented subset on the existing temporal pages until each track lands. Unsupported inputs must continue to fail loudly rather than silently guessing behavior.
```

- [ ] **Step 2: Link roadmap from feature index**

In `docs/dev/features/index.md`, add these links immediately after `Temporal Parsing and Recurrence`:

```markdown
- [Temporal Complete Library Roadmap](./temporal-complete-library)
- [Temporal Complete Acceptance](./temporal-complete-acceptance)
```

The acceptance page is created in Task 2, but the link is added here so the roadmap and matrix land together in one docs PR.

- [ ] **Step 3: Update existing temporal docs to point to the roadmap**

Add a concise paragraph to each existing temporal page:

- `docs/dev/features/temporal.md`: after `## Future layers`, state that the complete roadmap owns localization, recurrence, non-Gregorian calendars, migrations, and runtime scheduler redesign.
- `docs/dev/features/temporal-parsing-recurrence.md`: at the start of `## Deferred continuation map`, state that these items are no longer unowned future ideas; they are scheduled by the complete roadmap while current APIs still reject unsupported inputs loudly until track PRs land.
- `docs/dev/features/temporal-intervals.md`: before the unsupported list, state that full ISO/zoned/DST interval support is scheduled by the complete roadmap while current APIs preserve loud failures.
- `docs/dev/features/temporal-calendar-periods.md`: before the unsupported list, state that business calendars, non-Gregorian calendars, localization, and timezone-aware period arithmetic are scheduled by the complete roadmap while current period APIs remain bounded to PlainDateTime.

Use repo-relative Markdown links to `./temporal-complete-library`.

- [ ] **Step 4: Validate text coverage for Task 1**

Run:

```bash
rg "Temporal Complete Library Roadmap|Completion definition|Program tracks|Autonomy contract|Track-level spec gates" docs/dev/features/temporal-complete-library.md
rg "temporal-complete-library|temporal-complete-acceptance" docs/dev/features/index.md docs/dev/features/temporal.md docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/temporal-intervals.md docs/dev/features/temporal-calendar-periods.md
```

Expected: both commands find the new roadmap page and links from the index/existing temporal pages.

- [ ] **Step 5: Commit Task 1**

Commit only Task 1 files:

```bash
git add docs/dev/features/temporal-complete-library.md docs/dev/features/index.md docs/dev/features/temporal.md docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/temporal-intervals.md docs/dev/features/temporal-calendar-periods.md
git commit -m "docs(temporal): publish complete library roadmap"
```

---

### Task 2: Publish Acceptance Matrix and Final Docs Validation

**Files:**
- Create: `docs/dev/features/temporal-complete-acceptance.md`
- Modify: `docs/dev/features/temporal-complete-library.md`

**Interfaces:**
- Consumes: roadmap page from Task 1.
- Produces: acceptance matrix that later track specs update as implementation lands.

- [ ] **Step 1: Create acceptance matrix page**

Create `docs/dev/features/temporal-complete-acceptance.md` with:

```markdown
# Temporal Complete Acceptance Matrix

This matrix is the closeout contract for the complete temporal library program. A category is complete when it has public APIs, docs, focused tests, deterministic data or fixtures when applicable, validation commands, and PR CI evidence.

| Category | Public surface | Required evidence | Track |
| --- | --- | --- | --- |
| Dependency/data packaging | vendored ICU/CLDR, iCalendar library, holiday data metadata | version/license/source/checksum docs, CMake/package tests, build validation | Dependency and data packaging foundation |
| Provider registry | `Temporal.providers` | manifest validation tests, deterministic ordering tests, no-network invariant docs | Provider/plugin registry |
| RFC5545 recurrence | `Temporal.recurrence` | standard RRULE examples, full selector tests, invalid-rule diagnostics, focused recurrence suite | Full RFC5545 recurrence engine |
| Recurrence sets and zoned expansion | `Temporal.recurrence-set` | RDATE/EXDATE/exclusion tests, DST gap/overlap tests, explicit zone tests | Recurrence sets and explicit-zone/DST expansion |
| ISO intervals | `Temporal.interval`, `Temporal.repeating-interval` | full grammar tests, zoned interval tests, half-open invariant tests | Full ISO intervals and repeating intervals |
| ICS/iCalendar | `Temporal.ics` | fixture corpus, parse/export round trips, VTIMEZONE tests, invalid ICS diagnostics | ICS/iCalendar interoperability |
| Localization and calendars | `Temporal.localization`, `Temporal.calendar` | ICU data packaging tests, locale parse/format tests, explicit calendar conversion tests | ICU/CLDR localization and non-Gregorian calendars |
| Business calendars | `Temporal.business-calendar` | holiday fixture tests, observed-holiday tests, business-day arithmetic tests | Business and holiday calendars |
| Natural language | `Temporal.natural` | locale phrase corpus, candidate/ambiguity tests, missing-context diagnostics | Broad natural-language parsing |
| Timestamp migrations | `Temporal.migrations` and persistence call sites | schema inventory, idempotent migration tests, malformed-data diagnostics | Persisted timestamp migrations |
| Runtime scheduler | `RuntimeScheduler` and timer compatibility APIs | fixed-clock tests, recurrence scheduling tests, cancellation/lifecycle tests | Runtime timer and scheduler redesign |
| Final closeout | all temporal surfaces | end-to-end smoke tests, docs audit, focused suites, full `make test`, PR CI | Final conformance and closeout |

## Validation ladder

Track-specific validation starts narrow and broadens with risk. Fennel-facing tracks run compile checks, constraints, focused tests, and broader suite when public behavior changes. Native/dependency/binding tracks run `make cmake` or `make build` as needed, focused CTests, Fennel validation, and the broader suite when integration risk is broad. Final closeout runs the complete local validation ladder and relies on PR CI as the integration gate.

## Maintenance rule

After the closeout track lands, adding another locale, phrase, holiday jurisdiction, or client fixture updates this matrix's evidence corpus but does not reopen architecture unless the change requires a new public capability category.
```

- [ ] **Step 2: Link acceptance matrix from the roadmap page**

In `docs/dev/features/temporal-complete-library.md`, add this sentence at the end of `## Current implementation status`:

```markdown
The closeout evidence is tracked in [Temporal Complete Acceptance](./temporal-complete-acceptance).
```

- [ ] **Step 3: Run final docs validation**

Run:

```bash
rg "Temporal Complete Acceptance Matrix|Dependency/data packaging|Runtime scheduler|Maintenance rule" docs/dev/features/temporal-complete-acceptance.md
rg "temporal-complete-library|temporal-complete-acceptance|complete roadmap" docs/dev/features/index.md docs/dev/features/temporal.md docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/temporal-intervals.md docs/dev/features/temporal-calendar-periods.md docs/dev/features/temporal-complete-library.md docs/dev/features/temporal-complete-acceptance.md
rg "host-local timezone|Duration remains nanoseconds-only|Current implementation status" docs/dev/features/temporal-complete-library.md docs/dev/features/temporal.md docs/dev/features/temporal-parsing-recurrence.md docs/dev/features/temporal-intervals.md docs/dev/features/temporal-calendar-periods.md
git diff --check
```

Expected: `rg` commands find the required terms and `git diff --check` reports no whitespace errors.

- [ ] **Step 4: Commit Task 2**

Commit only Task 2 files:

```bash
git add docs/dev/features/temporal-complete-acceptance.md docs/dev/features/temporal-complete-library.md
git commit -m "docs(temporal): add complete acceptance matrix"
```

- [ ] **Step 5: Report next autonomous track**

After Task 2 review and branch finishing, the next autonomous effort is a new track spec and plan for dependency/data packaging foundation. It must choose concrete dependency candidates, licensing review scope, version/provenance recording, and packaging tests before any vendored dependency or build-file change.
