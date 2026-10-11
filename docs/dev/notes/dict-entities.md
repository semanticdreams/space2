---
type: dev-note
tags:
  - note
---

# Dict Entities

Dict entities are persistent keyed collections whose values are graph-addressable keys. They complement list entities: lists store ordered arrays of references, while dicts store string-keyed maps of references.

## Storage

- File: `assets/lua/entities/dict.fnl`
- Directory: `{user-data-dir}/entities/dict/`
- Format: one JSON file per entity, named `<uuid>.json`
- Required fields: `id`, `name`, `items`, `created-at`, `updated-at`

Example:

```fennel
{:id "profile"
 :name "Alice profile"
 :items {"name" "string-entity:name"
         "manager" "identity:bob"}
 :created-at 123
 :updated-at 456}
```

## API

`DictEntityStore` exposes CRUD plus `get-item`, `set-item`, `remove-item`, and `rename-item`. Mutating item operations reject missing or empty required keys/values with explicit errors.

## Graph keys

- `dict-entity:<id>` opens one dict entity.
- `dict-entity-list` opens the dict entity browser.

Graph-facing `DictEntityNode:set-item` wraps non-identity target keys through identity entities when possible. Unresolved references remain stored and can resolve later.

## UI

The initial dict view supports name editing, item count, stable key-sorted rows, key/value save, remove, selected-node insertion, focus/open for referenced keys, and delete.
