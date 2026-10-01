# Temporal Natural Language Design

## Purpose

Track 10 adds the first production natural-language temporal parsing surface. It upgrades `Temporal.natural` from a small English-only single-expression parser into a deterministic, corpus-backed parser that exposes candidate records, ambiguity diagnostics, missing-context diagnostics, and provider integration while preserving the existing unambiguous English `parse` behavior.

## Invariants

- Runtime temporal work must not fetch network data.
- Natural-language parsing remains policy/provider behavior, not native temporal core behavior.
- No host locale, host timezone, or host calendar defaults are allowed.
- Exact `Duration` remains nanoseconds-only; natural parsing may produce expressions and recurrence rules, not implicit business-day or fuzzy-duration values.
- All option keys are canonical; unsupported option keys and unsupported locales fail loudly.
- Ambiguous input must produce explicit candidates or an ambiguity error; it must not be resolved by guessing.
- Missing context for resolution must be diagnosed explicitly.

## Design choice

Use a packaged deterministic phrase corpus plus a pure Fennel matcher/provider.

### Considered approaches

1. **Packaged JSON corpus with pure Fennel matcher — selected.**
   - Pros: deterministic, no network, reviewable locale corpus, follows the temporal packaged-data pattern, and allows candidate-oriented behavior without native changes.
   - Cons: narrower phrase coverage than a broad external parser.
2. **Hard-coded Fennel grammar only.**
   - Pros: smallest data footprint and simplest initial implementation.
   - Cons: weak corpus provenance and harder locale expansion without code churn.
3. **Provider-only external parser integration.**
   - Pros: clean extension seam.
   - Cons: insufficient for Track 10 because Space still needs a built-in deterministic corpus and public `Temporal.natural` acceptance evidence.

## Initial packaged corpus

- Dataset id: `natural-phrase-seed`.
- Provider id: `space.temporal.natural-seed`.
- Version: `natural-phrase-seed-2026-10-track10`.
- Locales: exactly `en-US`, `fr-FR`, and `ja-JP`.
- Runtime network: disabled.
- Source/provenance: hand-authored Space seed corpus under the project license.

The checked-in data lives under `assets/temporal/natural/seed/`:

- `manifest.json` records schema version, dataset id, provider id, version, supported locale order, source/provenance, no-network invariant, and update process.
- `phrases.json` records locale order, weekday symbols, and phrase patterns for the initial families.

`assets/temporal/manifest.json` lists the natural phrase seed beside existing temporal data sets. The manifest validator enforces exactly one natural phrase seed entry, no-network metadata, exact locale order, required files, and provider id/version consistency.

## Initial phrase families

The initial corpus supports only these phrase families:

1. **Relative literals** — today/tomorrow equivalents.
2. **Relative count offsets** — days and weeks using ASCII decimal counts.
3. **Next weekday** — locale phrases equivalent to "next Tuesday".
4. **Weekly weekday recurrence** — locale phrases equivalent to "every Tuesday".
5. **Bare weekday ambiguity** — bare weekday names return ambiguous candidates instead of guessing whether the user means the next date or recurrence.

Localized numerals, times of day, date formats, ranges, holidays, business-day phrases, and scheduler commands are out of scope.

## Public API

`Temporal.natural` exposes:

- `candidates(text, options) -> array<table>` where `options` is optional and may contain only `:locale`.
- `parse(text, options) -> expression` for existing single-expression behavior on unambiguous input.
- `resolve(text, context) -> resolved expression result` for explicit parse-and-resolve flows.
- `provider() -> provider manifest table` for registration with `Temporal.providers`.

`Temporal.natural.parse(text)` preserves the current return shape for unambiguous existing English inputs such as `today`, `tomorrow`, `in 2 weeks`, `next Tuesday`, and `every Tuesday`. Unsupported text throws `unsupported temporal natural expression`. Ambiguous text throws `ambiguous temporal natural expression`.

`Temporal.natural.candidates` is the new broad API. It accepts explicit locale options and returns zero or more deterministic candidate records. If `:locale` is absent, it searches locales in corpus order (`en-US`, `fr-FR`, `ja-JP`) and still returns locale-tagged candidates; it does not read host locale.

`Temporal.natural.resolve(text, context)` requires explicit context and calls `Temporal.expression.resolve` after selecting exactly one unambiguous expression. Missing context throws `temporal natural resolve context is required`. Missing reference data throws `temporal natural resolve context requires reference plain date-time or reference instant with zone id`.

## Candidate schema

Each candidate includes:

- `:kind :natural-candidate`
- `:provider-id "space.temporal.natural-seed"`
- `:locale`
- `:phrase-id`
- `:family`
- `:matched-text`
- `:rank`
- `:expression`
- `:requires-context`

Candidate order is deterministic: rank, locale corpus order, then phrase id. Provider registry dispatch may annotate or preserve provider id, but built-in candidates always identify `space.temporal.natural-seed`.

## Provider integration

`Temporal.natural.provider()` returns a provider manifest:

- `:id "space.temporal.natural-seed"`
- `:version "natural-phrase-seed-2026-10-track10"`
- `:priority 10`
- `:capabilities ["natural"]`
- `:parse` function returning candidate arrays

`assets/lua/temporal.fnl` registers this provider with the default `Temporal.providers` registry. This makes `Temporal.providers.parse("today", {:locale "en-US"})` return the built-in natural candidates. Provider registration is deterministic and local; it does not call network services and does not alter native temporal primitives.

## Data flow

1. `natural-corpus` reads `assets/temporal/natural/seed/manifest.json` and `phrases.json` through the normal asset path.
2. The loader validates schema version, provider id, version, locale order, phrase families, weekday mappings, and no-network metadata.
3. `Temporal.natural.candidates` validates input/options, matches phrase patterns from the corpus, builds candidate records, and sorts them deterministically.
4. `Temporal.natural.parse` calls `candidates`, rejects unsupported/ambiguous results loudly, and returns one expression for unambiguous input.
5. `Temporal.natural.resolve` calls `parse` and then `Temporal.expression.resolve` with explicit context.
6. `Temporal.providers.parse` can dispatch the registered built-in provider alongside future local providers.

## Error handling

The parser and loader fail loudly for:

- missing `SPACE_ASSETS_PATH` or runtime asset path;
- malformed corpus manifests or phrase data;
- unsupported locales;
- unknown option keys;
- non-string input text;
- unsupported text;
- ambiguous input passed to `parse` or `resolve`;
- missing resolve context or missing reference data.

Returning an empty candidates array is allowed only for the candidate API when the text is unsupported; single-expression APIs must throw.

## Tests and acceptance evidence

Focused acceptance requires:

- packaged corpus manifest tests for missing files, locale drift, and no-network flags;
- Fennel corpus loader tests;
- existing English parse compatibility tests;
- `fr-FR` and `ja-JP` phrase parsing tests;
- candidate schema and deterministic ordering tests;
- bare weekday ambiguity tests;
- unsupported locale and unknown option tests;
- missing-context diagnostics tests;
- default provider registration tests through `Temporal.providers.parse`;
- fast-suite registration and docs updates.

Validation commands:

```bash
make fennel-check
make constraints
python3 -m pytest scripts/tests/test_temporal_dependency_manifests.py -q
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
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data \
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Run `make build` first if `./build/space` is missing or stale.

## Out of scope

- ML, LLM, or network-backed parsing.
- Host locale or host timezone inference.
- Full date formats such as `03/04/2026`.
- Times of day, fuzzy phrases, ranges, intervals, business-day phrases, holidays, scheduler behavior, timestamp migrations, or natural-language business calendars.
- Localized numerals beyond ASCII digits.
- Native C++ temporal core changes.
- Full CLDR natural-language grammar coverage.

Future corpus expansion may add phrase families or locales by extending the packaged corpus and manifest evidence. New semantic categories require a spec update rather than silent grammar expansion.
