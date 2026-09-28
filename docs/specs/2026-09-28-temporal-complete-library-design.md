# Complete Temporal Library Design

## Purpose

Space's temporal library should become a complete production temporal platform, not only a deterministic core with deferred future layers. This design converts the existing deferred continuation map into an executable multi-PR program that can proceed autonomously without asking for one slice at a time.

"Nothing deferred" means every temporal capability category has a production API, documentation, focused tests, packaged deterministic data when needed, fixture or conformance coverage, and an extension path. Future additions of more locales, holiday jurisdictions, natural-language phrases, or client interoperability quirks are data/corpus expansion, not missing architecture.

## In Scope

The completion program includes all currently deferred temporal areas:

- Full RFC5545 recurrence semantics and candidate-set expansion.
- Recurrence sets with `RRULE`, `RDATE`, `EXRULE` where supported by the chosen standard layer, `EXDATE`, deduplication, sorting, and bounded expansion.
- Full ISO interval and repeating-interval grammar for supported temporal endpoint families.
- Timezone-aware and DST-aware recurrence, recurrence-set, interval, and scheduler behavior with explicit zone and disambiguation policy.
- Full ICS/iCalendar ingestion and export for calendar records, `VEVENT`, recurrence, recurrence overrides, cancellations, all-day events, floating/UTC/zoned times, and `VTIMEZONE` interop.
- ICU/CLDR-backed localization, localized parsing/formatting, and explicit non-Gregorian calendar conversion.
- Business and holiday calendars backed by deterministic packaged data.
- Broad deterministic natural-language parsing with locale/provider packs and explicit ambiguity handling.
- Parser/provider/plugin registry for local deterministic temporal providers.
- Persisted timestamp migrations from legacy timestamp shapes to canonical temporal representations.
- Runtime timer and scheduler redesign around typed temporal values, fixed clocks, exact durations, explicit-zone recurrence scheduling, cancellation, and lifecycle-safe handles.
- Final conformance and acceptance matrix tying every category to public docs, tests, fixtures, and validation commands.

## Explicit Non-Negotiable Invariants

- No API silently defaults to the host-local timezone. Zone-sensitive operations require explicit zone context.
- Exact `Duration` remains nanoseconds-only. Calendar periods, business days, months, years, and localized calendar arithmetic remain separate types/policies.
- The existing native temporal core remains the primitive semantic layer for `Instant`, `Duration`, `PlainDateTime`, `ZonedDateTime`, clock, and tzdb behavior. It must not absorb natural-language parsing, recurrence policy, ICU/CLDR presentation, holiday policy, provider loading, or scheduler product semantics.
- Higher-risk domains live in separate adapters and Fennel-facing modules: e.g. `temporal_ical`, `temporal_localization`, `Temporal.providers`, `Temporal.ics`, `Temporal.business-calendar`, `Temporal.natural`, `Temporal.migrations`, and `RuntimeScheduler`.
- Public APIs consume and produce typed temporal values or explicit structured records, not ambient Unix timestamp numbers.
- Errors are loud for invalid data, unsupported manifests, invalid locales/calendars/zones, missing packaged data, malformed ICS/RRULE/natural text, migration failures, and scheduler misuse.
- Canonical option keys only; no legacy aliases or compatibility shims except explicit persisted-data migrations.
- Runtime parsing/formatting/scheduling/migration must not perform network fetches. Third-party standards/data dependencies are pinned, reviewed, packaged, and tested.

## Dependency Strategy

Third-party dependencies are allowed when they are the best choice for standards correctness and long-term maintainability.

Recommended dependency choices:

- **ICU4C/CLDR** for locale data, localized formatting/parsing, and non-Gregorian calendar systems.
- **libical or an equivalent vetted iCalendar library** for RFC5545, ICS, `VEVENT`, and `VTIMEZONE` interoperability.
- **Checked-in deterministic holiday datasets** for initial business-calendar support, with source, license, version, checksum, jurisdiction list, and update process documented.
- **Local deterministic grammar/provider packs** for broad natural-language parsing. Natural parsing must not call network services or model APIs at parse time.

Every vendored dependency or data snapshot must include version, source URL, license, checksum or reproducible provenance, build/package instructions, and focused packaging tests.

## Architecture

### Native core boundary

The existing native core continues to own correctness-critical primitives and timezone database behavior. It may gain small primitive helpers only when required by standards interoperability, such as date-only or time-only primitives for full ISO interval and ICS semantics. Even then, grammar and product policy remain above the primitive layer.

### Standards adapters

Standards-heavy integrations are isolated in native adapter modules:

- `temporal_ical` owns libical interaction, memory management, diagnostics, RFC5545 recurrence expansion, and ICS component normalization.
- `temporal_localization` owns ICU interaction, locale/calendar availability, localized formatting/parsing, and packaged-data diagnostics.

Adapters expose typed Lua bindings and structured records. They do not leak raw third-party handles into Fennel application code.

### Fennel facades

Fennel modules own public option shapes, provider ordering, policy composition, and documentation-facing APIs:

- `Temporal.recurrence` remains the recurrence facade, delegating full RFC5545 semantics to the standards adapter while preserving existing API names where possible.
- `Temporal.recurrence-set` composes rule expansion, inclusion dates, exclusion dates, dedupe, sorting, range bounds, and explicit-zone behavior.
- `Temporal.interval` and `Temporal.repeating-interval` own ISO interval grammar policy while delegating primitive arithmetic to temporal values.
- `Temporal.ics` normalizes calendar/event records and connects ICS text to recurrence sets, intervals, zones, and typed values.
- `Temporal.localization` and `Temporal.calendar` expose ICU/CLDR capabilities with explicit locale/calendar arguments.
- `Temporal.business-calendar` exposes deterministic holiday/business-day policy separate from duration and period arithmetic.
- `Temporal.providers` registers local deterministic providers with manifest validation and stable priority ordering.
- `Temporal.natural` becomes provider-backed and returns candidate records with diagnostics instead of pretending ambiguous input has one answer.
- `Temporal.migrations` owns explicit persisted timestamp migrations.
- `RuntimeScheduler` owns typed runtime scheduling and compatibility shims for existing timer APIs.

## Acceptance Corpus Policy

Each category must ship with a finite initial production corpus:

- RFC5545/ICS: standard examples plus fixture files covering recurring events, all-day events, floating times, UTC times, zoned times, `VTIMEZONE`, overrides, cancellations, invalid inputs, and round trips against the selected library.
- Localization/calendars: approved initial locale and calendar list with ICU-backed round-trip expectations where supported.
- Holidays/business calendars: approved initial jurisdictions with source/version metadata and observed-holiday fixtures.
- Natural language: approved locale/phrase families with expected candidate records, ambiguity cases, and missing-context diagnostics.
- Migrations: inventory of persisted timestamp schemas and legacy examples.
- Scheduler: deterministic fixed-clock, monotonic/wall-clock, recurrence, catch-up, cancellation, and lifecycle fixtures.

The initial corpus is the completion target. Later corpus growth is normal maintenance, not deferred architecture.

## Program Tracks and Order

The program should proceed through PR-sized tracks, each with its own spec/plan when implementation begins:

1. **Roadmap documentation and acceptance contract** — developer-facing completion roadmap, links from current temporal docs, and explicit validation matrix skeleton.
2. **Dependency and data packaging foundation** — vendored ICU/CLDR, iCalendar library, holiday-data layout, CMake/package wiring, and packaging tests.
3. **Provider/plugin registry** — deterministic local provider registry and manifest validation.
4. **Full RFC5545 recurrence engine** — full RRULE parse/serialize/expand and conformance fixtures.
5. **Recurrence sets and explicit-zone/DST expansion** — RDATE/EXDATE/exclusion semantics and zoned expansion policy.
6. **Full ISO intervals and repeating intervals** — complete selected endpoint grammar, period/duration endpoints, zoned endpoints, and bounded expansion.
7. **ICS/iCalendar interoperability** — calendar/event parse/export, `VEVENT`, `VTIMEZONE`, overrides, cancellations, all-day/floating/zoned/UTC behavior.
8. **ICU/CLDR localization and non-Gregorian calendars** — localized formatting/parsing and explicit calendar conversion.
9. **Business and holiday calendars** — deterministic holiday datasets and business-day operations.
10. **Broad natural-language parsing** — provider-backed candidate generation across approved phrase families/locales.
11. **Persisted timestamp migrations** — schema inventory, migration helpers, load/save integration, and idempotent validation.
12. **Runtime timer and scheduler redesign** — typed scheduler service, recurrence scheduling, fixed-clock tests, cancellation/lifecycle semantics, and compatibility wrappers.
13. **Final conformance and closeout** — acceptance matrix, end-to-end smoke tests, docs audit, and final PR CI gate.

Tracks may be split further if review or validation risk is high. They should not be combined into a single mega-branch.

## Autonomy Contract

After this design and the corresponding implementation plan are committed and self-reviewed, the supervisor may continue autonomously through the program:

- create a PR-sized spec and plan for each track;
- execute implementation through implementer/reviewer loops;
- run required validation;
- push, open PRs, enable auto-merge/merge queue, and poll until merged;
- proceed to the next track after merge.

The supervisor must stop only for:

- semantic decisions not finite in this design or a track spec;
- dependency/data license incompatibility;
- inability to package deterministic data;
- unavailable credentials or infrastructure;
- unsafe git history actions such as rebase/force-push/reset;
- validation failure whose root cause cannot be established with available evidence;
- PR CI or merge-queue blockers requiring human access or product decisions;
- material scope change outside this completion program.

## Known Decisions Already Approved

- All previously deferred temporal categories are in scope.
- Third-party and vendored dependencies are acceptable when they are the best choice for standards correctness and maintainability.
- "Nothing deferred" means every category gets production architecture/API/docs/tests/data/fixtures/extension path; future corpus additions are maintenance.
- Existing invariants about explicit timezones and exact duration semantics remain binding.

## Decisions to Resolve Per Track

The umbrella program can proceed, but these finite choices must be resolved in the relevant track specs before implementation of those tracks:

- Initial supported locale list for localization and natural-language parsing.
- Initial non-Gregorian calendar list.
- Initial holiday jurisdictions and data source.
- iCalendar interoperability corpus and target clients.
- Persisted timestamp schema inventory and compatibility window.
- Scheduler catch-up semantics after sleep, pause, missed deadlines, and app lifecycle transitions.
- Plugin trust policy for local provider manifests.

These are not reasons to stop the umbrella roadmap. They are track-level spec gates.

## Validation Strategy

Each implementation track uses the narrowest meaningful local validation plus PR CI. Fennel-facing work follows the project-native ladder: compile check, constraints, focused tests, then broader suite when public behavior is broad. Native/CMake/binding/dependency work runs `make cmake` or `make build` as needed, focused CTests, Fennel compile/constraints/tests, and full `make test` when integration risk is broad. Final closeout runs the complete local validation ladder and relies on PR CI as the integration gate.
