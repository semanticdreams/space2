# Temporal Localization and Calendar Seed

Space ships a deterministic `cldr-seed` corpus for the first public
`Temporal.calendar` and `Temporal.localization` facades. This slice supports a
small, exact CLDR 46-derived locale/calendar corpus from checked-in JSON under
`assets/temporal/icu/cldr-seed/`; it does not enable the native ICU4C adapter or
import full generated CLDR data.

## Public APIs

The public `Temporal` module exposes two seed-backed namespaces:

- `Temporal.calendar.supported-calendars()` returns the exact supported calendar
  ids sorted lexically.
- `Temporal.calendar.from-iso(plain-date-time, {:calendar "japanese"})` converts
  an ISO proleptic Gregorian `PlainDateTime` into a calendar field record.
- `Temporal.calendar.to-iso(calendar-fields)` converts a validated calendar field
  record back to a `PlainDateTime`.
- `Temporal.localization.supported-locales()` returns the exact supported locale
  ids sorted lexically.
- `Temporal.localization.supported-combinations()` returns supported
  `:locale`/`:calendar`/`:date-style` rows.
- `Temporal.localization.format-plain-date-time(plain-date-time, options)` formats
  only an exact supported combination.
- `Temporal.localization.parse-plain-date-time(text, options)` parses only exact
  text emitted by the selected seed pattern and returns a midnight
  `PlainDateTime`.

Option keys are canonical only. Unknown options, unknown calendar field keys,
unsupported locales, unsupported calendars, unsupported combinations,
unsupported styles, malformed localized text, invalid month names, invalid eras,
and out-of-range Japanese era dates fail loudly.

## Supported seed corpus

The initial locale ids are exactly `en-US`, `fr-FR`, and `ja-JP`. The initial
calendar ids are exactly `gregory`, `buddhist`, and `japanese`. Supported
`:date-style` values are exactly `:short` and `:long`, and locale ids are exact
and case-sensitive.

| Locale | Calendar | Date style | Pattern | Example for 2026-10-01 |
| --- | --- | --- | --- | --- |
| `en-US` | `gregory` | `:short` | `MM/DD/YYYY` | `10/01/2026` |
| `en-US` | `gregory` | `:long` | `Month D, YYYY` | `October 1, 2026` |
| `fr-FR` | `gregory` | `:short` | `DD/MM/YYYY` | `01/10/2026` |
| `fr-FR` | `gregory` | `:long` | `D month YYYY` | `1 octobre 2026` |
| `ja-JP` | `gregory` | `:short` | `YYYY/MM/DD` | `2026/10/01` |
| `ja-JP` | `gregory` | `:long` | `YYYY年M月D日` | `2026年10月1日` |
| `en-US` | `buddhist` | `:short` | `MM/DD/YYYY BE` | `10/01/2569 BE` |
| `en-US` | `buddhist` | `:long` | `Month D, YYYY BE` | `October 1, 2569 BE` |
| `ja-JP` | `japanese` | `:short` | `era-code year/MM/DD` | `R8/10/01` |
| `ja-JP` | `japanese` | `:long` | `era-name year年M月D日` | `令和8年10月1日` |

The built-in seed corpus provider identity is `space.temporal.cldr-seed`.

## Calendar conversion rules

Calendar conversion is presentation-oriented and separate from exact `Duration`
and `Temporal.period` arithmetic. The ISO `PlainDateTime` fields remain the
source of truth for time-of-day precision.

- `gregory` uses era `ce` with the same year, month, and day as ISO.
- `buddhist` uses era `be` with calendar year equal to ISO year plus `543`.
- `japanese` supports only the finite seed era corpus: Showa from
  `1926-12-25` through `1989-01-07`, Heisei from `1989-01-08` through
  `2019-04-30`, and Reiwa from `2019-05-01` onward.

`Temporal.calendar.to-iso` accepts only calendar field records with keys
`:kind`, `:calendar`, `:era`, `:year`, `:month`, `:day`, `:hour`, `:minute`,
`:second`, and `:nanosecond`. Japanese reverse conversion validates that era and
date fields are consistent with the supported era boundaries.

## Localization format and parse rules

Localization delegates calendar conversion to `Temporal.calendar` and formats or
parses only token patterns from `locales.json`. Parsing is exact: it consumes the
entire input, accepts only seed month and era strings, and does not perform
locale negotiation, fallback, numbering-system substitution, relative-time
formatting, range formatting, localized timezone names, or natural-language date
parsing.

## Packaged data and no-network behavior

The selected CLDR seed is packaged under `assets/temporal/icu/cldr-seed/` with:

- `manifest.json` for provenance, supported lists, file list, and no-network
  metadata.
- `calendars.json` for finite calendar era/conversion data.
- `locales.json` for exact locale/calendar/style token data.

The seed is a hand-curated selected subset derived from CLDR 46 date patterns,
month names, and era identifiers under the Unicode License v3. Runtime
localization and calendar conversion do not fetch network data.

## Native ICU4C adapter boundary

The full ICU4C/native adapter remains future work. This slice does not vendor
ICU4C source, does not import full generated CLDR data, does not add a native
`temporal_localization` adapter or C++ bindings, and does not enable
`SPACE_TEMPORAL_ENABLE_ICU_ADAPTER`. The native temporal core remains
independent from ICU/CLDR presentation and provider policy.

## Validation commands

Use the focused localization/calendar validation ladder when changing this
surface:

```bash
make fennel-check
make constraints
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-calendar:main
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_ASSETS_PATH=$(pwd)/assets \
FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
./build/space -m tests.test-temporal-localization:main
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
```

For docs-only edits, validate references with the focused `rg` commands from the
task brief.
