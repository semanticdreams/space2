# Temporal RRULE BYMONTHDAY Generator Design

## Context

The recurrence layer currently supports positive `BYMONTHDAY` as a filter over existing candidate streams. That is correct for daily and weekly scanning, but it leaves common monthly and yearly rules underpowered. For example, `FREQ=MONTHLY;BYMONTHDAY=15` should produce the 15th of selected months rather than only returning anchor-derived monthly candidates that already happen to land on the 15th.

The engine remains a `PlainDateTime` recurrence engine. It supports `COUNT`, caller `options.limit`, local compact `UNTIL`, `BYMONTH`, positive `BYMONTHDAY`, and daily/weekly `BYDAY`. Monthly and yearly stepping stays anchored through `Temporal.period` so interval grids do not drift.

## Goal

Add bounded generator semantics for positive `BYMONTHDAY` on monthly and yearly recurrences while preserving daily/weekly filter-only behavior and avoiding full RFC5545 candidate-set expansion.

## Supported Behavior

- Keep canonical option key `:by-month-day` and existing positive validation for integers `1..31`.
- Keep RRULE parse/serialize order: `FREQ`, optional `INTERVAL`, optional `COUNT`, optional `UNTIL`, optional `BYMONTH`, optional `BYMONTHDAY`, optional `BYDAY`.
- Daily and weekly `BYMONTHDAY` remain inclusion filters over existing daily/weekly candidates.
- Monthly `BYMONTHDAY` generates requested positive month days inside each selected monthly period bucket.
- Yearly `BYMONTHDAY` generates requested positive month days inside selected yearly period buckets.
- Monthly and yearly period buckets remain anchor-based from original `DTSTART` through `Temporal.period.add-to-plain-date-time`; no iterative drift is introduced.
- Generated candidates preserve the original `DTSTART` time-of-day and nanosecond fields.
- Generated candidates before `DTSTART` are skipped.
- Invalid generated dates such as February 30 or April 31 are skipped, not clamped and not surfaced as errors when the recurrence has at least one possible generated candidate in its bounded cycle.
- Generated candidates after local compact `UNTIL` are not emitted; `UNTIL` remains inclusive.
- `COUNT` and caller `options.limit` count returned occurrences after generated-date skipping, `DTSTART` lower-bound skipping, all filters, and `UNTIL` exclusion.
- Preserve caller-provided `BYMONTHDAY` order within each generated month; do not sort or deduplicate month days.
- For yearly rules with `BYMONTHDAY`, use `BYMONTH` as the generated month list when present; otherwise use the `DTSTART` anchor month.
- Preserve caller-provided `BYMONTH` order for yearly generated months.
- Monthly `BYMONTH` remains a filter over the monthly anchor grid; it does not generate extra months for monthly rules.
- Yearly `BYMONTH` without `BYMONTHDAY` remains existing filter-only behavior.
- Monthly/yearly `BYDAY` remains unsupported and throws before attempting generation.
- Unsatisfiable monthly/yearly generator combinations throw `unsupported temporal recurrence expansion` instead of hanging.

## Examples

- `DTSTART=2026-01-31T10:11:12`, `FREQ=MONTHLY;BYMONTHDAY=15;COUNT=3` returns `2026-02-15T10:11:12`, `2026-03-15T10:11:12`, `2026-04-15T10:11:12`. January 15 is before `DTSTART`, so it is skipped.
- `DTSTART=2026-01-31T10:11:12`, `FREQ=MONTHLY;BYMONTHDAY=1,15;COUNT=4` returns `2026-02-01T10:11:12`, `2026-02-15T10:11:12`, `2026-03-01T10:11:12`, `2026-03-15T10:11:12`.
- `DTSTART=2026-01-31T10:11:12`, `FREQ=MONTHLY;BYMONTHDAY=31;COUNT=3` skips months without a 31st and returns later valid 31st days.
- `DTSTART=2026-01-31T10:11:12`, `FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=14;COUNT=2` returns `2026-02-14T10:11:12` and `2027-02-14T10:11:12`.
- `DTSTART=2026-05-20T10:11:12`, `FREQ=YEARLY;BYMONTHDAY=15;COUNT=2` uses the anchor month and returns `2027-05-15T10:11:12`, `2028-05-15T10:11:12` because May 15 2026 is before `DTSTART`.

## Scope Exclusions

- Negative `BYMONTHDAY` semantics such as `-1` for the last day of the month.
- Full RFC5545 candidate-set expansion.
- `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, `BYWEEKNO`, and ordinal `BYDAY`.
- Timezone-aware recurrence, DST handling, UTC `UNTIL` expansion, and recurrence over `Instant` or `ZonedDateTime`.
- Natural-language recurrence changes.
- Native C++ temporal core changes.
- Public recurrence-set APIs.

## Approach Options Considered

### Option A: Keep filter-only behavior

This is already implemented and preserves a simple model, but it does not support the most common monthly/yearly `BYMONTHDAY` use cases. This option is rejected for this slice.

### Option B: Monthly/yearly generator semantics for positive `BYMONTHDAY`

This adds useful recurrence behavior while staying bounded and preserving daily/weekly filters. It reuses existing period buckets, `PlainDateTime` fields, and native `from-fields` validation. This option is selected.

### Option C: Full RFC5545 candidate-set expansion

This would eventually subsume `BYMONTHDAY` generation, but it is too broad for this slice and requires additional RFC5545 features and timezone policy. This option remains deferred.

## Implementation Shape

- Inject `Temporal.plain-date-time` into the recurrence factory so recurrence code can construct generated candidates with `from-fields`.
- Add private helpers to clone `DTSTART` time fields into a generated `PlainDateTime` for a target year, month, and requested day.
- Use `pcall` around `from-fields` so invalid generated dates return `nil` and are skipped.
- Split monthly/yearly calendar expansion: existing filter-only path remains for rules without `BYMONTHDAY`; generator path is used for monthly/yearly rules with `BYMONTHDAY`.
- Monthly generator path uses the anchor-derived month for each selected monthly interval bucket and applies `BYMONTH` as a filter over those buckets.
- Yearly generator path uses `BYMONTH` months when present, otherwise the anchor month from `DTSTART`.
- Add bounded satisfiability checks for generator paths over the Gregorian 400-year cycle.
- Keep monthly/yearly `BYDAY` rejection before generator logic.

## Acceptance Criteria

- Daily and weekly `BYMONTHDAY` tests continue to prove filter-only semantics.
- Monthly `BYMONTHDAY` generates requested valid days inside selected monthly buckets.
- Yearly `BYMONTHDAY` generates requested valid days in `BYMONTH` months when present and in the anchor month otherwise.
- Invalid generated dates are skipped, not clamped.
- Generated candidates before `DTSTART` are skipped.
- Local compact `UNTIL`, `COUNT`, and caller `options.limit` bound returned generated candidates correctly.
- Unsatisfiable monthly/yearly generator combinations throw instead of hanging.
- Existing `BYMONTH`, `BYDAY`, `UNTIL`, parse/serialize, validation, monthly interval, and yearly interval behavior remains intact.
- Documentation states frequency-dependent `BYMONTHDAY` semantics and deferred full-RFC5545 boundaries.

## Validation Plan

- Touched-file Fennel compile check for `assets/lua/temporal.fnl`, `assets/lua/temporal/recurrence.fnl`, and `assets/lua/tests/test-temporal-parsing-recurrence.fnl`.
- `make constraints` after the compile check.
- Focused recurrence test command: `SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main`.
- Full local suite during final validation because recurrence factory wiring and public recurrence behavior change.
