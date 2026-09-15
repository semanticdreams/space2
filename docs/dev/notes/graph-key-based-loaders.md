---
type: dev-note
tags:
  - note
---

# Graph Key-Based Node Loaders

## Overview

A general-purpose system where any node type can register key-based loaders. When a node key is referenced but the node isn't in the graph, the appropriate loader can create and add it.

## Motivation

Currently, when code references a node by key (e.g., `graph:lookup(key)`), it only returns nodes that are already in the graph. This is a problem for features that store node key references persistently:

- **ListEntityNode** stores item keys in its entity data. When displaying items, `add-item-nodes` calls `graph:lookup` for each item key, but nodes that aren't in the graph are silently ignored.
- **LinkEntity** edges reference source/target keys. If those nodes aren't loaded, the edge can't be created.

With key-based loaders, these features can load nodes on-demand from their keys.

## Design

### Scheme-Based Matching

Loaders register a string **scheme**. When `load-by-key` is called:

- If the key contains `:`, the scheme is the substring before the first `:`.
- Otherwise, the entire key is treated as the scheme.

The graph then looks up a loader by exact scheme match.

Examples:
- Scheme `"string-entity"` matches keys like `"string-entity:abc-123-def"`
- Scheme `"list-entity"` matches keys like `"list-entity:xyz-456"`
- Scheme `"fs"` matches keys like `"fs:/home/user/documents"`
- Scheme `"hackernews-story-list"` matches keys like `"hackernews-story-list:newstories"`

The payload portion may contain additional `:` characters; only the first colon separates scheme from payload (e.g. `"fs:/tmp/a:b:c"` still has scheme `"fs"`).

### Explicit Invocation

Loading is explicit via `graph:load-by-key(key)`. The existing `graph:lookup(key)` is unchanged and only returns existing nodes. This keeps the system predictable - nodes are only created when explicitly requested.

### Descriptor-Owned Installation

`graph:register-key-loader` is the low-level primitive that descriptor installer
code uses to attach a scheme loader to one graph runtime. App setup, HomeWorld
runtime setup, tests, and reloadable user modules should not call individual
built-in node `register-loader` helpers as setup APIs. They register graph
extension descriptors with `app.graph-extension-registry` (or a test-local
`GraphExtensionRegistry`) and let the registry install loaders and morphs into
live and future runtimes.

Built-in node types follow the same mechanism as user/runtime extensions:
`main.fnl` registers the family-scoped descriptors from
`graph/extensions/builtins`, and the registry installs them into each HomeWorld
runtime before persisted graph-map topology is hydrated. Those descriptors adapt
owning stores and systems into graph node adapters; the graph still persists only
topology keys and edge keys, while entity, workflow, LLM, kernel, filesystem, and
world systems own their domain data.

There is no centralized built-in key-loader registrar, compatibility wrapper, or
fallback setup path. The historical `graph/key-loaders.fnl` module has been
removed and is not a supported import path.

In practice, schemes should be treated as stable identifiers. This repo uses schemes that match the node type/module name (e.g. `hackernews-story`, `llm-message`, `string-entity`) so it’s easy to find the implementation and avoid drift.

## Implementation

### Step 1: Update Entity Node Key Formats

Entity-backed nodes must use `"<scheme>:<id>"` keys so scheme matching works.

**`assets/lua/graph/nodes/string-entity.fnl`**:
```fennel
;; Before
(local node (GraphNode {:key entity-id ...}))

;; After
(local node (GraphNode {:key (.. "string-entity:" entity-id) ...}))
```

Same pattern for:
- `list-entity.fnl` → `"list-entity:" .. entity-id`
- `link-entity.fnl` → `"link-entity:" .. entity-id`

### Step 2: Add Key Loader Registry to Graph

**`assets/lua/graph/core.fnl`**:

```fennel
;; After existing declarations in create-graph
(local key-loaders {})

(fn key-scheme [key]
  (when (and key (= (type key) "string"))
    (local (start _end) (string.find key ":" 1 true))
    (if start
        (string.sub key 1 (- start 1))
        key)))

(fn register-key-loader [_self scheme loader-fn]
  (assert scheme "register-key-loader requires a scheme")
  (assert (not (string.find scheme ":" 1 true))
          "register-key-loader scheme must not include ':'")
  (assert loader-fn "register-key-loader requires a loader function")
  (assert (not (. key-loaders scheme))
          (.. "register-key-loader duplicate scheme: " scheme))
  (set (. key-loaders scheme) loader-fn))

(fn load-by-key [_self key]
  (when (not key)
    (lua "return nil"))
  (assert (= (type key) "string") "load-by-key requires string key")
  ;; Return existing node if already in graph
  (local existing (. nodes key))
  (when existing
    (lua "return existing"))
  ;; Find loader and create node
  (local scheme (key-scheme key))
  (local loader (. key-loaders scheme))
  (when (not loader)
    (lua "return nil"))
  (local node (loader key))
  (when node
    (assert (. node :key) "load-by-key loader must return node with key")
    (assert (= (. node :key) key)
            (.. "load-by-key loader returned mismatched key: expected " key
                " got " (tostring (. node :key))))
    (self:add-node node))
  node)

;; Add to self table
(set self.register-key-loader register-key-loader)
(set self.load-by-key load-by-key)
```

### Step 3: Add Loader Installer Helpers to Node Modules

Node modules may expose focused `register-loader` helper functions as low-level
installer utilities, but those helpers are for descriptor implementations and
direct unit tests of the helper only. They are not an app/runtime/test setup API.

**`assets/lua/graph/nodes/string-entity.fnl`**:
```fennel
(local SCHEME "string-entity")
(local KEY_PREFIX (.. SCHEME ":"))

(fn extract-entity-id [key]
  (string.sub key (+ 1 (string.len KEY_PREFIX))))

(fn register-loader [graph opts]
  (local options (or opts {}))
  (local store (or options.store (StringEntityStore.get-default)))
  (graph:register-key-loader SCHEME
    (fn [key]
      (local entity-id (extract-entity-id key))
      (local entity (store:get-entity entity-id))
      (when entity
        (StringEntityNode {:entity-id entity-id :store store})))))

{:StringEntityNode StringEntityNode
 :register-loader register-loader}
```

Same pattern for `list-entity.fnl` and `link-entity.fnl`.

### Step 4: Register Built-in Descriptors on App Initialization

**`assets/lua/main.fnl`**:

During app initialization, register built-in graph extension descriptors and install them into graph runtimes:

```fennel
(local BuiltInGraphExtensions (require :graph/extensions/builtins))

;; During app setup, with app.graph-extension-registry initialized:
(BuiltInGraphExtensions.register! app.graph-extension-registry opts)
```

This registry call is the runtime installation path. Descriptor `install-loaders`
functions may call `graph:register-key-loader` internally, but app/runtime/test
setup should not bypass the registry by invoking those low-level installers
directly.

### Step 5: Update ListEntityNode to Use load-by-key

**`assets/lua/graph/nodes/list-entity.fnl`**:

In `add-item-nodes`, change from lookup to load-by-key:

```fennel
;; Before
(each [_ item-key (ipairs items)]
  (local target (graph:lookup item-key))
  (when target
    ;; create edge...

;; After
(each [_ item-key (ipairs items)]
  (local target (graph:load-by-key item-key))
  (when target
    ;; create edge...
```

## API Reference

### graph:register-key-loader(scheme, loader-fn)

Low-level descriptor installer primitive that registers a loader function for
keys matching the given scheme in one graph runtime.

**Parameters:**
- `scheme` (string): The key scheme to match (e.g., `"string-entity"`)
- `loader-fn` (function): A function that takes a key and returns a node (or nil)

**Loader function signature:**
```fennel
(fn [key] -> node-or-nil)
```

The loader should:
1. Decide whether the key has a payload (`"<scheme>:<payload>"`) or is a bare key (`"<scheme>"`)
2. For payload keys, extract and validate the payload string
3. Check if the underlying data exists (e.g., entity in store)
4. Return a new node instance, or nil if the key is unsupported or data doesn't exist

Call this from `GraphExtensionRegistry` descriptor `install-loaders` functions and
return the resulting owner-safe handles to the registry. Do not use it as an app
setup or test setup API for built-ins; install built-ins and user/runtime node
types by registering descriptors through the graph extension registry.

### graph:load-by-key(key)

Load or lookup a node by its key.

**Parameters:**
- `key` (string): The node key to load

**Returns:**
- The existing node if already in the graph
- A newly created and added node if a loader matches
- `nil` if no node exists and no loader matches (or loader returns nil)

## Extending to Other Node Types

Any node type can add key-based loading by:

1. Using a `"<scheme>:<payload>"` key format (or a bare key for singleton nodes)
2. Providing loader installer code inside a graph extension descriptor
3. Registering the descriptor through `GraphExtensionRegistry`

Example for a hypothetical `BookmarkNode`:

```fennel
(local SCHEME "bookmark")
(local KEY_PREFIX (.. SCHEME ":"))

(fn BookmarkNode [opts]
  (local url (assert opts.url "BookmarkNode requires url"))
  (GraphNode {:key (.. KEY_PREFIX url)
              :label (or opts.title url)
              :view BookmarkNodeView
              ...}))

(fn bookmark-descriptor [db]
  {:id "bookmark-extension"
   :unit-id "bookmark-unit"
   :schemes [SCHEME]
   :install-loaders
   (fn [graph ctx]
     (local bookmarks-db (or db (get-default-db)))
     [(graph:register-key-loader
        SCHEME
        (fn [key]
          (local url (string.sub key (+ 1 (string.len KEY_PREFIX))))
          (local bookmark (bookmarks-db:get url))
          (when bookmark
            (BookmarkNode {:url url :title bookmark.title})))
        {:owner-id ctx.owner-id
         :extension-id ctx.extension-id})])})

{:BookmarkNode BookmarkNode
 :descriptor bookmark-descriptor}
```

## Files Changed

| File | Change |
|------|--------|
| `assets/lua/graph/core.fnl` | Add key-loaders registry, scheme parsing, safety assertions, and link-entity integration via load-by-key |
| `assets/lua/graph/key-loader-utils.fnl` | Shared helper for store-backed loaders (safe on bare keys) |
| `assets/lua/graph/extensions/builtins/` | Built-in graph extension descriptors that install built-in node loaders |
| `assets/lua/graph/nodes/string-entity.fnl` | Scheme key, add register-loader |
| `assets/lua/graph/nodes/list-entity.fnl` | Scheme key, add register-loader, use load-by-key |
| `assets/lua/graph/nodes/link-entity.fnl` | Scheme key, add register-loader |
| `assets/lua/main.fnl` | Register built-in graph extension descriptors through the app registry |

## Testing

### Unit Tests

Add `assets/lua/tests/test-graph-loaders.fnl`:

1. **Loader registration**: Verify loaders are stored by scheme
2. **load-by-key existing node**: Returns existing node without calling loader
3. **load-by-key loadable key**: Calls loader, adds node, returns it
4. **load-by-key unknown key**: Returns nil when no loader matches
5. **load-by-key loader returns nil**: Returns nil when entity doesn't exist
6. **Scheme parsing**: Verify scheme-before-first-colon and bare-key scheme behavior
7. **Safety**: Duplicate scheme registration and loader key mismatch assertions

### Integration Tests

1. Create a string entity
2. Create a list entity and add the string entity's key to its items
3. Without loading the string entity node, call `graph:load-by-key` with its key
4. Verify the node is created and added to the graph

### Manual Testing

1. Create a string entity from the entities panel
2. Create a list entity
3. Add the string entity to the list
4. Close and reopen the app
5. Open the list entity view
6. Verify the string entity item is displayed (previously would be ignored)

## Migration Notes

Changing key formats from `entity-id` to `"<scheme>:" + entity-id` is a breaking change for existing persisted data. Affected stores:

- **ListEntityStore**: Items array contains node keys
- **LinkEntityStore**: source-key and target-key fields
- **Position persistence**: Node positions stored by key

Existing data with old-format keys will not match the new scheme-based keys. This is acceptable per design decision - old data won't load until manually migrated.


## See also

- [Graph Foundation](/dev/features/graph-foundation), [Graph Browsing](/dev/features/graph-browsing)
