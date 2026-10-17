(local fs (require :fs))
(local H (require :tests/test-reference-lifecycle-helpers))
(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "notebooks"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "notebooks-" (os.time) "-" temp-counter)))

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
      (local NotebookStore (require :notebooks/store))
      (local store (NotebookStore.NotebookStore {:base-dir root}))
      (f store root))))

(fn notebook-store-creates-notebooks []
  (with-temp-store
    (fn [store _root]
      (local notebook (store:create-notebook {:name "Ward rounds"
                                              :items ["node-a" "node-b"]}))
      (assert notebook "notebook should be created")
      (assert notebook.id "notebook should have id")
      (assert (= notebook.name "Ward rounds") "notebook should have correct name")
      (assert (= (length notebook.items) 2) "notebook should have two items")
      (H.assert-reference store.identity-store (. notebook.items 1) "node-a")
      (assert notebook.created-at "notebook should have created-at")
      (assert notebook.updated-at "notebook should have updated-at"))))

(fn notebook-store-retrieves-notebooks []
  (with-temp-store
    (fn [store _root]
      (local notebook (store:create-notebook {:name "Checklist"
                                              :items ["node-a" "node-b"]}))
      (local retrieved (store:get-notebook notebook.id))
      (assert retrieved "notebook should be retrieved")
      (assert (= retrieved.id notebook.id) "retrieved notebook should have same id")
      (assert (= retrieved.name "Checklist") "retrieved notebook should have correct name")
      (assert (= (length retrieved.items) 2) "retrieved notebook should have items"))))

(fn notebook-store-updates-notebooks []
  (with-temp-store
    (fn [store _root]
      (local notebook (store:create-notebook {:name "Old"
                                              :items ["a"]}))
      (local updated (store:update-notebook notebook.id {:name "New"}))
      (assert updated "notebook should be updated")
      (assert (= updated.name "New") "name should be updated")
      (local retrieved (store:get-notebook notebook.id))
      (assert (= retrieved.name "New") "persisted name should be updated"))))

(fn notebook-store-deletes-notebooks []
  (with-temp-store
    (fn [store _root]
      (local notebook (store:create-notebook {:name "Delete Me"}))
      (local deleted (store:retire-notebook! notebook.id))
      (assert deleted "notebook should be deleted")
      (local retrieved (store:get-notebook notebook.id))
      (assert (= retrieved nil) "notebook should no longer be retrievable"))))

(fn notebook-store-lists-notebooks-sorted []
  (with-temp-store
    (fn [store _root]
      (store:create-notebook {:name "old" :updated-at 10})
      (store:create-notebook {:name "mid" :updated-at 20})
      (store:create-notebook {:name "new" :updated-at 30})
      (local notebooks (store:list-notebooks))
      (assert (= (length notebooks) 3) "should list three notebooks")
      (assert (= (. notebooks 1 :updated-at) 30) "should sort by updated-at desc"))))

(fn notebook-store-emits-created-signal []
  (with-temp-store
    (fn [store _root]
      (var created-count 0)
      (store.notebook-created:connect (fn [_] (set created-count (+ created-count 1))))
      (store:create-notebook {:name "x"})
      (assert (= created-count 1) "created signal should be emitted"))))

(fn notebook-store-emits-updated-signal []
  (with-temp-store
    (fn [store _root]
      (var updated-count 0)
      (store.notebook-updated:connect (fn [_] (set updated-count (+ updated-count 1))))
      (local notebook (store:create-notebook {:name "x"}))
      (store:update-notebook notebook.id {:name "y"})
      (assert (= updated-count 1) "updated signal should be emitted"))))

(fn notebook-store-emits-deleted-signal []
  (with-temp-store
    (fn [store _root]
      (var deleted-count 0)
      (store.notebook-deleted:connect (fn [_] (set deleted-count (+ deleted-count 1))))
      (local notebook (store:create-notebook {:name "x"}))
      (store:retire-notebook! notebook.id)
      (assert (= deleted-count 1) "deleted signal should be emitted"))))

(fn notebook-store-adds-items-and-prevents-duplicates []
  (with-temp-store
    (fn [store _root]
      (local notebook (store:create-notebook {:name "x" :items ["a"]}))
      (var items-count 0)
      (store.notebook-items-changed:connect (fn [_] (set items-count (+ items-count 1))))
      (store:add-item notebook.id "b")
      (store:add-item notebook.id "b")
      (local retrieved (store:get-notebook notebook.id))
      (assert (= (length retrieved.items) 2) "should not add duplicates")
      (assert (= items-count 1) "items-changed should emit once for one actual change"))))

(fn notebook-store-removes-items []
  (with-temp-store
    (fn [store _root]
      (local notebook (store:create-notebook {:name "x" :items ["a" "b" "c"]}))
      (store:remove-item notebook.id "b")
      (local retrieved (store:get-notebook notebook.id))
      (assert (= (length retrieved.items) 2) "should remove one item")
      (H.assert-reference store.identity-store (. retrieved.items 1) "a")
      (H.assert-reference store.identity-store (. retrieved.items 2) "c"))))

(fn notebook-store-moves-items []
  (with-temp-store
    (fn [store _root]
      (local notebook (store:create-notebook {:name "x" :items ["a" "b" "c"]}))
      (store:move-item notebook.id 1 3)
      (local retrieved (store:get-notebook notebook.id))
      (H.assert-reference store.identity-store (. retrieved.items 1) "b")
      (H.assert-reference store.identity-store (. retrieved.items 2) "c")
      (H.assert-reference store.identity-store (. retrieved.items 3) "a"))))

(fn notebook-store-emits-items-changed-signal []
  (with-temp-store
    (fn [store _root]
      (local notebook (store:create-notebook {:name "x"}))
      (var payload-id nil)
      (store.notebook-items-changed:connect
        (fn [payload]
          (set payload-id (or (and payload payload.id) nil))))
      (store:add-item notebook.id "a")
      (assert (= payload-id notebook.id) "items-changed should include notebook id"))))

(fn graph-node-defaults-preview-to-view []
  (local {:GraphNode GraphNode} (require :graph/node-base))
  (local view-fn (fn [_node _opts] (fn [_ctx] {:layout {} :drop (fn [_] nil)})))
  (local node (GraphNode {:key "preview-default" :view view-fn}))
  (assert (= node.preview view-fn) "GraphNode should default preview to view"))

(fn notebook-node-loads []
  (local {:NotebookNode NotebookNode} (require :graph/nodes/notebook))
  (assert NotebookNode "NotebookNode should load")
  (assert (= (type NotebookNode) "function") "NotebookNode should be a function"))

(fn notebook-node-creates-with-correct-properties []
  (with-temp-store
    (fn [store _root]
      (local notebook (store:create-notebook {:name "x"}))
      (local {:NotebookNode NotebookNode} (require :graph/nodes/notebook))
      (local node (NotebookNode {:notebook-id notebook.id :store store}))
      (assert (= node.key (.. "notebook:" notebook.id)) "key should be prefixed notebook id")
      (assert node.color "should have color")
      (assert node.items-changed "should have items-changed signal")
      (assert node.notebook-deleted "should have notebook-deleted signal")
      (assert node.get-notebook "should have get-notebook method")
      (assert node.update-name "should have update-name method")
      (assert node.add-item "should have add-item method")
      (assert node.add-string-entity "should have add-string-entity method")
      (assert node.remove-item "should have remove-item method")
      (assert node.move-item "should have move-item method")
      (assert node.delete-notebook "should have delete-notebook method")
      (node:drop))))

(fn notebook-node-add-string-entity-creates-item-and-edge []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local IdentityStore (require :entities/identity))
      (local StringEntityStore (require :entities/string))
      (local identity-store store.identity-store)
      (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path root "string")}))
      (local notebook (store:create-notebook {:name "x"}))
      (local {:NotebookNode NotebookNode} (require :graph/nodes/notebook))
      (local node (NotebookNode {:notebook-id notebook.id
                                 :store store
                                 :identity-store identity-store
                                 :string-store string-store}))
      (local graph (Graph {:with-start false
                           :identity-store identity-store}))
      (graph:add-node node {})

      (local entity (node:add-string-entity {:value "hello"}))
      (assert entity "should create a string entity")
      (assert (= (or entity.value "") "hello") "created entity should keep value")

      (local current (store:get-notebook notebook.id))
      (assert (= (length (or current.items [])) 1) "notebook should contain one item")
      (local key (. current.items 1))
      (assert (= (string.sub key 1 9) "identity:")
              "notebook item should store an identity key")
      (local identity-entity (identity-store:get-entity (string.sub key 10)))
      (assert identity-entity "identity entity should exist")
      (assert (= identity-entity.target-key (.. "string-entity:" entity.id))
              "identity should point at created string entity key")

      (local loaded-entity (string-store:get-entity entity.id))
      (assert loaded-entity "created string entity should be persisted")
      (local entity-node (graph:lookup (.. "string-entity:" entity.id)))
      (assert entity-node "graph should contain node for created string entity")
      (assert (= (graph:edge-count) 1) "notebook should add one edge to created string entity")

      (graph:drop))))

(fn notebook-node-add-item-wraps-non-identity-key-and-dedupes []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local IdentityStore (require :entities/identity))
      (local identity-store store.identity-store)
      (local notebook (store:create-notebook {:name "x"}))
      (local {:NotebookNode NotebookNode} (require :graph/nodes/notebook))
      (local node (NotebookNode {:notebook-id notebook.id
                                 :store store
                                 :identity-store identity-store}))
      (local graph (Graph {:with-start false
                           :identity-store identity-store}))
      (graph:add-node node {})

      (node:add-item "node-a")
      (node:add-item "node-a")

      (local current (store:get-notebook notebook.id))
      (assert (= (length (or current.items [])) 1)
              "adding same target twice should dedupe to one identity key")
      (local stored-key (. current.items 1))
      (assert (= (string.sub stored-key 1 9) "identity:")
              "notebook should wrap non-identity keys with identity")
      (local identity-id (string.sub stored-key 10))
      (local identity-entity (identity-store:get-entity identity-id))
      (assert identity-entity "identity entity should be persisted")
      (assert (= identity-entity.target-key "node-a")
              "identity target key should match added key")

      (local identities (identity-store:list-entities))
      (assert (= (length identities) 1)
              "identity wrapping should reuse existing identity for same target")

      (graph:drop))))

(fn notebook-node-adds-item-edges-after-added []
  (with-temp-store
    (fn [store _root]
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local a (Graph.GraphNode {:key "node-a"}))
      (local b (Graph.GraphNode {:key "node-b"}))
      (graph:add-node a {})
      (graph:add-node b {})
      (local notebook (store:create-notebook {:name "x"
                                              :items ["node-a" "node-b"]}))
      (local {:NotebookNode NotebookNode} (require :graph/nodes/notebook))
      (local node (NotebookNode {:notebook-id notebook.id :store store}))
      (graph:add-node node {})
      (assert (= (graph:edge-count) 2)
              "notebook node should add edges to existing item nodes")
      (graph:drop))))

(fn notebook-node-loads-nested-notebook-item-via-load-by-key []
  (with-temp-store
    (fn [store _root]
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local {:NotebookNode NotebookNode :register-loader register-loader} (require :graph/nodes/notebook))
      (register-loader graph {:store store})
      (local child (store:create-notebook {:name "child"}))
      (local parent (store:create-notebook {:name "parent"
                                            :items [(.. "notebook:" child.id)]}))
      (local parent-node (NotebookNode {:notebook-id parent.id :store store}))
      (graph:add-node parent-node {})
      (local child-node (graph:lookup (.. "notebook:" child.id)))
      (assert child-node "notebook node should load nested notebook item node")
      (assert (= (graph:edge-count) 1)
              "notebook node should add one edge to nested notebook")
      (graph:drop))))

(fn notebook-node-preserves-item-when-node-disappears []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local IdentityStore (require :entities/identity))
      (local StringEntityStore (require :entities/string))
      (local identity-store store.identity-store)
      (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path root "string")}))
      (local string-entity (string-store:create-entity {:value "soon gone"}))
      (local source-key (.. "string-entity:" string-entity.id))
      (local notebook (store:create-notebook {:name "x"
                                              :items [source-key]}))
      (local graph (Graph {:with-start false
                           :identity-store identity-store}))
      (local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
      (register-string-loader graph {:store string-store})
      (local source-node (graph:load-by-key source-key))
      (local {:NotebookNode NotebookNode} (require :graph/nodes/notebook))
      (local notebook-node (NotebookNode {:notebook-id notebook.id
                                          :store store
                                          :identity-store identity-store}))
      (graph:add-node notebook-node {})
      (local initial (assert (store:get-notebook notebook.id)))
      (assert (= (# initial.items) 1) "notebook should start with stable key item")
      (local before (. (store:snapshot-notebook notebook.id) :bytes))
      (graph:remove-nodes [source-node])
      (local current (store:get-notebook notebook.id))
      (assert (= (# current.items) 1)
              "exposure removal must preserve owning notebook membership")
      (assert (= (. (store:snapshot-notebook notebook.id) :bytes) before))
      (graph:drop))))

(fn notebook-node-refreshes-identity-item-edges-on-target-change []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local IdentityStore (require :entities/identity))
      (local StringEntityStore (require :entities/string))
      (local identity-store store.identity-store)
      (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path root "string")}))
      (local a (string-store:create-entity {:value "a"}))
      (local b (string-store:create-entity {:value "b"}))
      (local key-a (.. "string-entity:" a.id))
      (local key-b (.. "string-entity:" b.id))
      (local identity (identity-store:create-entity {:target-key key-a}))
      (local identity-key (.. "identity:" identity.id))
      (local notebook (store:create-notebook {:name "x"
                                              :items [identity-key]}))
      (local graph (Graph {:with-start false
                           :identity-store identity-store}))
      (local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
      (register-string-loader graph {:store string-store})
      (graph:load-by-key key-a)
      (graph:load-by-key key-b)
      (local {:NotebookNode NotebookNode} (require :graph/nodes/notebook))
      (local notebook-node (NotebookNode {:notebook-id notebook.id
                                          :store store
                                          :identity-store identity-store}))
      (graph:add-node notebook-node {})
      (assert (= (graph:edge-count) 1) "notebook should have one item edge")
      (assert (= (. graph.edges 1 :target :key) key-a) "initial edge should point to original target")
      (identity-store:update-entity identity.id {:target-key key-b})
      (assert (= (graph:edge-count) 1) "notebook should keep one item edge after identity target change")
      (assert (= (. graph.edges 1 :target :key) key-b) "edge should retarget to updated identity target")
      (graph:drop))))

(fn notebook-node-refreshes-identity-item-edges-when-target-node-added-late []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local {:GraphNode GraphNode} (require :graph/node-base))
      (local IdentityStore (require :entities/identity))
      (local identity-store store.identity-store)
      (local target-key "manual-target:late")
      (local identity (identity-store:create-entity {:target-key "manual-target:old"}))
      (local identity-key (.. "identity:" identity.id))
      (local notebook (store:create-notebook {:name "x"
                                              :items [identity-key]}))
      (local graph (Graph {:with-start false
                           :identity-store identity-store}))
      (local {:NotebookNode NotebookNode} (require :graph/nodes/notebook))
      (local notebook-node (NotebookNode {:notebook-id notebook.id
                                          :store store
                                          :identity-store identity-store}))
      (graph:add-node notebook-node {})
      (identity-store:update-entity identity.id {:target-key target-key})
      (assert (= (graph:edge-count) 0)
              "edge should not exist until target node is present")
      (graph:add-node (GraphNode {:key target-key
                                  :label "late target"})
                      {})
      (assert (= (graph:edge-count) 1)
              "identity-backed notebook edge should appear when target node is added")
      (assert (= (. graph.edges 1 :target :key) target-key)
              "late-added target should become notebook edge target")
      (graph:drop))))

(fn notebook-node-emits-items-changed-on-node-morphed-for-identity-item []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local IdentityStore (require :entities/identity))
      (local identity-store store.identity-store)
      (local identity (identity-store:create-entity {:target-key "string-entity:s1"}))
      (local identity-key (.. "identity:" identity.id))
      (local notebook (store:create-notebook {:name "x"
                                              :items [identity-key]}))
      (local graph (Graph {:with-start false
                           :identity-store identity-store}))
      (local {:NotebookNode NotebookNode} (require :graph/nodes/notebook))
      (local notebook-node (NotebookNode {:notebook-id notebook.id
                                          :store store
                                          :identity-store identity-store}))
      (graph:add-node notebook-node {})
      (var refresh-count 0)
      (notebook-node.items-changed:connect (fn [_] (set refresh-count (+ refresh-count 1))))
      (graph.node-morphed:emit {:source-key "string-entity:s1"
                                :target-key "code-entity:c1"
                                :payload {:result {:updated-identity-keys [identity-key]}}})
      (assert (= refresh-count 1)
              "node-morphed should trigger notebook items refresh for affected identity item")
      (graph:drop))))

(fn notebooks-node-loads []
  (local NotebooksNode (require :graph/nodes/notebooks))
  (assert NotebooksNode "NotebooksNode should load")
  (assert (= (type NotebooksNode) "function") "NotebooksNode should be a function"))

(fn notebooks-node-creates-with-correct-properties []
  (with-temp-store
    (fn [store _root]
      (local NotebooksNode (require :graph/nodes/notebooks))
      (local node (NotebooksNode {:store store}))
      (assert (= node.key "notebooks") "key should be notebooks")
      (assert (= node.label "notebooks") "label should be notebooks")
      (assert node.color "should have color")
      (assert node.items-changed "should have items-changed signal")
      (assert node.collect-items "should have collect-items method")
      (assert node.emit-items "should have emit-items method")
      (assert node.add-notebook-node "should have add-notebook-node method")
      (assert node.create-notebook "should have create-notebook method")
      (node:drop))))

(fn notebook-node-view-loads []
  (local NotebookNodeView (require :graph/view/views/notebook))
  (assert NotebookNodeView "NotebookNodeView should load")
  (assert (= (type NotebookNodeView) "function") "NotebookNodeView should be a function"))

(fn string-entity-node-provides-preview []
  (local {:StringEntityNode StringEntityNode} (require :graph/nodes/string-entity))
  (local StringEntityStore (require :entities/string))
  (with-temp-dir
    (fn [root]
      (local store (StringEntityStore.StringEntityStore {:base-dir root}))
      (local entity (store:create-entity {:value "abc"}))
      (local node (StringEntityNode {:entity-id entity.id :store store}))
      (assert node.preview "StringEntityNode should provide a preview constructor")
      (assert (= (type node.preview) "function") "StringEntityNode preview should be a function")
      (node:drop))))

(fn notebooks-node-view-loads []
  (local NotebooksNodeView (require :graph/view/views/notebooks))
  (assert NotebooksNodeView "NotebooksNodeView should load")
  (assert (= (type NotebooksNodeView) "function") "NotebooksNodeView should be a function"))

(fn start-node-collect-targets-includes-notebooks []
  (local StartNode (require :graph/nodes/start))
  (local start (StartNode))
  (local targets (start:collect-targets))
  (var found false)
  (each [_ pair (ipairs targets)]
    (local target (and pair (. pair 1)))
    (when (and target (= target.key "notebooks"))
      (set found true)))
  (assert found "start node search targets should include notebooks")
  (start:drop))

(table.insert tests {:name "notebook store creates notebooks"
                     :fn notebook-store-creates-notebooks})
(table.insert tests {:name "notebook store retrieves notebooks"
                     :fn notebook-store-retrieves-notebooks})
(table.insert tests {:name "notebook store updates notebooks"
                     :fn notebook-store-updates-notebooks})
(table.insert tests {:name "notebook store deletes notebooks"
                     :fn notebook-store-deletes-notebooks})
(table.insert tests {:name "notebook store lists notebooks sorted"
                     :fn notebook-store-lists-notebooks-sorted})
(table.insert tests {:name "notebook store emits created signal"
                     :fn notebook-store-emits-created-signal})
(table.insert tests {:name "notebook store emits updated signal"
                     :fn notebook-store-emits-updated-signal})
(table.insert tests {:name "notebook store emits deleted signal"
                     :fn notebook-store-emits-deleted-signal})
(table.insert tests {:name "notebook store adds items and prevents duplicates"
                     :fn notebook-store-adds-items-and-prevents-duplicates})
(table.insert tests {:name "notebook store removes items"
                     :fn notebook-store-removes-items})
(table.insert tests {:name "notebook store moves items"
                     :fn notebook-store-moves-items})
(table.insert tests {:name "notebook store emits items-changed signal"
                     :fn notebook-store-emits-items-changed-signal})
(table.insert tests {:name "graph node defaults preview to view"
                     :fn graph-node-defaults-preview-to-view})
(table.insert tests {:name "notebook node loads"
                     :fn notebook-node-loads})
(table.insert tests {:name "notebook node creates with correct properties"
                     :fn notebook-node-creates-with-correct-properties})
(table.insert tests {:name "notebook node adds item edges after added"
                     :fn notebook-node-adds-item-edges-after-added})
(table.insert tests {:name "notebook node add-string-entity creates item and edge"
                     :fn notebook-node-add-string-entity-creates-item-and-edge})
(table.insert tests {:name "notebook node add-item wraps non-identity key and dedupes"
                     :fn notebook-node-add-item-wraps-non-identity-key-and-dedupes})
(table.insert tests {:name "notebook node loads nested notebook item via load-by-key"
                     :fn notebook-node-loads-nested-notebook-item-via-load-by-key})
(table.insert tests {:name "notebook node preserves item when node disappears"
                      :fn notebook-node-preserves-item-when-node-disappears})
(table.insert tests {:name "notebook node refreshes identity item edges on target change"
                     :fn notebook-node-refreshes-identity-item-edges-on-target-change})
(table.insert tests {:name "notebook node refreshes identity item edges when target node added late"
                     :fn notebook-node-refreshes-identity-item-edges-when-target-node-added-late})
(table.insert tests {:name "notebook node emits items-changed on node-morphed for identity item"
                     :fn notebook-node-emits-items-changed-on-node-morphed-for-identity-item})
(table.insert tests {:name "notebooks node loads"
                     :fn notebooks-node-loads})
(table.insert tests {:name "notebooks node creates with correct properties"
                     :fn notebooks-node-creates-with-correct-properties})
(table.insert tests {:name "notebook node view loads"
                     :fn notebook-node-view-loads})
(table.insert tests {:name "string entity node provides preview"
                     :fn string-entity-node-provides-preview})
(table.insert tests {:name "notebooks node view loads"
                     :fn notebooks-node-view-loads})
(table.insert tests {:name "start node collect-targets includes notebooks"
                     :fn start-node-collect-targets-includes-notebooks})

(local J (require :json-utils))
(local json (require :json))
(local preview-keys ["identity:z" "identity:a"])

(fn own-preview-resource [unit group resource first?]
  (local drop (assert resource.drop "unit fixture resource requires drop"))
  (local entry {:resource resource :closed? false})
  (if first? (table.insert (. unit group) 1 entry) (table.insert (. unit group) entry))
  (tset unit.records resource entry)
  (set resource.drop (fn [self] (set entry.closed? true) (drop self)))
  resource)

(fn drop-preview-resources [groups]
  (var failure nil)
  (each [_ entries (ipairs groups)]
    (for [i (# entries) 1 -1]
      (local entry (. entries i))
      (when (not entry.closed?)
        (local (ok result) (pcall entry.resource.drop entry.resource))
        (when (and (not ok) (not failure)) (set failure result)))))
  (when failure (error failure 0)))

(fn init-preview-unit [unit]
  (set unit.focus (own-preview-resource unit :ui ((. (require :focus) :FocusManager) {:root-name "notebook-preview"})))
  (set unit.camera (own-preview-resource unit :ui ((require :camera) {:position ((. (require :glm) :vec3) 0 0 100)})))
  (set unit.icons (own-preview-resource unit :ui ((require :icons))))
  (set unit.renderer (own-preview-resource unit :ui ((require :renderers)))))

(fn draw-notebook-target [f target]
  (target:update 0)
  (assert (> (# (target:get-text-ssbo-draw-list)) 0) "unit draw requires actual native text buffers")
  ;; Production renderer pipeline; GPU pixel comparisons stay in native E2E.
  (f.screen.renderer:draw-target target))

(fn same-preview-value [actual expected]
  (assert (= (J.stable-json actual) (J.stable-json expected))
          (.. "expected " (J.stable-json expected) ", got " (J.stable-json actual))))

(fn reset-preview-observation [f]
  (set f.writes 0) (set f.signals {}) (set f.calls []))

(fn preview-child [widget index] (. widget.children index :element))
(fn notebook-row [f index] (assert (. f.view.list.item-widgets index) "expected actual notebook row"))
(fn notebook-row-preview [f index] (preview-child (preview-child (notebook-row f index) 2) 2))
(fn notebook-row-button [f index column]
  (preview-child (preview-child (preview-child (notebook-row f index) 2) 1) column))
(fn click-notebook-row [f index column]
  (local button (notebook-row-button f index column))
  (button:on-click {}))
(fn notebook-action [f index] (preview-child f.view.actions-row index))
(fn assert-preview-text [widget text]
  (same-preview-value (widget:get-codepoints) ((. (require :text-utils) :codepoints-from-text) text)))

(fn assert-preview-rows [f keys terminals]
  (assert (= (# f.view.list.items) (# keys)) "current positive notebook row count")
  (each [i key (ipairs keys)]
    (same-preview-value (. f.view.list.items i)
      {:index i :total (# keys) :key key :terminal-key (. terminals i)})
    (local scheme (string.match (. terminals i) "^([^:]+)"))
    (assert-preview-text (preview-child (notebook-row f i) 1) scheme))
  (assert-preview-text f.view.items-label (.. "Items (" (# keys) "):")))

(fn assert-preview-membership [f keys]
  (assert (= f.record (f.store:get-notebook "n")) "owning held notebook record must survive")
  (same-preview-value f.record.items keys)
  (same-preview-value (. (json.loads (fs.read-file f.path)) :items) keys))

(fn assert-preview-passive [f before]
  (same-preview-value [f.writes f.signals] [0 {}])
  (same-preview-value (H.snapshot-tree f.root) before)
  (same-preview-value f.record (json.loads (fs.read-file f.path)))
  (assert (= f.record (f.store:get-notebook "n")) "passive reads preserve held notebook")
  (assert (= f.held (f.content:get-entity "s")) "passive reads preserve held content"))

(fn close-notebook-previews [f]
  (local entries (icollect [_ target (ipairs f.targets)] (. f.screen.records target)))
  (local (ok result) (pcall drop-preview-resources [entries]))
  (set f.targets [])
  (when (not ok) (error result)))

(fn open-notebook-preview [f]
  (local View (require :graph/view/views/notebook))
  (local glm (require :glm))
  (fn builder [ctx] (set f.view ((View f.node) ctx)) f.view)
  (local target (own-preview-resource f.screen :targets ((require :canvas)
    {:camera f.screen.camera :focus-manager f.screen.focus :icons f.screen.icons :states app.states})))
  (target:on-viewport-changed {:width f.screen.width :height f.screen.height})
  (target:add-panel-child {:builder builder :position (glm.vec3 0) :size (glm.vec3 80 45 0)})
  (table.insert f.targets target)
  f.view)

(fn preview-observed-methods [f store methods]
  (local out {})
  (each [_ method (ipairs methods)]
    (local original (. store method))
    (fn operation [self ...]
      (table.insert f.calls {:store store.base-dir :method method
                            :args (json.loads (J.stable-json [...]))})
      (original self ...))
    (tset out method operation))
  out)

(fn preview-subscription [f signal label]
  (assert signal "notebook preview observations require native owning signal")
  (fn handler [_]
    (assert f.signals "notebook preview signal counters must be initialized")
    (tset f.signals label (+ (or (. f.signals label) 0) 1)))
  (signal:connect handler)
  [signal handler])

(fn observe-notebook-preview [f body]
  (local subscriptions [])
  (each [_ pair (ipairs [[f.store.notebook-updated :notebook]
    [f.store.notebook-items-changed :items] [f.content.string-entity-updated :content]
    [f.content.string-entity-created :content-created] [f.author.string-entity-created :author-created]
    [f.author.string-entity-updated :author-updated] [f.store.identity-store.identity-created :allocated]
    [f.store.identity-store.identity-updated :identity] [f.stores.list-store.list-entity-created :list-created]
    [f.stores.list-store.list-entity-updated :list-updated]
    [f.stores.list-store.list-entity-items-changed :list-items]])]
    (table.insert subscriptions (preview-subscription f (. pair 1) (. pair 2))))
  (local original fs.write-file)
  (fn write [path bytes]
    (when (= (string.sub path 1 (# f.root)) f.root) (set f.writes (+ f.writes 1)))
    (original path bytes))
  (fn run [] (body f))
  (fn content [] (H.with-fields f.content (preview-observed-methods f f.content [:update-entity]) run))
  (fn notebook [] (H.with-fields f.store
    (preview-observed-methods f f.store [:update-notebook :add-item :remove-item :move-item]) content))
  (local (ok result) (pcall H.with-fields fs {:write-file write} notebook))
  (each [_ pair (ipairs subscriptions)]
    (local signal (. pair 1)) (signal:disconnect (. pair 2) true))
  (local (drop-ok drop-error) (pcall drop-preview-resources [f.screen.targets f.screen.domain]))
  (if (not ok) (error result) (not drop-ok) (error drop-error) result))

(fn make-preview-fixture [root screen]
  (local s (H.stores (fs.join-path root "owner")))
  (local Strings (require :entities/string))
  (local provider (H.stores (fs.join-path root "provider")))
  (local content provider.string-store)
  (local decoy (Strings.StringEntityStore {:base-dir (fs.join-path root "graph-default")}))
  (local author (Strings.StringEntityStore {:base-dir (fs.join-path root "node-author")}))
  (local graph-ids ((. (require :entities/identity) :IdentityStore)
    {:base-dir (fs.join-path root "graph-identities")}))
  (local held (content:create-entity {:id "s" :name "Content metadata" :value "CORRECT inline preview"}))
  (content:create-entity {:id "t" :value "Other provider content"})
  (decoy:create-entity {:id "s" :value "WRONG graph default"})
  (author:create-entity {:id "s" :value "WRONG node default"})
  (s.identity-store:create-entity {:id "a" :target-key "string-entity:s"})
  (s.identity-store:create-entity {:id "z" :target-key "identity:a"})
  (s.identity-store:create-entity {:id "c" :target-key "string-entity:t"})
  (graph-ids:create-entity {:id "a" :target-key "string-entity:wrong"})
  (graph-ids:create-entity {:id "z" :target-key "string-entity:wrong"})
  (local record (s.notebook-store:create-notebook {:id "n" :name "Presentation notebook" :items preview-keys}))
  (local lifecycle (H.lifecycle provider))
  (local graph (own-preview-resource screen :domain ((require :graph/core)
    {:with-start false :identity-store graph-ids :string-store decoy})))
  ((. (require :graph/nodes/string-entity) :register-loader) graph {:store content :lifecycle lifecycle})
  (local map (own-preview-resource screen :domain ((. (require :graph/map) :GraphMap) {:graph graph})))
  (local node (own-preview-resource screen :domain ((. (require :graph/nodes/notebook) :NotebookNode)
    {:notebook-id "n" :store s.notebook-store :string-store author}) true))
  ;; Real mount, without eager added/edge expansion: measure the view's own loading.
  (node:mount graph)
  {:root root :screen screen :stores s :store s.notebook-store :record record :held held
   :content content :decoy decoy :author author :graph graph :map map :node node :lifecycle lifecycle
   :path (fs.join-path s.notebook-store.notebooks-dir "n.json")
   :targets [] :writes 0 :signals {} :calls []})

(fn with-notebook-preview [body]
  (assert (and app app.engine (app.engine:is-started) (not (app.engine:is-shutdown)))
          "Notebook unit fixture requires initialized caller context")
  (fn stored [root]
    (local unit {:width 640 :height 360 :ui [] :targets [] :domain [] :records {}})
    (fn run [] (init-preview-unit unit) (observe-notebook-preview (make-preview-fixture root unit) body))
    (local (ok result) (pcall run))
    (local (clean-ok clean-error) (pcall drop-preview-resources [unit.targets unit.domain unit.ui]))
    (if (not ok) (error result) (not clean-ok) (error clean-error) result))
  (H.with-root stored))

(fn notebook-preview-provider [f]
  (open-notebook-preview f)
  ;; This assertion is intentionally independent of the new row projection fields.
  (local preview (notebook-row-preview f 1))
  (assert preview.input "owning identity must reach actual configured string preview, not fallback")
  (assert (= (preview.input:get-text) "CORRECT inline preview"))
  (local adapter (assert (f.graph:lookup "string-entity:s")))
  (assert (= adapter.store f.content) "registered content provider identity, not either default")
  (assert (= adapter.store.base-dir (fs.join-path f.root "provider")))
  (assert (= adapter.lifecycle f.lifecycle) "registered adapter retains lifecycle")
  (assert-preview-rows f preview-keys ["string-entity:s" "string-entity:s"])
  (close-notebook-previews f)
  (f.node:mount f.map)
  (open-notebook-preview f)
  (local mapped (assert (f.map:lookup "string-entity:s")))
  (assert (= mapped.store f.content)) (assert (= mapped.lifecycle f.lifecycle))
  (assert (= mapped.graph f.map))
  (local mapped-input (. (notebook-row-preview f 2) :input))
  (assert (= (mapped-input:get-text) "CORRECT inline preview")))

(fn notebook-preview-passive [f]
  ;; Positive resolver control: isolates the independent String initialization write.
  (fn run []
    (local before (H.snapshot-tree f.root))
    (open-notebook-preview f) (open-notebook-preview f)
    (f.view:refresh-items) (f.view:refresh-items)
    (each [_ target (ipairs f.targets)]
      (draw-notebook-target f target))
    (assert-preview-membership f preview-keys)
    (close-notebook-previews f)
    (assert-preview-passive f before))
  (H.with-fields f.graph {:identity-store f.store.identity-store} run))

(fn historical-notebook-items [f items]
  (local value (json.loads (fs.read-file f.path)))
  (set value.items items) (J.write-json! f.path value)
  (tset f.store.cache "n" nil)
  (set f.record (f.store:get-notebook "n"))
  (reset-preview-observation f))

(fn watch-notebook-preview-drop [drops widget]
  (local drop widget.drop)
  (tset drops widget 0)
  (set widget.drop (fn [self] (tset drops self (+ (. drops self) 1)) (drop self))))

(fn assert-concrete-list-preview [widget]
  (assert (and widget.name-input widget.list widget.items-label widget.actions-row widget.layout)
          "actual registered List preview required, not Text fallback")
  (assert (= widget.input nil) "retarget must replace the old String preview")
  (assert (= (widget.name-input:get-text) "Retargeted empty List"))
  (same-preview-value widget.list.items [])
  (assert-preview-text widget.items-label "Items (0):")
  (assert (= (# widget.actions-row.children) 2))
  (local add (preview-child widget.actions-row 1))
  (local delete (preview-child widget.actions-row 2))
  (assert-preview-text (preview-child add.text 2) "Add Selected")
  (assert-preview-text (preview-child delete.text 2) "Delete List"))

(fn observe-concrete-list-preview [drops widget]
  (assert-concrete-list-preview widget)
  (each [_ child (ipairs [widget widget.name-input widget.items-label widget.list widget.actions-row
                         (preview-child widget.actions-row 1) (preview-child widget.actions-row 2)])]
    (watch-notebook-preview-drop drops child))
  widget)

(fn notebook-open-handlers [signal]
  (var callbacks nil)
  (for [i 1 20]
    (local (name value) (debug.getupvalue signal.emit i))
    (when (= name "callbacks") (set callbacks value)))
  (assert callbacks "native Signal callbacks must be inspectable")
  (accumulate [n 0 _ record (ipairs callbacks)] (+ n (if record.active? 1 0))))

(fn notebook-open-baseline [f]
  [(# app.clickables.left-click-objects) (# app.clickables.right-click-objects)
   (# app.clickables.double-click-objects) (# app.hoverables.objects)
   (notebook-open-handlers f.node.items-changed)
   (notebook-open-handlers f.screen.focus.focus-focus) (notebook-open-handlers f.screen.focus.focus-blur)])

(fn assert-failed-notebook-open [f expected attempt]
  (local before (notebook-open-baseline f)) (local bytes (H.snapshot-tree f.root))
  (local (ok result) (pcall attempt))
  (assert (not ok) "initial notebook open must propagate its error")
  (when expected
    (if (= (type expected) :table) (assert (= result expected) "original initial-open exception identity")
        (assert (string.find (tostring result) expected 1 true))))
  (same-preview-value (notebook-open-baseline f) before)
  (local target (. f.screen.targets (# f.screen.targets) :resource))
  (assert (= (# (target:get-text-ssbo-draw-list)) 0) "failed initial open must release native text")
  (assert (= (# (target:get-quad-draw-list)) 0) "failed initial open must release native quads")
  (assert-preview-passive f bytes))

(fn exercise-notebook-list-chain [f adapter]
  (local original-preview adapter.preview) (local original-drop adapter.drop)
  (local drops {}) (var adapter-drops 0) (var built 0)
  (fn preview [node opts]
    (assert (= node adapter)) (assert (= opts.node adapter))
    (local builder (original-preview node opts))
    (fn build [ctx]
      (set built (+ built 1))
      (observe-concrete-list-preview drops (builder ctx))))
  (fn drop [self] (set adapter-drops (+ adapter-drops 1)) (original-drop self))
  (fn run []
    ;; Historical bad membership, without firing projection events before the view.
    (local entity (adapter:get-entity)) (local items entity.items)
    (local path (. (adapter.store:snapshot-entity entity.id) :path))
    (adapter.identity-store:create-entity {:id "nested-loop" :target-key "identity:nested-loop"})
    (set entity.items ["identity:nested-loop"]) (J.write-json! path entity)
    (historical-notebook-items f ["list-entity:empty"])
    (fn opening [] (open-notebook-preview f))
    (assert-failed-notebook-open f "cycle detected" opening)
    (assert (and (= built 1) (= adapter-drops 0) (= (notebook-open-handlers adapter.items-changed) 0)))
    (assert (= (f.graph:lookup "list-entity:empty") adapter))
    (set entity.items items) (J.write-json! path entity)
    (historical-notebook-items f ["identity:z" "string-entity:t"]) (set built 0)
    (local settled (H.snapshot-tree f.root)) (adapter.items-changed:emit {}) (assert-preview-passive f settled)
    (local before (H.snapshot-tree f.root))
    (for [_ 1 2]
      (f.view:refresh-items)
      (assert-preview-rows f ["identity:z" "string-entity:t"] ["list-entity:empty" "string-entity:t"])
      (local widget (notebook-row-preview f 1))
      (assert-concrete-list-preview widget)
      (local string-input (. (notebook-row-preview f 2) :input))
      (assert (= (string-input:get-text) "Other provider content"))
      (draw-notebook-target f (. f.targets 1))
      (assert (and (> widget.layout.size.x 0) (> widget.layout.size.y 0))))
    (assert (= built 2) "each refresh builds the real registered List preview")
    (assert-preview-membership f ["identity:z" "string-entity:t"])
    (close-notebook-previews f)
    (each [_ count (pairs drops)] (assert (= count 1) "each List row widget drops exactly once"))
    (assert (= adapter-drops 0) "row widget teardown must not own adapter")
    (assert (= (f.graph:load-by-key "list-entity:empty") adapter))
    (assert (= (f.graph:lookup "list-entity:empty") adapter))
    (f.graph:drop)
    (assert (= adapter-drops 1) "graph alone drops the registered List adapter")
    (assert-preview-passive f before))
  (H.with-fields adapter {:preview preview :drop drop} run))

(fn notebook-preview-chain [f]
  (historical-notebook-items f ["identity:z" "string-entity:t"])
  (open-notebook-preview f)
  (assert-preview-rows f ["identity:z" "string-entity:t"] ["string-entity:s" "string-entity:t"])
  (local original-input (. (notebook-row-preview f 1) :input))
  (assert (= (original-input:get-text) "CORRECT inline preview"))
  (local store f.stores.list-store)
  (local entity (store:create-entity {:id "empty" :name "Retargeted empty List" :items []}))
  (local lifecycle (H.lifecycle f.stores))
  ((. (require :graph/nodes/list-entity) :register-loader) f.graph {:store store :lifecycle lifecycle})
  (local adapter (f.graph:load-by-key "list-entity:empty"))
  (assert (= adapter.store store)) (assert (= adapter.store.base-dir (fs.join-path f.root "owner")))
  (assert (= adapter.identity-store f.store.identity-store))
  (assert (= adapter.lifecycle lifecycle)) (assert (= (adapter:resolve-reference-lifecycle!) lifecycle))
  (assert (= adapter.preview (require :graph/view/views/list-entity)))
  (assert (= adapter.preview adapter.view))
  (f.store.identity-store:update-entity "a" {:target-key "list-entity:empty"})
  (reset-preview-observation f)
  (exercise-notebook-list-chain f adapter)
  (assert (= (store:get-entity "empty") entity))
  (same-preview-value entity (. (store:snapshot-entity "empty") :value)))

(fn notebook-preview-actions [f]
  (open-notebook-preview f) (reset-preview-observation f)
  (click-notebook-row f 1 1) (click-notebook-row f 2 2)
  (same-preview-value f.calls [])
  (click-notebook-row f 1 2)
  (assert-preview-membership f ["identity:a" "identity:z"])
  (assert-preview-rows f ["identity:a" "identity:z"] ["string-entity:s" "string-entity:s"])
  (click-notebook-row f 2 1)
  (assert-preview-membership f preview-keys)
  (click-notebook-row f 2 3)
  (assert-preview-membership f ["identity:z"])
  (same-preview-value f.calls
    [{:store f.store.base-dir :method :move-item :args ["n" 1 2]}
     {:store f.store.base-dir :method :move-item :args ["n" 2 1]}
     {:store f.store.base-dir :method :remove-item :args ["n" "identity:a"]}])
  (same-preview-value [f.writes f.signals] [3 {:notebook 3 :items 3}]))

(fn notebook-preview-edits [f]
  (open-notebook-preview f) (reset-preview-observation f)
  (local original (json.loads (fs.read-file f.path)))
  (local content-before (. (f.content:snapshot-entity "s") :value))
  (local decoy-before (H.snapshot-tree f.decoy.base-dir))
  (local author-before (H.snapshot-tree f.author.base-dir))
  (f.view.name-input:set-text "Renamed metadata")
  (local input (. (notebook-row-preview f 1) :input))
  (input:set-text "Edited concrete value")
  (same-preview-value f.calls
    [{:store f.store.base-dir :method :update-notebook :args ["n" {:name "Renamed metadata"}]}
     {:store f.content.base-dir :method :update-entity :args ["s" {:value "Edited concrete value"}]}])
  (set original.name "Renamed metadata") (set original.updated-at f.record.updated-at)
  (same-preview-value f.record original)
  (set content-before.value "Edited concrete value") (set content-before.updated-at f.held.updated-at)
  (same-preview-value f.held content-before)
  (same-preview-value (H.snapshot-tree f.decoy.base-dir) decoy-before)
  (same-preview-value (H.snapshot-tree f.author.base-dir) author-before)
  (assert-preview-membership f preview-keys)
  (same-preview-value [f.writes f.signals] [2 {:notebook 1 :content 1}]))

(fn notebook-preview-selection [f]
  (open-notebook-preview f) (reset-preview-observation f)
  (fn select []
    (local add (notebook-action f 1)) (add:on-click {}))
  (H.with-fields app {:graph-view {:selection {:selected-nodes
    [{:key "identity:c"} {:key "identity:z"} {:key "string-entity:s"} {:key "identity:a"}]}}} select)
  (assert-preview-membership f ["identity:z" "identity:a" "identity:c"])
  (same-preview-value f.calls
    [{:store f.store.base-dir :method :add-item :args ["n" "identity:c"]}
     {:store f.store.base-dir :method :add-item :args ["n" "identity:z"]}
     {:store f.store.base-dir :method :add-item :args ["n" "string-entity:s"]}
     {:store f.store.base-dir :method :add-item :args ["n" "identity:a"]}])
  (same-preview-value [f.writes f.signals] [1 {:notebook 1 :items 1}])
  (reset-preview-observation f)
  (local create (notebook-action f 2)) (create:on-click {})
  (local key (. f.record.items 4))
  (local terminal (f.store.identity-store:resolve-key key))
  (assert (= (string.sub terminal 1 14) "string-entity:"))
  (local id (string.sub terminal 15))
  (assert (f.author:get-entity id) "explicit string creation belongs to authoring store")
  (assert (not (f.content:get-entity id)) "registered preview store must not steal authoring")
  (assert (= (. (f.graph:lookup terminal) :store) f.author))
  (assert-preview-membership f ["identity:z" "identity:a" "identity:c" key])
  (same-preview-value [f.writes f.signals] [3 {:notebook 1 :items 1 :author-created 1 :allocated 1}]))

(fn notebook-preview-missing [f]
  (f.store.identity-store:create-entity {:id "empty" :target-key ""})
  (f.store.identity-store:create-entity {:id "absent" :target-key "string-entity:absent"})
  (local long "external:abcdefghijklmnopqrstuvwxyz-0123456789-long-unavailable")
  (local keys ["identity:missing" "identity:empty" "identity:absent" long])
  (historical-notebook-items f keys)
  (local before (H.snapshot-tree f.root))
  (open-notebook-preview f)
  (assert-preview-rows f keys ["identity:missing" "identity:empty" "string-entity:absent" long])
  (each [i terminal (ipairs ["identity:missing" "identity:empty" "string-entity:absent" long])]
    (local widget (notebook-row-preview f i))
    (assert (not widget.input) "absence must not fabricate an editor")
    (assert-preview-text widget ((. (require :graph/view/utils) :truncate-with-ellipsis) terminal 42)))
  (assert-preview-passive f before)
  (historical-notebook-items f ["identity:z"])
  (fn detached [] (f.view:refresh-items)
    (assert-preview-rows f ["identity:z"] ["string-entity:s"])
    (assert-preview-text (notebook-row-preview f 1) "string-entity:s"))
  (local detached-before (H.snapshot-tree f.root))
  (H.with-fields f.node {:graph false} detached)
  (assert-preview-passive f detached-before)
  (historical-notebook-items f []) (f.view:refresh-items)
  (assert-preview-rows f [] []))

(fn assert-notebook-refresh-error [f fragment refresh]
  (local before (H.snapshot-tree f.root))
  (local rows f.view.list.items)
  (local label (J.stable-json (f.view.items-label:get-codepoints)))
  (H.assert-error fragment refresh)
  (assert (= rows f.view.list.items) "resolution must complete before any rows are published")
  (assert (= label (J.stable-json (f.view.items-label:get-codepoints))) "no partial count publication")
  (assert-preview-passive f before))

(fn notebook-initial-concrete-error [f]
  (historical-notebook-items f ["identity:z" "identity:c"])
  (local adapter (f.graph:load-by-key "string-entity:s"))
  (local original adapter.preview) (local original-drop adapter.drop) (local load f.graph.load-by-key)
  (local failure {}) (local drops {}) (var built 0) (var adapter-drops 0)
  (fn preview [node opts]
    (local builder (original node opts))
    (fn build [ctx]
      (local widget (builder ctx)) (set built (+ built 1))
      (watch-notebook-preview-drop drops widget) widget))
  (fn drop [self] (set adapter-drops (+ adapter-drops 1)) (original-drop self))
  (fn loading [self key]
    (if (= key "string-entity:t")
        (do (assert (= built 1) "concrete failure must follow one actual preview") (error failure 0))
        (load self key)))
  (fn opening [] (open-notebook-preview f))
  (fn attempt [] (H.with-fields f.graph {:load-by-key loading} opening))
  (fn run [] (assert-failed-notebook-open f failure attempt))
  (H.with-fields adapter {:preview preview :drop drop} run)
  (assert (= built 1)) (assert (= adapter-drops 0))
  (assert (= (f.graph:lookup "string-entity:s") adapter)) (assert (= adapter.store f.content))
  (local before (H.snapshot-tree f.root))
  (each [widget count (pairs drops)]
    (assert (= count 1) "acquired initial preview must drop exactly once")
    (widget.input.model:set-text "discarded failed preview edit"))
  (assert-preview-passive f before)
  (historical-notebook-items f preview-keys)
  (f.node:update-name "After failed initial open")
  (var loads 0)
  (fn counting [self key] (set loads (+ loads 1)) (load self key))
  (fn event [] (f.node.items-changed:emit {}))
  (H.with-fields f.graph {:load-by-key counting} event)
  (assert (= loads 2) "only the surviving view may refresh after subsequent authoring/event")
  (same-preview-value [f.writes f.signals] [1 {:notebook 1}])
  (reset-preview-observation f))

(fn notebook-preview-resolution-errors [f]
  (open-notebook-preview f)
  (local ids f.store.identity-store)
  (ids:create-entity {:id "self" :target-key "identity:self"})
  (ids:create-entity {:id "one" :target-key "identity:two"})
  (ids:create-entity {:id "two" :target-key "identity:one"})
  (for [i 1 34] (ids:create-entity {:id (.. "d" i) :target-key (.. "identity:d" (+ i 1))}))
  (ids:create-entity {:id "d35" :target-key "string-entity:s"})
  (fn refresh [] (f.view:refresh-items))
  (each [_ pair (ipairs [["identity:self" "cycle detected"] ["identity:one" "cycle detected"]
                         ["identity:d1" "depth exhausted"]])]
    (historical-notebook-items f ["identity:z" (. pair 1)])
    (assert-notebook-refresh-error f (. pair 2) refresh)
    (fn opening [] (open-notebook-preview f))
    (assert-failed-notebook-open f (. pair 2) opening))
  (historical-notebook-items f preview-keys)
  (fn missing-owner [] (H.with-fields f.store {:identity-store false} refresh))
  (assert-notebook-refresh-error f "owning IdentityStore" missing-owner)
  (fn ownerless-open [] (H.with-fields f.store {:identity-store false}
    (fn opening [] (open-notebook-preview f))))
  (assert-failed-notebook-open f "owning IdentityStore" ownerless-open)
  (ids:create-entity {:id "unreadable" :target-key "string-entity:s"})
  (tset ids.cache "unreadable" nil)
  (historical-notebook-items f ["identity:z" "identity:unreadable"])
  (fn unreadable [] (H.with-fs-failure :read-file (fs.join-path ids.entities-dir "unreadable.json") refresh))
  (assert-notebook-refresh-error f "injected permission denied" unreadable)
  (fn unreadable-open [] (H.with-fs-failure :read-file (fs.join-path ids.entities-dir "unreadable.json")
    (fn opening [] (open-notebook-preview f))))
  (assert-failed-notebook-open f "injected permission denied" unreadable-open))

(fn notebook-preview-required-errors [f]
  (open-notebook-preview f)
  (notebook-initial-concrete-error f)
  (local adapter (assert (f.graph:lookup "string-entity:s")))
  (fn refresh [] (f.view:refresh-items))
  (fn fail [...] (error "required concrete loader failure"))
  (fn loader [] (H.with-fields f.graph {:load-by-key fail} refresh))
  (H.assert-error "required concrete loader failure" loader)
  (each [_ preview (ipairs [false 42
    (fn invalid-builder [_ _opts] 42)
    (fn missing-layout [_ _opts] (fn build [_ctx] {}))
    (fn broken-preview [_ _opts] (error "preview failure"))
    (fn broken-builder [_ _opts] (fn build [_ctx] (error "builder failure")))])]
    (fn invalid [] (H.with-fields adapter {:preview preview} refresh))
    (fn initial [] (H.with-fields adapter {:preview preview}
      (fn opening [] (open-notebook-preview f))))
    (assert-failed-notebook-open f nil initial)
    (local (ok _err) (pcall invalid)) (assert (not ok) "required preview/builder/layout errors propagate"))
  (f.view:refresh-items)
  (local preview (notebook-row-preview f 1))
  (fn broken-layout [_self] (error "layouter failure"))
  (fn layout [] (preview.layout:layouter))
  (H.with-fields preview.layout {:layouter broken-layout}
    (fn check [] (H.assert-error "layouter failure" layout)))
  (historical-notebook-items f ["string-entity:t"])
  (local content-path (. (f.content:snapshot-entity "t") :path))
  (tset f.content.cache "t" nil)
  (fn read-error [] (H.with-fs-failure :read-file content-path refresh))
  (H.assert-error "injected permission denied" read-error)
  (fn read-open [] (H.with-fs-failure :read-file content-path
    (fn opening [] (open-notebook-preview f))))
  (assert-failed-notebook-open f "injected permission denied" read-open))

(fn notebook-preview-teardown [f]
  (local adapter (f.graph:load-by-key "string-entity:s"))
  (local original-preview adapter.preview) (local original-drop adapter.drop)
  (local drops {}) (var adapter-drops 0)
  (fn preview [node opts]
    (local builder (original-preview node opts))
    (fn build [ctx]
      (local widget (builder ctx)) (local drop widget.drop)
      (tset drops widget 0)
      (set widget.drop (fn [self] (tset drops self (+ (. drops self) 1)) (drop self)))
      widget))
  (fn drop [self] (set adapter-drops (+ adapter-drops 1)) (original-drop self))
  (fn run []
    (local before (H.snapshot-tree f.root))
    (open-notebook-preview f)
    (local old-input (. (notebook-row-preview f 1) :input))
    (f.view:refresh-items)
    (assert (= (f.graph:lookup "string-entity:s") adapter) "refresh reuses graph-owned adapter")
    (close-notebook-previews f)
    (each [_ count (pairs drops)] (assert (= count 1) "each row owns/drops only its widget once"))
    (assert (= adapter-drops 0) "row teardown must not drop graph-owned adapter")
    (f.node.items-changed:emit {})
    (old-input.model:set-text "stale edit after teardown")
    (assert-preview-passive f before)
    (assert (= (adapter:get-entity) f.held))
    (f.graph:drop)
    (assert (= adapter-drops 1) "graph alone drops its adapter"))
  (H.with-fields adapter {:preview preview :drop drop} run))

(fn add-notebook-preview-test [suffix body]
  (fn run [] (with-notebook-preview body))
  (table.insert tests {:name (.. "notebook preview presentation " suffix) :fn run}))

(add-notebook-preview-test "owning identity and configured concrete content provider" notebook-preview-provider)
(add-notebook-preview-test "passive construction and refresh never author content" notebook-preview-passive)
(add-notebook-preview-test "alias chains resolve current concrete type without reauthoring" notebook-preview-chain)
(add-notebook-preview-test "distinct aliases keep canonical remove and move identities" notebook-preview-actions)
(add-notebook-preview-test "metadata and content edits use isolated payloads" notebook-preview-edits)
(add-notebook-preview-test "selection and string creation retain canonical ownership" notebook-preview-selection)
(add-notebook-preview-test "missing targets use explicit nonauthoring fallback" notebook-preview-missing)
(add-notebook-preview-test "cycles and depth exhaustion surface before preview authoring" notebook-preview-resolution-errors)
(add-notebook-preview-test "required concrete preview failures surface" notebook-preview-required-errors)
(add-notebook-preview-test "refresh teardown preserves adapter and callback ownership" notebook-preview-teardown)

(fn assert-notebook-fixture-lifetime [run expected]
  (local caller (assert app)) (local engine (assert caller.engine))
  (local fields (collect [key value (pairs caller)] key value))
  (local runtime (require :state-system-runtime))
  (local provider _G.__space_state_system_runtime.states-provider)
  (local host (runtime.maybe-states-host)) (local preload package.preload.jobs)
  (local input-state (require :input-state-router)) (local active-input (input-state.active-input))
  (local module (require :engine)) (local constructor module.Engine)
  (local start engine.start) (local shutdown engine.shutdown)
  (var constructed 0) (var started 0) (var stopped 0) (var delivered 0)
  (fn construct [opts] (set constructed (+ constructed 1)) (constructor opts))
  (fn start-engine [self] (set started (+ started 1)) (start self))
  (fn stop-engine [self] (set stopped (+ stopped 1)) (shutdown self))
  (fn received [payload] (assert (= payload.token "Notebook caller")) (set delivered (+ delivered 1)))
  (local id (engine.callbacks.register received))
  (fn observed [] (H.with-fields engine {:start start-engine :shutdown stop-engine} run))
  (local (ok result) (pcall H.with-fields module {:Engine construct} observed))
  (assert (= constructed 0) "Notebook fixture must borrow caller Engine, never construct another")
  (assert (and (= started 0) (= stopped 0)) "Notebook fixture must not start/shut down caller Engine")
  (assert (= app caller)) (assert (= app.engine engine))
  (each [key value (pairs fields)] (assert (= (. caller key) value)))
  (each [key value (pairs caller)] (assert (= (. fields key) value)))
  (assert (and (engine:is-started) (not (engine:is-shutdown))))
  (assert (= (type (engine:now-ms)) :number))
  (assert (= _G.__space_state_system_runtime.states-provider provider))
  (assert (= (runtime.maybe-states-host) host))
  (assert (= (input-state.active-input) active-input))
  (assert (= package.preload.jobs preload)) (assert (= (preload) engine.jobs))
  (engine.callbacks.enqueue id {:token "Notebook caller"}) (engine.callbacks.dispatch)
  (assert (= delivered 1)) (assert (engine.callbacks.unregister id))
  (if expected (assert (and (not ok) (= result expected)) "original Notebook error object must survive cleanup")
      (assert ok (tostring result))))

(fn notebook-lifetime-scenario [callback-error? cleanup-error?]
  (local callback-error {}) (local cleanup-error {}) (local drops {})
  (var fixture nil)
  (fn body [f]
    (set fixture f) (open-notebook-preview f)
    (local target (. f.targets 1)) (local drop target.drop)
    (set target.drop (fn [self]
      (tset drops :target (+ (or drops.target 0) 1)) (drop self)
      (when cleanup-error? (error cleanup-error 0))))
    (local input (. (notebook-row-preview f 1) :input))
    (input:request-focus) (assert input.focused?) (input:enter-insert-mode)
    (input:on-text-input {:text "typed"})
    (local move f.store.move-item)
    (fn operation [self ...]
      (local result (move self ...))
      (when callback-error? (error callback-error 0)) result)
    (fn click [] (click-notebook-row f 1 2))
    (H.with-fields f.store {:move-item operation} click))
  (fn run [] (with-notebook-preview body))
  (assert-notebook-fixture-lifetime run (if callback-error? callback-error cleanup-error? cleanup-error nil))
  (assert (= drops.target 1)) (assert (not (fs.exists fixture.root)))
  (each [_ entries (ipairs [fixture.screen.targets fixture.screen.domain fixture.screen.ui])]
    (each [_ entry (ipairs entries)] (assert entry.closed? "all acquired unit resources must be released")))
  (local target (. fixture.targets 1))
  (assert (= (# (target:get-text-ssbo-draw-list)) 0))
  (assert (= (fixture.graph:node-count) 0)) (assert (= (fixture.map:node-count) 0))
  (fixture.node.items-changed:emit {}))

(fn notebook-lifetime-constructor-failure []
  (local Io (require :io-utils)) (local read Io.read-file) (local failure {})
  (local Focus (require :focus)) (local constructor Focus.FocusManager)
  (var drops 0) (var called? false)
  (fn focus [opts]
    (local manager (constructor opts)) (local drop manager.drop)
    (set manager.drop (fn [self] (set drops (+ drops 1)) (drop self))) manager)
  (fn failed-read [path]
    (if (string.find path ".codepoints" 1 true) (error failure 0) (read path)))
  (fn body [_f] (set called? true))
  (fn run [] (with-notebook-preview body))
  (fn reading [] (H.with-fields Io {:read-file failed-read} run))
  (fn observed [] (H.with-fields Focus {:FocusManager focus} reading))
  (assert-notebook-fixture-lifetime observed failure)
  (assert (not called?)) (assert (= drops 1) "partially acquired FocusManager must be dropped"))

(fn notebook-lifetime-normal []
  (notebook-lifetime-scenario false false)
  (notebook-lifetime-constructor-failure)
  (notebook-lifetime-scenario false true))
(fn notebook-lifetime-exception []
  (notebook-lifetime-scenario true false)
  (notebook-lifetime-scenario true true))
(table.insert tests {:name "presentation fixture lifetime Notebook normal return" :fn notebook-lifetime-normal})
(table.insert tests {:name "presentation fixture lifetime Notebook callback exception" :fn notebook-lifetime-exception})

tests
