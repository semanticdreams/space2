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

`Temporal.providers` is the local deterministic provider registry used by temporal extension tracks. It validates in-process provider manifests, orders providers by priority and id, exposes defensive summaries, and provides natural-parse and business-calendar candidate dispatch. The built-in `space.temporal.natural-seed` natural-language provider and the business-calendar provider path are registered locally without network behavior.

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

The current implementation includes the documented temporal foundation, provider registry, standalone RFC5545 RRULE engine, `Temporal.recurrence-set` finite recurrence-set assembly with explicit-zone expansion, DST gap/overlap disambiguation, compact UTC `UNTIL` support under an explicit zone, Track 6 full ISO intervals through `Temporal.interval` and `Temporal.repeating-interval`, selected-corpus ICS/iCalendar interoperability through `Temporal.ics`, selected-corpus CLDR seed localization/calendar presentation through `Temporal.localization` and `Temporal.calendar`, Track 9 business/holiday calendars through `Temporal.business-calendar`, Track 10 deterministic natural-language candidates through `Temporal.natural` plus `Temporal.providers`, Track 11 persisted timestamp migrations through `Temporal.migrations` plus workflow store integration, and Track 12 runtime scheduling through `RuntimeScheduler` plus `RuntimeTimers` compatibility wrappers.

The interval surface supports concrete and derived `start/end`, `start/P...`, `P.../end`, `start/PT...`, and `PT.../end` forms for instant, plain date-time, and explicit bracketed-IANA zoned endpoints, while preserving exact-duration versus calendar-period repeating semantics and DST disambiguation policy. The ICS surface supports parsing, formatting, and expansion for supported `VCALENDAR`/`VEVENT` fixture records, including all-day, UTC, floating, zoned, recurrence, override, cancellation, folded-line, escaped-text, and metadata-only `VTIMEZONE` cases. The localization/calendar seed surface supports exactly the selected `en-US`, `fr-FR`, and `ja-JP` locale corpus, `gregory`, `buddhist`, and finite `japanese` calendars, and `:short`/`:long` date styles from packaged `cldr-seed` data. The business-calendar seed surface supports exactly `US-FED` observed holiday dates in calendar years `2026` and `2027`, ISO weekend weekdays `6` and `7`, defensive holiday lookup, predicates, whole-date business-day addition, half-open business-day counts, and explicit provider dispatch. The natural-language seed surface supports exactly the Track 10 seed corpus. The migration surface supports the canonical persisted timestamp representation, explicit `Temporal.migrations` helpers, `workflows/definitions` and workflow-run schema integration, dry-run file/tree migrations, idempotent rewrites, and malformed-data diagnostics; `agent-sessions`, `entities/code`, `llm/conversations`, and messages are inventory-only follow-up schema families.

Later tracks remain unsupported and must continue to fail loudly rather than silently guessing behavior, including broader ICS conformance, calendar-client quirks, libical-backed native adaptation, custom `VTIMEZONE` observance evaluation, full ICU4C/native `temporal_localization` adaptation, full generated CLDR data, broader locale/calendar coverage, business-calendar jurisdictions or years beyond the packaged `US-FED` 2026-2027 seed, natural-language phrase families/locales beyond the Track 10 seed, and non-workflow timestamp migration call-site integration. Track 6 also deliberately leaves exhaustive ISO 8601-1/-2 interval conformance, open intervals, date-only/all-day intervals, week-date or ordinal-date endpoints, offset-only zoned intervals, business-day intervals, natural-language intervals, interval algebra, and host-local or implicit zone fallback out of scope. Track 13 closeout adds cross-surface temporal smoke coverage and marks the bounded Space temporal roadmap complete. This is a roadmap-completion claim for the documented Space surfaces, not a claim of full ecosystem-equivalent temporal breadth.

## Ecosystem-equivalent gaps

Space's bounded temporal roadmap is complete after Track 13, but mature ecosystem temporal libraries still cover broader data and conformance surfaces. The following remain future conformance or corpus-expansion work:

- exhaustive ISO 8601-1/-2 interval conformance, including open intervals, date-only/all-day intervals, week-date and ordinal-date endpoints, offset-only zoned intervals, business-day intervals, natural-language intervals, and interval algebra;
- broader RFC5545/iCalendar conformance, calendar-client quirks, libical-backed native adaptation, and custom `VTIMEZONE` observance evaluation;
- full ICU4C/native localization adaptation, generated CLDR data, and broader locale/calendar coverage;
- business-calendar jurisdictions and years beyond the packaged `US-FED` 2026-2027 seed;
- natural-language phrase families and locales beyond the Track 10 seed corpus;
- timestamp migration integration beyond workflow persistence call sites, including the inventory-only `agent-sessions`, `entities/code`, `llm/conversations`, and message families.

Unsupported inputs in these areas must continue to fail loudly or return documented unsupported results until a future reviewed track explicitly expands the surface.

The closeout evidence is tracked in [Temporal Complete Acceptance](./temporal-complete-acceptance).
