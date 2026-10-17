(local fs (require :fs))
(local BuildContext (require :build-context))
(local Signal (require :signal))
(local H (require :tests/test-reference-lifecycle-helpers))
(local tests [])
(var temp-counter 0)
(var observed-updated-count 0)
(var observed-items-count 0)
(var observed-deleted-count 0)
(local temp-root (fs.join-path "/tmp/space/tests" "dict-entities"))

(fn make-icons-stub []
  {:resolve (fn [_self _name]
              nil)})

(fn make-ctx []
  (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                 :hoverables (assert app.hoverables "test requires app.hoverables")
                 :icons (make-icons-stub)}))

(fn count-updated [_]
  (set observed-updated-count (+ observed-updated-count 1)))

(fn count-items [_]
  (set observed-items-count (+ observed-items-count 1)))

(fn count-deleted [_]
  (set observed-deleted-count (+ observed-deleted-count 1)))

(fn fail-remove [_path]
  (error "forced remove failure"))

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
      (local DictEntityStore (require :entities/dict))
      (local store (DictEntityStore.DictEntityStore {:base-dir root}))
      (f store root))))

(fn dict-entity-store-creates-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "Alice profile"
                                          :items {"name" "string-entity:name"
                                                  "manager" "identity:bob"}}))
      (assert entity "entity should be created")
      (assert entity.id "entity should have id")
      (assert (= entity.name "Alice profile") "entity should keep name")
      (H.assert-reference store.identity-store (. entity.items "name") "string-entity:name")
      (assert (= (. entity.items "manager") "identity:bob") "items should store graph keys")
      (assert (= (length entity.items) 0) "dict items must not be stored as an array")
      (assert entity.created-at "entity should have created-at")
      (assert entity.updated-at "entity should have updated-at"))))

(fn dict-entity-store-persists-and-reloads-json []
  (with-temp-store
    (fn [store root]
      (local entity (store:create-entity {:id "profile"
                                          :name "Profile"
                                          :items {"role" "string-entity:role"}}))
      (local DictEntityStore (require :entities/dict))
      (local reloaded-store (DictEntityStore.DictEntityStore {:base-dir root}))
      (local reloaded (reloaded-store:get-entity entity.id))
      (assert reloaded "reloaded entity should exist")
      (assert (= reloaded.id "profile") "id should persist")
      (assert (= reloaded.name "Profile") "name should persist")
      (H.assert-reference reloaded-store.identity-store (. reloaded.items "role") "string-entity:role"))))

(fn dict-entity-store-set-get-remove-rename-items []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "x"}))
      (store:set-item entity.id "name" "string-entity:a")
      (H.assert-reference store.identity-store (store:get-item entity.id "name") "string-entity:a")
      (store:rename-item entity.id "name" "display-name")
      (assert (= (store:get-item entity.id "name") nil) "rename should remove old key")
      (H.assert-reference store.identity-store (store:get-item entity.id "display-name") "string-entity:a")
      (store:remove-item entity.id "display-name")
      (assert (= (store:get-item entity.id "display-name") nil) "remove should delete item"))))

(fn dict-entity-store-rejects-invalid-item-mutations []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {}))
      (local (ok-empty-key err-empty-key) (pcall store.set-item store entity.id "" "node-a"))
      (assert (not ok-empty-key) "empty item key should error")
      (assert (string.find (tostring err-empty-key) "item key" 1 true) "empty key error should mention item key")
      (local (ok-empty-value err-empty-value) (pcall store.set-item store entity.id "k" ""))
      (assert (not ok-empty-value) "empty item value should error")
      (assert (string.find (tostring err-empty-value) "item value" 1 true) "empty value error should mention item value")
      (store:set-item entity.id "a" "node-a")
      (store:set-item entity.id "b" "node-b")
      (local (ok-collision err-collision) (pcall store.rename-item store entity.id "a" "b"))
      (assert (not ok-collision) "rename collision should error")
      (assert (string.find (tostring err-collision) "already exists" 1 true) "collision error should mention existing key"))))

(fn dict-entity-store-skips-unchanged-item-signals []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:items {"role" "string-entity:role"}}))
      (set observed-updated-count 0)
      (set observed-items-count 0)
      (store.dict-entity-updated:connect count-updated)
      (store.dict-entity-items-changed:connect count-items)
      (store:set-item entity.id "role" "string-entity:role")
      (store:remove-item entity.id "missing")
      (store:rename-item entity.id "role" "role")
      (assert (= observed-updated-count 0) "unchanged item operations should not emit updated")
      (assert (= observed-items-count 0) "unchanged item operations should not emit items-changed")
      (store.dict-entity-updated:clear)
      (store.dict-entity-items-changed:clear))))

(fn dict-entity-store-surfaces-delete-remove-failure []
  (with-temp-store
    (fn [store root]
      (local entity (store:create-entity {:id "delete-failure"
                                          :name "Delete failure"}))
      (local original-remove fs.remove)
      (set observed-deleted-count 0)
      (store.dict-entity-deleted:connect count-deleted)
      (set fs.remove fail-remove)
      (local (ok err) (pcall store.retire-entity! store entity.id))
      (set fs.remove original-remove)
      (store.dict-entity-deleted:clear)
      (assert (not ok) "delete should error when persistent removal fails")
      (assert (string.find (tostring err) "forced remove failure" 1 true) "delete error should surface remove failure")
      (assert (= observed-deleted-count 0) "failed delete should not emit deleted signal")
      (assert (store:get-entity entity.id) "failed delete should keep cached entity")
       (assert (fs.exists (fs.join-path root "entities" "dict" "delete-failure.json"))
               "failed delete should leave persisted json for retry"))))

(fn dict-entity-node-creates-with-correct-properties []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "Profile"}))
      (local {:DictEntityNode DictEntityNode} (require :graph/nodes/dict-entity))
      (local node (DictEntityNode {:entity-id entity.id :store store}))
      (assert (= node.key (.. "dict-entity:" entity.id)) "key should be prefixed entity id")
      (assert (= node.label "Profile") "named dict should label by name")
      (assert (= node.compact-label "Profile") "named dict should use compact label")
      (assert node.items-changed "should have items-changed signal")
      (assert node.changed "should have changed signal")
      (assert node.entity-deleted "should have entity-deleted signal")
      (assert node.get-entity "should expose get-entity")
      (assert node.update-name "should expose update-name")
      (assert node.get-item "should expose get-item")
      (assert node.set-item "should expose set-item")
      (assert node.remove-item "should expose remove-item")
      (assert node.rename-item "should expose rename-item")
      (assert node.delete-entity "should expose delete-entity")
      (assert (= (type node.view) "function") "dict entity node should expose view")
      (node:drop))))

(fn dict-entity-node-adds-edges-for-resolved-values []
  (with-temp-store
    (fn [store _root]
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false :identity-store store.identity-store}))
      (local a (Graph.GraphNode {:key "node-a"}))
      (local b (Graph.GraphNode {:key "node-b"}))
      (graph:add-node a {})
      (graph:add-node b {})
      (local entity (store:create-entity {:items {"first" "node-a"
                                                  "second" "node-b"
                                                  "missing" "node-missing"}}))
      (local {:DictEntityNode DictEntityNode} (require :graph/nodes/dict-entity))
      (local node (DictEntityNode {:entity-id entity.id :store store}))
      (graph:add-node node {})
      (assert (= (graph:edge-count) 2) "dict entity node should edge only resolved values")
      (H.assert-reference store.identity-store (. (store:get-entity entity.id) :items "missing")
                          "node-missing")
      (graph:drop))))

(fn dict-entity-node-set-item-wraps-non-identity-key []
  (with-temp-store
    (fn [store root]
      (local Graph (require :graph/init))
      (local IdentityStore (require :entities/identity))
      (local identity-store store.identity-store)
      (local entity (store:create-entity {:name "x"}))
      (local {:DictEntityNode DictEntityNode} (require :graph/nodes/dict-entity))
      (local graph (Graph {:with-start false :identity-store identity-store}))
      (local node (DictEntityNode {:entity-id entity.id
                                   :store store
                                   :identity-store identity-store}))
      (graph:add-node node {})
      (node:set-item "manager" "node-a")
      (local stored-key (. (store:get-entity entity.id) :items "manager"))
      (assert (= (string.sub stored-key 1 9) "identity:")
              "dict graph node should wrap non-identity values")
      (local identity-id (string.sub stored-key 10))
      (local identity-entity (identity-store:get-entity identity-id))
      (assert identity-entity "identity should be persisted")
      (assert (= identity-entity.target-key "node-a") "identity target should match source key")
      (graph:drop))))

(fn dict-entity-list-node-collects-items-with-counts []
  (with-temp-store
    (fn [store _root]
      (store:create-entity {:name "old" :updated-at 10 :items {"a" "node-a"}})
      (store:create-entity {:name "new" :updated-at 20 :items {"a" "node-a" "b" "node-b"}})
      (local DictEntityListNode (require :graph/nodes/dict-entity-list))
      (local node (DictEntityListNode {:store store}))
      (local items (node:collect-items))
      (assert (= (length items) 2) "should collect two dicts")
      (assert (string.find (. items 1 2) "2 items" 1 true) "newer label should include item count")
      (assert (= (type node.view) "function") "dict entity list node should expose view")
      (node:drop))))

(fn entities-node-includes-dict-type []
  (local EntitiesNode (require :graph/nodes/entities))
  (local {:EntityTypeCatalog EntityTypeCatalog} (require :entities/type-catalog))
  (local Builtins (require :graph/extensions/builtins))
  (local node (EntitiesNode {:entity-type-catalog (EntityTypeCatalog {:types (Builtins.entity-types)})}))
  (local types (node:collect-types))
  (var found false)
  (each [_ t (ipairs types)]
    (when (= (. t 1) :dict)
      (set found true)))
  (assert found "entities node should include dict type"))

(fn built-in-loaders-resolve-dict-entity-keys []
  (with-temp-store
    (fn [dict-store root]
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false :identity-store dict-store.identity-store}))
      (local IdentityStore (require :entities/identity))
      (local identity-store dict-store.identity-store)
      (local entity (dict-store:create-entity {:name "x"}))
      (local DictNodeModule (require :graph/nodes/dict-entity))
      (DictNodeModule.register-loader graph {:store dict-store :identity-store identity-store})
      (assert (graph:load-by-key (.. "dict-entity:" entity.id)) "dict entity key should load")
      (graph:drop))))

(fn dict-entity-node-view-loads []
  (local DictEntityNodeView (require :graph/view/views/dict-entity))
  (assert DictEntityNodeView "DictEntityNodeView should load")
  (assert (= (type DictEntityNodeView) "function") "DictEntityNodeView should be a function"))

(fn dict-entity-list-node-view-loads []
  (local DictEntityListNodeView (require :graph/view/views/dict-entity-list))
  (assert DictEntityListNodeView "DictEntityListNodeView should load")
  (assert (= (type DictEntityListNodeView) "function") "DictEntityListNodeView should be a function"))

(fn dict-entity-node-view-rejects-empty-save-value-before-rename []
  (local DictEntityNodeView (require :graph/view/views/dict-entity))
  (local state {:items {"old" "node-a"}})
  (local target {:items-changed (Signal)
                 :get-entity (fn [_self]
                               state)
                 :rename-item (fn [_self old-key new-key]
                                (set (. state.items new-key) (. state.items old-key))
                                (set (. state.items old-key) nil))
                 :set-item (fn [_self _key value]
                             (when (= value "")
                               (error "item value is required")))})
  (local view ((DictEntityNodeView target) (make-ctx)))
  (local row (. view.list.item-widgets 1))
  (local key-input (. (. row.children 1) :element))
  (local value-input (. (. row.children 3) :element))
  (local save-button (. (. row.children 4) :element))
  (key-input:set-text "new")
  (value-input:set-text "")
  (local (ok err) (pcall save-button.on-click save-button {:button 1}))
  (assert (not ok) "empty final value should reject the save")
  (assert (string.find (tostring err) "item value" 1 true) "save error should mention item value")
  (assert (= (. state.items "old") "node-a") "failed save should keep original item key")
  (assert (= (. state.items "new") nil) "failed save should not persist rename")
  (view:drop))

(fn dict-entity-list-node-view-preserves-emitted-order []
  (local DictEntityListNodeView (require :graph/view/views/dict-entity-list))
  (local emitted [[{:key "newest"} "zzz"]
                  [{:key "older"} "aaa"]])
  (local target {:items-changed (Signal)
                 :emit-items (fn [_self]
                               emitted)})
  (local view ((DictEntityListNodeView target) (make-ctx)))
  (assert (= (. (. view.search.list-view.items 1) 2) "zzz")
          "visible list should keep newest emitted item first")
  (assert (= (. (. view.search.list-view.items 2) 2) "aaa")
          "visible list should keep older emitted item second")
  (view:drop))

(table.insert tests {:name "dict entity store creates entities"
                     :fn dict-entity-store-creates-entities})
(table.insert tests {:name "dict entity store persists and reloads json"
                     :fn dict-entity-store-persists-and-reloads-json})
(table.insert tests {:name "dict entity store set get remove rename items"
                     :fn dict-entity-store-set-get-remove-rename-items})
(table.insert tests {:name "dict entity store rejects invalid item mutations"
                     :fn dict-entity-store-rejects-invalid-item-mutations})
(table.insert tests {:name "dict entity store skips unchanged item signals"
                     :fn dict-entity-store-skips-unchanged-item-signals})
(table.insert tests {:name "dict entity store surfaces delete remove failure"
                      :fn dict-entity-store-surfaces-delete-remove-failure})
(table.insert tests {:name "dict entity node creates with correct properties"
                     :fn dict-entity-node-creates-with-correct-properties})
(table.insert tests {:name "dict entity node adds edges for resolved values"
                     :fn dict-entity-node-adds-edges-for-resolved-values})
(table.insert tests {:name "dict entity node set item wraps non identity key"
                     :fn dict-entity-node-set-item-wraps-non-identity-key})
(table.insert tests {:name "dict entity list node collects items with counts"
                     :fn dict-entity-list-node-collects-items-with-counts})
(table.insert tests {:name "entities node includes dict type"
                     :fn entities-node-includes-dict-type})
(table.insert tests {:name "built in loaders resolve dict entity keys"
                      :fn built-in-loaders-resolve-dict-entity-keys})
(table.insert tests {:name "dict entity node view loads"
                     :fn dict-entity-node-view-loads})
(table.insert tests {:name "dict entity list node view loads"
                      :fn dict-entity-list-node-view-loads})
(table.insert tests {:name "dict entity node view rejects empty save value before rename"
                     :fn dict-entity-node-view-rejects-empty-save-value-before-rename})
(table.insert tests {:name "dict entity list node view preserves emitted order"
                     :fn dict-entity-list-node-view-preserves-emitted-order})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "dict-entities"
                       :tests tests})))

{:name "dict-entities"
 :tests tests
 :main main}
