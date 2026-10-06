# String Entity Full-Text Search

String entity full-text search is exposed through the graph node key
`string-entity-search`. The node is a UX-purpose search surface: it owns
runtime query, status, and result state, but it owns no string entity records.

The string entity store remains the source of truth. GraphMap topology stores
only explicit visible nodes and edges, so search query text and result rows are
not written into graph capture state.

## Backend contract

Search nodes consume a backend with:

```text
backend:search-text(query, callback) -> token|nil
```

The callback receives `{:ok boolean :query string :results table :stderr string|nil :error string|nil}`.
Result rows use `{:entity-id string :entity table :matches table :match-count number}`.

## Ripgrep backend

The initial backend uses `ripgrep.fnl` with fixed-string, case-insensitive
search. It searches only `store.entities-dir`, only `*.md` files, and maps
`<id>.md` paths back to string entity IDs through `store:get-entity`.

## Result opening

Selecting a result loads `string-entity:<id>` into the active `GraphMap`.
It does not create a `LinkEntity`, does not author a domain relationship, and
does not silently expand every matching entity.
