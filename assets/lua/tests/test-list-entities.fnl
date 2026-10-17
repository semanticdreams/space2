(local fs (require :fs))
(local H (require :tests/test-reference-lifecycle-helpers))
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
      (H.assert-reference store.identity-store (. entity.items 1) "node-a")
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
      (local deleted (store:retire-entity! entity.id))
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
      (store:retire-entity! entity.id)
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
      (H.assert-reference store.identity-store (. retrieved.items 1) "a")
      (H.assert-reference store.identity-store (. retrieved.items 2) "c"))))

(fn list-entity-store-moves-items []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "x" :items ["a" "b" "c"]}))
      (store:move-item entity.id 1 3)
      (local retrieved (store:get-entity entity.id))
      (H.assert-reference store.identity-store (. retrieved.items 1) "b")
      (H.assert-reference store.identity-store (. retrieved.items 2) "c")
      (H.assert-reference store.identity-store (. retrieved.items 3) "a"))))

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
      (local identity-store store.identity-store)
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

(fn list-entity-node-preserves-item-when-node-disappears []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local IdentityStore (require :entities/identity))
      (local StringEntityStore (require :entities/string))
      (local identity-store store.identity-store)
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
      (local initial (assert (store:get-entity entity.id)))
      (assert (= (# initial.items) 1) "list should start with stable key item")
      (local before (. (store:snapshot-entity entity.id) :bytes))
      (graph:remove-nodes [source-node])
      (local current (store:get-entity entity.id))
      (assert (= (# current.items) 1)
              "exposure removal must preserve owning list membership")
      (assert (= (. (store:snapshot-entity entity.id) :bytes) before))
      (graph:drop))))

(fn list-entity-node-refreshes-identity-item-edges-on-target-change []
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
      (local identity-store store.identity-store)
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
      (local identity-store store.identity-store)
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
  (local {:EntityTypeCatalog EntityTypeCatalog} (require :entities/type-catalog))
  (local Builtins (require :graph/extensions/builtins))
  (local node (EntitiesNode {:entity-type-catalog (EntityTypeCatalog {:types (Builtins.entity-types)})}))
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
(table.insert tests {:name "list entity node preserves item when node disappears"
                      :fn list-entity-node-preserves-item-when-node-disappears})
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

(local JsonUtils (require :json-utils))
(local json (require :json))
(local canonical-items ["identity:z" "identity:a" "identity:c"])

(fn own-list-resource [unit group resource first?]
  (local drop (assert resource.drop "unit fixture resource requires drop"))
  (local entry {:resource resource :closed? false})
  (if first? (table.insert (. unit group) 1 entry) (table.insert (. unit group) entry))
  (tset unit.records resource entry)
  (set resource.drop (fn [self] (set entry.closed? true) (drop self)))
  resource)

(fn drop-list-resources [groups]
  (var failure nil)
  (each [_ entries (ipairs groups)]
    (for [i (# entries) 1 -1]
      (local entry (. entries i))
      (when (not entry.closed?)
        (local (ok result) (pcall entry.resource.drop entry.resource))
        (when (and (not ok) (not failure)) (set failure result)))))
  (when failure (error failure 0)))

(fn init-list-unit [unit]
  (set unit.focus (own-list-resource unit :ui ((. (require :focus) :FocusManager) {:root-name "list-presentation"})))
  (set unit.camera (own-list-resource unit :ui ((require :camera) {:position ((. (require :glm) :vec3) 0 0 100)})))
  (set unit.icons (own-list-resource unit :ui ((require :icons))))
  (set unit.renderer (own-list-resource unit :ui ((require :renderers)))))

(fn draw-list-target [f target]
  (target:update 0)
  (assert (> (# (target:get-text-ssbo-draw-list)) 0) "unit draw requires actual native text buffers")
  ;; Production renderer pipeline; the unit runner owns its existing GL backend.
  (f.screen.renderer:draw-target target))

(fn same-presentation-value [actual expected]
  (assert (= (JsonUtils.stable-json actual) (JsonUtils.stable-json expected))
          (.. "expected " (JsonUtils.stable-json expected) ", got " (JsonUtils.stable-json actual))))

(fn reset-list-observation [f]
  (set f.writes 0) (set f.updated 0) (set f.changed 0) (set f.created 0)
  (set f.calls []))

(fn assert-list-membership [f expected]
  (assert (= f.entity (f.store:get-entity "list")) "held owning record must survive")
  (same-presentation-value f.entity.items expected)
  (same-presentation-value (. (json.loads (fs.read-file f.path)) :items) expected))

(fn assert-list-passive [f before]
  (same-presentation-value [f.writes f.updated f.changed f.created] [0 0 0 0])
  (same-presentation-value (H.snapshot-tree f.root) before)
  (assert (= f.entity (f.store:get-entity "list")) "passive reads must retain held record")
  (same-presentation-value f.entity (json.loads (fs.read-file f.path)))
  (each [id held (pairs f.store.identity-store.cache)]
    (same-presentation-value held (. (f.store.identity-store:snapshot-entity id) :value))))

(fn list-row-button [f row column]
  (local count (# f.view.list.items))
  (assert (and (> row 0) (<= row count)) "expected a current visible row")
  (assert (. f.buttons (+ (- (# f.buttons) (* 4 count)) (* (- row 1) 4) column))
          "expected actual row Button"))

(fn click-list-row [f row column]
  (local button (list-row-button f row column))
  (button:on-click {}))

(fn assert-list-text [widget expected]
  (same-presentation-value (widget:get-codepoints)
                           ((. (require :text-utils) :codepoints-from-text) expected)))

(fn assert-list-rows [f keys texts]
  (assert (= (# f.view.list.items) (# keys)) "positive/current row count")
  (each [i key (ipairs keys)]
    (same-presentation-value (. f.view.list.items i)
                             {:key key :text (. texts i) :index i :total (# keys)})
    (assert-list-text (. (list-row-button f i 1) :text)
                      ((. (require :graph/view/utils) :truncate-with-ellipsis) (. texts i) 28)))
  (assert-list-text f.view.items-label (.. "Items (" (# keys) "):")))

(fn open-list-presentation [f]
  (local View (require :graph/view/views/list-entity))
  (local glm (require :glm))
  (local start (# f.buttons))
  (fn builder [ctx]
    (set f.view ((View f.node) ctx))
    f.view)
  (local target (own-list-resource f.screen :targets ((require :canvas)
    {:camera f.screen.camera :focus-manager f.screen.focus :icons f.screen.icons :states app.states})))
  (target:on-viewport-changed {:width f.screen.width :height f.screen.height})
  (target:add-panel-child {:builder builder :position (glm.vec3 0) :size (glm.vec3 80 45 0)})
  (table.insert f.targets target)
  (set f.add-button (. f.buttons (+ start 1)))
  f.view)

(fn drop-list-presentation [f]
  (drop-list-resources [f.screen.targets f.screen.domain]))

(fn observe-list-methods [f]
  (local observed {})
  (each [_ method (ipairs [:update-entity :add-item :remove-item :move-item])]
    (local original (. f.store method))
    (fn operation [store id ...]
      (table.insert f.calls {:method method :id id :args (json.loads (JsonUtils.stable-json [...]))})
      (original store id ...))
    (tset observed method operation))
  observed)

(fn observe-list-presentation [f body]
  (local original-write JsonUtils.write-json!)
  (local clickables (assert app.clickables "list presentation requires native clickables"))
  (local original-register clickables.register)
  (fn write [path value]
    (when (= (string.sub path 1 (# f.root)) f.root) (set f.writes (+ f.writes 1)))
    (original-write path value))
  (fn register [self widget]
    (when widget.clicked (table.insert f.buttons widget))
    (original-register self widget))
  (fn created [_] (set f.created (+ f.created 1)))
  (fn updated [_] (set f.updated (+ f.updated 1)))
  (fn changed [_] (set f.changed (+ f.changed 1)))
  (local subscriptions [[f.store.identity-store.identity-created created]
                        [f.store.list-entity-updated updated]
                        [f.store.list-entity-items-changed changed]])
  (each [_ pair (ipairs subscriptions)]
    (local signal (. pair 1))
    (signal:connect (. pair 2)))
  (fn run [] (body f))
  (fn with-register [] (H.with-fields clickables {:register register} run))
  (fn with-write [] (H.with-fields JsonUtils {:write-json! write} with-register))
  (local (ok result) (pcall H.with-fields f.store (observe-list-methods f) with-write))
  (each [_ pair (ipairs subscriptions)]
    (local signal (. pair 1))
    (signal:disconnect (. pair 2) true))
  (local (drop-ok drop-error) (pcall drop-list-presentation f))
  (if (not ok) (error result) (not drop-ok) (error drop-error) result))

(fn run-list-presentation [store root screen body]
  (local ids store.identity-store)
  (ids:create-entity {:id "z" :target-key "node-key-alpha"})
  (ids:create-entity {:id "a" :target-key "node-key-alpha"})
  (ids:create-entity {:id "c" :target-key "node-key-beta"})
  (local entity (store:create-entity {:id "list" :name "Presentation List"
    :items ["identity:z" "identity:a" "identity:z" "node-key-alpha" "identity:c"]}))
  (local node (own-list-resource screen :domain
    ((. (require :graph/nodes/list-entity) :ListEntityNode) {:entity-id "list" :store store}) true))
  (observe-list-presentation {:store store :root root :screen screen :entity entity :node node
    :path (fs.join-path store.entities-dir "list.json") :targets [] :buttons []
    :calls [] :writes 0 :updated 0 :changed 0 :created 0} body))

(fn with-list-presentation [body]
  (assert (and app app.engine (app.engine:is-started) (not (app.engine:is-shutdown)))
          "List unit fixture requires initialized caller context")
  (fn stored [store root]
    (local unit {:width 640 :height 360 :ui [] :targets [] :domain [] :records {}})
    (fn run [] (init-list-unit unit) (run-list-presentation store root unit body))
    (local (ok result) (pcall run))
    (local (clean-ok clean-error) (pcall drop-list-resources [unit.targets unit.domain unit.ui]))
    (if (not ok) (error result) (not clean-ok) (error clean-error) result))
  (with-temp-store stored))

(fn list-presentation-passive [f]
  (local before (H.snapshot-tree f.root))
  (open-list-presentation f)
  (open-list-presentation f)
  (f.view:refresh-items)
  (each [_ target (ipairs f.targets)]
    (draw-list-target f target))
  (assert-list-rows f canonical-items ["node-key-alpha" "node-key-alpha" "node-key-beta"])
  (assert-list-membership f canonical-items)
  (assert-list-passive f before)
  (each [_ target (ipairs f.targets)] (target:drop))
  (set f.targets [])
  (local buttons-after-drop (# f.buttons))
  (f.node.items-changed:emit {})
  (assert (= (# f.buttons) buttons-after-drop) "dropped views must disconnect refresh handlers")
  (assert-list-passive f before)
  ;; Different generated IDs and a long terminal must not leak identity/truncate keys.
  (local terminal "terminal:abcdefghijklmnopqrstuvwxyz-0123456789")
  (local one (f.store.identity-store:create-entity {:target-key terminal}))
  (local two (f.store.identity-store:create-entity {:target-key terminal}))
  (local keys [(.. "identity:" one.id) (.. "identity:" two.id)])
  (f.store:update-entity "list" {:items keys})
  (reset-list-observation f)
  (local fresh (H.snapshot-tree f.root))
  (open-list-presentation f)
  (f.view:refresh-items)
  (assert-list-rows f keys [terminal terminal])
  (assert-list-passive f fresh))

(fn list-presentation-duplicates [f]
  (assert-list-membership f canonical-items)
  (local before (H.snapshot-tree f.root))
  (open-list-presentation f)
  (assert-list-rows f canonical-items ["node-key-alpha" "node-key-alpha" "node-key-beta"])
  (f.view:refresh-items)
  (assert-list-membership f canonical-items)
  (assert-list-passive f before))

(fn list-presentation-move [f]
  (open-list-presentation f)
  (reset-list-observation f)
  (click-list-row f 1 2)
  (click-list-row f 3 3)
  (same-presentation-value f.calls [])
  (click-list-row f 1 3)
  (assert-list-membership f ["identity:a" "identity:z" "identity:c"])
  (assert (= (. f.view.list.items 2 :key) "identity:z") "subscription must rebuild current rows")
  (click-list-row f 2 2)
  (assert-list-membership f canonical-items)
  (same-presentation-value f.calls [{:method :move-item :id "list" :args [1 2]}
                                  {:method :move-item :id "list" :args [2 1]}])
  (same-presentation-value [f.writes f.updated f.changed f.created] [2 2 2 0]))

(fn list-presentation-remove [f]
  (open-list-presentation f)
  (click-list-row f 1 3)
  (reset-list-observation f)
  (click-list-row f 1 4)
  (assert-list-membership f ["identity:z" "identity:c"])
  (same-presentation-value f.calls [{:method :remove-item :id "list" :args ["identity:a"]}])
  (same-presentation-value [f.writes f.updated f.changed f.created] [1 1 1 0]))

(fn list-presentation-selection [f]
  (open-list-presentation f)
  (click-list-row f 2 4)
  (reset-list-observation f)
  (fn select []
    (f.add-button:on-click {})
    (set app.graph-view.selection.selected-nodes [])
    (f.add-button:on-click {}))
  (H.with-fields app {:graph-view {:selection {:selected-nodes
    [{:key "identity:a"} {:key "identity:z"} {:key "node-key-alpha"}]}}} select)
  (assert-list-membership f ["identity:z" "identity:c" "identity:a"])
  (same-presentation-value f.calls [{:method :add-item :id "list" :args ["identity:a"]}
    {:method :add-item :id "list" :args ["identity:z"]}
    {:method :add-item :id "list" :args ["node-key-alpha"]}])
  (same-presentation-value [f.writes f.updated f.changed f.created] [1 1 1 0]))

(fn list-focus-actions [f graph alias manager focus]
  (local lookups []) (local reasons [])
  (local lookup graph.lookup) (local request focus.request-focus)
  (fn observed-lookup [self key] (table.insert lookups key) (lookup self key))
  (fn observed-focus [self opts] (table.insert reasons opts.reason) (request self opts))
  (fn forbidden [...] (error "list focus must not resolve/load/open"))
  (local mapping {}) (tset mapping alias focus)
  (fn click []
    (click-list-row f 1 1)
    (assert (= (manager:get-focused-node) focus) "existing canonical alias must receive real focus")
    (tset mapping alias nil)
    (click-list-row f 1 1)
    (click-list-row f 2 1))
  (fn with-focus [] (H.with-fields focus {:request-focus observed-focus} click))
  (fn with-graph [] (H.with-fields graph {:lookup observed-lookup :load-by-key forbidden
    :resolve-node forbidden :add-node forbidden} with-focus))
  (H.with-fields app {:graph-map graph :graph-view {:focus-nodes mapping}} with-graph)
  (same-presentation-value lookups ["identity:z" "identity:z" "identity:a"])
  (same-presentation-value reasons [:list-entity])
  (assert (= (graph:node-count) 1) "focus must not expose terminal nodes"))

(fn list-presentation-focus [f]
  (open-list-presentation f)
  (local graph ((require :graph/core) {:with-start false :identity-store f.store.identity-store}))
  (local alias ((. (require :graph/nodes/identity) :IdentityNode)
    {:entity-id "z" :store f.store.identity-store}))
  (graph:add-node alias {})
  (local manager ((. (require :focus) :FocusManager) {:root-name "list-presentation"}))
  (local focus (manager:create-node {:name "canonical-alias"}))
  (manager:attach focus (manager:get-root-scope))
  (reset-list-observation f)
  (local before (H.snapshot-tree f.root))
  (local (ok err) (pcall list-focus-actions f graph alias manager focus))
  (manager:drop) (graph:drop)
  (when (not ok) (error err))
  (assert-list-membership f canonical-items)
  (assert-list-passive f before))

(fn list-presentation-name [f]
  (open-list-presentation f)
  (local before (json.loads (fs.read-file f.path)))
  (reset-list-observation f)
  (f.view.name-input:set-text "Renamed")
  (same-presentation-value f.calls [{:method :update-entity :id "list" :args [{:name "Renamed"}]}])
  (assert-list-membership f canonical-items)
  (set before.name "Renamed") (set before.updated-at f.entity.updated-at)
  (same-presentation-value f.entity before)
  (same-presentation-value [f.writes f.updated f.changed f.created] [1 1 0 0]))

(fn list-legacy-items [f items]
  ;; Real historical record input; production decoding/persistence is not replaced.
  (local record (json.loads (fs.read-file f.path)))
  (set record.items items)
  (JsonUtils.write-json! f.path record)
  (tset f.store.cache "list" nil)
  (set f.entity (f.store:get-entity "list"))
  (reset-list-observation f))

(fn assert-list-refresh-error [f fragment refresh]
  (local before (H.snapshot-tree f.root))
  (local rows f.view.list.items)
  (local count (JsonUtils.stable-json (f.view.items-label:get-codepoints)))
  (H.assert-error fragment refresh)
  (assert (= f.view.list.items rows) "failed resolution must not publish partial rows")
  (assert (= (JsonUtils.stable-json (f.view.items-label:get-codepoints)) count)
          "failed resolution must not publish new count")
  (assert-list-passive f before))

(fn list-open-handlers [signal]
  (var callbacks nil)
  (for [i 1 20]
    (local (name value) (debug.getupvalue signal.emit i))
    (when (= name "callbacks") (set callbacks value)))
  (assert callbacks "native Signal callbacks must be inspectable")
  (accumulate [n 0 _ record (ipairs callbacks)] (+ n (if record.active? 1 0))))

(fn list-open-baseline [f]
  (assert (and app.clickables app.hoverables) "initial List baseline requires caller interactions")
  [(# app.clickables.left-click-objects) (# app.clickables.right-click-objects)
   (# app.clickables.double-click-objects) (# app.hoverables.objects)
   (list-open-handlers f.node.items-changed)
   (list-open-handlers f.screen.focus.focus-focus) (list-open-handlers f.screen.focus.focus-blur)])

(fn assert-failed-list-open [f fragment attempt]
  (local before (list-open-baseline f)) (local bytes (H.snapshot-tree f.root))
  (H.assert-error fragment attempt)
  (same-presentation-value (list-open-baseline f) before)
  (local target (. f.screen.targets (# f.screen.targets) :resource))
  (assert (= (# (target:get-text-ssbo-draw-list)) 0) "failed initial List must release native text")
  (assert (= (# (target:get-quad-draw-list)) 0) "failed initial List must release native quads")
  (assert-list-passive f bytes))

(fn assert-list-resolution-failure [f items fragment]
  (list-legacy-items f items)
  (fn refresh [] (f.view:refresh-items))
  (assert-list-refresh-error f fragment refresh)
  (fn opening [] (open-list-presentation f))
  (assert-failed-list-open f fragment opening))

(fn list-presentation-errors [f]
  (local ids f.store.identity-store)
  (ids:create-entity {:id "empty" :target-key ""})
  (ids:create-entity {:id "chain" :target-key "identity:z"})
  (list-legacy-items f [])
  (open-list-presentation f)
  (assert-list-rows f [] [])
  (local keys ["legacy:raw" "identity:missing" "identity:empty" "identity:chain"])
  (list-legacy-items f keys)
  (local before (H.snapshot-tree f.root))
  (f.view:refresh-items)
  (assert-list-rows f keys ["legacy:raw" "identity:missing" "identity:empty" "node-key-alpha"])
  (assert-list-membership f keys)
  (assert-list-passive f before)
  (fn refresh-without-owner [] (f.view:refresh-items))
  (fn missing-owner [] (H.assert-error "owning IdentityStore" refresh-without-owner))
  (H.with-fields f.store {:identity-store false} missing-owner)
  (assert-list-passive f before)
  (ids:create-entity {:id "self" :target-key "identity:self"})
  (ids:create-entity {:id "one" :target-key "identity:two"})
  (ids:create-entity {:id "two" :target-key "identity:one"})
  (for [i 1 34]
    (ids:create-entity {:id (.. "depth-" i) :target-key (.. "identity:depth-" (+ i 1))}))
  (ids:create-entity {:id "depth-35" :target-key "node-key-alpha"})
  (assert-list-resolution-failure f ["identity:z" "identity:self"] "cycle detected")
  (assert-list-resolution-failure f ["identity:one"] "cycle detected")
  (assert-list-resolution-failure f ["identity:depth-1"] "depth exhausted")
  (fn ownerless-open [] (H.with-fields f.store {:identity-store false}
    (fn opening [] (open-list-presentation f))))
  (assert-failed-list-open f "owning IdentityStore" ownerless-open)
  (ids:create-entity {:id "unreadable" :target-key "node-key-alpha"})
  (tset ids.cache "unreadable" nil)
  (list-legacy-items f ["identity:z" "identity:unreadable"])
  (fn refresh [] (f.view:refresh-items))
  (fn failed-read []
    (H.with-fs-failure :read-file (fs.join-path ids.entities-dir "unreadable.json") refresh))
  (assert-list-refresh-error f "injected permission denied" failed-read)
  (fn failed-open [] (H.with-fs-failure :read-file (fs.join-path ids.entities-dir "unreadable.json")
    (fn opening [] (open-list-presentation f))))
  (assert-failed-list-open f "injected permission denied" failed-open)
  (list-legacy-items f canonical-items)
  (f.node:update-name "After failed List open")
  (local count (# f.buttons)) (f.node.items-changed:emit {})
  (assert (= (- (# f.buttons) count) 12) "only the surviving List view may rebuild three rows")
  (assert-list-rows f canonical-items ["node-key-alpha" "node-key-alpha" "node-key-beta"])
  (same-presentation-value [f.writes f.updated f.changed f.created] [1 1 0 0]))

(fn add-list-presentation-test [suffix body]
  (fn run [] (with-list-presentation body))
  (table.insert tests {:name (.. "list item presentation " suffix) :fn run}))

(add-list-presentation-test "passive display preserves canonical aliases" list-presentation-passive)
(add-list-presentation-test "duplicate semantics retain distinct aliases" list-presentation-duplicates)
(add-list-presentation-test "move callbacks preserve exact order after refresh" list-presentation-move)
(add-list-presentation-test "remove targets canonical alias only" list-presentation-remove)
(add-list-presentation-test "selection authoring preserves explicit references" list-presentation-selection)
(add-list-presentation-test "focus uses canonical existing key without opening/loading" list-presentation-focus)
(add-list-presentation-test "name-only edit preserves membership" list-presentation-name)
(add-list-presentation-test "unresolved and resolver errors do not author" list-presentation-errors)

(fn assert-list-fixture-lifetime [run expected]
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
  (fn received [payload] (assert (= payload.token "List caller")) (set delivered (+ delivered 1)))
  (local id (engine.callbacks.register received))
  (fn observed [] (H.with-fields engine {:start start-engine :shutdown stop-engine} run))
  (local (ok result) (pcall H.with-fields module {:Engine construct} observed))
  (assert (= constructed 0) "List fixture must borrow caller Engine, never construct another")
  (assert (and (= started 0) (= stopped 0)) "List fixture must not start/shut down caller Engine")
  (assert (= app caller)) (assert (= app.engine engine))
  (each [key value (pairs fields)] (assert (= (. caller key) value)))
  (each [key value (pairs caller)] (assert (= (. fields key) value)))
  (assert (and (engine:is-started) (not (engine:is-shutdown))))
  (assert (= (type (engine:now-ms)) :number))
  (assert (= _G.__space_state_system_runtime.states-provider provider))
  (assert (= (runtime.maybe-states-host) host))
  (assert (= (input-state.active-input) active-input))
  (assert (= package.preload.jobs preload)) (assert (= (preload) engine.jobs))
  (engine.callbacks.enqueue id {:token "List caller"}) (engine.callbacks.dispatch)
  (assert (= delivered 1)) (assert (engine.callbacks.unregister id))
  (if expected (assert (and (not ok) (= result expected)) "original List error object must survive cleanup")
      (assert ok (tostring result))))

(fn list-lifetime-scenario [callback-error? cleanup-error?]
  (local callback-error {}) (local cleanup-error {}) (local drops {})
  (var fixture nil)
  (fn body [f]
    (set fixture f) (open-list-presentation f)
    (local target (. f.targets 1)) (local drop target.drop)
    (set target.drop (fn [self]
      (tset drops :target (+ (or drops.target 0) 1)) (drop self)
      (when cleanup-error? (error cleanup-error 0))))
    (local input f.view.name-input)
    (input:request-focus) (assert input.focused?) (input:enter-insert-mode)
    (input:on-text-input {:text "typed"})
    (local move f.store.move-item)
    (fn operation [self ...]
      (local result (move self ...))
      (when callback-error? (error callback-error 0)) result)
    (fn click [] (click-list-row f 1 3))
    (H.with-fields f.store {:move-item operation} click))
  (fn run [] (with-list-presentation body))
  (assert-list-fixture-lifetime run (if callback-error? callback-error cleanup-error? cleanup-error nil))
  (assert (= drops.target 1)) (assert (not (fs.exists fixture.root)))
  (each [_ entries (ipairs [fixture.screen.targets fixture.screen.domain fixture.screen.ui])]
    (each [_ entry (ipairs entries)] (assert entry.closed? "all acquired unit resources must be released")))
  (local target (. fixture.targets 1))
  (assert (= (# (target:get-text-ssbo-draw-list)) 0))
  (local count (# fixture.buttons)) (fixture.node.items-changed:emit {})
  (assert (= (# fixture.buttons) count)))

(fn list-lifetime-constructor-failure []
  (local Io (require :io-utils)) (local read Io.read-file) (local failure {})
  (local Focus (require :focus)) (local constructor Focus.FocusManager)
  (var drops 0) (var called? false)
  (fn focus [opts]
    (local manager (constructor opts)) (local drop manager.drop)
    (set manager.drop (fn [self] (set drops (+ drops 1)) (drop self))) manager)
  (fn failed-read [path]
    (if (string.find path ".codepoints" 1 true) (error failure 0) (read path)))
  (fn body [_f] (set called? true))
  (fn run [] (with-list-presentation body))
  (fn reading [] (H.with-fields Io {:read-file failed-read} run))
  (fn observed [] (H.with-fields Focus {:FocusManager focus} reading))
  (assert-list-fixture-lifetime observed failure)
  (assert (not called?)) (assert (= drops 1) "partially acquired FocusManager must be dropped"))

(fn list-lifetime-normal []
  (list-lifetime-scenario false false)
  (list-lifetime-constructor-failure)
  (list-lifetime-scenario false true))
(fn list-lifetime-exception []
  (list-lifetime-scenario true false)
  (list-lifetime-scenario true true))
(table.insert tests {:name "presentation fixture lifetime List normal return" :fn list-lifetime-normal})
(table.insert tests {:name "presentation fixture lifetime List callback exception" :fn list-lifetime-exception})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "list-entities"
                       :tests tests})))

{:name "list-entities"
 :tests tests
 :main main}
