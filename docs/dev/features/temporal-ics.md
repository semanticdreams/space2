# Temporal ICS/iCalendar

`Temporal.ics` is the selected-corpus iCalendar facade for `VCALENDAR` files containing supported `VEVENT` records. It is implemented in Space Fennel above the temporal core, recurrence, recurrence-set, period, and interval layers. The native temporal core stays independent from ICS grammar, provider policy, calendar-client quirks, and scheduler behavior.

## Public API

Load the public temporal module and use the `ics` namespace:

```fennel
(local Temporal (require :temporal))

(local calendar (Temporal.ics.parse ics-text))
(local formatted (Temporal.ics.format calendar {:line-ending :crlf}))
(local occurrences (Temporal.ics.expand calendar {:zone-id "America/New_York"
                                                 :limit 32
                                                 :disambiguation :reject}))
```

Canonical option keys only are accepted. For parsing, `:unknown-property-policy` may be `:reject` or `:preserve`. For formatting, `:line-ending` may be `:crlf` or `:lf`. For expansion, floating events require `:zone-id`; `:limit` bounds unbounded recurrence; and `:disambiguation` selects the temporal core DST policy. Aliases such as `:timezone`, `:tz`, `:ics-text`, `:ical`, or `:newline` are rejected.

## Supported corpus

The supported selected-corpus shape is `VCALENDAR` with `VERSION:2.0`, canonical `:prod-id`, optional `CALSCALE:GREGORIAN`, optional preserved `VTIMEZONE` metadata, optional preserved calendar `X-...` properties under `{:unknown-property-policy :preserve}`, and `VEVENT` records using the properties covered by the fixture suite. `UID` and `DTSTART` are required. Event records include `:source-order` from the parsed component. `STATUS` defaults to confirmed, and unsupported statuses fail loudly. Unsupported components, unsupported properties under strict parsing, unsupported parameters on supported non-date-time properties, invalid date-time parameter combinations, non-IANA `TZID` values, and malformed date/time or duration values throw explicit errors.

The fixture corpus covers single UTC, floating, zoned, all-day, multi-day all-day, duration, recurrence, `RDATE`, `EXDATE`, `EXRULE`, UTC `UNTIL`, overrides, cancellations, folded lines, and escaped text records.

## Value modes

`Temporal.ics` preserves the difference between date-only and date-time values:

- `VALUE=DATE` is an all-day calendar date and remains calendar data, not an exact `Duration`.
- UTC date-times carry an exact `Instant`.
- Floating date-times carry a `PlainDateTime` and require caller-supplied `:zone-id` only when expansion needs a concrete zone.
- Zoned date-times carry local fields plus an explicit IANA `TZID` resolved through Space tzdb.

`DTEND` and `DURATION` are mutually exclusive. Exact durations remain nanoseconds-only for timed events, while all-day duration values use calendar periods.

## Recurrence, overrides, and cancellations

Expansion delegates recurrence selection to `Temporal.recurrence` and recurrence-set assembly to `Temporal.recurrence-set`. `RRULE`, `RDATE`, `EXDATE`, and `EXRULE` records are combined with duplicate de-duplication and exclusion precedence. Unbounded recurrence requires `:limit`.

Recurring event overrides match by `UID` and `RECURRENCE-ID`. Cancelled masters produce no occurrences, cancelled overrides remove their target occurrence, duplicate masters or duplicate overrides fail loudly, and override `RECURRENCE-ID` value modes must match the master `DTSTART` mode.

## Formatting contract

Formatting emits canonical `VCALENDAR` text for the supported event model. `:line-ending` defaults to `:crlf`, `:lf` is accepted for tests and fixtures, and long content lines are folded. Parser-supported event properties are emitted in deterministic order. Constructed calendar records use `:prod-id`; legacy `:prodid` is rejected. Preserved properties remain context-validated, unknown constructed record keys are rejected during format and expansion, and constructed or inconsistent `VTIMEZONE` records are rejected rather than guessed.

Round trips are guaranteed for the selected fixture corpus, not for arbitrary calendar-client output.

## VTIMEZONE and libical boundary

`VTIMEZONE` is metadata-only in this selected-corpus facade. Space tzdb resolves IANA `TZID` values; custom `VTIMEZONE` observance evaluation is unsupported. A `VTIMEZONE` block may be preserved with its raw lines and formatted back when it is consistent with the event `TZID`, but it does not override Space tzdb rules.

libical remains the future conformance-expansion gate. The dependency manifest for `external/temporal/libical` deliberately remains `"status": "planned"`; this track does not vendor libical, import its source, or enable a native iCalendar adapter.

## Non-goals

- Full RFC5545/iTIP/iMIP conformance.
- Evaluation of custom `VTIMEZONE` observances.
- Calendar-client compatibility quirks outside the fixture corpus.
- Network fetching during parse, export, or expansion.
- Host-local timezone defaults.
- Native `temporal_ical` adapter enablement.
- Scheduler policy, alarms, attendees, tasks, journals, free/busy, or localization.

## Validation

Task-local validation for this selected-corpus track uses docs search, touched-file Fennel compile check, constraints, and the focused ICS suite:

```bash
rg "Temporal\.ics|temporal-ics|libical remains|selected-corpus|VTIMEZONE" \
  docs/dev/features/temporal-ics.md \
  docs/dev/features/temporal.md \
  docs/dev/features/temporal-complete-acceptance.md \
  docs/dev/features/temporal-complete-library.md
./build/space -m tools.fennel-check:main -- --target files \
  --file assets/lua/tests/test-temporal-ics.fnl
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-ics:main
```
