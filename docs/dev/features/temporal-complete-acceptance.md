# Temporal Complete Acceptance Matrix

This matrix is the closeout contract for the complete temporal library program. A category is complete when it has public APIs, docs, focused tests, deterministic data or fixtures when applicable, validation commands, and PR CI evidence.

| Category | Public surface | Required evidence | Track |
| --- | --- | --- | --- |
| Dependency/data packaging | vendored ICU/CLDR, iCalendar library, holiday data metadata | manifest/layout foundation, no-network validator, CMake/CTest registration, version/license/source/checksum docs before source/data import | Dependency and data packaging foundation |
| Provider registry | `Temporal.providers` | manifest validation tests, deterministic ordering tests, no-network invariant docs, fast-suite registration | Provider/plugin registry |
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
