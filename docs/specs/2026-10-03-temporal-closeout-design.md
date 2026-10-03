# Track 13 Temporal Closeout Design

## Summary

Track 13 closes the current Space temporal roadmap as a bounded conformance and documentation closeout. It does not attempt to implement every feature needed for ecosystem-equivalent breadth with Rust, Go, Python, JavaScript, ICU, libical, or full ISO/RFC conformance suites.

The track adds final cross-surface smoke coverage for the temporal APIs already landed in Tracks 1-12, updates the roadmap and acceptance matrix to mark the Space roadmap closed, and documents the remaining gaps required for a broadly ecosystem-equivalent temporal library.

## Product Positioning

After Track 13, Space may claim that its **planned bounded temporal roadmap** is complete: public APIs are documented, supported behavior has tests, deterministic seed data is packaged where needed, unsupported behavior fails loudly, and extension paths exist.

Space must not claim full ecosystem-equivalent temporal breadth. Mature ecosystem libraries offer far larger conformance/data surfaces, including exhaustive ISO 8601 and RFC5545 behavior, broad ICU/CLDR locale and calendar coverage, many holiday jurisdictions, natural-language breadth, and calendar-client compatibility quirks. Track 13 documents those as future conformance and corpus expansion work rather than silently folding them into the closeout claim.

## Goals

- Add a final closeout smoke suite that exercises the already-supported public temporal surfaces together.
- Verify representative unsupported future surfaces still fail loudly rather than guessing behavior.
- Update the temporal roadmap and acceptance docs so Track 13 is closed with concrete validation evidence.
- Explicitly document what remains missing for ecosystem-equivalent temporal breadth.
- Preserve existing temporal invariants and public API boundaries.

## Non-Goals

- No full libical-backed native iCalendar adapter.
- No custom `VTIMEZONE` observance evaluation beyond the selected supported fixture behavior.
- No full ICU4C/native localization adapter or generated full CLDR data import.
- No broad locale/calendar corpus beyond the current selected seed.
- No holiday jurisdictions or years beyond the packaged business-calendar seed.
- No broad natural-language phrase families or locales beyond the current seed corpus.
- No non-workflow timestamp migration call-site integration.
- No exhaustive ISO 8601-1/-2 interval conformance, open intervals, date-only/all-day intervals, week-date or ordinal-date endpoints, offset-only zoned intervals, business-day intervals, natural-language intervals, or interval algebra.
- No host-local timezone fallback, implicit zone guessing, runtime network temporal data fetches, or native temporal core policy expansion.

## Existing Surfaces To Smoke

The closeout smoke suite should exercise shallow, compositional examples across:

- Native/Fennel core: `Temporal.duration`, `Temporal.instant`, `Temporal.plain-date-time`, `Temporal.zoned-date-time`, `Temporal.period`.
- Recurrence and schedule data: `Temporal.recurrence`, `Temporal.recurrence-set`.
- Intervals: `Temporal.interval`, `Temporal.repeating-interval`.
- Interchange and presentation: `Temporal.ics`, `Temporal.localization`, `Temporal.calendar`.
- Policy/data extensions: `Temporal.business-calendar`, `Temporal.natural`, `Temporal.providers`, `Temporal.migrations`.
- Runtime scheduling: `RuntimeScheduler` and compatibility wrappers where useful.

The suite is not a replacement for focused per-track tests. Its purpose is to catch broken exports, incompatible option shapes, missing packaged data, and cross-surface regressions that per-track suites can miss.

## Representative Loud-Failure Checks

Track 13 should keep broad future behavior explicitly unsupported. Representative closeout checks should cover a small sample of unsupported cases, such as:

- unsupported locale/calendar outside the seed corpus;
- unsupported business-calendar jurisdiction or year outside `US-FED` 2026-2027;
- unsupported natural-language locale or phrase outside the seed corpus;
- unsupported custom iCalendar/`VTIMEZONE` behavior;
- unsupported interval families deliberately left outside Track 6.

These checks should assert explicit errors or empty unsupported results according to the relevant module contract.

## Documentation Updates

`docs/dev/features/temporal-complete-library.md` should replace the remaining “Track 13 future work” language with a closed-roadmap status. It must preserve a visible section explaining that ecosystem-equivalent breadth remains future work.

`docs/dev/features/temporal-complete-acceptance.md` should add Track 13 acceptance evidence: closeout smoke suite, docs audit, focused temporal/runtime suites when relevant, full local `make test`, and PR CI/merge queue as the integration gate.

## Considered Approaches

### Option A: Documentation-only closeout

This would mark the roadmap complete without new tests. It is low risk and fast, but too weak for a final conformance track because it would not prove that the public surfaces still compose.

### Option B: Bounded smoke tests plus docs — selected

This adds a focused closeout suite and documentation updates while preserving the finite scope of Tracks 1-12. It proves the supported surfaces remain wired together, avoids scope explosion, and makes ecosystem-equivalent gaps explicit.

### Option C: Broad ecosystem-parity expansion

This would pursue full libical/ICU/CLDR/native adapters, broad locale and holiday corpora, natural-language breadth, complete migrations, and exhaustive standards conformance. It is closer to ecosystem parity, but it contradicts Track 13’s closeout role and would reopen multiple completed tracks. It should be treated as future roadmap work, not this track.

## Validation Strategy

Track 13 is Fennel-facing and closeout-oriented, so validation must follow the Space Fennel ladder:

1. `make fennel-check`
2. `make constraints`
3. focused `tests.test-temporal-closeout:main`
4. relevant focused temporal/runtime suites if implementation or review identifies interaction risk
5. broad `make test` because Track 13 is the final local closeout gate
6. PR CI and merge queue as the integration gate

Direct Fennel validation must use project-native tooling only, not system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`, `./build/space --compile`, or `./build/space -e`.

## Acceptance Criteria

- A dedicated closeout smoke suite exists and is registered in the fast suite.
- The smoke suite exercises every already-landed temporal capability category at least once through public APIs.
- Representative unsupported future cases still fail loudly or return documented unsupported results.
- Roadmap docs mark Track 13 closed without claiming ecosystem-equivalent parity.
- Docs explicitly list remaining gaps for ecosystem-equivalent breadth.
- Required validation passes in order and PR CI/merge queue is green.
