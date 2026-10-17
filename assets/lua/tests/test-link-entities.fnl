(local fs (require :fs))
(local H (require :tests/test-reference-lifecycle-helpers))
(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "link-entities"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "entities-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn with-temp-store [f]
  (with-temp-dir
    (fn [root]
      (local LinkEntityStore (require :entities/link))
      (local store (LinkEntityStore.LinkEntityStore {:base-dir root}))
      (f store root))))

(fn disconnect-signal-handlers [records]
  (each [_ record (ipairs records)]
    (record.signal:disconnect record.handler true)))

(fn rethrow-after-signal-cleanup [ok result cleanup-records]
  (local (cleanup-ok cleanup-result) (pcall disconnect-signal-handlers cleanup-records))
  (if (not ok)
      (error result)
      (not cleanup-ok)
      (error cleanup-result)))

(fn exercise-link-created-signal [store counts]
  (store:create-entity {:source-key "a" :target-key "b"})
  (assert (= counts.created 1) "created signal should be emitted"))

(fn exercise-link-updated-signal [store counts]
  (local entity (store:create-entity {:source-key "a" :target-key "b"}))
  (store:update-entity entity.id {:source-key "c"})
  (assert (= counts.updated 1) "updated signal should be emitted"))

(fn exercise-link-deleted-signal [store counts]
  (local entity (store:create-entity {:source-key "a" :target-key "b"}))
  (store:retire-entity! entity.id)
  (assert (= counts.deleted 1) "deleted signal should be emitted"))

(fn link-entity-store-creates-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:source-key "node-a"
                                          :target-key "node-b"}))
      (assert entity "entity should be created")
      (assert entity.id "entity should have id")
      (H.assert-reference store.identity-store entity.source-key "node-a")
      (H.assert-reference store.identity-store entity.target-key "node-b")
      (assert entity.created-at "entity should have created-at"))))

(fn link-entity-store-retrieves-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:source-key "node-a"
                                          :target-key "node-b"}))
      (local retrieved (store:get-entity entity.id))
      (assert retrieved "entity should be retrieved")
      (assert (= retrieved.id entity.id) "retrieved entity should have same id")
      (H.assert-reference store.identity-store retrieved.source-key "node-a")
      (H.assert-reference store.identity-store retrieved.target-key "node-b"))))

(fn link-entity-store-updates-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:source-key "node-a"
                                          :target-key "node-b"}))
      (local updated (store:update-entity entity.id {:source-key "node-c"}))
      (assert updated "entity should be updated")
      (H.assert-reference store.identity-store updated.source-key "node-c")
      (local retrieved (store:get-entity entity.id))
      (H.assert-reference store.identity-store retrieved.source-key "node-c"))))

(fn link-entity-store-deletes-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:source-key "node-a"
                                          :target-key "node-b"}))
      (local deleted (store:retire-entity! entity.id))
      (assert deleted "entity should be deleted")
      (local retrieved (store:get-entity entity.id))
      (assert (= retrieved nil) "entity should no longer be retrievable"))))

(fn link-entity-store-lists-entities []
  (with-temp-store
    (fn [store _root]
      (store:create-entity {:source-key "a" :target-key "b"})
      (store:create-entity {:source-key "c" :target-key "d"})
      (store:create-entity {:source-key "e" :target-key "f"})
      (local entities (store:list-entities))
      (assert (= (length entities) 3) "should list three entities"))))

(fn link-entity-store-emits-created-signal []
  (with-temp-store
    (fn [store _root]
      (local counts {:created 0})
      (local created-handler (fn [_] (set counts.created (+ counts.created 1))))
      (store.link-entity-created:connect created-handler)
      (local (ok result) (pcall exercise-link-created-signal store counts))
      (rethrow-after-signal-cleanup
        ok result [{:signal store.link-entity-created :handler created-handler}]))))

(fn link-entity-store-emits-updated-signal []
  (with-temp-store
    (fn [store _root]
      (local counts {:updated 0})
      (local updated-handler (fn [_] (set counts.updated (+ counts.updated 1))))
      (store.link-entity-updated:connect updated-handler)
      (local (ok result) (pcall exercise-link-updated-signal store counts))
      (rethrow-after-signal-cleanup
        ok result [{:signal store.link-entity-updated :handler updated-handler}]))))

(fn link-entity-store-emits-deleted-signal []
  (with-temp-store
    (fn [store _root]
      (local counts {:deleted 0})
      (local deleted-handler (fn [_] (set counts.deleted (+ counts.deleted 1))))
      (store.link-entity-deleted:connect deleted-handler)
      (local (ok result) (pcall exercise-link-deleted-signal store counts))
      (rethrow-after-signal-cleanup
        ok result [{:signal store.link-entity-deleted :handler deleted-handler}]))))

(fn link-entity-store-stores-metadata []
  (with-temp-store
    (fn [store root]
      (local entity (store:create-entity {:source-key "a"
                                          :target-key "b"
                                          :metadata {:foo "bar" :nested {:x 1}}}))
      (local LinkEntityStore (require :entities/link))
      (local new-store (LinkEntityStore.LinkEntityStore {:base-dir root}))
      (local retrieved (new-store:get-entity entity.id))
      (assert (= retrieved.metadata.foo "bar") "metadata.foo should be preserved")
      (assert (= retrieved.metadata.nested.x 1) "nested metadata should be preserved"))))

(fn link-entity-store-finds-edges-for-nodes []
  (with-temp-store
    (fn [store _root]
      (store:create-entity {:source-key "a" :target-key "b"})
      (store:create-entity {:source-key "b" :target-key "c"})
      (store:create-entity {:source-key "x" :target-key "y"})
      (local found (store:find-edges-for-nodes ["a" "b"]))
      (assert (= (length found) 1) "should find one link with both a and b")
      (local found2 (store:find-edges-for-nodes ["a" "b" "c"]))
      (assert (= (length found2) 2) "should find two links with a, b, c"))))

(fn link-entity-node-loads []
  (local {:LinkEntityNode LinkEntityNode} (require :graph/nodes/link-entity))
  (assert LinkEntityNode "LinkEntityNode should load")
  (assert (= (type LinkEntityNode) "function") "LinkEntityNode should be a function"))

(fn link-entity-node-creates-with-correct-properties []
  (with-temp-store
    (fn [store _root]
      (local {:LinkEntityNode LinkEntityNode} (require :graph/nodes/link-entity))
      (local entity (store:create-entity {:source-key "node-a" :target-key "node-b"}))
      (local node (LinkEntityNode {:entity-id entity.id :store store}))
      (assert (= node.key (.. "link-entity:" entity.id)) "key should be prefixed entity id")
      (assert node.color "should have color")
      (assert node.entity-deleted "should have entity-deleted signal")
      (assert node.get-entity "should have get-entity method")
      (assert node.update-source "should have update-source method")
      (assert node.update-target "should have update-target method")
      (assert node.delete-entity "should have delete-entity method")
      (node:drop))))

(fn link-entity-list-node-loads []
  (local LinkEntityListNode (require :graph/nodes/link-entity-list))
  (assert LinkEntityListNode "LinkEntityListNode should load")
  (assert (= (type LinkEntityListNode) "function") "LinkEntityListNode should be a function"))

(fn link-entity-list-node-creates-with-correct-properties []
  (local LinkEntityListNode (require :graph/nodes/link-entity-list))
  (local node (LinkEntityListNode {}))
  (assert (= node.key "link-entity-list") "key should be 'link-entity-list'")
  (assert (= node.label "link entities") "label should be 'link entities'")
  (assert node.color "should have color")
  (assert node.items-changed "should have items-changed signal")
  (assert node.collect-items "should have collect-items method")
  (assert node.emit-items "should have emit-items method")
  (assert node.add-entity-node "should have add-entity-node method")
  (assert node.create-entity "should have create-entity method"))

(fn link-entity-node-view-loads []
  (local LinkEntityNodeView (require :graph/view/views/link-entity))
  (assert LinkEntityNodeView "LinkEntityNodeView should load")
  (assert (= (type LinkEntityNodeView) "function") "LinkEntityNodeView should be a function"))

(fn link-entity-list-node-view-loads []
  (local LinkEntityListNodeView (require :graph/view/views/link-entity-list))
  (assert LinkEntityListNodeView "LinkEntityListNodeView should load")
  (assert (= (type LinkEntityListNodeView) "function") "LinkEntityListNodeView should be a function"))

(fn entities-node-includes-link-type []
  (local EntitiesNode (require :graph/nodes/entities))
  (local {:EntityTypeCatalog EntityTypeCatalog} (require :entities/type-catalog))
  (local Builtins (require :graph/extensions/builtins))
  (local node (EntitiesNode {:entity-type-catalog (EntityTypeCatalog {:types (Builtins.entity-types)})}))
  (local types (node:collect-types))
  (var found-link false)
  (each [_ t (ipairs types)]
    (when (= (. t 1) :link)
      (set found-link true)))
  (assert found-link "entities node should include link type"))

(table.insert tests {:name "link entity store creates entities"
                     :fn link-entity-store-creates-entities})
(table.insert tests {:name "link entity store retrieves entities"
                     :fn link-entity-store-retrieves-entities})
(table.insert tests {:name "link entity store updates entities"
                     :fn link-entity-store-updates-entities})
(table.insert tests {:name "link entity store deletes entities"
                     :fn link-entity-store-deletes-entities})
(table.insert tests {:name "link entity store lists entities"
                     :fn link-entity-store-lists-entities})
(table.insert tests {:name "link entity store emits created signal"
                     :fn link-entity-store-emits-created-signal})
(table.insert tests {:name "link entity store emits updated signal"
                     :fn link-entity-store-emits-updated-signal})
(table.insert tests {:name "link entity store emits deleted signal"
                     :fn link-entity-store-emits-deleted-signal})
(table.insert tests {:name "link entity store stores metadata"
                     :fn link-entity-store-stores-metadata})
(table.insert tests {:name "link entity store finds edges for nodes"
                     :fn link-entity-store-finds-edges-for-nodes})
(table.insert tests {:name "link entity node loads"
                     :fn link-entity-node-loads})
(table.insert tests {:name "link entity node creates with correct properties"
                     :fn link-entity-node-creates-with-correct-properties})
(table.insert tests {:name "link entity list node loads"
                     :fn link-entity-list-node-loads})
(table.insert tests {:name "link entity list node creates with correct properties"
                     :fn link-entity-list-node-creates-with-correct-properties})
(table.insert tests {:name "link entity node view loads"
                     :fn link-entity-node-view-loads})
(table.insert tests {:name "link entity list node view loads"
                     :fn link-entity-list-node-view-loads})
(table.insert tests {:name "entities node includes link type"
                      :fn entities-node-includes-link-type})

(local JsonUtils (require :json-utils))
(local json (require :json))

(fn same-value [actual expected]
  (assert (= (JsonUtils.stable-json actual) (JsonUtils.stable-json expected))
          (.. "expected " (JsonUtils.stable-json expected) ", got " (JsonUtils.stable-json actual))))

(fn assert-endpoint-pair [f source target]
  (local disk (json.loads (fs.read-file (fs.join-path f.store.entities-dir "link.json"))))
  (assert (= f.entity (f.store:get-entity "link")) "held canonical record must survive edits")
  (same-value [f.entity.source-key f.entity.target-key] [source target])
  (same-value [disk.source-key disk.target-key] [source target]))

(fn reset-endpoint-observation [f]
  (set f.updates [])
  (set f.writes 0)
  (set f.created 0)
  (set f.updated 0))

(fn assert-endpoint-passive [f before]
  (assert (= f.writes 0) "presentation must perform zero JSON writes")
  (assert (= (# f.updates) 0) "presentation must not submit updates")
  (assert (= f.created 0) "presentation must not allocate identities")
  (assert (= f.updated 0) "presentation must not emit link-updated")
  (same-value (H.snapshot-tree f.root) before))

(fn open-endpoint-view [f]
  (local {: LinkEntityNode} (require :graph/nodes/link-entity))
  (local View (require :graph/view/views/link-entity))
  (local node (LinkEntityNode {:entity-id f.entity.id :store f.store}))
  (table.insert f.nodes node)
  (local start (# f.buttons))
  (local view ((View node) f.ctx))
  (table.insert f.views view)
  {:node node :view view
   :source-button (. f.buttons (+ start 1))
   :target-button (. f.buttons (+ start 2))
   :swap-button (. f.buttons (+ start 3))})

(fn drop-endpoint-fixture [f]
  (each [_ view (ipairs f.views)] (view:drop))
  (each [_ node (ipairs f.nodes)] (node:drop)))

(fn observe-endpoint-fixture [f body]
  (local original-update f.store.update-entity)
  (local original-write JsonUtils.write-json!)
  (local clickables (assert f.ctx.clickables "endpoint fixture requires clickables"))
  (local original-register clickables.register)
  (fn update [store id fields]
    (table.insert f.updates (json.loads (JsonUtils.stable-json fields)))
    (original-update store id fields))
  (fn write [path value]
    (when (= (string.sub path 1 (# f.root)) f.root) (set f.writes (+ f.writes 1)))
    (original-write path value))
  (fn register [clickables widget]
    (when widget.clicked (table.insert f.buttons widget))
    (original-register clickables widget))
  (fn created [_entity] (set f.created (+ f.created 1)))
  (fn updated [_entity] (set f.updated (+ f.updated 1)))
  (local created-handler (f.store.identity-store.identity-created:connect created))
  (local updated-handler (f.store.link-entity-updated:connect updated))
  (fn run [] (body f))
  (fn with-register [] (H.with-fields clickables {:register register} run))
  (fn with-write [] (H.with-fields JsonUtils {:write-json! write} with-register))
  (local (ok result) (pcall H.with-fields f.store {:update-entity update} with-write))
  (f.store.identity-store.identity-created:disconnect created-handler true)
  (f.store.link-entity-updated:disconnect updated-handler true)
  (local (drop-ok drop-error) (pcall drop-endpoint-fixture f))
  (if (not ok) (error result) (not drop-ok) (error drop-error) result))

(fn run-endpoint-fixture [store root body]
  (local Bootstrap (require :app-bootstrap))
  (Bootstrap.init-themes)
  (Bootstrap.init-icons)
  (local BuildContext (require :build-context))
  (local intersector ((require :intersectables)))
  (local clickables ((require :clickables) {:intersectables intersector}))
  (local hoverables ((require :hoverables) {:intersectables intersector}))
  (local ids store.identity-store)
  (ids:create-entity {:id "a" :target-key "terminal:shared"})
  (ids:create-entity {:id "z" :target-key "terminal:shared"})
  (ids:create-entity {:id "c" :target-key "terminal:other"})
  (local entity (store:create-entity {:id "link" :source-key "identity:z" :target-key "identity:a"
                                    :metadata {:note "initial"}}))
  (local ctx (BuildContext {:clickables clickables :hoverables hoverables :icons app.icons
                           :theme (app.themes.get-active-theme)}))
  (observe-endpoint-fixture {:store store :root root :entity entity :ctx ctx :nodes [] :views []
                            :buttons [] :updates [] :writes 0 :created 0 :updated 0} body))

(fn with-endpoint-fixture [body]
  (fn run [store root] (run-endpoint-fixture store root body))
  (with-temp-store run))

(fn endpoint-construction [f]
  (local before (H.snapshot-tree f.root))
  (local first (open-endpoint-view f))
  (local second (open-endpoint-view f))
  (local glm (require :glm))
  (first.view.layout:measurer)
  (set first.view.layout.size (glm.vec3 30 20 0))
  (first.view.layout:layouter)
  (first.node:refresh-label)
  (same-value [(first.view.source-input:get-text) (first.view.target-input:get-text)]
              ["terminal:shared" "terminal:shared"])
  (assert (= first.node.label "terminal:shared → terminal:shared"))
  (assert (= first.node.label second.node.label))
  (assert-endpoint-pair f "identity:z" "identity:a")
  (assert-endpoint-passive f before)
  (local one (f.store.identity-store:create-entity {:target-key "terminal:shared"}))
  (local two (f.store.identity-store:create-entity {:target-key "terminal:shared"}))
  (f.store:update-entity "link" {:source-key (.. "identity:" one.id) :target-key (.. "identity:" two.id)})
  (reset-endpoint-observation f)
  (local random-before (H.snapshot-tree f.root))
  (local fresh (open-endpoint-view f))
  (assert (= fresh.node.label first.node.label))
  (assert-endpoint-passive f random-before))

(fn endpoint-source-edit [f]
  (f.store:update-entity "link" {:target-key "identity:z"})
  (local w (open-endpoint-view f))
  (reset-endpoint-observation f)
  (w.view.source-input:set-text "terminal:other")
  (same-value f.updates [{:source-key "terminal:other"}])
  (assert-endpoint-pair f "identity:c" "identity:z")
  (w.node:refresh-label)
  (assert (= (w.view.target-input:get-text) "terminal:shared"))
  (assert (= f.writes 1)))

(fn endpoint-target-edit [f]
  (local w (open-endpoint-view f))
  (reset-endpoint-observation f)
  (w.view.target-input:set-text "terminal:other")
  (same-value f.updates [{:target-key "terminal:other"}])
  (assert-endpoint-pair f "identity:z" "identity:c")
  (w.node:refresh-label)
  (assert (= (w.view.source-input:get-text) "terminal:shared"))
  (assert (= f.writes 1)))

(fn endpoint-metadata [f]
  (local w (open-endpoint-view f))
  (reset-endpoint-observation f)
  (local before (H.snapshot-tree f.root))
  (w.view.metadata-input:set-text "display only")
  (assert-endpoint-passive f before)
  (w.node:update-metadata {:note "edited"})
  (same-value f.updates [{:metadata {:note "edited"}}])
  (assert-endpoint-pair f "identity:z" "identity:a")
  (same-value f.entity.metadata {:note "edited"})
  (assert (= (w.view.source-input:get-text) "terminal:shared")))

(fn click-endpoint [button]
  (assert button "expected real endpoint button")
  (button:on-click {}))

(fn endpoint-swap [f]
  (local w (open-endpoint-view f))
  (reset-endpoint-observation f)
  (click-endpoint w.swap-button)
  (assert-endpoint-pair f "identity:a" "identity:z")
  (same-value f.updates [{:source-key "identity:a"} {:target-key "identity:z"}])
  (assert (= f.writes 2))
  (same-value [(w.view.source-input:get-text) (w.view.target-input:get-text)]
              ["terminal:shared" "terminal:shared"]))

(fn endpoint-swap-source [f]
  (local w (open-endpoint-view f))
  (w.view.source-input:set-text "identity:c")
  (reset-endpoint-observation f)
  (click-endpoint w.swap-button)
  (assert-endpoint-pair f "identity:a" "identity:c")
  (same-value f.updates [{:source-key "identity:a"} {:target-key "identity:c"}])
  (assert (= (w.view.target-input:get-text) "terminal:other")))

(fn endpoint-swap-target [f]
  (local w (open-endpoint-view f))
  (w.view.target-input:set-text "identity:c")
  (reset-endpoint-observation f)
  (click-endpoint w.swap-button)
  (assert-endpoint-pair f "identity:c" "identity:z")
  (same-value f.updates [{:source-key "identity:c"} {:target-key "identity:z"}])
  (f.store:update-entity "link" {:target-key "identity:a"})
  (reset-endpoint-observation f)
  (click-endpoint w.swap-button)
  (assert-endpoint-pair f "identity:a" "identity:c")
  (assert (= f.writes 2)))

(fn assert-typed-endpoint [f original field input text]
  (local expected (collect [key value (pairs original)] key value))
  (tset expected field text)
  (local update {})
  (tset update field text)
  (same-value f.updates [update])
  (assert-endpoint-pair f expected.source-key expected.target-key)
  (same-value f.entity expected)
  (local disk (fs.read-file (fs.join-path f.store.entities-dir "link.json")))
  (assert (= disk (json.dumps expected)) "only the authored endpoint may change persisted bytes")
  (assert (= (input:get-text) text) "author text must remain verbatim")
  (assert (= f.writes 1) "one native edit must write once")
  (assert (= f.updated 1) "one native edit must publish once")
  (assert (= f.created 0) "explicit identity drafts must not allocate identities"))

(fn assert-reopened-draft [f field input]
  (reset-endpoint-observation f)
  (local before (H.snapshot-tree f.root))
  (local reopened (open-endpoint-view f))
  (local reopened-input (if (= field :source-key) reopened.view.source-input reopened.view.target-input))
  (assert (= (reopened-input:get-text) "identity:") "persisted unfinished alias must reopen")
  (assert (= (input:get-text) "identity:") "opening another view must not replace typing")
  (assert (= (reopened.node:endpoint-text "identity:") "identity:"))
  (reopened.node:refresh-label)
  (assert-endpoint-passive f before))

(fn endpoint-type-side [f field]
  (f.store:update-entity "link" {:source-key "identity:z" :target-key "identity:z"})
  (local original (json.loads (fs.read-file (fs.join-path f.store.entities-dir "link.json"))))
  (local w (open-endpoint-view f))
  (local input (if (= field :source-key) w.view.source-input w.view.target-input))
  (input:set-text "identity")
  (input.model:enter-insert-mode)
  (reset-endpoint-observation f)
  (local (ok err) (pcall input.on-text-input input {:text ":"}))
  (assert ok (.. "native ':' must preserve a usable unfinished identity draft: " (tostring err)))
  (assert-typed-endpoint f original field input "identity:")
  (w.node:refresh-label)
  (assert (= (input:get-text) "identity:"))
  (assert-reopened-draft f field input)
  (reset-endpoint-observation f)
  (input:on-text-input {:text "z"})
  (assert-typed-endpoint f original field input "identity:z")
  (w.node:refresh-label)
  (assert (= (input:get-text) "identity:z"))
  (assert (= w.node.label "terminal:shared → terminal:shared"))
  (reset-endpoint-observation f)
  (assert (input:delete-before-cursor) "native deletion must reach the unfinished prefix")
  (assert-typed-endpoint f original field input "identity:")
  (assert-reopened-draft f field input)
  (reset-endpoint-observation f)
  (input:on-text-input {:text "z"})
  (assert-typed-endpoint f original field input "identity:z")
  (reset-endpoint-observation f)
  (input:set-text "identity:z")
  (assert-typed-endpoint f original field input "identity:z"))

(fn endpoint-typed-alias [f]
  (endpoint-type-side f :source-key)
  (endpoint-type-side f :target-key))

(fn endpoint-selection-actions [f w]
  (set app.graph-view.selection.selected-nodes [{:key "identity:z"}])
  (reset-endpoint-observation f)
  (click-endpoint w.target-button)
  (same-value f.updates [{:target-key "identity:z"}])
  (assert-endpoint-pair f "identity:z" "identity:z")
  (assert (= (w.view.target-input:get-text) "terminal:shared"))
  (set app.graph-view.selection.selected-nodes [{:key "terminal:shared"}])
  (reset-endpoint-observation f)
  (click-endpoint w.source-button)
  (same-value f.updates [{:source-key "terminal:shared"}])
  (assert-endpoint-pair f "identity:a" "identity:z")
  (set app.graph-view.selection.selected-nodes [{:key "identity:z"}])
  (reset-endpoint-observation f)
  (click-endpoint w.source-button)
  (assert-endpoint-pair f "identity:z" "identity:z")
  (assert (= f.writes 1))
  (set app.graph-view.selection.selected-nodes [{:key "terminal:shared"}])
  (reset-endpoint-observation f)
  (click-endpoint w.target-button)
  (assert-endpoint-pair f "identity:z" "identity:a")
  (assert (= f.writes 1))
  (reset-endpoint-observation f)
  (set app.graph-view.selection.selected-nodes [])
  (click-endpoint w.source-button)
  (set app.graph-view.selection.selected-nodes [{:key "identity:a"} {:key "identity:z"}])
  (click-endpoint w.target-button)
  (assert (= f.writes 0)))

(fn endpoint-selection [f]
  (local w (open-endpoint-view f))
  (fn run [] (endpoint-selection-actions f w))
  (H.with-fields app {:graph-view {:selection {:selected-nodes []}}} run))

(fn endpoint-unresolved [f]
  (f.store.identity-store:create-entity {:id "empty" :target-key ""})
  (each [_ key (ipairs ["" "identity:missing" "identity:empty"])]
    (f.store:update-entity "link" {:source-key key :target-key "identity:z"})
    (reset-endpoint-observation f)
    (local before (H.snapshot-tree f.root))
    (local w (open-endpoint-view f))
    (assert (= (w.view.source-input:get-text) key))
    (assert-endpoint-passive f before)
    (w.view.target-input:set-text "identity:c")
    (w.node:update-metadata {:note "unresolved"})
    (assert-endpoint-pair f key "identity:c")
    (reset-endpoint-observation f)
    (click-endpoint w.swap-button)
    (assert-endpoint-pair f "identity:c" key)
    (assert (= f.writes 2)))
  ;; A legacy record is written as historical input, never through a fake store.
  (local path (fs.join-path f.store.entities-dir "link.json"))
  (local record (json.loads (fs.read-file path)))
  (set record.source-key "legacy:raw")
  (JsonUtils.write-json! path record)
  (tset f.store.cache "link" nil)
  (set f.entity (f.store:get-entity "link"))
  (reset-endpoint-observation f)
  (local before (H.snapshot-tree f.root))
  (local w (open-endpoint-view f))
  (assert (= (w.view.source-input:get-text) "legacy:raw"))
  (assert (= (w.node:endpoint-text nil) ""))
  (assert-endpoint-passive f before))

(fn endpoint-failing-resolution [f key fragment]
  (f.store:update-entity "link" {:source-key key})
  (reset-endpoint-observation f)
  (local before (H.snapshot-tree f.root))
  (fn open [] (open-endpoint-view f))
  (H.assert-error fragment open)
  (assert-endpoint-passive f before))

(fn endpoint-guard-error [f w]
  (fn fail [_input _text _opts] (error "injected endpoint presentation failure"))
  (fn click [] (click-endpoint w.source-button))
  (fn failing [] (H.assert-error "injected endpoint presentation failure" click))
  (H.with-fields w.view.source-input {:set-text fail} failing)
  (assert-endpoint-pair f "identity:a" "identity:a")
  (reset-endpoint-observation f)
  (w.view.source-input:set-text "identity:z")
  (w.view.target-input:set-text "identity:c")
  (assert-endpoint-pair f "identity:z" "identity:c")
  (same-value f.updates [{:source-key "identity:z"} {:target-key "identity:c"}]))

(fn endpoint-pre-resolution [f]
  (local w (open-endpoint-view f))
  (f.store.identity-store:update-entity "z" {:target-key "identity:z"})
  (reset-endpoint-observation f)
  (local before (H.snapshot-tree f.root))
  (fn refresh [] (w.node:refresh-label))
  (fn swap [] (click-endpoint w.swap-button))
  (fn select [] (click-endpoint w.source-button))
  (H.assert-error "cycle detected" refresh)
  (H.assert-error "cycle detected" swap)
  (H.with-fields app {:graph-view {:selection {:selected-nodes [{:key "identity:z"}]}}}
                 (fn selected [] (H.assert-error "cycle detected" select)))
  (assert-endpoint-passive f before)
  (f.store.identity-store:update-entity "z" {:target-key "terminal:shared"})
  (fn guarded [] (endpoint-guard-error f w))
  (H.with-fields app {:graph-view {:selection {:selected-nodes [{:key "identity:a"}]}}} guarded))

(fn endpoint-read-error [f]
  (local ids f.store.identity-store)
  (ids:create-entity {:id "unreadable" :target-key "terminal:shared"})
  (tset ids.cache "unreadable" nil)
  (f.store:update-entity "link" {:source-key "identity:unreadable"})
  (reset-endpoint-observation f)
  (local before (H.snapshot-tree f.root))
  (fn open [] (open-endpoint-view f))
  (fn failed-read [] (H.assert-error "injected permission denied" open))
  (H.with-fs-failure :read-file (fs.join-path ids.entities-dir "unreadable.json") failed-read)
  (assert-endpoint-passive f before))

(fn endpoint-errors [f]
  (endpoint-pre-resolution f)
  (local ids f.store.identity-store)
  (ids:create-entity {:id "self" :target-key "identity:self"})
  (ids:create-entity {:id "one" :target-key "identity:two"})
  (ids:create-entity {:id "two" :target-key "identity:one"})
  (for [i 1 34]
    (ids:create-entity {:id (.. "depth-" i) :target-key (.. "identity:depth-" (+ i 1))}))
  (ids:create-entity {:id "depth-35" :target-key "terminal:shared"})
  ;; Drop healthy subscribers before authoring intentionally invalid fixtures.
  (each [_ node (ipairs f.nodes)] (node:drop))
  (set f.nodes [])
  (endpoint-failing-resolution f "identity:self" "cycle detected")
  (endpoint-failing-resolution f "identity:one" "cycle detected")
  (endpoint-failing-resolution f "identity:depth-1" "depth exhausted")
  (endpoint-read-error f))

(fn add-endpoint-test [suffix body]
  (fn run [] (with-endpoint-fixture body))
  (table.insert tests {:name (.. "link endpoint presentation " suffix) :fn run}))

(add-endpoint-test "construction and refresh preserve distinct aliases without writes" endpoint-construction)
(add-endpoint-test "source edit preserves target alias" endpoint-source-edit)
(add-endpoint-test "target edit preserves source alias" endpoint-target-edit)
(add-endpoint-test "metadata preserves both aliases" endpoint-metadata)
(add-endpoint-test "swap preserves distinct same-terminal keys" endpoint-swap)
(add-endpoint-test "swap reads current source after edit" endpoint-swap-source)
(add-endpoint-test "swap reads current target after edit" endpoint-swap-target)
(add-endpoint-test "explicit typed aliases retain exact identity" endpoint-typed-alias)
(add-endpoint-test "selection authoring is side specific" endpoint-selection)
(add-endpoint-test "empty and unresolved endpoints stay explicit" endpoint-unresolved)
(add-endpoint-test "resolver failures surface without presentation writes" endpoint-errors)

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "link-entities"
                       :tests tests})))

{:name "link-entities"
 :tests tests
 :main main}
