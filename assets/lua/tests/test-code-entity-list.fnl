(local Graph (require :graph/init))
(local {:GraphMap GraphMap} (require :graph/map))
(local Helpers (require :tests/graph-builtin-extension-helpers))
(local BuildContext (require :build-context))
(local tests [])

(fn browser-factory [] (require :graph/nodes/code-entity-list))

(fn assert-error [f text]
  (local (ok err) (pcall f))
  (assert (not ok) (.. "expected error: " text))
  (assert (string.find (tostring err) text 1 true) (tostring err)))

(fn with-runtime [f]
  (local tempfile (require :tempfile))
  (local LinkStore (require :entities/link))
  (local IdentityStore (require :entities/identity))
  (local StringStore (require :entities/string))
  (local dir (tempfile.TemporaryDirectory {:prefix "code-browser-map-stores-"}))
  (local link-store (LinkStore.LinkEntityStore {:base-dir dir.path}))
  (local identity-store (IdentityStore.IdentityStore {:base-dir dir.path}))
  (local string-store (StringStore.StringEntityStore {:base-dir dir.path}))
  (local graph (Graph {:with-start false :entity-events? false
                       :link-store link-store :identity-store identity-store :string-store string-store}))
  (local fixture (Helpers.install-builtins! graph {:only-schemes ["code-entity-list" "code-entity"]
                                                  :link-store link-store :identity-store identity-store
                                                  :string-store string-store}))
  (local map-a (GraphMap {:graph graph :id "code-browser-a"}))
  (local map-b (GraphMap {:graph graph :id "code-browser-b"}))
  (local (ok result) (pcall f fixture.opts.code-store map-a map-b graph fixture.opts))
  (map-a:drop)
  (map-b:drop)
  (graph:drop)
  (fixture:drop)
  (dir:drop)
  (when (not ok) (error result)))

;; Delegate to real signals; instrumentation remains private to this suite.
(fn counted-signal [signal]
  (local counts {:active 0 :connections 0})
  (fn connect [_self handler]
    (set counts.active (+ counts.active 1))
    (set counts.connections (+ counts.connections 1))
    (signal:connect handler))
  (fn disconnect [_self handler _allow-missing]
    (signal:disconnect handler)
    (set counts.active (- counts.active 1)))
  (fn clear [_self]
    (signal:clear)
    (set counts.active 0))
  {:counts counts :connect connect :disconnect disconnect :clear clear
   :emit (fn emit [_self payload] (signal:emit payload))})

(fn instrument-store [store]
  (local counts {:reads 0 :signals []})
  (local list-entities store.list-entities)
  (set store.list-entities
       (fn list-counted-entities [self]
         (set counts.reads (+ counts.reads 1))
         (list-entities self)))
  (each [_ key (ipairs [:code-entity-created :code-entity-updated :code-entity-deleted])]
    (local wrapper (counted-signal (. store key)))
    (set (. store key) wrapper)
    (table.insert counts.signals wrapper.counts))
  counts)

(fn assert-subscriptions [counts active connections]
  (each [_ signal-counts (ipairs counts.signals)]
    (assert (= signal-counts.active active))
    (assert (= signal-counts.connections connections))))

(fn items-by-id [items]
  (local result {})
  (each [_ item (ipairs items)] (set (. result (. (. item 1) :id)) item))
  result)

(fn make-ctx []
  (BuildContext {:clickables (assert app.clickables)
                 :hoverables (assert app.hoverables)}))

(fn browser-requires-store []
  (local factory (browser-factory))
  (assert-error (fn missing-store [] (factory {})) "CodeEntityListNode requires :store"))

(fn listing-is-bounded-single-line-metadata []
  (with-runtime
    (fn exercise-listing [store map-a _map-b _graph]
      (store:create-entity {:id "named" :name "  Alpha\n\t beta  " :source "SECRET SOURCE"})
      (store:create-entity {:id "blank" :name " \n\t " :language "lua" :source "SECRET SOURCE"})
      (store:create-entity {:id "utf8" :name (string.rep "界" 60)})
      (store:create-entity {:id (string.rep "x" 65) :language "lua\n\t jit"})
      (local browser (assert (map-a:load-by-key "code-entity-list")))
      (assert (= browser.store store))
      (assert (= browser.key "code-entity-list"))
      (assert (= browser.label "code entities"))
      (assert (= browser.size 8.0))
      (local items (browser:collect-items))
      (assert (= (length items) 4))
      (local indexed (items-by-id items))
      (assert (= (. indexed.named 2) "Alpha beta"))
      (local fallback (. indexed.blank 2))
      (assert (string.find fallback "blank" 1 true))
      (assert (string.find fallback "lua" 1 true))
      (assert (= (utf8.len (. indexed.utf8 2)) 50))
      (assert (= (string.sub (. indexed.utf8 2) -3) "..."))
      (each [_ item (ipairs items)]
        (assert (<= (utf8.len (. item 2)) 50))
        (assert (not (string.find (. item 2) "[\r\n\t]")))
        (assert (= (. (. item 1) :source) nil) "rows must not carry source payloads")
        (assert (not (string.find (. item 2) "SECRET" 1 true))))
      (assert (= (length browser.actions) 1))
      (assert (= (. (. browser.actions 1) :name) "Refresh"))
      (var emits 0)
      (browser.items-changed:connect (fn count-emits [_items] (set emits (+ emits 1))))
      ((. (. browser.actions 1) :fn) nil nil)
      (assert (= emits 1)))))

(fn exact-loader-and-map-local-opening []
  (with-runtime
    (fn exercise-map-local-opening [store map-a map-b graph]
      (local entity (store:create-entity {:id "shared" :name "Shared"}))
      (assert (= (map-a:load-by-key "code-entity-list:unexpected") nil))
      (local browser-a (assert (map-a:load-by-key "code-entity-list")))
      (local browser-b (assert (map-b:load-by-key "code-entity-list")))
      (assert (= browser-a (map-a:load-by-key "code-entity-list")))
      (assert (not (= browser-a browser-b)))
      (assert (= browser-a.store store))
      (assert (= browser-b.store store))
      (local opened-a (browser-a:add-entity-node entity))
      (local opened-b (browser-b:add-entity-node entity))
      (assert (= opened-a.key "code-entity:shared"))
      (assert (= opened-a.store store))
      (assert (= opened-b.store store))
      (assert (= opened-a.graph map-a))
      (assert (= opened-b.graph map-b))
      (assert (not (= opened-a opened-b)))
      (assert (= opened-a (browser-a:add-entity-node entity)))
      (assert (= opened-b (browser-b:add-entity-node entity)))
      (assert (= (map-a:edge-count) 1))
      (assert (= (map-b:edge-count) 1))
      (assert (= (graph:node-count) 0))
      (assert (= (graph:edge-count) 0)))))

(fn navigation-errors-are-loud []
  (with-runtime
    (fn exercise-navigation-errors [store map-a _map-b _graph]
      (local factory (browser-factory))
      (local unmounted (factory {:store store}))
      (assert-error (fn missing-map [] (unmounted:add-entity-node {:id "missing"}))
                    "missing GraphMap for code-entity:missing")
      (assert-error (fn missing-id [] (unmounted:add-entity-node {})) "requires entity id")
      (unmounted:mount {})
      (assert-error (fn missing-load [] (unmounted:add-entity-node {:id "missing"})) "GraphMap:load-by-key")
      (unmounted:mount {:load-by-key (fn load-nothing [_self _key] nil)})
      (assert-error (fn missing-edge [] (unmounted:add-entity-node {:id "missing"})) "GraphMap:add-edge")
      (unmounted:drop)
      (local browser (assert (map-a:load-by-key "code-entity-list")))
      (store:create-entity {:id "stale"})
      (local stale (. (browser:collect-items) 1))
      (store:retire-entity! "stale")
      (assert-error (fn stale-record [] (browser:add-entity-node (. stale 1))) "failed to load code-entity:stale")
      (assert (= (map-a:edge-count) 0)))))

(fn fixture-ignores-unrelated-default-links []
  (local LinkStore (require :entities/link))
  (local tempfile (require :tempfile))
  (local fs (require :fs))
  (local dir (tempfile.TemporaryDirectory {:prefix "code-browser-unrelated-default-"}))
  ;; Seed only a test-owned stand-in, never the real default singleton.
  (local unrelated (LinkStore.LinkEntityStore {:base-dir dir.path}))
  (unrelated:create-entity {:id "unrelated" :source-key "code-entity-list" :target-key "code-entity:shared"})
  (local path (fs.join-path unrelated.entities-dir "unrelated.json"))
  (local original-content (fs.read-file path))
  (local get-default LinkStore.get-default)
  (fn exercise-maps [store map-a map-b graph options]
    (local entity (store:create-entity {:id "shared" :name "Shared"}))
    (each [_ graph-map (ipairs [map-a map-b])]
      (local browser (assert (graph-map:load-by-key "code-entity-list")))
      (local target (assert (graph-map:load-by-key "code-entity:shared")))
      (assert (= (graph-map:edge-count) 0) "fixture must ignore unrelated default-store topology")
      (assert (= (browser:add-entity-node entity) target))
      (assert (= (browser:add-entity-node entity) target))
      (assert (= (graph-map:edge-count) 1)))
    (assert (= graph.link-store options.link-store))
    (assert (= graph.identity-store options.identity-store))
    (assert (= graph.string-store options.string-store))
    (assert (= (graph:node-count) 0))
    (assert (= (graph:edge-count) 0)))
  (set LinkStore.get-default (fn unrelated-default [_opts] unrelated))
  (local (ok result)
    (pcall
      (fn exercise-isolation []
        (with-runtime exercise-maps)
        ;; Verify preservation after the fixture and both maps have been dropped.
        (assert (= (length (unrelated:list-entities)) 1) "unrelated data must remain untouched")
        (assert (= (fs.read-file path) original-content) "unrelated persisted link must remain byte-for-byte unchanged"))))
  (set LinkStore.get-default get-default)
  (dir:drop)
  (when (not ok) (error result)))

(fn real-store-events-and-node-cleanup []
  (with-runtime
    (fn exercise-store-events [store map-a map-b _graph]
      (local counts (instrument-store store))
      (local browser-a (assert (map-a:load-by-key "code-entity-list")))
      (assert-subscriptions counts 1 1)
      (local browser-b (assert (map-b:load-by-key "code-entity-list")))
      (assert-subscriptions counts 2 2)
      (local seen-a [])
      (local seen-b [])
      (browser-a.items-changed:connect (fn observe-a [items] (table.insert seen-a items)))
      (browser-b.items-changed:connect (fn observe-b [items] (table.insert seen-b items)))
      (store:create-entity {:id "live" :name "Before"})
      (store:update-entity "live" {:name "After"})
      (store:retire-entity! "live")
      (assert (= (length seen-a) 3))
      (assert (= (length seen-b) 3))
      (assert (= (. (. (. seen-a 1) 1) 2) "Before"))
      (assert (= (. (. (. seen-a 2) 1) 2) "After"))
      (assert (= (length (. seen-a 3)) 0))
      (assert (= counts.reads 6))
      (browser-a:drop)
      (browser-a:drop)
      (assert-subscriptions counts 1 2)
      (store:create-entity {:id "still-live"})
      (assert (= counts.reads 7))
      (assert (= (length seen-a) 3))
      (assert (= (length seen-b) 4))
      (browser-b:drop)
      (browser-b:drop)
      (assert-subscriptions counts 0 2)
      (store:update-entity "still-live" {:name "Unobserved"})
      (store:retire-entity! "still-live")
      (assert (= counts.reads 7)))))

(fn two-views-route-and-drop-independently []
  (with-runtime
    (fn exercise-view-lifecycle [store map-a _map-b _graph]
      (local counts (instrument-store store))
      (store:create-entity {:id "z" :name "Zulu"})
      (store:create-entity {:id "a" :name "Alpha"})
      (local browser (assert (map-a:load-by-key "code-entity-list")))
      (set browser.items-changed (counted-signal browser.items-changed))
      (local navigate browser.add-entity-node)
      (var opens 0)
      (set browser.add-entity-node
           (fn count-navigation [self entity]
             (set opens (+ opens 1))
             (navigate self entity)))
      (local ctx (make-ctx))
      (local view-a ((browser.view browser) ctx))
      (local view-b ((browser.view browser) ctx))
      (assert (= view-a.layout view-a.search.layout))
      (assert (= browser.items-changed.counts.active 2))
      (assert (= browser.items-changed.counts.connections 2))
      (assert (= (length view-a.search.items) 2))
      (assert (= (. (. view-a.search.items 1) 2) "Alpha"))
      (local button (. view-a.search.list-view.item-widgets 1))
      (button.clicked:emit nil)
      (assert (= opens 1) "default row must route exactly once")
      (assert (= (. (map-a:lookup "code-entity:a") :store) store))
      (view-b.search.submitted:emit (. view-b.search.items 2))
      (assert (= opens 2))
      (assert (= (. (map-a:lookup "code-entity:z") :store) store))
      (assert (= (map-a:edge-count) 2))
      (store:update-entity "z" {:name "Beta"})
      (assert (= (. (. view-a.search.items 2) 2) "Beta"))
      (assert (= (. (. view-b.search.items 2) 2) "Beta"))
      (view-a:drop)
      (view-a:drop)
      (assert (= view-a.search.list-view.scroll-view nil))
      (assert (= browser.items-changed.counts.active 1))
      (view-a.search.submitted:emit (. view-a.search.items 1))
      (assert (= opens 2) "dropped view must disconnect navigation")
      (store:create-entity {:id "c" :name "Charlie"})
      (assert (= (length view-a.search.items) 2))
      (assert (= (length view-b.search.items) 3))
      (view-b.search.submitted:emit (. view-b.search.items 3))
      (assert (= opens 3))
      (store:retire-entity! "c")
      (assert (= (length view-b.search.items) 2))
      (view-b:refresh-items)
      (view-b:drop)
      (assert (= browser.items-changed.counts.active 0))
      (assert (= view-b.search.list-view.scroll-view nil))
      (local reads counts.reads)
      (store:create-entity {:id "node-still-live"})
      (assert (= counts.reads (+ reads 1)) "views must not drop node/store subscriptions")
      (assert (= (length (browser:collect-items)) 3)))))

(fn view-requires-build-context []
  (with-runtime
    (fn exercise-missing-build-context [store _map-a _map-b _graph]
      (local browser ((browser-factory) {:store store}))
      (assert-error (fn missing-context [] ((browser.view browser) nil)) "CodeEntityListNodeView requires a build context")
      (browser:drop))))

(fn make-teardown-views [browser]
  (local counts {:opens 0})
  (local navigate browser.add-entity-node)
  (fn count-navigation [self entity]
    (set counts.opens (+ counts.opens 1))
    (navigate self entity))
  (set browser.add-entity-node count-navigation)
  (local ctx (make-ctx))
  (local views [((browser.view browser) ctx) ((browser.view browser) ctx)])
  (local first-view (. views 1))
  (local item (. first-view.search.items 1))
  (first-view.search.submitted:emit item)
  (assert (= counts.opens 1) "navigation must be live before teardown")
  {:views views :counts counts :item item})

(fn drop-teardown-views [state]
  (each [_ view (ipairs state.views)]
    (view:drop)
    (view:drop)))

(fn assert-teardown-complete [state]
  (each [_ view (ipairs state.views)]
    (assert view.search.__dropped "both SearchView children must be dropped")
    (assert (= view.search.list-view.scroll-view nil) "ListView must release its scroll child")
    (assert-error (fn drop-input-again [] (view.search.input:drop)) "Input dropped twice")
    (view.search.submitted:emit state.item))
  (assert (= state.counts.opens 1) "both views must disconnect navigation"))

(fn node-before-two-views-teardown []
  (with-runtime
    (fn exercise-node-first-teardown [store map-a _map-b _graph]
      (store:create-entity {:id "teardown" :name "Teardown"})
      (local browser (assert (map-a:load-by-key "code-entity-list")))
      (local state (make-teardown-views browser))
      (browser:drop)
      (drop-teardown-views state)
      (assert-teardown-complete state))))

(fn map-removal-notification-drops-two-views []
  (with-runtime
    (fn exercise-removal-teardown [store map-a _map-b _graph]
      (store:create-entity {:id "teardown" :name "Teardown"})
      (local browser (assert (map-a:load-by-key "code-entity-list")))
      (local state (make-teardown-views browser))
      (var notifications 0)
      (fn on-removed [payload]
        (assert (= (. payload.nodes 1) browser))
        (assert (= browser.graph nil) "node must be unmounted before notification")
        (drop-teardown-views state)
        (set notifications (+ notifications 1)))
      (local handler (map-a.node-removed:connect on-removed))
      (assert (= (map-a:remove-nodes [browser]) 1))
      (assert (= notifications 1))
      (assert (= (map-a:lookup "code-entity-list") nil))
      (assert-teardown-complete state)
      (map-a.node-removed:disconnect handler))))

(fn map-replacement-notification-drops-two-views []
  (with-runtime
    (fn exercise-replacement-teardown [store map-a _map-b _graph]
      (store:create-entity {:id "teardown" :name "Teardown"})
      (local browser (assert (map-a:load-by-key "code-entity-list")))
      (local state (make-teardown-views browser))
      (local replacement ((browser-factory) {:store store}))
      (var notifications 0)
      (fn on-replaced [payload]
        (assert (= payload.old browser))
        (assert (= payload.new replacement))
        (assert (= browser.graph nil) "old node must be unmounted before notification")
        (drop-teardown-views state)
        (set notifications (+ notifications 1)))
      (local handler (map-a.node-replaced:connect on-replaced))
      (assert (= (map-a:add-node replacement) replacement))
      (assert (= notifications 1))
      (assert (= (map-a:lookup "code-entity-list") replacement))
      (assert (= replacement.graph map-a))
      (assert-teardown-complete state)
      (local replacement-view ((replacement.view replacement) (make-ctx)))
      (store:update-entity "teardown" {:name "Still live"})
      (assert (= (. (. replacement-view.search.items 1) 2) "Still live"))
      (replacement-view:drop)
      (map-a.node-replaced:disconnect handler))))

(table.insert tests {:name "code browser requires explicit store" :fn browser-requires-store})
(table.insert tests {:name "code browser lists bounded single-line metadata" :fn listing-is-bounded-single-line-metadata})
(table.insert tests {:name "code browser exact loader and map-local deduplication" :fn exact-loader-and-map-local-opening})
(table.insert tests {:name "code browser fixture ignores unrelated default-store links" :fn fixture-ignores-unrelated-default-links})
(table.insert tests {:name "code browser navigation errors are loud" :fn navigation-errors-are-loud})
(table.insert tests {:name "code browser real store signals and idempotent cleanup" :fn real-store-events-and-node-cleanup})
(table.insert tests {:name "code browser two views route and drop independently" :fn two-views-route-and-drop-independently})
(table.insert tests {:name "code browser view requires build context" :fn view-requires-build-context})
(table.insert tests {:name "code browser node-before-two-views teardown" :fn node-before-two-views-teardown})
(table.insert tests {:name "code browser map removal notification drops two views" :fn map-removal-notification-drops-two-views})
(table.insert tests {:name "code browser map replacement notification drops two views" :fn map-replacement-notification-drops-two-views})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "test-code-entity-list" :tests tests}))

{:tests tests :main main}
