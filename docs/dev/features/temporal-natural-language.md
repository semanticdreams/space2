# Temporal Natural Language

`Temporal.natural` is Space's deterministic, packaged natural-language parsing layer. It is a Fennel/provider feature above the native temporal core; it does not add native C++ parsing, fetch network data, read the host locale, or infer host timezone/calendar defaults.

## Scope

The initial seed corpus is `natural-phrase-seed` from provider `space.temporal.natural-seed`, version `natural-phrase-seed-2026-10-track10`, packaged under `assets/temporal/natural/seed/`.

Supported locales are exactly:

- `en-US`
- `fr-FR`
- `ja-JP`

Supported phrase families are exactly relative literals, relative count offsets, next weekday, weekly weekday recurrence, and bare weekday ambiguity. Localized numerals beyond ASCII digits, times of day, date formats, ranges, holidays, business-day phrases, scheduler commands, fuzzy durations, and business calendars are out of scope.

## Public API

- `Temporal.natural.candidates(text, options)` returns zero or more deterministic candidate records. `options` may contain only `:locale`; unsupported option keys and unsupported locales fail loudly.
- `Temporal.natural.parse(text, options)` preserves the existing unambiguous English expression behavior and throws `unsupported temporal natural expression` or `ambiguous temporal natural expression` instead of guessing.
- `Temporal.natural.resolve(text, context)` requires explicit context and delegates to `Temporal.expression.resolve`. Missing context throws `temporal natural resolve context is required`; missing reference data throws `temporal natural resolve context requires reference plain date-time or reference instant with zone id`.
- `Temporal.natural.provider()` returns the built-in provider manifest registered with `Temporal.providers` by default.

Candidate records include `:kind :natural-candidate`, `:provider-id`, `:locale`, `:phrase-id`, `:family`, `:matched-text`, `:rank`, `:expression`, and `:requires-context`. Ordering is deterministic by rank, locale corpus order, then phrase id. Bare weekday text returns multiple candidates so callers can present ambiguity; `parse` and `resolve` reject it loudly.

## Provider integration

The default `Temporal.providers` registry registers the local natural provider with id `space.temporal.natural-seed`, priority `10`, capability `:natural`, and no network behavior. `Temporal.providers.parse "today" {:locale "en-US"}` returns built-in candidate arrays. Unsupported natural text returns an empty array through provider dispatch, while single-expression APIs still throw.

## Validation

When changing this layer, run compile checks before constraints and focused tests:

```bash
make fennel-check
make constraints
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

Run `python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q` when changing the packaged corpus or temporal data manifests.
