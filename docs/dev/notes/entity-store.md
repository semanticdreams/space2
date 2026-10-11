---
type: dev-note
tags:
  - note
---

# Entity store

## Overview

The entity store provides JSON file-based persistence for the core data types used by the graph system. Six entity types exist, each backed by its own subdirectory under `{data-dir}/entities/` with CRUD operations, UUID-based keys, and signal emission for changes.

## Entity types

### String entity (`entities/string.fnl`, 163 lines)

The simplest entity type — arbitrary text content with optional YAML frontmatter. The module parses frontmatter blocks (`---\n...\n---\n...`) into a `{:frontmatter table :body string}` structure.

- **Store**: `entities/string/` — one JSON file per entity
- **Content**: Text with optional frontmatter
- **Search**: Linear scan over all string entities
- **Signals**: `string-entity-created`, `string-entity-updated`, `string-entity-deleted`
- **API**: `get`, `create`, `save`, `delete`, `search`, `all`, `count`

### Code entity (`entities/code.fnl`)

Source code entities with language, kernel, and metadata.

- **Fields**: `:code` (source text), `:language` (string), `:kernel-id` (optional), `:meta` (table)
- **Store**: `entities/code/`
- **Signals**: `code-entity-created`, `code-entity-updated`, `code-entity-deleted`

### Link entity (`entities/link.fnl`, 176 lines)

Bidirectional labeled connections between graph keys. Links have a source key, target key, and label. They are indexed in both directions for fast lookup.

- **Fields**: `:from` (source key), `:to` (target key), `:label` (string)
- **Store**: `entities/link/`
- **Indexing**: In-memory caches for `from` and `to` direction lookups
- **Signals**: `link-entity-created`, `link-entity-updated`, `link-entity-deleted`
- **API**: `get-by-from`, `get-by-to` — fast reverse lookup for graph traversal

### List entity (`entities/list.fnl`)

Ordered collections of entity references. Used for grouping related entities exposed through the graph.

- **Fields**: `:items` (array of entity reference keys)
- **Store**: `entities/list/`
- **Signals**: `list-entity-created`, `list-entity-updated`, `list-entity-deleted`

### Dict entity (`entities/dict.fnl`)

Keyed collections of graph-addressable references. Used for profile-like or object-like structures composed from primitive entity references.

- **Fields**: `:items` (string-keyed table of graph reference keys)
- **Store**: `entities/dict/`
- **Signals**: `dict-entity-created`, `dict-entity-updated`, `dict-entity-deleted`, `dict-entity-items-changed`
- **API**: `get-item`, `set-item`, `remove-item`, `rename-item`

### Identity entity (`entities/identity.fnl`)

Self-referential identity nodes for stable references within the graph. Identity entities let other entities reference them by a persistent key that survives content changes — essential for notebook references, task links, and graph edges where the target may be updated.

- **Store**: `entities/identity/`
- **API**: `get-or-create` — ensure an identity exists, returning existing or creating new
- **Signals**: `identity-entity-created`, `identity-entity-updated`, `identity-entity-deleted`

## Architecture pattern

All entity stores follow the same pattern:
1. **Directory-backed**: Entities are `.json` files in typed subdirectories
2. **UUID keys**: Each entity has a UUID as its primary key
3. **In-memory cache**: `cache` table holds loaded entities; writes go to disk then update cache
4. **Signal emission**: Every mutation (create, update, delete) emits a signal with the entity data
5. **Factory pattern**: `StringEntityStore(opts)`, `CodeEntityStore(opts)`, etc. — no constructors, plain tables

## Integration with graph system

The graph system (`graph/core.fnl`) uses entity stores as one of several persistence backends for domain objects that are exposed through the graph. Not every graph node is entity-backed — world/terrain/light nodes are backed by world scene state, LLM nodes by the LLM store, filesystem nodes by the real filesystem. When an entity-backed graph node adapter is created, its backing entity lives in the corresponding entity store. When loaded by key, the entity store resolves the node's key to its data.

Link entities are especially important — they are the backing store for persisted user/domain relationship edges exposed through the graph. The bidirectional index on link entities (`get-by-from` / `get-by-to`) enables the graph to traverse relationships in either direction without scanning.

Identity entities provide stable references: a notebook reference to a code file uses an identity entity as the target. If the code file's content changes, the identity persists and all references remain valid.


## See also

- [Core Platform](/dev/features/core-platform), [Graph Foundation](/dev/features/graph-foundation)
