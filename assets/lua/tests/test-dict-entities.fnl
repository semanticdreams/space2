(local fs (require :fs))

(local tests [])
(var temp-counter 0)
(var observed-updated-count 0)
(var observed-items-count 0)
(local temp-root (fs.join-path "/tmp/space/tests" "dict-entities"))

(fn count-updated [_]
  (set observed-updated-count (+ observed-updated-count 1)))

(fn count-items [_]
  (set observed-items-count (+ observed-items-count 1)))

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
      (assert (= (. entity.items "name") "string-entity:name") "items should be keyed table")
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
      (assert (= (. reloaded.items "role") "string-entity:role") "dict item should persist"))))

(fn dict-entity-store-set-get-remove-rename-items []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:name "x"}))
      (store:set-item entity.id "name" "string-entity:a")
      (assert (= (store:get-item entity.id "name") "string-entity:a") "set-item should store value")
      (store:rename-item entity.id "name" "display-name")
      (assert (= (store:get-item entity.id "name") nil) "rename should remove old key")
      (assert (= (store:get-item entity.id "display-name") "string-entity:a") "rename should keep value")
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

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "dict-entities"
                       :tests tests})))

{:name "dict-entities"
 :tests tests
 :main main}
