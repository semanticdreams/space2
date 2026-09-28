# Temporal Provider Registry Design

## Purpose

The complete temporal roadmap needs a deterministic provider/plugin registry before broad natural language, localization, business-calendar, and parsing providers are added. This slice adds the local Fennel-facing registry surface only: `Temporal.providers` can register trusted in-process provider tables, validate their manifests, list providers by capability, and unregister via handles.

This slice does not load provider files, execute remote providers, call network services, or implement natural-language/localization/calendar behavior. It establishes the policy and API that later temporal tracks can compose.

## Public API

`Temporal.providers` is exported from `(require :temporal)` and provides:

- `Temporal.providers.register(provider-table) -> provider-handle`
- `Temporal.providers.unregister(provider-handle) -> boolean`
- `Temporal.providers.list(capability-key) -> provider-summary[]`
- `Temporal.providers.all() -> provider-summary[]`
- `Temporal.providers.parse(text, context) -> candidate[]`

Provider handles are opaque tables returned by `register`. A handle can unregister only the provider it represents. Unregistering the same handle twice returns `false` rather than throwing, so cleanup paths can be idempotent.

## Provider Manifest Shape

A provider is a plain table with canonical keys:

- `:id`: non-empty string. Must be unique while registered.
- `:version`: non-empty string.
- `:capabilities`: non-empty sequential array of keyword capability keys.
- `:priority`: optional number; defaults to `100` when absent.
- `:parse`: optional function with signature `(fn [text context] -> candidates-or-nil)`.
- `:format`: optional function reserved for later formatting providers.
- `:calendar`: optional function/table reserved for later calendar providers.
- `:business-calendar`: optional function/table reserved for later business-calendar providers.

At least one operational provider function/table among `:parse`, `:format`, `:calendar`, or `:business-calendar` must be present. Unknown top-level keys are rejected loudly to preserve canonical option-key discipline.

Capabilities are keywords such as `:natural`, `:localized-format`, `:calendar`, or `:business-calendar`. This slice does not require a fixed global capability enum because later tracks introduce new provider families; it only validates that capabilities are keywords and deduplicates per provider.

## Deterministic Ordering

The registry orders providers deterministically by:

1. lower numeric `:priority` first;
2. lexicographic `:id` as the tie-breaker.

Registration order does not affect list or parse order. This makes tests, replay, and plugin composition deterministic.

## Defensive Summaries

`list` and `all` return provider summaries, not the mutable registered provider tables. A summary contains:

- `:id`
- `:version`
- `:capabilities`
- `:priority`

The `:capabilities` array is copied. Mutating returned summaries must not mutate registry state.

## Parse Composition

`parse` is the only operational dispatcher in this slice. It:

- validates `text` is a string;
- accepts `context` as a table or `nil`; `nil` is treated as an empty table;
- selects registered providers with capability `:natural` and a `:parse` function;
- calls matching providers in deterministic order;
- accepts a provider return of `nil` or an empty array as no candidates;
- requires candidate results to be a sequential array when present;
- annotates each returned candidate with `:provider-id` when the candidate does not already set one;
- concatenates candidates in provider order;
- propagates provider errors with an explicit `temporal provider <id> parse failed:` prefix.

`parse` does not resolve candidate semantics and does not guess when there are no providers; with no matching providers it returns an empty array.

## Error Handling

The registry fails loudly for:

- non-table providers;
- missing or invalid `:id`, `:version`, `:capabilities`, or operational fields;
- duplicate provider IDs;
- non-keyword or duplicate capabilities;
- non-number priority;
- unknown top-level manifest keys;
- invalid parse result shape;
- invalid unregister handle shape.

Idempotent cleanup is the only non-throwing exception: unregistering an already inactive valid handle returns `false`.

## Architecture

Add `assets/lua/temporal/provider-registry.fnl` as a pure Fennel factory module following existing temporal module patterns. It owns all provider storage internally and exports a final literal API table.

Update `assets/lua/temporal.fnl` to instantiate and export `:providers` from the new factory. No native C++ changes, no dependency packaging changes, and no runtime plugin loading are introduced.

Tests live in `assets/lua/tests/test-temporal-provider-registry.fnl` and are registered from `assets/lua/tests/fast.fnl` if runtime remains fast. The test surface covers validation, duplicate rejection, deterministic ordering, handle unregister, defensive summaries, parse composition, no-provider empty results, and provider parse error prefixing.

## Validation

This is Fennel-facing behavior. Validation order:

1. touched-file `tools.fennel-check` for `assets/lua/temporal/provider-registry.fnl`, `assets/lua/temporal.fnl`, `assets/lua/tests/test-temporal-provider-registry.fnl`, and `assets/lua/tests/fast.fnl` if touched;
2. `make constraints`;
3. focused `tests.test-temporal-provider-registry:main`;
4. broader `tests.fast:main` because the new test module is registered in fast tests;
5. final branch validation may run `make test` if finishing policy or reviewer requires it.

## Out of Scope

- Loading provider modules from disk.
- Native plugin ABI or sandboxing.
- Remote/network providers.
- ICU/CLDR, libical, holiday data, or dependency packaging changes.
- Natural-language grammar expansion.
- Localization, calendar, or business-calendar implementation.
- Persisted provider registries.
