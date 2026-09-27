# Temporal RRULE UNTIL Expansion Bound Design

## Context

The temporal recurrence layer currently parses and serializes RRULE `UNTIL`, but occurrence expansion ignores it. Bounded expansion is instead enforced only by `COUNT` or the caller-provided `:limit` option. This leaves a visible semantic gap: a rule can round-trip `UNTIL` while still returning occurrences after the boundary.

The recurrence engine currently produces `PlainDateTime` candidates for `DAILY`, `WEEKLY`, `MONTHLY`, and `YEARLY` frequencies. Monthly and yearly candidates remain anchor-based through `Temporal.period`; timezone-aware recurrence, DST handling, and full RFC5545 candidate-set machinery are not present.

## Goal

Add `UNTIL` as an inclusive finite expansion bound for the existing bounded recurrence subset without changing the native temporal core or introducing timezone-aware recurrence semantics.

## Supported Behavior

- Keep canonical option key `:until`.
- Keep `Temporal.recurrence.parse-rrule` storing `UNTIL` as the raw RRULE string.
- Keep `Temporal.recurrence.to-rrule` emitting the raw `UNTIL` string unchanged.
- During `Temporal.recurrence.occurrences`, parse compact local `UNTIL` values of the form `YYYYMMDDTHHMMSS` as `PlainDateTime` bounds.
- Treat `UNTIL` as inclusive: return candidates where `candidate <= until`.
- Allow supported local `UNTIL` to satisfy the finite-bound requirement without `COUNT` or `options.limit`.
- Combine `COUNT`, `options.limit`, and `UNTIL` by stopping at the earliest reached bound.
- Return an empty occurrence list when a supported local `UNTIL` is before `DTSTART`.
- Preserve existing `BYDAY` and `BYMONTH` filtering behavior; `COUNT` and `options.limit` continue to count returned occurrences after filters.
- Preserve monthly and yearly anchor-based expansion semantics.

## Validation and Error Behavior

- `Temporal.recurrence.from` validates only that `:until` is a string, preserving parse/serialize compatibility.
- Malformed `UNTIL` strings throw during occurrence expansion with a clear `invalid temporal recurrence UNTIL` error.
- Compact UTC `UNTIL=YYYYMMDDTHHMMSSZ` remains parse/serialize-compatible but throws during expansion with `unsupported temporal recurrence UNTIL` because recurrence candidates are currently plain date-times and no timezone context exists.
- Recurrence expansion with no `COUNT`, no `options.limit`, and no supported local `UNTIL` continues to throw a finite-bound error.

## Scope Exclusions

- Timezone-aware recurrence and DST handling.
- Comparing plain recurrence candidates against instants.
- Date-only `UNTIL` values.
- Fractional-second `UNTIL` values.
- Offset `UNTIL` values other than the preserved-but-unsupported compact UTC `Z` form.
- Full RFC5545 candidate-set expansion.
- `BYMONTHDAY`, `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, `BYWEEKNO`, and ordinal `BYDAY`.
- Native C++ temporal core changes.
- Public recurrence-set APIs.

## Approach Options Considered

### Option A: Parse `UNTIL` in `Temporal.recurrence.from`

This would validate earlier, but it would reject raw RRULE strings in parse/serialize-only workflows and would move expansion-specific compatibility decisions into normalization. It also has no `DTSTART` or occurrence context. This option is rejected.

### Option B: Lazy parse `UNTIL` during occurrence expansion

This preserves existing parse/serialize behavior while making expansion semantics loud and explicit. It is the recommended approach.

### Option C: Support compact UTC `UNTIL` as the only active bound

This is closer to common RFC5545 examples, but the current recurrence engine produces `PlainDateTime` candidates and has no zone context for converting them to instants. This option risks inventing implicit timezone defaults, so it is rejected for this slice.

### Option D: Support compact local plain-date-time `UNTIL` as the active bound

This matches the current candidate type and avoids host-local timezone defaults. Compact UTC `UNTIL` remains accepted for round-trip compatibility but unsupported for expansion. This option is selected.

## Implementation Shape

- Inject `temporal.standard` into the recurrence factory so the recurrence module can reuse project-native `parse-plain-date-time` validation for the ISO text produced from compact local `UNTIL`.
- Add private helper logic that recognizes:
  - local compact `YYYYMMDDTHHMMSS` and converts it to `YYYY-MM-DDTHH:MM:SS` before parsing;
  - UTC compact `YYYYMMDDTHHMMSSZ` as recognized but unsupported for expansion;
  - all other values as invalid for expansion.
- Replace the numeric-only occurrence limit calculation with a bounds object containing optional numeric limit and optional plain-date-time until value.
- Update daily, weekly, monthly, and yearly loops so they stop before inserting candidates after the inclusive `UNTIL` bound.
- Keep existing satisfiability guards for `BYDAY` and `BYMONTH`; do not add full RFC5545 candidate machinery.

## Acceptance Criteria

- Local compact `UNTIL` bounds daily, weekly, monthly, and yearly occurrence arrays inclusively.
- `UNTIL` alone no longer triggers the unbounded expansion error when it is a supported local bound.
- `COUNT`, `options.limit`, and `UNTIL` combine by earliest reached bound.
- A local `UNTIL` before `DTSTART` returns `[]`.
- Invalid `UNTIL` throws during occurrence expansion.
- Compact UTC `UNTIL` round-trips through parse/serialize and throws during occurrence expansion.
- Existing `FREQ`, `INTERVAL`, `COUNT`, `BYDAY`, and `BYMONTH` behaviors remain intact.
- Documentation states supported `UNTIL` semantics and the timezone-aware recurrence exclusion.

## Validation Plan

- Touched-file Fennel compile check for `assets/lua/temporal.fnl`, `assets/lua/temporal/recurrence.fnl`, and `assets/lua/tests/test-temporal-parsing-recurrence.fnl`.
- `make constraints` after the compile check.
- Focused recurrence test command: `SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main`.
- Broader validation during branch finishing if reviewer risk assessment or finishing policy requires it.
