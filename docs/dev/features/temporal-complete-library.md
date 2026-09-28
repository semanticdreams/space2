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

## Provider registry status

`Temporal.providers` is the local deterministic provider registry used by later temporal tracks. It validates in-process provider manifests, orders providers by priority and id, exposes defensive summaries, and provides natural-parse candidate dispatch. Concrete localization, calendar, business-calendar, and natural-language providers are added by later tracks.

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

The manifest and runtime data layout for these dependencies is defined in [Temporal Dependency/Data Packaging](../notes/temporal-dependency-data-packaging).

## Autonomy contract

After this roadmap and its plan are committed and reviewed, temporal implementation proceeds through PR-sized track specs and plans. The supervisor continues from track to track after each PR merges and stops only for semantic ambiguity not resolved by the active track spec, dependency or data license incompatibility, nondeterministic packaging, unavailable infrastructure, unsafe git history actions, validation failures without establishable root cause, PR CI or merge-queue blockers requiring human access, or material scope change.

## Track-level spec gates

Track specs must resolve the finite choices they introduce, including initial locale lists, non-Gregorian calendar lists, holiday jurisdictions and data source, iCalendar interoperability corpus, persisted timestamp schema inventory, scheduler catch-up semantics, and provider trust policy.

## Current implementation status

The current implementation remains the documented subset on the existing temporal pages until each track lands. Unsupported inputs must continue to fail loudly rather than silently guessing behavior.

The closeout evidence is tracked in [Temporal Complete Acceptance](./temporal-complete-acceptance).
