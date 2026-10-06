# String Entity Text Search Design

## Summary

Add a graph-native mechanism for searching string entities by body text. The
existing `string entities` node remains the collection entry point and gains a
`Search Text` control that materializes a child search node. The new search node
is a UX-purpose graph node: it owns the search interaction state for the active
view, but it does not own string entity data and it does not persist search
queries or result sets into graph topology.

The initial backend uses the existing `ripgrep` wrapper. The design introduces a
small string-entity search backend boundary so Xapian can be added later without
rewriting graph node or widget code.

## Goals

- Provide a visible `Search Text` path from the existing string entities node.
- Search persisted string entity Markdown files by text.
- Use literal, case-insensitive ripgrep search for the first implementation.
- Keep query text and result lists runtime-only.
- Materialize selected results as normal `string-entity:<id>` graph nodes in the
  active `GraphMap`.
- Preserve graph doctrine: the graph exposes/adapts domain objects and focused
  operations; entity stores own entity data; graph maps persist explicit visible
  topology only.
- Keep a clean backend seam for a later Xapian implementation.

## Non-goals

- No Xapian indexing or query implementation in this slice.
- No persisted saved searches, search history, or query-bearing graph keys.
- No regex/advanced query language UI.
- No cross-entity search.
- No creation of `LinkEntity` records or domain links for search results.
- No hidden expansion of every matching entity; only explicit result selection
  materializes an entity node.

## Existing Context

- `assets/lua/graph/nodes/string-entity-list.fnl` creates the `string entities`
  collection node, owns a `StringEntityStore`, emits item lists, and can add a
  selected `StringEntityNode` through an explicit graph edge.
- `assets/lua/graph/view/views/string-entity-list.fnl` currently has a `Create`
  button and a `SearchView` that filters the already-listed entities by label.
  That is local list filtering, not full-text search.
- `assets/lua/entities/string.fnl` persists each string entity as
  `<store.entities-dir>/<id>.md` and can load entities by ID.
- `assets/lua/ripgrep.fnl` already exposes synchronous and async ripgrep search
  with `:literal`, `:case`, `:globs`, and `:paths` options.
- Built-in graph entity loaders register collection and entity schemes in
  `assets/lua/graph/extensions/builtins/entities.fnl`.

## Approach

### Graph node

Add a loader-backed UX-purpose node with exact key:

```text
string-entity-search
```

The node label should be human-readable, such as `string entity text search`.
The node owns runtime state needed to drive the search view:

- current query string;
- current status string;
- current result rows;
- active async search token/sequence for cancellation and stale-callback
  suppression;
- `results-changed` and `status-changed` signals.

The key intentionally contains no query text. Restoring a graph map that includes
the search node restores only the existence of the search surface, not the last
query or results.

### Entry point

The existing string entity list node gains an `add-search-node` method. It
requires a mounted `GraphMap`, loads the exact key `string-entity-search`, adds a
visible edge from the list node to the search node, and returns the search node.

The string entity list view adds a `Search Text` button using the existing UI
button patterns. Clicking the button calls `target:add-search-node()`. The
existing `Create` button and local list `SearchView` remain unchanged.

### Backend boundary

Add a small string entity search module, for example
`entities/string-search.fnl`, with a backend constructor such as:

```text
RipgrepStringEntitySearchBackend({:store store :ripgrep ripgrep?})
```

The backend exposes:

```text
backend:search-text(query, callback) -> token|nil
```

Callback payload shape:

```text
{:ok boolean
 :query string
 :results [result ...]
 :stderr string|nil
 :error string|nil}
```

Result shape:

```text
{:entity-id string
 :entity table
 :matches [ripgrep-match ...]
 :match-count number}
```

The backend depends on the string store for `entities-dir` and `get-entity`. It
does not create graph nodes and does not know about `GraphMap`.

### Ripgrep behavior

The ripgrep backend trims the query. A blank query returns an empty successful
result without invoking ripgrep.

For non-blank queries, it invokes the existing ripgrep wrapper asynchronously
with:

- `:literal true` for fixed-string matching;
- `:case :ignore` for case-insensitive matching;
- `:globs ["*.md"]` to restrict to string entity Markdown files;
- `:paths [store.entities-dir]` to restrict search to the string entity store.

This is “as fuzzy as possible” for the initial ripgrep-backed slice without
inventing a ranking or query language. Richer tokenization/ranking can belong to
a later backend or explicit query-mode option.

### Mapping matches to entities

The ripgrep backend maps each match path back to an entity ID by requiring the
file to be under `store.entities-dir`, taking the basename, and stripping the
`.md` suffix. Paths outside the store directory, non-Markdown paths, or IDs that
do not resolve through `store:get-entity` are ignored.

Multiple matches for one entity are deduplicated into one result row with all
match records preserved in `:matches` and counted in `:match-count`.

### Result materialization

Selecting a result calls the search node’s `open-result` method. The method
asserts the node is mounted in a `GraphMap`, builds the key
`string-entity:<entity-id>`, loads that key through `GraphMap:load-by-key`, and
returns the loaded node. It must fail loudly if the node cannot be loaded.

The search-result relationship is runtime-only, so opening a result does not
create a `LinkEntity` and does not create a persistent domain relationship.
Visible graph topology remains explicit: the user chose to add the search node,
then chose a result entity.

### Search view

Add a view for the search node using standard widget ownership rules:

- `Input` for query text;
- `Button` for explicit search submission;
- `Text` for status;
- `ListView` for result rows;
- `Flex` for layout.

The view subscribes to `node.results-changed` and `node.status-changed`, updates
the list/status text on signal emissions, and disconnects both listeners during
drop. Result rows are buttons; clicking a row calls `node:open-result(result)`.

The view owns widgets only. It does not call ripgrep directly and does not load
string entities except through node methods.

## Alternatives Considered

### Embed full-text search in the string entity list view

This would be smaller, but it mixes the local list filter with a backend text
search operation, gives no focused graph-addressable search surface, and makes a
future Xapian backend leak into the collection view. It also weakens the graph
doctrine distinction between collection nodes and UX-purpose operation nodes.

### Query-bearing graph keys

Keys such as `string-entity-search:<query>` would make each search independently
restorable, but they would persist user query text into graph topology. That
conflicts with the approved runtime-only query behavior and turns transient
search state into durable graph state.

### Search methods directly on `StringEntityStore`

The store owns entity persistence and CRUD. Directly adding ripgrep policy there
would couple persistence to a specific search implementation. A separate backend
module keeps the store focused and makes Xapian an additive backend change.

## Error Handling

- Missing `store.entities-dir` is an explicit backend error; do not silently
  search `.` or another fallback path.
- Blank queries return a successful empty result.
- Ripgrep cancellation and stale callbacks must not overwrite newer search
  results or status.
- Failed ripgrep calls surface a status/error payload; they do not silently clear
  results as if no matches were found.
- `open-result` asserts required GraphMap APIs and entity ID data; missing data
  is a programming/configuration error.

## Testing Strategy

- Backend unit tests with a fake ripgrep module:
  - ripgrep options are literal, ignore-case, `*.md`, and scoped to
    `store.entities-dir`;
  - file paths map to entity IDs;
  - duplicate file matches dedupe into one entity result with match counts;
  - outside/non-Markdown/missing entities are ignored;
  - blank queries do not invoke ripgrep.
- Node tests:
  - exact node key and label shape;
  - search delegates to backend and emits signals;
  - new searches cancel prior tokens and stale callbacks are ignored;
  - result opening loads `string-entity:<id>` through GraphMap;
  - graph capture state does not include query text.
- View tests:
  - `Search Text` button on the list view invokes `add-search-node`;
  - search view input/button calls `node:search-text`;
  - result/status signals refresh widgets;
  - clicking result rows calls `node:open-result`.
- Validation follows the Space Fennel ladder: touched-file compile check,
  constraints, focused Fennel tests, then the relevant broader fast suite for the
  graph loader/UI surface.

## Acceptance Criteria

- From a `string entities` node, the user can click `Search Text` and get a child
  search node in the current graph map.
- The search node can run literal, case-insensitive text search over persisted
  string entity Markdown files using the ripgrep backend.
- Matching rows identify string entities and selecting a row materializes the
  corresponding `string-entity:<id>` node.
- Search query text and result data are not persisted in graph topology.
- Backend code is isolated so a Xapian implementation can later satisfy the same
  node-facing contract.
