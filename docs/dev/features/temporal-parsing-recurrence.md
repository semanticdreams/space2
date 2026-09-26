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

The initial RRULE subset supports `FREQ` values `DAILY`, `WEEKLY`, `MONTHLY`, and `YEARLY`, plus `INTERVAL`, `COUNT`, `UNTIL`, and `BYDAY`. Occurrence expansion currently supports bounded daily and weekly rules. Expansion requires either `count` on the rule or `{:limit n}` in occurrence options; monthly and yearly expansion throw until their semantics are specified.

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

The context requires an explicit `zone-id` and a reference value. Resolution currently supports relative dates (`:day` and `:week`), `:next-weekday`, and recurrence expressions. Natural parsing returns these structured expressions first; resolving them into temporal values is always a separate, context-dependent operation.

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

- **ICU/CLDR localization:** Deferred. Localized parsing and formatting need an explicit ICU/CLDR/data-packaging strategy before implementation.
- **Broad natural language:** Deferred. Wider language coverage, ambiguous phrases, locales, and product ambiguity UX need their own design.
- **Full RFC5545:** Deferred. The current RRULE subset is intentionally small; full RFC5545 recurrence requires separate semantics and compatibility tests.
- **ISO intervals/repeating intervals:** Deferred. Interval values and repeating interval syntax are not part of this slice.
- **Calendar periods:** Deferred. Exact `Duration` remains separate from calendar periods such as months, years, and business days.
- **Non-Gregorian calendars:** Deferred. The current foundation uses ISO proleptic Gregorian civil fields only.
- **Parser providers/plugins:** Deferred. No parser provider registry or plugin system is introduced in this layer.

## Validation

When changing temporal parsing or recurrence APIs, validate the native core and Fennel layers in this order:

```bash
make build
ctest --test-dir build -R 'test_temporal_core|test_lua_temporal_core_binding' --output-on-failure
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal.fnl --file assets/lua/temporal/standard.fnl --file assets/lua/temporal/pattern.fnl --file assets/lua/temporal/recurrence.fnl --file assets/lua/temporal/expression.fnl --file assets/lua/temporal/natural.fnl --file assets/lua/tests/test-temporal-parsing-recurrence.fnl --file assets/lua/tests/fast.fnl
make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-parsing-recurrence:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

For docs-only edits, also run a focused term check over this page, the core temporal page, and the feature index to confirm public names and deferred boundaries remain documented.
