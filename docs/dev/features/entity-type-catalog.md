# Entity-type catalog and browsing

Entities browsing is composed from explicit, immutable metadata, not discovered
from files, entity records, or registered graph loaders. App composition owns
`app.entity-type-catalog`. The catalog inventories **browsable types**, not every
domain store or graph scheme.

## Descriptors

`entities/type-catalog` exports the `EntityTypeCatalog` factory. Construct it with
`{:types descriptors}`, a dense ordered sequence. Each descriptor requires five
canonical nonempty string fields:

| Field | Meaning |
| --- | --- |
| `id` | Unique type ID and Entities row navigation identity |
| `label` | SearchView row label |
| `action-name` | Node action label |
| `icon` | Existing material-design icon name for that action |
| `browser-key` | Canonical graph key resolved when the type is opened |

`list-types` returns descriptors in declaration order. `get-type` returns the
descriptor for an ID or raises on an unknown ID. Input descriptors and returned
descriptors are copied, so changing either does not mutate catalog contents.
There is no registration/removal API, store, node instance or change signal.

`graph/extensions/builtins.entity-types` returns a fresh built-in sequence:

| ID / label | Action | Icon | Browser key |
| --- | --- | --- | --- |
| string | String Entities | text_fields | string-entity-list |
| link | Link Entities | link | link-entity-list |
| list | List Entities | list | list-entity-list |
| dict | Dict Entities | data_object | dict-entity-list |
| code | Code Entities | code | code-entity-list |

Entities rows remain `[type-id, label]`; actions follow declaration order. The
SearchView presents rows alphabetically, as usual, without changing catalog or
action order. Both row clicks and submissions navigate once through the same
submitted handler.

## Startup composition and separate loader installation

The default is composed by `Main.ensure-built-in-graph-extensions!`. To advertise
a custom type, **precompose only metadata** in `app.entity-type-catalog` before
`Main.init`. Do not call the built-in ensure function at this early phase:
Main composes canonical owning stores through their lazy default getters, including
`app.code-store`, with one normalized root/shared IdentityStore. It constructs the
five-owner reference lifecycle and completes pending recovery/migration before
ensuring built-in loaders or exposing/activating worlds. An early ensure can
capture providers before those ownership/lifecycle checks; repeated ensure reuses
loader handles rather than rebinding them. There is no separate Main-only code cache.

Separately register a graph extension providing the advertised browser loader.
The following custom bootstrap owns engine startup and shutdown. It suppresses
Main's automatic run, precomposes metadata, and registers the custom loader before
runtime creation. The demo module/store belong to that extension, not to Main:

```fennel
(global app {:__suppress-main-run? true})
(local Main (require :main))
(local Builtins (require :graph/extensions/builtins))
(local {:EntityTypeCatalog EntityTypeCatalog} (require :entities/type-catalog))
(local DemoBrowser (require :demo/browser))
(local DemoStore (require :demo/store))
(local demo-store (DemoStore {}))

(local types (Builtins.entity-types))
(table.insert types {:id "demo" :label "demo" :action-name "Demo Entities"
                     :icon "code" :browser-key "demo-entity-list"})
(local catalog (EntityTypeCatalog {:types types}))

(set app.entity-type-catalog catalog)
(local registry (Main.ensure-graph-extension-registry!))
(registry:register-extension
  {:id "demo-browser" :unit-id "demo-browser" :schemes ["demo-entity-list"]
   :install-loaders
   (fn install-demo [graph ctx]
     [(graph:register-key-loader
        "demo-entity-list"
        (fn load-demo [key]
          (when (= key "demo-entity-list") (DemoBrowser {:store demo-store})))
        {:owner-id ctx.owner-id :extension-id ctx.extension-id})])})

(assert (app.engine:start) "engine failed to start")
(Main.init) ; canonical stores, lifecycle recovery/migration, then built-ins/world exposure
(app.engine:run)
(Main.drop)
(app.engine:shutdown)
```

Precomposition above does not install built-ins or capture their stores. The
registry call before `Main.init` installs only the separately owned demo loader;
it must not be replaced with an early built-in ensure call. If initialization is
already complete, an explicit
`Main.ensure-built-in-graph-extensions! {:entity-type-catalog catalog}` is safe
only as reuse of the same catalog/reference and already-initialized app stores.
Do not reset `app` or its catalog in an already-running app. Callers that compose
their own stores without `Main.init` must initialize canonical app-owned stores,
compose/start all five real owners, then ensure built-ins once before activation.
Equivalent directories alone do not satisfy provider identity or shared
IdentityStore ownership. See [Reference lifecycle](reference-lifecycle.md).

The descriptor does **not** install the loader. Registering a loader does **not**
advertise a type. Graph extension descriptors remain the sole loader-installation
mechanism; they capture the owning stores and install into each runtime. Keep the
returned custom extension handle under the extension's normal teardown owner.

The built-in `composition` helper receives app and its lazy registry resolver
explicitly; Main retains registry ownership and its public ensure APIs. Catalog
shape is validated before registry/store dependency work. Registration failures
propagate and roll back earlier registrations through the existing built-ins
registration contract. Neither candidate catalog nor handles are published on
failure. A prior app catalog reference is preserved, so initialization can retry.

Repeated initialization reuses the same catalog/handles. Passing a different
explicit catalog reference while built-ins are installed is an error, even if
its descriptors have identical values. Runtime creation, unloading, loader
uninstallation and adapter refresh do not replace the app catalog. App teardown
unregisters built-ins before releasing its catalog reference. Tests should create
isolated catalogs rather than modifying global membership.

## Map and store ownership

Start advertises `["entities", "entities"]` without constructing Entities during
target collection. Activation resolves that key through its containing GraphMap,
so the built-in loader supplies the app's catalog.

Entities requires `:entity-type-catalog` and derives rows/actions/key dispatch
only from it. Opening a type resolves `browser-key` through the containing map,
adds an explicit display edge, and returns that map's browser adapter. Reopening
does not replace an existing adapter or duplicate topology. Two maps have
independent adapters and edges, even when their injected catalog/store is shared.
Domain stores own entity data; graph core persists topology only.

The code browser captures the same resolved `:code-store` as `code-entity:<id>`
loaders, including an app-owned store. It lists bounded single-line metadata,
never source payloads. Refresh and store create/update/delete events refresh the
listing; opening a row resolves the existing record through the same map. It
does not add a creation or execution surface.

Destructive browser-child actions use explicit lifecycle injection or the checked
mounted GraphMap lifecycle. Existing browser factory exports stay unchanged;
children mounted by actual row submission deliberately acquire service there.
Detached children without explicit injection, conflicting services, same-root
substitute stores, or changed identity-store dependencies error before writes.
The catalog does not register deletion capabilities or own cleanup. Public node
delete actions call logical lifecycle coordination; store `retire-entity!` /
`retire-notebook!` methods are internal physical primitives with no old aliases.

Nodes own their store subscriptions. Views own their SearchView children and
their own node/submitted callbacks. Dropping one view leaves sibling views and
node/store subscriptions live. Map removal/replacement drops the node before
notifying view owners, so Entities and code-browser views tolerate the node-owned
signal having already been cleared. Adapter refresh replaces subscriptions, not
catalog metadata or persisted topology.

## Errors and exclusions

Invalid/dense-sequence metadata, duplicate IDs, unknown type lookup, missing
catalog, and invalid catalog method shape fail loudly. Navigation requires map
load/edge methods. An advertised browser with no resolving loader raises an
error containing its browser key; it is not hidden or turned into a no-op.
Entities views require a node and explicit build context.

This is not a live type registry, generic CRUD framework, filesystem discovery,
identity browser, or notebook-menu migration. Existing entity formats, graph keys,
action labels and persisted topology remain unchanged; the code-list key is
additive. Custom catalog composition does not transfer domain ownership to the
graph or automate loader installation.
