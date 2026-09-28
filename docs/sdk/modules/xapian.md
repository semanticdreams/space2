# xapian

## Canonical Import

```fennel
(local xapian (require :xapian))
```

## Source Files

- `src/lua_xapian.cpp`
- `assets/lua/tests/test-xapian.fnl`

## What It Provides

`xapian` provides full-text indexing and search over native Xapian databases, including writable/read-only database handles, document construction, query parsing options, metadata, spelling, synonyms, term/posting/value inspection, range filters, sorting, collapsing, weighting, and expansion.

## API Summary

- `document([opts])` creates a document. Options include `data`, `text`, `stemmer`, `terms`, and `values`.
- `open(path [opts])` opens a database. Options include `writable`, `create`, and `overwrite`.
- `version()` returns the native Xapian version string.
- `sortable-serialise(value)` converts a number to a sortable Xapian value string.
- `Document` supports `data`, `add-term(term)`, and `add-value(slot value)`.
- `Database` supports lifecycle (`close`, `is-closed`, `is-writable`), writes (`add-document`, `replace-document`, `delete-document`, `commit`), spelling/synonym/metadata APIs, collection statistics, term/posting/value inspection, `get-document`, and `search(query [opts])`.
- Search options include `limit`, `offset`, `default-op`, `stemmer`, `flags`, `prefixes`, `boolean-prefixes`, `boolean-filters`, `value-ranges`, `ranges`, `weighting`, `sort`, `collapse`, `rset`, `expand`, and include flags for corrected queries, stoplists, unstemming, collapse data, sort keys, and matching terms.

## Examples

```fennel
(local xapian (require :xapian))

(local db (xapian.open "/tmp/space-xapian-example" {:writable true :create true}))
(local doc (xapian.document {:data "hello document" :text "hello searchable world"}))
(db:add-document doc)
(db:commit)

(local result (db:search "hello" {:limit 5}))
(print result.count)
(db:close)
```

## Errors and Platform Notes

Native Xapian exceptions are converted to Lua errors prefixed with `xapian <operation>:`. Creating or overwriting a database requires `writable=true`. Closed databases reject operations. Query/search options validate their shapes and names; unknown flags, weighting schemes, range types, negative slots/limits, and malformed prefixes/filters raise explicit errors. Writable operations require a writable database handle.

## Related Modules

- [`fs`](/sdk/modules/fs) for preparing and removing database directories.
- [`json`](/sdk/modules/json) for serializing document payloads into `data` fields.

## Aliases and Search Terms

Search terms: Xapian, full-text search, index, query parser, spelling, synonyms, BM25, postings, terms.
