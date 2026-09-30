# Temporal Recurrence Set and Zoned Expansion Design

## Context

The temporal roadmap has completed the dependency/data foundation, provider
registry, and standalone RFC5545 `Temporal.recurrence` RRULE engine. The next
ordered track is recurrence sets plus explicit-zone and DST-aware expansion.

The existing `Temporal.recurrence` API deliberately expands a single normalized
RRULE from a caller-provided `PlainDateTime` `DTSTART`. It rejects recurrence-set
composition, explicit-zone expansion, and UTC/instant `UNTIL` because those
require a layer that can combine inclusion and exclusion sources and resolve
local candidates through an explicit timezone policy.

This track adds that layer as `Temporal.recurrence-set` while preserving the
roadmap invariants:

- no host-local timezone defaults;
- `Duration` remains exact nanoseconds-only and is not used for calendar policy;
- native temporal core stays independent from recurrence-set, ICS, provider,
  localization, and scheduler policy;
- canonical option keys only;
- unsupported semantics fail loudly.

## Goals

- Add a public `Temporal.recurrence-set` namespace for finite recurrence-set
  assembly and explicit-zone expansion.
- Support local inclusion sources from multiple RRULEs and RDATEs.
- Support exclusions from EXDATEs and EXRULEs, with exclusions winning over
  inclusions.
- Deduplicate and sort the final included occurrences deterministically.
- Require an explicit IANA `:zone-id` for expansion and return typed
  `ZonedDateTime` values.
- Use existing core disambiguation policies for DST gaps and overlaps:
  `:reject`, `:earliest`, and `:latest`, defaulting to `:reject`.
- Support compact UTC `UNTIL=YYYYMMDDTHHMMSSZ` in recurrence-set expansion by
  comparing resolved candidate instants against the explicit UTC bound.
- Keep standalone `Temporal.recurrence.occurrences` `PlainDateTime`-only and
  unchanged for callers.
- Document the new API, boundaries, and validation evidence in temporal docs and
  the acceptance matrix.

## Non-goals

- Do not implement ICS/VEVENT parsing or serialization, `VTIMEZONE`, recurrence
  overrides, cancellations, all-day events, or client interoperability in this
  track.
- Do not import or bind libical for recurrence sets. The later ICS track may feed
  parsed records into this public facade.
- Do not add date-only RDATE/EXDATE values, fractional-second `UNTIL`, offset
  UNTIL forms other than compact UTC `Z`, or leap-second support.
- Do not add host-local timezone fallback or output-mode switches.
- Do not change exact `Duration`, calendar period, localization, business
  calendar, natural-language, migration, or runtime scheduler behavior.

## Considered approaches

### Approach A: New Fennel `Temporal.recurrence-set` facade

This is selected. A focused Fennel module composes the existing
`Temporal.recurrence` RRULE primitive, local inclusion/exclusion dates, and
`Temporal.zoned-date-time.from-plain` conversion. It owns recurrence-set policy
while leaving native core responsible only for primitive timezone conversion.

This matches the roadmap's named facade, preserves the clean output contract of
`Temporal.recurrence.occurrences`, and gives the future ICS adapter a stable
record shape to target.

### Approach B: Extend `Temporal.recurrence` with set and zone options

This is rejected. It would make `Temporal.recurrence.occurrences` context
dependent: sometimes returning `PlainDateTime`, sometimes returning zoned values,
and sometimes applying inclusion/exclusion sources. That blurs the documented
boundary between standalone RRULE expansion and recurrence-set policy.

### Approach C: Wait for libical or the ICS adapter

This is rejected for this track. Recurrence-set assembly can be implemented over
the existing rule engine and core timezone primitives without prematurely
deciding `VEVENT`, `VTIMEZONE`, property parameter, memory-management, or
third-party adapter shapes. Standards adapter work remains appropriate for the
later ICS/iCalendar track.

## Public API

Add `Temporal.recurrence-set` with two functions:

```fennel
(local set
  (Temporal.recurrence-set.from
    {:dtstart (Temporal.plain-date-time.parse "2026-03-06T01:30:00")
     :rrules [(Temporal.recurrence.parse-rrule "RRULE:FREQ=DAILY;COUNT=3")]
     :rdates [(Temporal.plain-date-time.parse "2026-03-10T01:30:00")]
     :exdates [(Temporal.plain-date-time.parse "2026-03-07T01:30:00")]
     :exrules [(Temporal.recurrence.parse-rrule "RRULE:FREQ=WEEKLY;COUNT=1")]}))

(Temporal.recurrence-set.occurrences set
  {:zone-id "America/New_York"
   :disambiguation :earliest
   :limit 10})
```

Constructor keys are canonical and exact:

- `:dtstart` — required `PlainDateTime` start for RRULE and EXRULE expansion.
- `:rrules` — optional list of normalized recurrence rules.
- `:rdates` — optional list of local `PlainDateTime` inclusion dates.
- `:exdates` — optional list of local `PlainDateTime` exclusion dates.
- `:exrules` — optional list of normalized recurrence rules used as exclusions.

No singular aliases such as `:rrule`, no `:start`, and no raw ICS property text
are accepted.

Expansion options are canonical and exact:

- `:zone-id` — required IANA timezone id.
- `:disambiguation` — optional DST policy, defaulting to `:reject`; accepted
  values are `:reject`, `:earliest`, and `:latest`.
- `:limit` — optional maximum number of returned zoned occurrences.

`Temporal.recurrence-set.occurrences` returns an ordered vector of
`ZonedDateTime` values. Callers needing instants can use the existing
`ZonedDateTime` instant accessors; this API does not add output-mode switches.

## Semantics

### Inclusion and exclusion

A recurrence set must have at least one inclusion source: a non-empty `:rrules`
list or a non-empty `:rdates` list. `:dtstart` is required even for RDATE-only
sets so later ICS and scheduler layers have one consistent anchor shape.

For local set assembly:

1. Expand each RRULE from `:dtstart` using the standalone recurrence engine.
2. Add each `:rdates` value.
3. Expand each EXRULE from `:dtstart`.
4. Add each `:exdates` value.
5. Deduplicate local inclusion candidates.
6. Remove any candidate whose local `PlainDateTime` matches an exclusion.
7. Sort by local plain date-time before zone conversion.

Exclusions win over inclusions. Duplicate inclusion dates collapse to one result.
`options.limit` caps the number of returned occurrences after exclusions; it does
not require backfilling additional generated instances after exclusions remove
some candidates.

### Bounds and finite expansion

Expansion must be finite. A set is finite when every recurrence rule and
exclusion rule has its own finite bound (`COUNT`, compact local `UNTIL`, or
compact UTC `UNTIL` under this recurrence-set API) or when the caller supplies
`:limit`.

Unbounded sets throw with diagnostics that mention the missing finite bounds.
Empty result sets are allowed when exclusions remove all included occurrences.

### Explicit zone and DST policy

Expansion requires `options.zone-id`. There is no host-local default and no
fallback to UTC.

Each surviving local candidate is converted through
`Temporal.zoned-date-time.from-plain candidate zone-id {:disambiguation policy}`.
The default `:reject` policy throws on DST gaps and overlaps. `:earliest` and
`:latest` opt into the core behavior documented by the temporal core API.

The returned order is by resolved instant after zone conversion, with local
plain-date-time order as a deterministic tie-breaker for any equivalent instants.

### UTC UNTIL support

Standalone `Temporal.recurrence.occurrences` remains `PlainDateTime`-only and
continues to reject compact UTC `UNTIL` values.

`Temporal.recurrence-set.occurrences` supports compact UTC
`UNTIL=YYYYMMDDTHHMMSSZ` because it requires an explicit zone. For each candidate
from a UTC-UNTIL rule, the set layer resolves the local candidate through the
explicit zone and disambiguation policy, then includes it only when the resolved
instant is less than or equal to the parsed UTC `UNTIL` instant.

Unsupported `UNTIL` forms, including date-only, fractional, and non-compact
offset forms, continue to fail loudly.

## Module boundaries

- `assets/lua/temporal/recurrence-set.fnl` owns validation, set assembly,
  deduplication, sorting, exclusion semantics, explicit-zone conversion, and UTC
  `UNTIL` filtering.
- `assets/lua/temporal.fnl` exports the new namespace.
- `assets/lua/temporal/recurrence/rule.fnl` may expose or normalize enough UTC
  `UNTIL` metadata for the set layer, but standalone recurrence expansion must
  keep rejecting UTC `UNTIL` without an explicit zone.
- Native C++ temporal core should not change for this track unless an existing
  primitive binding bug blocks zoned conversion tests.
- Future `Temporal.ics` can parse ICS properties into this recurrence-set record
  shape without changing the core set semantics.

## Diagnostics

Errors must identify the rejected key or semantic boundary where practical:

- unknown constructor or expansion option keys;
- invalid list shapes for `:rrules`, `:rdates`, `:exrules`, or `:exdates`;
- missing `:dtstart`;
- missing `:zone-id`;
- missing inclusion sources;
- unbounded recurrence-set expansion;
- invalid disambiguation policy;
- unsupported date-only/fractional/offset `UNTIL` forms;
- DST gap or overlap when using `:reject`.

## Documentation and acceptance

Update `docs/dev/features/temporal-parsing-recurrence.md` to describe
`Temporal.recurrence-set`, recurrence-set examples, explicit-zone expansion,
DST policy, UTC `UNTIL`, and remaining ICS boundaries.

Update `docs/dev/features/temporal-complete-acceptance.md` after implementation
with the concrete focused test and validation evidence for the recurrence sets
and zoned expansion row.

If useful, update `docs/dev/features/temporal-complete-library.md` status notes
to record that this track has landed once the PR merges.

## Testing strategy

- Add focused Fennel tests for `Temporal.recurrence-set` and register them in the
  fast suite.
- Preserve all existing recurrence and natural recurrence tests.
- Cover constructor validation, unknown keys, required `:dtstart`, required
  `:zone-id`, required inclusion sources, and invalid disambiguation.
- Cover RRULE plus RDATE union, duplicate inclusion dedupe, EXDATE removal,
  EXRULE removal, exclusions winning over inclusions, multiple RRULE ordering,
  empty results after exclusions, and bounded/unbounded behavior.
- Cover output values as `ZonedDateTime` and verify explicit zone behavior without
  host-local fallback.
- Cover DST overlaps and gaps for `:reject`, `:earliest`, and `:latest` using an
  explicit IANA zone such as `America/New_York`.
- Cover compact local `UNTIL` and compact UTC `UNTIL` in recurrence-set expansion.
- Run the Space Fennel validation ladder: touched-file compile check, constraints,
  focused recurrence-set tests, existing recurrence-focused tests, and broader
  suite when finishing the branch.

## Acceptance criteria

- `Temporal.recurrence-set.from` and `Temporal.recurrence-set.occurrences` are
  exported from the public temporal facade.
- Recurrence-set inclusion, exclusion, deduplication, sorting, and bounded
  expansion semantics match this spec.
- Expansion requires explicit `:zone-id` and returns typed `ZonedDateTime` values.
- DST gap/overlap behavior is governed only by explicit `:disambiguation`, with
  `:reject` as the default.
- Compact UTC `UNTIL` works only in recurrence-set zoned expansion and standalone
  `Temporal.recurrence.occurrences` remains unchanged.
- Unsupported ICS, VTIMEZONE, date-only RDATE/EXDATE, fractional `UNTIL`, offset
  `UNTIL`, leap seconds, host-local defaults, and scheduler behavior fail loudly
  or remain out of scope.
- Focused tests, Fennel compile checks, constraints, broader validation, PR CI,
  and merge queue pass.
