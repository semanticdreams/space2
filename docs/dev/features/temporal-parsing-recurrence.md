# Temporal Parsing and Recurrence

The temporal parsing and recurrence layer adds strict standard text handling, explicit pattern parsing/formatting, recurrence rules, structured expression resolution, and a small deterministic natural grammar above the native temporal core. The C++ core remains the primitive semantic layer; it stays independent from natural language, recurrence, ICU, CLDR, localization data, parser providers, and plugin loading.

## Layering model

- `temporal-core` and the base `temporal` namespaces (`duration`, `instant`, `plain-date-time`, `zoned-date-time`, `clock`, and `tzdb`) remain the dependency-free semantic foundation.
- `temporal.standard`, `temporal.pattern`, `temporal.recurrence`, `temporal.expression`, and `temporal.natural` are Fennel-facing layers that translate external representations into typed temporal values or structured expressions.
- Higher layers do not use raw Unix timestamps as their public API boundary. They either return core temporal values (`Instant`, `PlainDateTime`, `ZonedDateTime`) or explicit structured expression/recurrence tables.
- Zoned conversion continues to require explicit IANA zone ids. No parser silently defaults to the host-local timezone.
- Errors are loud: invalid standard text, invalid patterns, invalid RRULE values, unsupported recurrence expansion, unsupported natural expressions, and missing expression context throw.

## Standard parse and format

`temporal.standard` is the strict standard-text facade over the core types:

```fennel
(local Temporal (require :temporal))

(local instant (Temporal.standard.parse-instant "2026-09-25T08:34:56-04:00"))
(Temporal.standard.format-instant instant) ; => "2026-09-25T12:34:56Z"

(local plain (Temporal.standard.parse-plain-date-time "2026-09-25T12:34:56"))
(Temporal.standard.format-plain-date-time plain) ; => "2026-09-25T12:34:56"

(local zdt
  (Temporal.standard.parse-zoned-date-time
    "2026-11-01T01:30:00-04:00[America/New_York]"))
(Temporal.standard.format-zoned-date-time zdt)
```

Instants require an explicit `Z` or numeric offset. Zoned date-times require an explicit numeric offset and bracketed IANA zone id; the parser verifies that the supplied offset matches the zone at that local time.

## Explicit patterns

`temporal.pattern` provides a deliberately small explicit pattern API for `PlainDateTime` values. Compile patterns once, then parse or format with the compiled pattern:

```fennel
(local pattern (Temporal.pattern.compile "yyyy/MM/dd HH:mm:ss"))
(local plain
  (Temporal.pattern.parse pattern "2026/09/25 12:34:56"
                          {:type :plain-date-time}))
(Temporal.pattern.format pattern plain) ; => "2026/09/25 12:34:56"
```

Supported field tokens are `yyyy`, `MM`, `dd`, `HH`, `mm`, and `ss`; quoted literals use single quotes. Unsupported tokens, malformed quotes, literal mismatches, trailing text, and unsupported parse types throw instead of being guessed.

## Recurrence and RRULE

`temporal.recurrence` is its own semantic subsystem, separate from standard parsing and natural-language parsing. Rules are explicit tables created with canonical option keys:

```fennel
(local rule (Temporal.recurrence.from {:freq :weekly
                                       :count 3
                                       :by-day [:tu]}))
(Temporal.recurrence.to-rrule rule) ; => "RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=TU"

(local parsed
  (Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=TU"))
(Temporal.recurrence.occurrences parsed
                                (Temporal.plain-date-time.parse "2026-09-22T09:00:00")
                                {})
```

The in-scope RFC5545 RRULE engine supports `FREQ` values `SECONDLY`, `MINUTELY`, `HOURLY`, `DAILY`, `WEEKLY`, `MONTHLY`, and `YEARLY`, plus `INTERVAL`, `COUNT`, compact local `UNTIL=YYYYMMDDTHHMMSS`, `BYSECOND`, `BYMINUTE`, `BYHOUR`, `BYDAY`, `BYMONTHDAY`, `BYYEARDAY`, `BYWEEKNO`, `BYMONTH`, `BYSETPOS`, and `WKST`. Expansion is `PlainDateTime`-only: rules expand from a caller-supplied `PlainDateTime` `DTSTART`; compact local `UNTIL` is inclusive; `COUNT`, `options.limit`, and local `UNTIL` stop at the first reached bound.

Rules use RFC5545 candidate-set ordering. Each frequency bucket generates date and time candidates, sorts the full bucket by plain date-time, applies `BYSETPOS` to that sorted bucket, then applies bounds including `DTSTART`, compact local `UNTIL`, `COUNT`, and `options.limit`. For example, `RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1` selects the first and last weekday in each month. `WKST` controls week bucket starts and week-number calculations for weekly interval rules and `BYWEEKNO`.

Selector examples:

```text
RRULE:FREQ=MONTHLY;BYDAY=1MO,-1FR;COUNT=4          ; ordinal BYDAY
RRULE:FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3           ; negative BYMONTHDAY
RRULE:FREQ=YEARLY;BYYEARDAY=1,-1;COUNT=4           ; BYYEARDAY
RRULE:FREQ=YEARLY;BYWEEKNO=-1;BYDAY=MO;COUNT=2     ; BYWEEKNO
RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3
RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=SU;WKST=SU;COUNT=3
RRULE:FREQ=HOURLY;BYMINUTE=0;UNTIL=20260101T101500 ; sub-daily rule
```

Unsupported continuation areas fail explicitly instead of falling back: recurrence sets (`RDATE`, `EXDATE`, `EXRULE`), ICS/VEVENT parsing, UTC/instant `UNTIL` expansion, explicit-zone/DST expansion, host-local timezone defaults, date-only/fractional `UNTIL`, and leap-second `BYSECOND=60` are outside this `PlainDateTime` recurrence slice.

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

## Structured expressions

`temporal.expression` resolves structured expression tables explicitly against caller-provided context:

```fennel
(local ctx
  (Temporal.expression.context
    {:reference-plain-date-time (Temporal.plain-date-time.parse "2026-09-25T15:30:00")
     :zone-id "America/New_York"}))

(Temporal.expression.resolve {:kind :relative-date :amount 1 :unit :day} ctx)
; => {:kind :plain-date-time :value <2026-09-26T00:00:00>}
```

Expression contexts require an explicit `:zone-id` and either a
`:reference-plain-date-time` or a `:reference-instant`. Plain references are
used directly. Instant references are projected through the explicit zone id
before relative expressions are resolved, so the same instant can produce
different civil dates in different zones. Space never falls back to the host
local timezone for expression resolution.

Resolution currently supports relative dates (`:day` and `:week`),
`:next-weekday`, and recurrence expressions. Supported relative-date and
next-weekday expressions resolve to plain-date-time results. Natural parsing
returns these structured expressions first; resolving them into temporal values
is always a separate, context-dependent operation.

## Natural grammar subset

`temporal.natural` is a small deterministic grammar, not broad natural-language understanding. It recognizes:

- `today`
- `tomorrow`
- `in N day(s)`
- `in N week(s)`
- `next <weekday>`
- `every <weekday>`

Examples:

```fennel
(Temporal.natural.parse "next Tuesday")
; => {:kind :next-weekday :weekday :tu}

(Temporal.natural.parse "every Tuesday")
; => {:kind :recurrence :rule {:freq :weekly :interval 1 :by-day [:tu]}}
```

Unsupported phrases throw. Natural-language recurrence is only a frontend that emits recurrence expressions/rules; recurrence behavior itself remains in `temporal.recurrence`.

## Deferred continuation map

These items are no longer unowned future ideas; the [Temporal Complete Library Roadmap](./temporal-complete-library) schedules them as follow-up tracks while current APIs continue to reject unsupported inputs loudly until those track PRs land.

- **ICU/CLDR localization:** Deferred. Localized parsing and formatting need an explicit ICU/CLDR/data-packaging strategy before implementation.
- **Broad natural language:** Deferred. Wider language coverage, ambiguous phrases, locales, and product ambiguity UX need their own design.
- **RFC5545 recurrence continuations:** The standalone RRULE engine is implemented for `PlainDateTime`, and `Temporal.recurrence-set` now covers finite recurrence-set assembly with explicit-zone expansion, DST disambiguation, and compact UTC `UNTIL` under an explicit zone. ICS/VEVENT parsing, `VTIMEZONE`, all-day events, overrides, cancellations, client interoperability, serialization, date-only/fractional/non-compact-offset `UNTIL`, and leap-second support remain deferred follow-up tracks with loud errors in the current API.
- **ISO intervals/repeating intervals:** Track 6 `Temporal.interval` and `Temporal.repeating-interval` are covered by [Temporal Intervals](./temporal-intervals). The supported interval grammar is `start/end`, `start/P...`, `P.../end`, `start/PT...`, and `PT.../end` for `:instant`, `:plain-date-time`, and explicit bracketed-IANA `:zoned-date-time` endpoints, with calendar `P...` endpoint forms limited to plain and zoned intervals and repeating expansion preserving exact-duration versus calendar-period step semantics. Exhaustive ISO 8601-1/-2 grammar, open intervals, date-only/all-day intervals, offset-only zoned intervals, non-Gregorian calendars, business-day intervals, natural-language intervals, ICS/VEVENT/VTIMEZONE parsing, interval algebra, localization, and scheduler policy remain deferred.
- **Calendar periods:** Date-only calendar period records and `PlainDateTime` arithmetic are covered by [Temporal Calendar Periods](./temporal-calendar-periods). Business days and locale calendar policy remain deferred. Exact `Duration` remains separate from calendar periods such as months and years.
- **Non-Gregorian calendars:** Deferred. The current foundation uses ISO proleptic Gregorian civil fields only.
- **Parser providers/plugins:** Deferred. No parser provider registry or plugin system is introduced in this layer.

## Validation

When changing temporal parsing or recurrence APIs, validate the native core and Fennel layers in this order:

```bash
make build
ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/standard.fnl --file assets/lua/temporal/pattern.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/temporal/expression.fnl --file assets/lua/temporal/natural.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl --file assets/lua/tests/fast.fnl
make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-recurrence-rfc5545:main
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

For docs-only edits, also run a focused term check over this page, the core temporal page, and the feature index to confirm public names and deferred boundaries remain documented.
