# Temporal Expression Reference-Instant Projection Design

## Summary

`Temporal.expression.context` will support contexts that provide an exact
`:reference-instant` instead of a civil `:reference-plain-date-time`. The instant
will be projected through the required explicit `:zone-id` to produce the civil
reference used by existing structured expression resolution.

This slice closes the existing deferred path where expression resolution throws
`reference instant resolution requires projection support`. It keeps the change
small: no new native API, no new public projection helper, no recurrence maturity,
and no broader natural-language parser behavior.

## Goals

- Allow `Temporal.expression.context` to accept either:
  - `{:reference-plain-date-time <plain> :zone-id <zone>}`, or
  - `{:reference-instant <instant> :zone-id <zone>}`.
- Project `:reference-instant` through the explicit `:zone-id` before resolving
  relative expressions.
- Preserve current result shapes: supported relative expressions still resolve to
  `{:kind :plain-date-time :value <plain-date-time>}`.
- Preserve current `:reference-plain-date-time` behavior and compatibility.
- Make invalid zones or invalid temporal values fail loudly through existing
  temporal-core behavior.
- Document that expression contexts never use a host-local timezone default.

## Non-Goals

- Adding a public `Temporal` helper for instant-to-plain-date-time projection.
- Adding a native C++ projection binding.
- Changing `Temporal.natural` parsing coverage.
- Adding monthly/yearly recurrence expansion or RFC5545 maturity.
- Adding zoned interval or DST-aware period arithmetic.
- Adding localization, ICU, CLDR, provider, or plugin behavior.

## Current Behavior

`assets/lua/temporal/expression.fnl` currently accepts both reference fields in
`context`, but `reference-plain-date-time` throws when only
`:reference-instant` exists. Existing expression tests use only
`:reference-plain-date-time`, so the deferred instant path is not covered by a
regression test.

The project already exposes the required projection building blocks:

1. `Temporal.zoned-date-time.from-instant instant zone-id` creates a zoned value
   using native timezone rules.
2. `zdt:fields()` returns projected local civil fields.
3. `Temporal.plain-date-time.from-fields fields` builds the civil reference used
   by existing expression resolution.

## Design

Projection will be private to `assets/lua/temporal/expression.fnl`.

When `Temporal.expression.context` receives a `:reference-instant`, it will:

1. Require `:zone-id` to be a string, as it does today.
2. Build a zoned date-time from the instant and zone.
3. Extract local civil fields from that zoned date-time.
4. Build the effective `:reference-plain-date-time` from those fields.
5. Store that effective plain date-time in the returned context.

If both `:reference-plain-date-time` and `:reference-instant` are supplied,
`:reference-plain-date-time` remains the effective reference. This avoids
surprising existing callers and keeps the compatibility rule explicit.

`Temporal.expression.resolve` will continue to operate on the effective plain
date-time reference. That keeps relative-date and next-weekday logic unchanged
after context normalization.

## Alternatives Considered

### A. Private projection inside expression context — chosen

This uses existing temporal-core bindings and keeps the public API unchanged. It
is the smallest slice that satisfies the user-facing behavior and avoids adding
abstractions before a second consumer needs them.

### B. Public Fennel projection helper

A public helper such as `Temporal.zoned-date-time.plain-date-time-from-instant`
could improve reuse later, but this slice has only one consumer. Adding a public
helper now would commit API surface before the broader zoning/DST design is
complete.

### C. Native C++ projection binding

A native method would duplicate behavior already available through
`ZonedDateTime::from_instant` and `fields`. It would increase binding surface
without improving correctness for this slice.

## Error Handling

- Missing or non-table context options remain errors.
- Missing or non-string `:zone-id` remains an error.
- Missing both reference forms remains an error.
- Invalid `:reference-instant`, invalid `:reference-plain-date-time`, or invalid
  zones propagate existing temporal-core errors.
- No fallback to host-local time is permitted.

## Testing

Add focused Fennel tests in `assets/lua/tests/test-temporal-parsing-recurrence.fnl`:

- A single instant near a UTC day boundary resolves `today` to different local
  dates in `America/New_York` and `Asia/Tokyo`.
- Existing plain-reference natural expression tests continue to pass unchanged.

Validation order for the implementation:

1. Touched-file `tools.fennel-check` for expression and test files.
2. `make constraints`.
3. Focused `tests.test-temporal-parsing-recurrence:main`.
4. Broader validation during final branch finishing.

## Documentation

Update `docs/dev/features/temporal-parsing-recurrence.md` to state that
`Temporal.expression.context` accepts either a plain date-time reference or an
instant reference, and that instant references are projected through the required
explicit zone id with no host-local timezone default.

## Acceptance Criteria

- `Temporal.expression.context {:reference-instant instant :zone-id
  "America/New_York"}` does not throw merely because projection is unsupported.
- The same instant can resolve to different civil dates in different explicit
  zones.
- Existing `:reference-plain-date-time` expression behavior remains unchanged.
- No new public temporal namespace/helper or native binding is added.
- Documentation describes the explicit-zone projection rule.
- Required focused validation passes before handoff, and final branch validation
  passes before integration.
