# Temporal Complete Acceptance Matrix

This matrix is the closeout contract for the complete temporal library program. A category is complete when it has public APIs, docs, focused tests, deterministic data or fixtures when applicable, validation commands, and PR CI evidence.

| Category | Public surface | Required evidence | Track |
| --- | --- | --- | --- |
| Dependency/data packaging | vendored ICU/CLDR, iCalendar library, holiday data metadata | manifest/layout foundation, no-network validator, CMake/CTest registration, version/license/source/checksum docs before source/data import | Dependency and data packaging foundation |
| Provider registry | `Temporal.providers` | manifest validation tests, deterministic ordering tests, no-network invariant docs, fast-suite registration | Provider/plugin registry |
| RFC5545 recurrence | `Temporal.recurrence` | standard RRULE examples, full selector tests, sub-daily tests, candidate-set ordering and `BYSETPOS` tests, invalid-rule diagnostics, focused recurrence suite, existing natural recurrence regression suite, fast-suite registration, PR CI | Full RFC5545 recurrence engine |
| Recurrence sets and zoned expansion | `Temporal.recurrence-set` | RDATE, EXDATE, and EXRULE focused tests; duplicate dedupe and exclusion-precedence tests; explicit `:zone-id` rejection tests; DST gap/overlap `:reject`, `:earliest`, and `:latest` policy tests; compact UTC `UNTIL` zoned recurrence-set tests; standalone `Temporal.recurrence.occurrences` UTC `UNTIL` rejection regression; focused recurrence-set suite; existing RFC5545 recurrence regression suite; constraints gate; broader local `make test`; PR CI | Recurrence sets and explicit-zone/DST expansion |
| ISO intervals | `Temporal.interval`, `Temporal.repeating-interval` | Track 6 grammar tests for `start/end`, `start/P...`, `P.../end`, `start/PT...`, and `PT.../end`; instant, plain date-time, and explicit bracketed-IANA zoned interval tests; half-open invariant tests; exact-duration versus calendar-period repeat-step tests; DST `:disambiguation` tests; final acceptance smoke in `tests.test-temporal-intervals`; compile, constraints, focused interval suite, broader `make test`, and PR CI | Full ISO intervals and repeating intervals |
| ICS/iCalendar | `Temporal.ics` | selected-corpus fixture corpus, parse/export round trips, VTIMEZONE metadata tests, override/cancellation tests, invalid ICS diagnostics, focused `tests.test-temporal-ics` suite, constraints gate, and PR CI requirement | ICS/iCalendar interoperability |
| Localization and calendars | `Temporal.localization`, `Temporal.calendar` | selected CLDR seed packaging tests with `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q`; Space Fennel compile check; `make constraints`; focused `tests.test-temporal-calendar` conversion suite; focused `tests.test-temporal-localization` format/parse suite | ICU/CLDR localization and non-Gregorian calendars |
| Business calendars | `Temporal.business-calendar`, `Temporal.providers.business-calendar` | packaged `US-FED` holiday seed validator tests; Space Fennel compile check; `make constraints`; focused `tests.test-temporal-business-calendar` loader/facade suite; focused `tests.test-temporal-provider-registry` dispatcher coverage; fast-suite registration | Business and holiday calendars |
| Natural language | `Temporal.natural`, `Temporal.providers.parse` | packaged `natural-phrase-seed` corpus validator tests; candidate schema/order tests; `en-US`, `fr-FR`, and `ja-JP` phrase tests; ambiguity and missing-context diagnostics; provider integration coverage; fast-suite registration | Broad natural-language parsing |
| Timestamp migrations | `Temporal.migrations` and workflow persistence call sites | schema inventory, canonical persisted timestamp docs, idempotent migration tests, malformed-data diagnostics, dry-run coverage, workflow JSON write/read integration | Persisted timestamp migrations |
| Runtime scheduler | `RuntimeScheduler` and timer compatibility APIs | fixed-clock tests, recurrence scheduling tests, cancellation/lifecycle tests, host pause/step tests, `RuntimeTimers` compatibility tests, Space Fennel compile check, constraints gate, focused scheduler/timer/host suites, broader `make test`, and PR CI | Runtime timer and scheduler redesign |
| Final closeout | all temporal surfaces | `tests.test-temporal-closeout` cross-surface smoke suite, ecosystem-gap docs audit, focused suites when relevant, full `make test`, PR CI and merge queue | Final conformance and closeout |

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

## Track 9 business-calendar acceptance evidence

The business and holiday calendars track is accepted locally when these commands
pass in order:

```bash
make fennel-check
make constraints
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-business-calendar:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-provider-registry:main
```

The focused business-calendar suite covers the packaged `US-FED` 2026-2027 seed,
defensive loader/facade return values, observed holidays, weekend exclusion,
zero/positive/negative business-day addition, half-open business-day counts, and
loud failures for unsupported data or invalid options.

## Track 10 natural-language acceptance evidence

The broad natural-language parsing track is accepted locally when these commands
pass in order:

```bash
make fennel-check
make constraints
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-natural-language:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-provider-registry:main
```

The focused natural-language suite covers the packaged `en-US`, `fr-FR`, and
`ja-JP` seed corpus, candidate schema fields, unambiguous English compatibility,
bare weekday ambiguity, unsupported locale/option diagnostics, and missing
resolve context. The provider-registry suite covers default built-in provider
registration, provider id preservation, deterministic candidate order, and empty
arrays for unsupported natural text.

## Track 11 persisted timestamp migration acceptance evidence

The persisted timestamp migrations track is accepted locally when these commands
pass in order:

```bash
make build
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-migrations:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-workflow-runner:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

The focused migration suite covers `Temporal.migrations` conversions, canonical
string round trips, legacy integer epoch seconds, optional nil handling,
dry-run/no-write behavior, idempotent file rewrites, malformed-data diagnostics,
and nested workflow-run schema fields. The workflow runner suite covers the
integrated `workflows/definitions` and run persistence call sites that write
canonical UTC strings while preserving numeric epoch seconds in memory.

## Track 12 runtime scheduler acceptance evidence

The runtime timer and scheduler redesign track is accepted locally when these
commands pass in order:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-runtime-scheduler:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-runtime-timers:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-app-host-services:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-standalone-app-runtime:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

The focused runtime scheduler suite covers fixed-clock/manual advance,
one-shot/interval catch-up, deterministic deadline ordering, recurrence
`:zone-id` requirements, recurrence callback payloads, cancellation, clear/drop,
unknown legacy-key rejection, and callback error propagation. The compatibility
and host suites cover `RuntimeTimers` millisecond wrapper behavior, typed host
scheduler delegation, pause, and explicit step semantics.

## Track 13 final closeout acceptance evidence

The final conformance and closeout track is accepted locally when these commands pass in order:

```bash
make fennel-check
make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-closeout:main
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

The closeout suite is a cross-surface smoke test. It does not replace focused per-track suites; it proves that public exports, packaged deterministic data, representative integrations, and loud unsupported behavior remain wired together after the roadmap closes. PR CI and the merge queue remain the integration gate.

## Maintenance rule

After the closeout track lands, adding another locale, phrase, holiday jurisdiction, or client fixture updates this matrix's evidence corpus but does not reopen architecture unless the change requires a new public capability category.
