# Reloadable Graph Extension Units

Reloadable graph extension units let user-code `ModuleUnit`s add graph-exposed node
types without reloading the app root or tearing down world graph runtimes. The seam
is the app-owned graph extension registry (`app.graph-extension-registry`), which
installs descriptors into every live HomeWorld graph runtime and into future
runtimes when worlds are opened, resumed, or recreated.

## Runtime lifecycle

`main.fnl` creates the registry during app initialization before user-code units
load. A unit may register an extension in its `init` export and unregister the
returned handle in its `drop` export. `home-world.fnl` installs each runtime after
the runtime has a shared `Graph` and `GraphMapManager`, and uninstalls the runtime
before graph-map-manager or graph cleanup.

This ordering means:

- existing worlds receive newly registered extension loaders and morphs;
- newly created or resumed worlds receive already registered extensions;
- unit unload removes descriptor handles, key-loader handles, morph handles, and
  unit-owned signal subscriptions before the registry is discarded during app
  shutdown.

## Descriptor shape

Register extensions with `GraphExtensionRegistry:register-extension`:

```fennel
(app.graph-extension-registry:register-extension
  {:id "demo-extension"
   :unit-id "user-demo-extension"
   :schemes ["demo-node"]
   :refresh-schemes ["demo-node"] ; optional; defaults to :schemes
   :install-loaders
   (fn [graph ctx]
     [(graph:register-key-loader
        "demo-node"
        make-demo-node
        {:owner-id ctx.owner-id
         :extension-id ctx.extension-id})])
   :install-morphs
   (fn [morphs ctx]
     [(morphs:register
        "demo-node"
        "other-node"
        demo-morph
        {:label "Open as other node"}
        {:owner-id ctx.owner-id
         :extension-id ctx.extension-id})])})
```

Required fields are `:id`, `:unit-id`, non-empty `:schemes`, and
`:install-loaders`. `:install-morphs` and `:refresh-schemes` are optional. Loader
and morph installers must return tables of owner-safe registration handles. The
registry records those handles per runtime and unregisters them in reverse order.
Duplicate active key-loader or morph registrations fail loudly; re-unregistering
an inactive handle is idempotent, and stale handles cannot remove a newer active
registration.

Installer code may also call `ctx:record-handle` for handles that must be tracked
before additional installer work can fail. If any runtime install fails, the
registry rolls back every handle installed during that attempt and rethrows the
error.

## Adapter refresh on reload

Unit reload and hot reload use the registry refresh seam after the unit has been
reloaded. For each descriptor owned by the reloaded unit, the registry calls
`GraphMap:refresh-adapters-by-scheme` on every live runtime's active map for the
descriptor's `:refresh-schemes` (or `:schemes`).

Refresh rebuilds visible map-local node adapter instances by key, replaces edges
to point at the fresh adapters, and preserves map selection/focus keys. It fails
loudly if a visible node for the refreshed scheme cannot be rebuilt; hot reload
rolls the unit back and refreshes again so the runtime returns to the previous
working adapter version.

## Built-in graph extensions

Built-in graph node families and user/runtime graph extensions use the same app
registry. At startup, `main.fnl` creates `app.graph-extension-registry`, then
`graph/extensions/builtins/init.fnl` registers family-scoped built-in descriptors
for entities, workflows, filesystem, LLM, Hacker News, kernels, and worlds. The
registry installs those descriptors into every live HomeWorld graph runtime and
into future runtimes before graph-map topology is hydrated, so built-in schemes
such as `start`, `fs`, `string-entity`, `world`, `llm-conversation`, and workflow
schemes arrive through the same descriptor path as reloadable user extensions.

Built-in descriptor modules are adapter/installers, not domain stores. Each
family receives the owning stores or systems it needs from app/runtime context and
adapts those records into graph node adapters. Entity descriptors adapt entity
stores, workflow descriptors adapt workflow stores, world descriptors adapt
`world-manager`/`WorldData`, and so on. Graph core remains the key-loader and
topology primitive layer; it does not take ownership of the domain data behind
those keys.

`graph:register-key-loader` is low-level installer code only. Descriptor
`install-loaders` functions may call it and return the owner-safe handles that the
registry tracks. App initialization, HomeWorld setup, tests, and user modules
should not call individual built-in node `register-loader` helpers as setup APIs;
they should register descriptors through `app.graph-extension-registry` (or a
test-local `GraphExtensionRegistry`) and let the registry install runtime handles.

The old `graph/key-loaders.fnl` centralized built-in registrar no longer exists
and is not a supported import path. Do not add forwarding shims or fallback
registrars for it; the graph extension registry is the only node-type
installation mechanism for both built-ins and user/runtime extensions.

## Topology and ownership invariants

Graph topology remains key-only. A graph extension owns the domain data behind its
keys and adapts that data into graph node adapters through key loaders. `GraphMap`
stores map membership, explicit display edges, selected keys, focused key, and
view metadata; it does not persist extension-owned domain records.

Preview and full-view builders returned by extension node adapters must return
build closures and assert required context. Node actions should materialize
related topology only through explicit graph-map operations such as
`graph-map:load-by-key` and `graph-map:add-edge`.

## Minimal demo-node unit

```fennel
(local Graph (require :graph/init))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(var extension-handle nil)

(fn demo-preview [node]
  (fn build [ctx]
    (assert ctx "demo-preview requires build context")
    {:text (.. "Preview " node.demo-id)}))

(fn demo-view [node]
  (fn build [ctx]
    (assert ctx "demo-view requires build context")
    {:text (.. "Full view " node.demo-id)}))

(fn make-demo-node [key]
  (local id (KeyLoaderUtils.extract-id "demo-node" key))
  (when id
    (local node (Graph.GraphNode {:key key
                                  :label (.. "Demo " id)
                                  :preview demo-preview
                                  :view demo-view}))
    (set node.demo-id id)
    node))

(fn init []
  (assert app.graph-extension-registry
          "demo extension requires app.graph-extension-registry")
  (set extension-handle
       (app.graph-extension-registry:register-extension
         {:id "demo-extension"
          :unit-id "user-demo-extension"
          :schemes ["demo-node"]
          :install-loaders
          (fn [graph ctx]
            [(graph:register-key-loader
               "demo-node"
               make-demo-node
               {:owner-id ctx.owner-id
                :extension-id ctx.extension-id})])}))
  true)

(fn drop []
  (when extension-handle
    (extension-handle:unregister)
    (set extension-handle nil))
  true)

{:init init :drop drop}
```

During development, run the graph extension unit tests and the runtime plumbing
test before broader validation:

```bash
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-runtime-plumbing:main
SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-extension-units:main
```
