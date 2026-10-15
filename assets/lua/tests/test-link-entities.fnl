(local fs (require :fs))

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
  (store:delete-entity entity.id)
  (assert (= counts.deleted 1) "deleted signal should be emitted"))

(fn link-entity-store-creates-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:source-key "node-a"
                                          :target-key "node-b"}))
      (assert entity "entity should be created")
      (assert entity.id "entity should have id")
      (assert (= entity.source-key "node-a") "entity should have correct source-key")
      (assert (= entity.target-key "node-b") "entity should have correct target-key")
      (assert entity.created-at "entity should have created-at"))))

(fn link-entity-store-retrieves-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:source-key "node-a"
                                          :target-key "node-b"}))
      (local retrieved (store:get-entity entity.id))
      (assert retrieved "entity should be retrieved")
      (assert (= retrieved.id entity.id) "retrieved entity should have same id")
      (assert (= retrieved.source-key "node-a") "retrieved entity should have correct source-key")
      (assert (= retrieved.target-key "node-b") "retrieved entity should have correct target-key"))))

(fn link-entity-store-updates-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:source-key "node-a"
                                          :target-key "node-b"}))
      (local updated (store:update-entity entity.id {:source-key "node-c"}))
      (assert updated "entity should be updated")
      (assert (= updated.source-key "node-c") "source-key should be updated")
      (local retrieved (store:get-entity entity.id))
      (assert (= retrieved.source-key "node-c") "persisted source-key should be updated"))))

(fn link-entity-store-deletes-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:source-key "node-a"
                                          :target-key "node-b"}))
      (local deleted (store:delete-entity entity.id))
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

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "link-entities"
                       :tests tests})))

{:name "link-entities"
 :tests tests
 :main main}
