# Temporal RRULE BYMONTHDAY Filter Design

## Context

The temporal recurrence layer now supports bounded recurrence expansion for `DAILY`, `WEEKLY`, `MONTHLY`, and `YEARLY`, including `COUNT`, caller `options.limit`, local compact `UNTIL`, `BYDAY`, and filter-only `BYMONTH`. The current engine produces `PlainDateTime` candidates. Monthly and yearly expansion remains anchor-based through `Temporal.period`, and selectors filter those existing candidates rather than generating full RFC5545 candidate sets.

`BYMONTHDAY` is still deferred in the public docs. This slice adds the smallest useful form: positive day-of-month filters over the existing candidate streams.

## Goal

Add bounded positive RRULE `BYMONTHDAY` support as a filter-only selector while preserving the existing recurrence architecture and avoiding full RFC5545 candidate-set expansion.

## Supported Behavior

- Add canonical recurrence option key `:by-month-day`.
- Parse RRULE month-day lists such as `BYMONTHDAY=1,15,31`.
- Serialize normalized `:by-month-day` values as `BYMONTHDAY=1,15,31`.
- Accept only positive integer month days `1..31`.
- Preserve caller/list order for parse/serialize; do not sort or deduplicate values.
- Apply `BYMONTHDAY` as an inclusion filter over existing candidates for `DAILY`, `WEEKLY`, `MONTHLY`, and `YEARLY` frequencies.
- Filter by the actual candidate day after monthly/yearly anchor clamping.
- Preserve existing `BYMONTH` filter behavior and allow `BYMONTH` and `BYMONTHDAY` to combine conjunctively.
- Preserve existing `BYDAY` behavior for daily/weekly rules and existing monthly/yearly `BYDAY` rejection.
- Preserve existing `COUNT`, `options.limit`, and local `UNTIL` behavior: numeric bounds count returned occurrences after filters, and `UNTIL` stops candidate scanning inclusively.
- Avoid unbounded scans for unsatisfiable filters by extending the existing satisfiability guards.

## Filter-Only Semantics

This slice intentionally does not make `BYMONTHDAY` generate new dates inside a month. It only filters the candidate stream that already exists.

Examples:

- `FREQ=DAILY;BYMONTHDAY=31` returns daily candidates whose actual day-of-month is `31`.
- `FREQ=WEEKLY;BYDAY=MO;BYMONTHDAY=2,16` returns selected Mondays whose actual day-of-month is `2` or `16`.
- `FREQ=MONTHLY` starting at `2026-01-31T10:11:12` with `BYMONTHDAY=30` returns clamped monthly candidates that actually land on day `30`, such as `2026-04-30T10:11:12`; it does not create a `2026-01-30` candidate.
- `FREQ=YEARLY` starting at `2028-02-29T10:11:12` with `BYMONTHDAY=29` returns leap-year candidates such as `2028-02-29` and `2032-02-29`; with `BYMONTHDAY=28`, it returns non-leap clamped candidates such as `2029-02-28`.

## Validation and Error Behavior

- `BYMONTHDAY=0`, `BYMONTHDAY=32`, negative values such as `BYMONTHDAY=-1`, empty members, and non-integer values throw.
- Programmatic `:by-month-day` must be a non-empty table of integers in `1..31`; non-table or empty values throw.
- Unknown RRULE keys still throw.
- Unsatisfiable `BYMONTHDAY` filter combinations throw `unsupported temporal recurrence expansion` instead of hanging.

## Scope Exclusions

- Negative `BYMONTHDAY` semantics such as `-1` for the last day of the month.
- Monthly/yearly generator semantics that create requested month days inside each period.
- Full RFC5545 candidate-set expansion.
- `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, `BYWEEKNO`, and ordinal `BYDAY`.
- Timezone-aware recurrence and DST handling.
- Native C++ temporal core changes.
- Natural-language recurrence changes.
- Public recurrence-set APIs.

## Approach Options Considered

### Option A: Filter-only positive `BYMONTHDAY`

This mirrors current `BYMONTH` architecture. It is small, bounded, testable, and preserves the current recurrence candidate model. This is the selected option.

### Option B: Generator semantics for monthly/yearly requested days

This would allow rules such as “monthly on the 15th” to create day-15 occurrences even when `DTSTART` is on a different day. It is useful, but it requires new policy for invalid month days, clamping versus skipping, interaction with anchor-based periods, and consistency with future RFC5545 candidate sets. This option is deferred.

### Option C: Full RFC5545 candidate-set expansion

This is the standards-aligned destination, but it is too broad for this slice. It would need negative `BYMONTHDAY`, ordinal `BYDAY`, `BYSETPOS`, `WKST`, timezone-aware `UNTIL`, and compatibility tests. This option is deferred.

## Implementation Shape

- Add `:by-month-day` to recurrence option validation.
- Add private normalization, parsing, and serialization helpers following the existing `BYMONTH` pattern.
- Add `plain-day`, membership, and candidate calendar filter helpers alongside existing `plain-month` and `month-filter-allowed?` helpers.
- Replace month-only filter checks in daily, weekly, and calendar expansion with a combined calendar filter that checks both `BYMONTH` and `BYMONTHDAY`.
- Extend daily and weekly satisfiability scans so they consider `BYMONTHDAY` as well as `BYMONTH` and `BYDAY`.
- Extend monthly/yearly satisfiability checks with bounded cycle scans that account for clamped dates and leap-year cycles.

## Acceptance Criteria

- `Temporal.recurrence.parse-rrule` accepts `BYMONTHDAY=1,29,31`.
- `Temporal.recurrence.to-rrule` emits canonical order: `FREQ`, optional `INTERVAL`, optional `COUNT`, optional `UNTIL`, optional `BYMONTH`, optional `BYMONTHDAY`, optional `BYDAY`.
- `Temporal.recurrence.from` accepts `{:by-month-day [1 15 31]}` and rejects empty, non-table, non-integer, negative, zero, and greater-than-31 values.
- Daily, weekly, monthly, and yearly occurrence expansion filters by actual candidate day-of-month.
- `BYMONTH` and `BYMONTHDAY` combine conjunctively.
- `COUNT` and `options.limit` count returned occurrences after filters.
- `UNTIL` remains an inclusive candidate-scanning stop.
- Unsatisfiable daily, weekly, monthly, and yearly `BYMONTHDAY` filters throw instead of hanging.
- Existing `BYMONTH`, `BYDAY`, `UNTIL`, monthly clamp, and yearly leap-day behavior remains intact.
- Documentation states supported positive filter-only `BYMONTHDAY` semantics and deferred negative/generator/full-RFC5545 behavior.

## Validation Plan

- Touched-file Fennel compile check for `assets/lua/temporal/recurrence.fnl` and `assets/lua/tests/test-temporal-parsing-recurrence.fnl`.
- `make constraints` after the compile check.
- Focused recurrence test command: `SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main`.
- Broader validation during branch finishing if reviewer risk assessment or finishing policy requires it.
