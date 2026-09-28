# Temporal RRULE BYDAY Generator Design

## Context

The recurrence layer parses and serializes simple non-ordinal `BYDAY` values such as `MO,TU`, and daily/weekly expansion already supports them. Monthly and yearly expansion currently rejects `BYDAY` at occurrence time. Recent recurrence slices added bounded monthly/yearly generation for positive `BYMONTHDAY`; the same bucket-generation architecture can support common simple weekday rules such as monthly Mondays and yearly November Thursdays without adding full RFC5545 candidate-set expansion.

## Goal

Support simple non-ordinal `BYDAY` generation for monthly and yearly recurrence rules while preserving existing daily/weekly behavior and keeping ordinal/full-RFC5545 semantics deferred.

## Supported Behavior

- Keep existing `BYDAY` parse/serialize shape for simple weekdays only: `MO`, `TU`, `WE`, `TH`, `FR`, `SA`, `SU`.
- Daily and weekly `BYDAY` behavior remains unchanged.
- Monthly `BYDAY` generates matching weekdays inside selected monthly buckets.
- Yearly `BYDAY` generates matching weekdays inside selected yearly buckets.
- Monthly/yearly period buckets remain anchor-based from original `DTSTART` through `Temporal.period.add-to-plain-date-time`; no iterative drift is introduced.
- Generated weekday candidates preserve the original `DTSTART` time-of-day and nanosecond fields.
- Generated candidates before `DTSTART` are skipped.
- Generated candidates after local compact `UNTIL` are not emitted; `UNTIL` remains inclusive.
- `COUNT` and caller `options.limit` count returned occurrences after generated-date skipping, `DTSTART` lower-bound skipping, all filters, and `UNTIL` exclusion.
- For monthly rules, `BYMONTH` continues to filter the monthly anchor grid; it does not generate extra months.
- For yearly rules, `BYMONTH` supplies the generated month list when present; otherwise yearly `BYDAY` uses the `DTSTART` anchor month.
- Preserve caller-provided `BYMONTH` order for yearly generated months.
- When `BYDAY` and positive `BYMONTHDAY` are both present on monthly/yearly rules, generated candidates must satisfy both selectors.
- Positive `BYMONTHDAY` generation semantics remain unchanged.
- Unsatisfiable monthly/yearly generator combinations throw `unsupported temporal recurrence expansion` instead of hanging.

## Examples

- `DTSTART=2026-01-14T09:00:00`, `FREQ=MONTHLY;BYDAY=MO;COUNT=4` returns `2026-01-19T09:00:00`, `2026-01-26T09:00:00`, `2026-02-02T09:00:00`, `2026-02-09T09:00:00`.
- `DTSTART=2026-01-01T09:00:00`, `FREQ=YEARLY;BYMONTH=11;BYDAY=TH;COUNT=4` returns the four Thursdays in November 2026.
- `DTSTART=2026-05-20T09:00:00`, `FREQ=YEARLY;BYDAY=FR;COUNT=3` uses May, the anchor month, and returns `2026-05-22T09:00:00`, `2026-05-29T09:00:00`, `2027-05-07T09:00:00`.
- `DTSTART=2026-05-20T09:00:00`, `FREQ=MONTHLY;BYMONTHDAY=1,15;BYDAY=MO;COUNT=2` returns generated dates that are both requested month days and Mondays.

## Validation and Error Behavior

- Ordinal `BYDAY` strings such as `1MO` and `-1FR` continue to throw `invalid RRULE BYDAY` during parse.
- Unknown weekday tokens and empty `BYDAY` members continue to throw.
- Monthly/yearly impossible combinations throw `unsupported temporal recurrence expansion` rather than scanning forever.
- Existing monthly/yearly rules without `BYDAY` and without `BYMONTHDAY` continue to use the existing anchor/filter expansion path.

## Scope Exclusions

- Ordinal `BYDAY` semantics such as `1MO` and `-1FR`.
- `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, `BYWEEKNO`, and recurrence sets.
- Full RFC5545 candidate-set expansion.
- Timezone-aware recurrence, DST handling, UTC `UNTIL` expansion, and recurrence over `Instant` or `ZonedDateTime`.
- Natural-language recurrence changes.
- Native C++ temporal core changes.
- Public recurrence-set APIs.

## Approach Options Considered

### Option A: Keep monthly/yearly `BYDAY` rejected

This is simple but blocks common rules such as monthly Mondays. This option is rejected for this slice.

### Option B: Simple monthly/yearly weekday generation

This reuses the existing generator path and native `PlainDateTime.from-fields` construction. It unlocks common non-ordinal weekday recurrences while preserving the bounded architecture. This option is selected.

### Option C: Full RFC5545 weekday candidate sets

This would include ordinal weekdays, `BYSETPOS`, `WKST`, and broader candidate ordering semantics. It is too broad for this slice and remains deferred.

## Implementation Shape

- Keep `parse-by-day`, `normalize-by-day`, and `serialize-by-day` unchanged.
- Add helper logic to generate all valid days in a target month whose ISO weekday is allowed by `rule.by-day`.
- Extend the existing monthly/yearly generator path so it is used when either `rule.by-month-day` or `rule.by-day` is present.
- For monthly rules with `BYDAY` and no `BYMONTHDAY`, generate all matching weekdays in the anchor month in ascending day order.
- For yearly rules with `BYDAY` and no `BYMONTHDAY`, generate all matching weekdays in each selected month in ascending day order.
- For rules with both `BYDAY` and `BYMONTHDAY`, generate requested month days and filter them by weekday.
- Reuse existing `append-generated-candidates` behavior for `DTSTART`, `UNTIL`, `COUNT`, and `options.limit` bounds.
- Reuse bounded Gregorian-cycle satisfiability scans for generator paths.

## Acceptance Criteria

- `FREQ=MONTHLY;BYDAY=MO` expands instead of throwing.
- `FREQ=YEARLY;BYMONTH=11;BYDAY=TH` expands matching weekdays in the requested month.
- Yearly `BYDAY` without `BYMONTH` uses the `DTSTART` month.
- Monthly/yearly `BYDAY` combines with positive `BYMONTHDAY` by intersection.
- Existing daily/weekly `BYDAY`, `BYMONTH`, `BYMONTHDAY`, bounds, parse/serialize, and invalid-date behavior remains intact.
- Ordinal `BYDAY`, `BYSETPOS`, `WKST`, `RDATE`, `EXDATE`, timezone recurrence, and full RFC5545 candidate-set expansion remain unsupported.
- Documentation reflects supported simple `BYDAY` generation and deferred boundaries.

## Validation Plan

- Touched-file Fennel compile check for `assets/lua/temporal/recurrence.fnl`, `assets/lua/tests/test-temporal-parsing-recurrence.fnl`, and any touched facade files.
- `make constraints` after compile check.
- Focused recurrence test command: `SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main`.
- Full local suite during final validation because public recurrence behavior changes.
