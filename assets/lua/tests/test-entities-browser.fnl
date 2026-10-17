(local Graph (require :graph/init))
(local {:GraphMap GraphMap} (require :graph/map))
(local Helpers (require :tests/graph-builtin-extension-helpers))
(local Builtins (require :graph/extensions/builtins))
(local {:EntityTypeCatalog EntityTypeCatalog} (require :entities/type-catalog))
(local EntitiesNode (require :graph/nodes/entities))
(local BuildContext (require :build-context))
(local tests [])

(fn assert-error [f text]
  (local (ok err) (pcall f))
  (assert (not ok) (.. "expected error: " text))
  (assert (string.find (tostring err) text 1 true) (tostring err)))

(fn demo-catalog []
  (local types (Builtins.entity-types))
  (table.insert types {:id "demo" :label "demo" :action-name "Demo Entities"
                       :icon "code" :browser-key "demo-entity-list"})
  (EntityTypeCatalog {:types types}))

(fn with-maps [f]
  (local catalog (demo-catalog))
  (local tempfile (require :tempfile))
  (local LinkStore (require :entities/link))
  (local IdentityStore (require :entities/identity))
  (local StringStore (require :entities/string))
  (local dir (tempfile.TemporaryDirectory {:prefix "entities-map-stores-"}))
  (local link-store (LinkStore.LinkEntityStore {:base-dir dir.path}))
  (local identity-store (IdentityStore.IdentityStore {:base-dir dir.path}))
  (local string-store (StringStore.StringEntityStore {:base-dir dir.path}))
  (local graph (Graph {:with-start false :entity-events? false
                       :link-store link-store :identity-store identity-store :string-store string-store}))
  (local fixture (Helpers.install-builtins! graph {:entity-type-catalog catalog
                                                  :link-store link-store :identity-store identity-store
                                                  :string-store string-store}))
  ;; Metadata intentionally does not install this loader.
  (local handle (graph:register-key-loader "demo-entity-list"
                  (fn load-demo [key]
                    (when (= key "demo-entity-list")
                      (Graph.GraphNode {:key key :label "demo entities"})))))
  (local map-a (GraphMap {:graph graph :id "entities-a"}))
  (local map-b (GraphMap {:graph graph :id "entities-b"}))
  (local (ok result) (pcall f catalog fixture.opts map-a map-b graph))
  (map-a:drop)
  (map-b:drop)
  (handle:unregister)
  (graph:drop)
  (fixture:drop)
  (dir:drop)
  (when (not ok) (error result)))

(fn rows-actions-and-map-local-loaders []
  (with-maps
    (fn exercise [catalog options map-a map-b graph]
      (local a (assert (map-a:load-by-key "entities")))
      (local b (assert (map-b:load-by-key "entities")))
      (assert (= a.entity-type-catalog catalog))
      (assert (= b.entity-type-catalog catalog))
      (assert (not (= a b)))
      (local rows (a:collect-types))
      (local descriptors (catalog:list-types))
      (assert (= (length rows) 6))
      (assert (= (length a.actions) 6))
      (var emissions 0)
      (a.types-changed:connect (fn on-types [items]
                                 (assert (= (length items) 6))
                                 (set emissions (+ emissions 1))))
      (a:emit-types)
      (assert (= emissions 1))
      (each [i descriptor (ipairs descriptors)]
        (assert (= (. (. rows i) 1) descriptor.id))
        (assert (= (. (. rows i) 2) descriptor.label))
        (local action (. a.actions i))
        (assert (= action.name descriptor.action-name))
        (assert (= action.icon descriptor.icon))
        ;; Invoked after construction: catches loop-variable closure capture.
        (action.fn nil nil)
        (local opened-a (assert (map-a:lookup descriptor.browser-key)))
        (local opened-b (b:add-type-node descriptor.id))
        (assert (= opened-b.key descriptor.browser-key))
        (assert (= opened-a.graph map-a))
        (assert (= opened-b.graph map-b))
        (assert (not (= opened-a opened-b)))
        (assert (= (a:add-type-node descriptor.id) opened-a))
        (when (not (= descriptor.id "demo"))
          (local store (. options (.. descriptor.id "-store")))
          (assert (= opened-a.store store))
          (assert (= opened-b.store store))))
      (assert (= (map-a:edge-count) 6))
      (assert (= (map-b:edge-count) 6))
      (assert (= (graph:node-count) 0))
      (assert (= (graph:edge-count) 0)))))

(fn fixture-ignores-unrelated-default-links []
  (local LinkStore (require :entities/link))
  (local tempfile (require :tempfile))
  (local dir (tempfile.TemporaryDirectory {:prefix "entities-unrelated-default-"}))
  ;; This stand-in represents persistent default data without opening or changing
  ;; the real default singleton. Only this test-owned temporary store is seeded.
  (local unrelated (LinkStore.LinkEntityStore {:base-dir dir.path}))
  (unrelated:create-entity {:id "unrelated" :source-key "entities" :target-key "code-entity-list"})
  (local before (unrelated:snapshot-entity "unrelated"))
  (local original-target before.value.target-key)
  (local get-default LinkStore.get-default)
  (set LinkStore.get-default (fn unrelated-default [_opts] unrelated))
  (local (ok result)
    (pcall with-maps
      (fn exercise-isolation [_catalog options map-a map-b graph]
        (local entities (map-a:load-by-key "entities"))
        (entities:add-type-node "code")
        (assert (= (map-a:edge-count) 1) "fixture must ignore unrelated default-store display links")
        (assert (= (map-b:edge-count) 0))
        (assert (= graph.link-store options.link-store))
        (assert (= graph.identity-store options.identity-store))
        (assert (= (length (unrelated:list-entities)) 1) "unrelated data must remain untouched")
         (local after (unrelated:snapshot-entity "unrelated"))
         (assert (= after.bytes before.bytes) "navigation must preserve exact unrelated owning bytes")
         (assert (= after.value.target-key original-target))
         (assert (= (string.sub original-target 1 9) "identity:"))
         (assert (= (unrelated.identity-store:resolve-key original-target) "code-entity-list")))))
  (set LinkStore.get-default get-default)
  (dir:drop)
  (when (not ok) (error result)))

(fn navigation-errors []
  (assert-error (fn missing-catalog [] (EntitiesNode {})) "EntitiesNode requires :entity-type-catalog")
  (local EntityExtension (require :graph/extensions/builtins/entities))
  (local descriptor (. (EntityExtension.descriptors {}) 1))
  (assert-error (fn missing-loader-catalog [] (descriptor.install-loaders {} {}))
                "builtin-graph-entities requires :entity-type-catalog")
  (with-maps
    (fn exercise [catalog _options map-a _map-b _graph]
      (local node (EntitiesNode {:entity-type-catalog catalog}))
      (assert-error (fn unknown [] (node:add-type-node "unknown")) "unknown")
      (assert-error (fn missing-map [] (node:add-type-node "code")) "missing GraphMap for code-entity-list")
      (node:mount {})
      (assert-error (fn missing-load [] (node:add-type-node "code")) "GraphMap:load-by-key")
      (node:mount {:load-by-key (fn load-nothing [_self _key] nil)})
      (assert-error (fn missing-edge [] (node:add-type-node "code")) "GraphMap:add-edge")
      (node:drop)
      (local missing-catalog (EntityTypeCatalog {:types [{:id "missing" :label "missing"
                                                        :action-name "Missing" :icon "code"
                                                        :browser-key "unregistered-browser"}]}))
      (local missing (EntitiesNode {:entity-type-catalog missing-catalog}))
      (map-a:add-node missing)
      (assert-error (fn unresolved [] (missing:add-type-node "missing")) "failed to load unregistered-browser")
      (assert (= (map-a:edge-count) 0)))))

(fn make-ctx []
  (BuildContext {:clickables (assert app.clickables) :hoverables (assert app.hoverables)}))

(fn two-views-route-and-disconnect []
  (with-maps
    (fn exercise [_catalog _options map-a _map-b _graph]
      (local node (map-a:load-by-key "entities"))
      (local navigate node.add-type-node)
      (var opens 0)
      (set node.add-type-node (fn count-navigation [self id] (set opens (+ opens 1)) (navigate self id)))
      (local view-a ((node.view node) (make-ctx)))
      (local view-b ((node.view node) (make-ctx)))
      (local expected ["code" "demo" "dict" "link" "list" "string"])
      (each [i id (ipairs expected)]
        (assert (= (. (. view-a.search.items i) 1) id)))
      (local button (. view-a.search.list-view.item-widgets 1))
      (button.clicked:emit nil)
      (assert (= opens 1))
      (assert (map-a:lookup "code-entity-list"))
      (view-b.search.submitted:emit (. view-b.search.items 2))
      (assert (= opens 2))
      (assert (map-a:lookup "demo-entity-list"))
      (view-a:drop)
      (view-a:drop)
      (assert view-a.search.__dropped)
      (view-a.search.submitted:emit (. view-a.search.items 1))
      (assert (= opens 2))
      ;; A dropped view must not receive this emission; the sibling remains live.
      (node:emit-types)
      (view-b.search.submitted:emit (. view-b.search.items 3))
      (assert (= opens 3))
      (view-b:drop)
      (node:emit-types))))

(fn node-first-map-teardown [replace?]
  (with-maps
    (fn exercise [catalog _options map-a _map-b _graph]
      (local node (map-a:load-by-key "entities"))
      (local views [((node.view node) (make-ctx)) ((node.view node) (make-ctx))])
      (local navigate node.add-type-node)
      (var opens 0)
      (set node.add-type-node (fn count-navigation [self id] (set opens (+ opens 1)) (navigate self id)))
      (var notifications 0)
      (fn on-teardown [_payload]
        (assert (= node.graph nil))
        (each [_ view (ipairs views)] (view:drop) (view:drop))
        (set notifications (+ notifications 1)))
      (local signal (if replace? map-a.node-replaced map-a.node-removed))
      (local handler (signal:connect on-teardown))
      (if replace?
          (map-a:add-node (EntitiesNode {:entity-type-catalog catalog}))
          (map-a:remove-nodes [node]))
      (assert (= notifications 1))
      (each [_ view (ipairs views)]
        (assert view.search.__dropped)
        (assert (= view.search.list-view.scroll-view nil))
        (assert-error (fn drop-input-again [] (view.search.input:drop)) "Input dropped twice")
        (view.search.submitted:emit (. view.search.items 1)))
      (assert (= opens 0))
      (signal:disconnect handler))))

(fn view-errors []
  (local View (require :graph/view/views/entities))
  (assert-error (fn missing-node [] (View nil)) "EntitiesNodeView requires node")
  (local node (EntitiesNode {:entity-type-catalog (demo-catalog)}))
  (assert-error (fn missing-context [] ((View node) nil)) "EntitiesNodeView requires a build context")
  (node:drop))

(fn start-preserves-targets-and-errors []
  (with-maps
    (fn exercise [_catalog _options map-a _map-b _graph]
      (local StartNode (require :graph/nodes/start))
      (local unmounted (StartNode))
      (assert-error (fn missing-map [] (unmounted:add-target "entities")) "missing GraphMap for entities")
      (unmounted:mount {})
      (assert-error (fn missing-load [] (unmounted:add-target "entities")) "GraphMap:load-by-key")
      (unmounted:mount {:load-by-key (fn load-nothing [_self _key] nil)})
      (assert-error (fn missing-edge [] (unmounted:add-target "entities")) "GraphMap:add-edge")
      (unmounted:drop)
      (local start (map-a:load-by-key "start"))
      (assert-error (fn unresolved [] (start:add-target "missing-start-target")) "failed to load missing-start-target")
      (local target (map-a:load-by-key "demo-entity-list"))
      (assert (= (start:add-target target) target))
      (var calls 0)
      (fn make-target [] (set calls (+ calls 1)) (map-a:load-by-key "quit"))
      (assert (= (. (start:add-target make-target) :key) "quit"))
      (assert (= calls 1))
      (assert (= (map-a:edge-count) 2)))))

(fn start-to-existing-code-smoke []
  (with-maps
    (fn exercise [catalog options map-a map-b _graph]
      (options.code-store:create-entity {:id "smoke" :name "Existing code" :source "return 42"})
      (local start (map-a:load-by-key "start"))
      (local targets (start:collect-targets))
      (var entities-target nil)
      (each [_ row (ipairs targets)]
        (if (= (. row 2) "entities")
            (set entities-target (. row 1))
            ;; collect-targets still owns the other eagerly constructed adapters.
            (when (= (type (. row 1)) "table") ((. (. row 1) :drop) (. row 1)))))
      (assert (= entities-target "entities"))
      (assert (= (map-a:lookup "entities") nil) "collection must not resolve Entities")
      (local entities (start:add-target entities-target))
      (assert (= entities.entity-type-catalog catalog))
      (local view ((entities.view entities) (make-ctx)))
      (local code-button (. view.search.list-view.item-widgets 1))
      (code-button.clicked:emit nil)
      (local browser (assert (map-a:lookup "code-entity-list")))
      (local code-view ((browser.view browser) (make-ctx)))
      (code-view.search.submitted:emit (. code-view.search.items 1))
      (local entity (assert (map-a:lookup "code-entity:smoke")))
      (assert (= entity.store options.code-store))
      (assert (= (map-a:edge-count) 3))
      (assert (= (map-b:node-count) 0))
      (code-view:drop)
      (view:drop))))

(fn counted-store-signal [signal]
  (local counts {:active 0 :connections 0 :disconnections 0 :handlers {}})
  (fn connect [_self handler]
    (signal:connect handler)
    (when (= counts.first-handler nil) (set counts.first-handler handler))
    (set (. counts.handlers handler) true)
    (set counts.active (+ counts.active 1))
    (set counts.connections (+ counts.connections 1))
    handler)
  (fn disconnect [_self handler allow-missing]
    (signal:disconnect handler allow-missing)
    (when (. counts.handlers handler)
      (set (. counts.handlers handler) nil)
      (set counts.active (- counts.active 1))
      (set counts.disconnections (+ counts.disconnections 1))))
  {:counts counts :connect connect :disconnect disconnect
   :emit (fn emit [_self payload] (signal:emit payload))})

(fn instrument-code-signals [store]
  (icollect [_ key (ipairs [:code-entity-created :code-entity-updated :code-entity-deleted])]
    (do
      (local wrapper (counted-store-signal (. store key)))
      (set (. store key) wrapper)
      wrapper.counts)))

(fn assert-refresh-subscriptions [counts expected-active expected-connections expected-disconnections]
  (each [i count (ipairs counts)]
    (assert (= count.active (. expected-active i)))
    (assert (= count.connections (. expected-connections i)))
    (assert (= count.disconnections expected-disconnections))))

(fn refresh-code-adapter-preserves-catalog-and-topology []
  (with-maps
    (fn exercise [catalog options map-a _map-b _graph]
      (options.code-store:create-entity {:id "refresh" :name "Before"})
      (local counts (instrument-code-signals options.code-store))
      (local entities (map-a:load-by-key "entities"))
      (local old (entities:add-type-node "code"))
      (assert-refresh-subscriptions counts [1 1 1] [1 1 1] 0)
      (old:add-entity-node {:id "refresh"})
      (assert-refresh-subscriptions counts [1 2 2] [1 2 2] 0)
      (var old-emits 0)
      (old.items-changed:connect (fn count-old-emits [_items] (set old-emits (+ old-emits 1))))
      (map-a:refresh-adapters-by-scheme "code-entity-list")
      (local replacement (assert (map-a:lookup "code-entity-list")))
      (assert (not (= old replacement)))
      (assert (= replacement.store options.code-store))
      (assert (= (map-a:edge-count) 2))
      (assert (= entities.entity-type-catalog catalog))
      (assert-refresh-subscriptions counts [1 2 2] [2 3 3] 1)
      (each [_ count (ipairs counts)]
        (assert (= (. count.handlers count.first-handler) nil) "old browser subscription must be gone"))
      (var emits 0)
      (replacement.items-changed:connect (fn count-emits [_items] (set emits (+ emits 1))))
      (options.code-store:update-entity "refresh" {:name "After"})
      (assert (= old-emits 0))
      (assert (= emits 1))
      (assert (= (. (. (replacement:collect-items) 1) 2) "After"))
      (map-a:remove-nodes [replacement])
      (assert-refresh-subscriptions counts [0 1 1] [2 3 3] 2)
      (map-a:remove-nodes [(map-a:lookup "code-entity:refresh")])
      (each [_ count (ipairs counts)] (assert (= count.active 0))))))

(table.insert tests {:name "Entities catalog rows/actions and six map-local loaders" :fn rows-actions-and-map-local-loaders})
(table.insert tests {:name "Entities fixture ignores unrelated default-store links" :fn fixture-ignores-unrelated-default-links})
(table.insert tests {:name "Entities navigation errors are explicit" :fn navigation-errors})
(table.insert tests {:name "Entities two views sort route and disconnect" :fn two-views-route-and-disconnect})
(table.insert tests {:name "Entities node-first map removal teardown" :fn (fn [] (node-first-map-teardown false))})
(table.insert tests {:name "Entities node-first map replacement teardown" :fn (fn [] (node-first-map-teardown true))})
(table.insert tests {:name "Entities view requires node and context" :fn view-errors})
(table.insert tests {:name "Start preserves function and node targets with loud string errors" :fn start-preserves-targets-and-errors})
(table.insert tests {:name "Start lazy Entities to code UI smoke" :fn start-to-existing-code-smoke})
(table.insert tests {:name "Code adapter refresh retains catalog and topology" :fn refresh-code-adapter-preserves-catalog-and-topology})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "test-entities-browser" :tests tests}))

{:tests tests :main main}
