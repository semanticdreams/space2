(local fs (require :fs))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "list-entities"))

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
      (local ListEntityStore (require :entities/list))
      (local store (ListEntityStore.ListEntityStore {:base-dir root}))
      (f store root))))

(fn list-entity-store-creates-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "My List"
                                          :items ["node-a" "node-b"]}))
      (assert entity "entity should be created")
      (assert entity.id "entity should have id")
      (assert (= entity.name "My List") "entity should have correct name")
      (assert (= (length entity.items) 2) "entity should have two items")
      (assert (= (. entity.items 1) "node-a") "items should preserve ordering")
      (assert entity.created-at "entity should have created-at")
      (assert entity.updated-at "entity should have updated-at"))))

(fn list-entity-store-retrieves-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "My List"
                                          :items ["node-a" "node-b"]}))
      (local retrieved (store:get-entity entity.id))
      (assert retrieved "entity should be retrieved")
      (assert (= retrieved.id entity.id) "retrieved entity should have same id")
      (assert (= retrieved.name "My List") "retrieved entity should have correct name")
      (assert (= (length retrieved.items) 2) "retrieved entity should have items"))))

(fn list-entity-store-updates-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "Old"
                                          :items ["a"]}))
      (local updated (store:update-entity entity.id {:name "New"}))
      (assert updated "entity should be updated")
      (assert (= updated.name "New") "name should be updated")
      (local retrieved (store:get-entity entity.id))
      (assert (= retrieved.name "New") "persisted name should be updated"))))

(fn list-entity-store-deletes-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "Delete Me"}))
      (local deleted (store:delete-entity entity.id))
      (assert deleted "entity should be deleted")
      (local retrieved (store:get-entity entity.id))
      (assert (= retrieved nil) "entity should no longer be retrievable"))))

(fn list-entity-store-lists-entities-sorted []
  (with-temp-store
    (fn [store _root]
      (store:create-entity {:name "old" :updated-at 10})
      (store:create-entity {:name "mid" :updated-at 20})
      (store:create-entity {:name "new" :updated-at 30})
      (local entities (store:list-entities))
      (assert (= (length entities) 3) "should list three entities")
      (assert (= (. entities 1 :updated-at) 30) "should sort by updated-at desc"))))

(fn list-entity-store-emits-created-signal []
  (with-temp-store
    (fn [store _root]
      (var created-count 0)
      (store.list-entity-created:connect (fn [_] (set created-count (+ created-count 1))))
      (store:create-entity {:name "x"})
      (assert (= created-count 1) "created signal should be emitted"))))

(fn list-entity-store-emits-updated-signal []
  (with-temp-store
    (fn [store _root]
      (var updated-count 0)
      (store.list-entity-updated:connect (fn [_] (set updated-count (+ updated-count 1))))
      (local entity (store:create-entity {:name "x"}))
      (store:update-entity entity.id {:name "y"})
      (assert (= updated-count 1) "updated signal should be emitted"))))

(fn list-entity-store-emits-deleted-signal []
  (with-temp-store
    (fn [store _root]
      (var deleted-count 0)
      (store.list-entity-deleted:connect (fn [_] (set deleted-count (+ deleted-count 1))))
      (local entity (store:create-entity {:name "x"}))
      (store:delete-entity entity.id)
      (assert (= deleted-count 1) "deleted signal should be emitted"))))

(fn list-entity-store-adds-items-and-prevents-duplicates []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "x" :items ["a"]}))
      (var items-count 0)
      (store.list-entity-items-changed:connect (fn [_] (set items-count (+ items-count 1))))
      (store:add-item entity.id "b")
      (store:add-item entity.id "b")
      (local retrieved (store:get-entity entity.id))
      (assert (= (length retrieved.items) 2) "should not add duplicates")
      (assert (= items-count 1) "items-changed should emit once for one actual change"))))

(fn list-entity-store-removes-items []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "x" :items ["a" "b" "c"]}))
      (store:remove-item entity.id "b")
      (local retrieved (store:get-entity entity.id))
      (assert (= (length retrieved.items) 2) "should remove one item")
      (assert (= (. retrieved.items 1) "a") "should preserve order after removal")
      (assert (= (. retrieved.items 2) "c") "should preserve order after removal"))))

(fn list-entity-store-moves-items []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "x" :items ["a" "b" "c"]}))
      (store:move-item entity.id 1 3)
      (local retrieved (store:get-entity entity.id))
      (assert (= (. retrieved.items 1) "b") "move should reorder items")
      (assert (= (. retrieved.items 2) "c") "move should reorder items")
      (assert (= (. retrieved.items 3) "a") "move should reorder items"))))

(fn list-entity-store-emits-items-changed-signal []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "x"}))
      (var payload-id nil)
      (store.list-entity-items-changed:connect
        (fn [payload]
          (set payload-id (or (and payload payload.id) nil))))
      (store:add-item entity.id "a")
      (assert (= payload-id entity.id) "items-changed should include entity id"))))

(fn list-entity-node-loads []
  (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
  (assert ListEntityNode "ListEntityNode should load")
  (assert (= (type ListEntityNode) "function") "ListEntityNode should be a function"))

(fn list-entity-node-creates-with-correct-properties []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "x"}))
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local node (ListEntityNode {:entity-id entity.id :store store}))
      (assert (= node.key (.. "list-entity:" entity.id)) "key should be prefixed entity id")
      (assert node.color "should have color")
      (assert node.items-changed "should have items-changed signal")
      (assert node.entity-deleted "should have entity-deleted signal")
      (assert node.get-entity "should have get-entity method")
      (assert node.update-name "should have update-name method")
      (assert node.add-item "should have add-item method")
      (assert node.remove-item "should have remove-item method")
      (assert node.move-item "should have move-item method")
      (assert node.delete-entity "should have delete-entity method")
      (node:drop))))

(fn list-entity-node-sets-compact-label-for-named-list []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "Named List"}))
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local node (ListEntityNode {:entity-id entity.id :store store}))
      (assert (= node.label "Named List")
              "named list entity should keep custom name as node.label")
      (assert (= node.compact-label "Named List")
              "named list entity should use custom name as compact-label")
      (node:drop))))

(fn list-entity-node-opts-out-compact-label-for-unnamed-list []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {}))
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local node (ListEntityNode {:entity-id entity.id :store store}))
      (assert (= node.label entity.id)
              "unnamed list entity should keep raw id fallback as node.label")
      (assert (= node.compact-label false)
              "unnamed list entity should opt out of compact labels")
      (node:drop))))

(fn list-entity-node-refreshes-compact-label-and-emits-changed []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "Visible"}))
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local node (ListEntityNode {:entity-id entity.id :store store}))
      (var changed-count 0)
      (var changed-payload nil)
      (node.changed:connect
        (fn [payload]
          (set changed-count (+ changed-count 1))
          (set changed-payload payload)))

      (store:update-entity entity.id {:name ""})
      (assert (= node.label entity.id)
              "clearing the custom name should restore raw id fallback label")
      (assert (= node.compact-label false)
              "clearing the custom name should opt out of compact labels")
      (assert (> changed-count 0)
              "clearing the custom name should emit node.changed")
      (assert (= changed-payload node)
              "node.changed payload should be the list entity node")

      (set changed-count 0)
      (store:update-entity entity.id {:name "Restored"})
      (assert (= node.label "Restored")
              "setting the custom name should refresh node.label")
      (assert (= node.compact-label "Restored")
              "setting the custom name should refresh compact-label")
      (assert (> changed-count 0)
              "setting the custom name should emit node.changed")
      (node:drop))))

(fn list-entity-node-adds-item-edges-after-added []
  (with-temp-store
    (fn [store _root]
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local a (Graph.GraphNode {:key "node-a"}))
      (local b (Graph.GraphNode {:key "node-b"}))
      (graph:add-node a {})
      (graph:add-node b {})
      (local entity (store:create-entity {:name "x"
                                          :items ["node-a" "node-b"]}))
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local node (ListEntityNode {:entity-id entity.id :store store}))
      ;; Used to recurse because mount ran before the node was inserted into graph.nodes.
      (graph:add-node node {})
      (assert (= (graph:edge-count) 2)
              "list entity node should add edges to existing item nodes")
      (graph:drop))))

(fn list-entity-node-add-item-wraps-non-identity-key-and-dedupes []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local IdentityStore (require :entities/identity))
      (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path root "identity")}))
      (local entity (store:create-entity {:name "x"}))
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local node (ListEntityNode {:entity-id entity.id
                                   :store store
                                   :identity-store identity-store}))
      (local graph (Graph {:with-start false
                           :identity-store identity-store}))
      (graph:add-node node {})

      (node:add-item "node-a")
      (node:add-item "node-a")

      (local current (store:get-entity entity.id))
      (assert (= (length (or current.items [])) 1)
              "adding same target twice should dedupe to one identity key")
      (local stored-key (. current.items 1))
      (assert (= (string.sub stored-key 1 9) "identity:")
              "list entity should wrap non-identity keys with identity")
      (local identity-id (string.sub stored-key 10))
      (local identity-entity (identity-store:get-entity identity-id))
      (assert identity-entity "identity entity should be persisted")
      (assert (= identity-entity.target-key "node-a")
              "identity target key should match added key")

      (local identities (identity-store:list-entities))
      (assert (= (length identities) 1)
              "identity wrapping should reuse existing identity for same target")

      (graph:drop))))

(fn list-entity-node-removes-direct-item-when-node-disappears []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local IdentityStore (require :entities/identity))
      (local StringEntityStore (require :entities/string))
      (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path root "identity")}))
      (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path root "string")}))
      (local string-entity (string-store:create-entity {:value "soon gone"}))
      (local source-key (.. "string-entity:" string-entity.id))
      (local entity (store:create-entity {:name "x"
                                          :items [source-key]}))
      (local graph (Graph {:with-start false
                           :identity-store identity-store}))
      (local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
      (register-string-loader graph {:store string-store})
      (local source-node (graph:load-by-key source-key))
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local list-node (ListEntityNode {:entity-id entity.id
                                        :store store
                                        :identity-store identity-store}))
      (graph:add-node list-node {})
      (assert (= (length (or (. (store:get-entity entity.id) :items) [])) 1)
              "list should start with direct key item")
      (graph:remove-nodes [source-node])
      (local current (store:get-entity entity.id))
      (assert (= (length (or current.items [])) 0)
              "list should remove direct key item when node disappears")
      (graph:drop))))

(fn list-entity-node-refreshes-identity-item-edges-on-target-change []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local IdentityStore (require :entities/identity))
      (local StringEntityStore (require :entities/string))
      (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path root "identity")}))
      (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path root "string")}))
      (local a (string-store:create-entity {:value "a"}))
      (local b (string-store:create-entity {:value "b"}))
      (local key-a (.. "string-entity:" a.id))
      (local key-b (.. "string-entity:" b.id))
      (local identity (identity-store:create-entity {:target-key key-a}))
      (local identity-key (.. "identity:" identity.id))
      (local entity (store:create-entity {:name "x"
                                          :items [identity-key]}))
      (local graph (Graph {:with-start false
                           :identity-store identity-store}))
      (local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
      (register-string-loader graph {:store string-store})
      (graph:load-by-key key-a)
      (graph:load-by-key key-b)
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local list-node (ListEntityNode {:entity-id entity.id
                                        :store store
                                        :identity-store identity-store}))
      (graph:add-node list-node {})
      (assert (= (graph:edge-count) 1) "list should have one item edge")
      (assert (= (. graph.edges 1 :target :key) key-a) "initial edge should point to original target")
      (identity-store:update-entity identity.id {:target-key key-b})
      (assert (= (graph:edge-count) 1) "list should keep one item edge after identity target change")
      (assert (= (. graph.edges 1 :target :key) key-b) "edge should retarget to updated identity target")
      (graph:drop))))

(fn list-entity-node-refreshes-identity-item-edges-when-target-node-added-late []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local {:GraphNode GraphNode} (require :graph/node-base))
      (local IdentityStore (require :entities/identity))
      (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path root "identity")}))
      (local target-key "manual-target:late")
      (local identity (identity-store:create-entity {:target-key "manual-target:old"}))
      (local identity-key (.. "identity:" identity.id))
      (local entity (store:create-entity {:name "x"
                                          :items [identity-key]}))
      (local graph (Graph {:with-start false
                           :identity-store identity-store}))
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local list-node (ListEntityNode {:entity-id entity.id
                                        :store store
                                        :identity-store identity-store}))
      (graph:add-node list-node {})
      (identity-store:update-entity identity.id {:target-key target-key})
      (assert (= (graph:edge-count) 0)
              "edge should not exist until target node is present")
      (graph:add-node (GraphNode {:key target-key
                                  :label "late target"})
                      {})
      (assert (= (graph:edge-count) 1)
              "identity-backed list edge should appear when target node is added")
      (assert (= (. graph.edges 1 :target :key) target-key)
              "late-added target should become list edge target")
      (graph:drop))))

(fn list-entity-node-emits-items-changed-on-node-morphed-for-identity-item []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local IdentityStore (require :entities/identity))
      (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path root "identity")}))
      (local identity (identity-store:create-entity {:target-key "string-entity:s1"}))
      (local identity-key (.. "identity:" identity.id))
      (local entity (store:create-entity {:name "x"
                                          :items [identity-key]}))
      (local graph (Graph {:with-start false
                           :identity-store identity-store}))
      (local {:ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (local list-node (ListEntityNode {:entity-id entity.id
                                        :store store
                                        :identity-store identity-store}))
      (graph:add-node list-node {})
      (var refresh-count 0)
      (list-node.items-changed:connect (fn [_] (set refresh-count (+ refresh-count 1))))
      (graph.node-morphed:emit {:source-key "string-entity:s1"
                                :target-key "code-entity:c1"
                                :payload {:result {:updated-identity-keys [identity-key]}}})
      (assert (= refresh-count 1)
              "node-morphed should trigger list items refresh for affected identity item")
      (graph:drop))))

(fn list-entity-list-node-loads []
  (local ListEntityListNode (require :graph/nodes/list-entity-list))
  (assert ListEntityListNode "ListEntityListNode should load")
  (assert (= (type ListEntityListNode) "function") "ListEntityListNode should be a function"))

(fn list-entity-list-node-creates-with-correct-properties []
  (local ListEntityListNode (require :graph/nodes/list-entity-list))
  (local node (ListEntityListNode {}))
  (assert (= node.key "list-entity-list") "key should be 'list-entity-list'")
  (assert (= node.label "list entities") "label should be 'list entities'")
  (assert node.color "should have color")
  (assert node.items-changed "should have items-changed signal")
  (assert node.collect-items "should have collect-items method")
  (assert node.emit-items "should have emit-items method")
  (assert node.add-entity-node "should have add-entity-node method")
  (assert node.create-entity "should have create-entity method"))

(fn list-entity-node-view-loads []
  (local ListEntityNodeView (require :graph/view/views/list-entity))
  (assert ListEntityNodeView "ListEntityNodeView should load")
  (assert (= (type ListEntityNodeView) "function") "ListEntityNodeView should be a function"))

(fn list-entity-list-node-view-loads []
  (local ListEntityListNodeView (require :graph/view/views/list-entity-list))
  (assert ListEntityListNodeView "ListEntityListNodeView should load")
  (assert (= (type ListEntityListNodeView) "function") "ListEntityListNodeView should be a function"))

(fn entities-node-includes-list-type []
  (local EntitiesNode (require :graph/nodes/entities))
  (local node (EntitiesNode {}))
  (local types (node:collect-types))
  (var found false)
  (each [_ t (ipairs types)]
    (when (= (. t 1) :list)
      (set found true)))
  (assert found "entities node should include list type"))

(table.insert tests {:name "list entity store creates entities"
                     :fn list-entity-store-creates-entities})
(table.insert tests {:name "list entity store retrieves entities"
                     :fn list-entity-store-retrieves-entities})
(table.insert tests {:name "list entity store updates entities"
                     :fn list-entity-store-updates-entities})
(table.insert tests {:name "list entity store deletes entities"
                     :fn list-entity-store-deletes-entities})
(table.insert tests {:name "list entity store lists entities sorted"
                     :fn list-entity-store-lists-entities-sorted})
(table.insert tests {:name "list entity store emits created signal"
                     :fn list-entity-store-emits-created-signal})
(table.insert tests {:name "list entity store emits updated signal"
                     :fn list-entity-store-emits-updated-signal})
(table.insert tests {:name "list entity store emits deleted signal"
                     :fn list-entity-store-emits-deleted-signal})
(table.insert tests {:name "list entity store adds items and prevents duplicates"
                     :fn list-entity-store-adds-items-and-prevents-duplicates})
(table.insert tests {:name "list entity store removes items"
                     :fn list-entity-store-removes-items})
(table.insert tests {:name "list entity store moves items"
                     :fn list-entity-store-moves-items})
(table.insert tests {:name "list entity store emits items-changed signal"
                     :fn list-entity-store-emits-items-changed-signal})
(table.insert tests {:name "list entity node loads"
                     :fn list-entity-node-loads})
(table.insert tests {:name "list entity node creates with correct properties"
                      :fn list-entity-node-creates-with-correct-properties})
(table.insert tests {:name "list entity node sets compact-label for named list"
                     :fn list-entity-node-sets-compact-label-for-named-list})
(table.insert tests {:name "list entity node opts out compact-label for unnamed list"
                     :fn list-entity-node-opts-out-compact-label-for-unnamed-list})
(table.insert tests {:name "list entity node refreshes compact-label and emits changed"
                     :fn list-entity-node-refreshes-compact-label-and-emits-changed})
(table.insert tests {:name "list entity node adds item edges after added"
                      :fn list-entity-node-adds-item-edges-after-added})
(table.insert tests {:name "list entity node add-item wraps non-identity key and dedupes"
                     :fn list-entity-node-add-item-wraps-non-identity-key-and-dedupes})
(table.insert tests {:name "list entity node removes direct item when node disappears"
                     :fn list-entity-node-removes-direct-item-when-node-disappears})
(table.insert tests {:name "list entity node refreshes identity item edges on target change"
                     :fn list-entity-node-refreshes-identity-item-edges-on-target-change})
(table.insert tests {:name "list entity node refreshes identity item edges when target node added late"
                     :fn list-entity-node-refreshes-identity-item-edges-when-target-node-added-late})
(table.insert tests {:name "list entity node emits items-changed on node-morphed for identity item"
                     :fn list-entity-node-emits-items-changed-on-node-morphed-for-identity-item})
(table.insert tests {:name "list entity list node loads"
                     :fn list-entity-list-node-loads})
(table.insert tests {:name "list entity list node creates with correct properties"
                     :fn list-entity-list-node-creates-with-correct-properties})
(table.insert tests {:name "list entity node view loads"
                     :fn list-entity-node-view-loads})
(table.insert tests {:name "list entity list node view loads"
                     :fn list-entity-list-node-view-loads})
(table.insert tests {:name "entities node includes list type"
                      :fn entities-node-includes-list-type})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "list-entities"
                       :tests tests})))

{:name "list-entities"
 :tests tests
 :main main}
