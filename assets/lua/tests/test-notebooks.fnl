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

tests
