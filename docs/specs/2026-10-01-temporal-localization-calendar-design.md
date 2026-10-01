# Temporal Localization and Calendar Seed Design

## Context

The temporal roadmap has landed recurrence, recurrence sets, intervals, and
selected-corpus ICS/iCalendar interoperability. The next ordered roadmap track is
ICU/CLDR localization and non-Gregorian calendars. The repository already
reserves ICU/CLDR dependency and runtime data roots, but `ICU4C` source, full
generated CLDR data, and a native `temporal_localization` adapter are not yet
selected or vendored.

This slice is Track 8A: a PR-sized first localization/calendar slice that ships
public `Temporal.localization` and `Temporal.calendar` Fennel facades backed by a
deterministic checked-in CLDR seed corpus. It proves the API shape, packaging
contract, locale format/parse behavior, and explicit calendar conversion model
before importing ICU4C or enabling the native adapter.

## Non-negotiable invariants

- No host locale or host timezone defaults.
- Exact `Duration` remains nanoseconds-only.
- Localized calendars are separate from exact duration and period arithmetic.
- Native temporal core remains independent from ICU/CLDR presentation, provider
  policy, business calendars, natural language, and scheduler behavior.
- Runtime localization and calendar conversion do not fetch network data.
- Canonical option keys only; no aliases or compatibility shims.
- Unsupported locales, calendars, options, styles, eras, date ranges, and
  malformed localized text fail loudly.

## Goals

- Add public `Temporal.localization` and `Temporal.calendar` namespaces.
- Add deterministic packaged CLDR seed data under `assets/temporal/icu/` with
  provenance, supported-locale/calendar lists, and no-network validation.
- Update the ICU dependency manifest from `planned` to `packaged` for the seed
  data while keeping the ICU4C/native adapter follow-up gate explicit.
- Support a finite initial locale corpus: `en-US`, `fr-FR`, and `ja-JP`.
- Support a finite initial calendar corpus: `gregory`, `buddhist`, and
  `japanese`.
- Provide locale format/parse round trips for selected date styles.
- Provide explicit calendar conversion round trips between ISO `PlainDateTime`
  values and calendar field records.
- Document the CLDR seed boundary and keep full ICU4C/native adapter work as a
  later expansion.

## Non-goals

- Do not vendor ICU4C source in this slice.
- Do not enable `SPACE_TEMPORAL_ENABLE_ICU_ADAPTER`.
- Do not add a native `temporal_localization` adapter or C++ bindings.
- Do not import full generated CLDR data.
- Do not implement BCP47 locale negotiation, fallback chains, plural rules,
  range formatting, relative-time formatting, localized timezone names, or
  numbering-system substitution.
- Do not support lunar or algorithmically complex calendars such as Islamic,
  Hebrew, or Chinese calendars.
- Do not parse arbitrary natural-language dates; parsing is exact selected-format
  parsing for strings emitted by this API.
- Do not add business calendars, holiday calendars, natural-language providers,
  timestamp migrations, or scheduler behavior.

## Considered approaches

### Approach A: Vendor ICU4C and native adapter now

This is rejected for this slice. Full ICU4C introduces source selection,
checksums, license notices, data packaging mode, build-system changes, C++/Lua
bindings, and adapter API design in one PR. The existing CMake option is
reserved and intentionally hard-fails if enabled. A native adapter remains the
long-term expansion path after the public facade and selected corpus are proven.

### Approach B: Pure Fennel hardcoded locale/calendar tables

This is rejected as insufficient. It would prove some behavior but would not
satisfy the roadmap's deterministic data-packaging evidence. The selected corpus
must live under the temporal runtime data root and be validated as packaged data.

### Approach C: Packaged CLDR seed corpus with Fennel facades

This is selected. It adds real public behavior and acceptance tests while keeping
dependency risk bounded. The seed data is deterministic, checked in, documented,
and replaceable by a later ICU4C-backed provider/adapter without changing the
public API shape.

## Packaged data and manifests

Add seed data under:

```text
assets/temporal/icu/cldr-seed/
  manifest.json
  locales.json
  calendars.json
```

The seed manifest records:

- `schema_version: 1`
- `id: "cldr-seed"`
- `version: "CLDR-46-selected-seed"`
- `source_url: "https://unicode.org/Public/cldr/46/"`
- `license: "Unicode License v3"`
- `runtime_network_fetch_allowed: false`
- `supported_locales: ["en-US" "fr-FR" "ja-JP"]`
- `supported_calendars: ["gregory" "buddhist" "japanese"]`
- `reproducible_provenance`: a statement that the files are a hand-curated
  selected corpus derived from CLDR locale date patterns, month names, and era
  identifiers, with every supported value represented in focused tests.
- file list for `locales.json` and `calendars.json`.

Update `external/temporal/icu/DEPENDENCY_MANIFEST.json`:

- set `status` to `packaged` for the selected CLDR seed data;
- add `version`, `source_url`, `license`, and `reproducible_provenance`;
- keep `candidate: "ICU4C/CLDR"`;
- keep `adapter_boundary: "temporal_localization"`;
- keep `runtime.network_fetch_allowed: false`;
- update `follow_up_gate` to state that full ICU4C source, generated data,
  license notice handling, and adapter build strategy remain future work.

Update `assets/temporal/manifest.json` with a `packaged_data_sets` entry for the
CLDR seed corpus and expand manifest validation so packaged ICU seed files must
exist and keep network fetches disabled.

## Public API

### `Temporal.calendar`

Functions:

```fennel
(Temporal.calendar.supported-calendars)
(Temporal.calendar.from-iso plain-date-time {:calendar "japanese"})
(Temporal.calendar.to-iso calendar-fields)
```

Canonical option keys:

- `:calendar` — required for `from-iso`.

Calendar field record:

```fennel
{:kind :temporal-calendar-fields
 :calendar "japanese"
 :era "reiwa"
 :year 8
 :month 10
 :day 1
 :hour 9
 :minute 30
 :second 0
 :nanosecond 0}
```

Rules:

- `from-iso` accepts only a `PlainDateTime` value and explicit `:calendar`.
- `to-iso` accepts only canonical calendar field records.
- Unknown option keys and unknown record keys throw.
- Returned supported calendar ids are sorted deterministically.
- Calendar conversion preserves time fields exactly.
- `gregory` returns Gregorian fields with `:era "ce"` for positive years.
- `buddhist` returns `:era "be"` and `:year = iso-year + 543`.
- `japanese` supports finite era data for:
  - `showa`, from 1926-12-25 through 1989-01-07;
  - `heisei`, from 1989-01-08 through 2019-04-30;
  - `reiwa`, from 2019-05-01 onward.
- Japanese dates before 1926-12-25 throw a clear unsupported-era-range error.
- `to-iso` validates era/date consistency; for example, `{:era "reiwa" :year 1
  :month 4 :day 30}` throws because Reiwa began on 2019-05-01.

### `Temporal.localization`

Functions:

```fennel
(Temporal.localization.supported-locales)
(Temporal.localization.supported-combinations)
(Temporal.localization.format-plain-date-time plain-date-time
  {:locale "fr-FR" :calendar "gregory" :date-style :long})
(Temporal.localization.parse-plain-date-time text
  {:locale "fr-FR" :calendar "gregory" :date-style :long})
```

Canonical option keys:

- `:locale` — required;
- `:calendar` — required;
- `:date-style` — required; supported values are `:short` and `:long`.

Supported format/parse combinations:

| Locale | Calendar | Short example | Long example |
| --- | --- | --- | --- |
| `en-US` | `gregory` | `10/01/2026` | `October 1, 2026` |
| `fr-FR` | `gregory` | `01/10/2026` | `1 octobre 2026` |
| `ja-JP` | `gregory` | `2026/10/01` | `2026年10月1日` |
| `en-US` | `buddhist` | `10/01/2569 BE` | `October 1, 2569 BE` |
| `ja-JP` | `japanese` | `R8/10/01` | `令和8年10月1日` |

Rules:

- Formatting requires a `PlainDateTime` and explicit supported options.
- Parsing accepts only strings that exactly match the selected corpus pattern.
- Parse/format round trips preserve year, month, day, hour, minute, second, and
  nanosecond for the date-time's calendar date; the formatted strings in this
  slice display date fields only, so parsing returns midnight for time fields.
- Unsupported locale/calendar combinations throw.
- Locale ids are exact and case-sensitive in this slice.
- Month and era names are exact selected-corpus strings.
- No host locale, host timezone, or system ICU data is consulted.

## Data flow

1. `Temporal.calendar` loads `assets/temporal/icu/cldr-seed/calendars.json` once
   through the project asset path and validates the schema.
2. `Temporal.localization` loads `locales.json` and delegates calendar field
   conversion to `Temporal.calendar`.
3. Formatting converts an ISO `PlainDateTime` into calendar fields, then applies
   the selected locale/calendar/date-style pattern from seed data.
4. Parsing matches the selected pattern exactly, converts localized calendar
   fields back through `Temporal.calendar.to-iso`, and returns a `PlainDateTime`.

## Provider registry role

The built-in seed corpus acts as provider identity `space.temporal.cldr-seed` in
docs and manifest data. This slice does not redesign provider dispatch. A later
ICU4C adapter may register a higher-priority provider or replace the internal
provider behind the same public `Temporal.localization` and `Temporal.calendar`
facades.

## Diagnostics

Errors must identify the rejected boundary where practical:

- missing `:locale`, `:calendar`, or `:date-style`;
- unknown option key;
- unsupported locale;
- unsupported calendar;
- unsupported locale/calendar combination;
- unsupported date style;
- malformed localized text;
- invalid month name or era name;
- invalid calendar field type or unknown record key;
- Japanese date outside the finite era corpus;
- inconsistent Japanese era/date fields;
- missing or malformed CLDR seed data;
- any runtime manifest enabling network fetches.

## Documentation updates

Add `docs/dev/features/temporal-localization-calendar.md` describing:

- public APIs;
- supported locales/calendars/combinations;
- seed data provenance and no-network behavior;
- calendar conversion rules;
- parsing limitations;
- native ICU4C adapter boundary and future expansion;
- validation commands.

Update:

- `docs/dev/features/temporal.md` to link the new feature page;
- `docs/dev/features/temporal-complete-library.md` current status;
- `docs/dev/features/temporal-complete-acceptance.md` localization/calendar row
  with local evidence expectations;
- `docs/dev/notes/temporal-dependency-data-packaging.md` to describe the CLDR
  seed corpus as packaged data while full ICU4C remains future work.

## Testing strategy

- Add focused Fennel tests for `Temporal.calendar` conversion:
  - supported calendar list ordering;
  - Gregorian round trip;
  - Buddhist year offset round trip;
  - Japanese Showa/Heisei/Reiwa boundary conversions;
  - invalid era/date diagnostics;
  - missing/unknown option diagnostics.
- Add focused Fennel tests for `Temporal.localization`:
  - supported locale and combination listing;
  - format examples for all supported combinations/styles;
  - parse/format round trips for all supported combinations/styles;
  - unsupported locale/calendar/style/combination diagnostics;
  - malformed localized text diagnostics;
  - unknown option diagnostics.
- Register focused tests in the fast suite.
- Expand manifest/package tests for the CLDR seed data and ICU packaged manifest.
- Validate with Space Fennel ladder: compile check, constraints, focused tests,
  packaging validator tests, broader suite when finishing.

## Acceptance criteria

- `Temporal.calendar` and `Temporal.localization` are exported from the public
  temporal facade.
- CLDR seed data is checked in under `assets/temporal/icu/cldr-seed/` with
  manifest/provenance and no-network metadata.
- ICU dependency manifest status is `packaged` with required provenance fields;
  full ICU4C source and adapter remain future work.
- Runtime temporal manifest lists the CLDR seed packaged data set.
- Supported calendar conversions round trip for `gregory`, `buddhist`, and the
  finite Japanese era corpus.
- Supported localization format/parse examples pass for `en-US`, `fr-FR`, and
  `ja-JP` selected combinations.
- Unsupported locales, calendars, styles, combinations, malformed localized text,
  invalid eras, and unknown option/record keys fail loudly.
- Native temporal core and C++ bindings remain unchanged unless a later reviewed
  implementation plan proves a small host helper is necessary.
- `SPACE_TEMPORAL_ENABLE_ICU_ADAPTER` continues to hard-fail in this slice.
- Focused tests, manifest validation, compile checks, constraints, broader local
  validation, PR CI, and merge queue pass.
