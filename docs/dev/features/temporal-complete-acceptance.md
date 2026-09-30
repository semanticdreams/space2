# Temporal Complete Acceptance Matrix

This matrix is the closeout contract for the complete temporal library program. A category is complete when it has public APIs, docs, focused tests, deterministic data or fixtures when applicable, validation commands, and PR CI evidence.

| Category | Public surface | Required evidence | Track |
| --- | --- | --- | --- |
| Dependency/data packaging | vendored ICU/CLDR, iCalendar library, holiday data metadata | manifest/layout foundation, no-network validator, CMake/CTest registration, version/license/source/checksum docs before source/data import | Dependency and data packaging foundation |
| Provider registry | `Temporal.providers` | manifest validation tests, deterministic ordering tests, no-network invariant docs, fast-suite registration | Provider/plugin registry |
| RFC5545 recurrence | `Temporal.recurrence` | standard RRULE examples, full selector tests, sub-daily tests, candidate-set ordering and `BYSETPOS` tests, invalid-rule diagnostics, focused recurrence suite, existing natural recurrence regression suite, fast-suite registration, PR CI | Full RFC5545 recurrence engine |
| Recurrence sets and zoned expansion | `Temporal.recurrence-set` | RDATE, EXDATE, and EXRULE focused tests; duplicate dedupe and exclusion-precedence tests; explicit `:zone-id` rejection tests; DST gap/overlap `:reject`, `:earliest`, and `:latest` policy tests; compact UTC `UNTIL` zoned recurrence-set tests; standalone `Temporal.recurrence.occurrences` UTC `UNTIL` rejection regression; focused recurrence-set suite; existing RFC5545 recurrence regression suite; constraints gate; broader local `make test`; PR CI | Recurrence sets and explicit-zone/DST expansion |
| ISO intervals | `Temporal.interval`, `Temporal.repeating-interval` | Track 6 grammar tests for `start/end`, `start/P...`, `P.../end`, `start/PT...`, and `PT.../end`; instant, plain date-time, and explicit bracketed-IANA zoned interval tests; half-open invariant tests; exact-duration versus calendar-period repeat-step tests; DST `:disambiguation` tests; final acceptance smoke in `tests.test-temporal-intervals`; compile, constraints, focused interval suite, broader `make test`, and PR CI | Full ISO intervals and repeating intervals |
| ICS/iCalendar | `Temporal.ics` | fixture corpus, parse/export round trips, VTIMEZONE tests, invalid ICS diagnostics | ICS/iCalendar interoperability |
| Localization and calendars | `Temporal.localization`, `Temporal.calendar` | ICU data packaging tests, locale parse/format tests, explicit calendar conversion tests | ICU/CLDR localization and non-Gregorian calendars |
| Business calendars | `Temporal.business-calendar` | holiday fixture tests, observed-holiday tests, business-day arithmetic tests | Business and holiday calendars |
| Natural language | `Temporal.natural` | locale phrase corpus, candidate/ambiguity tests, missing-context diagnostics | Broad natural-language parsing |
| Timestamp migrations | `Temporal.migrations` and persistence call sites | schema inventory, idempotent migration tests, malformed-data diagnostics | Persisted timestamp migrations |
| Runtime scheduler | `RuntimeScheduler` and timer compatibility APIs | fixed-clock tests, recurrence scheduling tests, cancellation/lifecycle tests | Runtime timer and scheduler redesign |
| Final closeout | all temporal surfaces | end-to-end smoke tests, docs audit, focused suites, full `make test`, PR CI | Final conformance and closeout |

## Validation ladder

Track-specific validation starts narrow and broadens with risk. Fennel-facing tracks run compile checks, constraints, focused tests, and broader suite when public behavior changes. Native/dependency/binding tracks run `make cmake` or `make build` as needed, focused CTests, Fennel validation, and the broader suite when integration risk is broad. Final closeout runs the complete local validation ladder and relies on PR CI as the integration gate.

## Track 6 ISO interval acceptance evidence

The full ISO intervals and repeating intervals track is accepted locally when these commands pass in order:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-intervals:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

The focused interval suite includes a final Track 6 smoke test that parses and formats instant `start/PT...`, plain date-time `start/P...`, concrete zoned `start/end`, rejects `P1D` for instant intervals, and verifies repeating calendar-period step semantics across a month-end clamp.

## Maintenance rule

After the closeout track lands, adding another locale, phrase, holiday jurisdiction, or client fixture updates this matrix's evidence corpus but does not reopen architecture unless the change requires a new public capability category.
