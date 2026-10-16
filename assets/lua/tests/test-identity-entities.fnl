(local fs (require :fs))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "identity-entities"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "identity-" (os.time) "-" temp-counter)))

(fn with-temp-store [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result)
    (pcall
      (fn []
        (local IdentityStore (require :entities/identity))
        (local store (IdentityStore.IdentityStore {:base-dir dir}))
        (f store dir))))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn disconnect-signal-handlers [records]
  (each [_ record (ipairs records)]
    (record.signal:disconnect record.handler true)))

(fn exercise-identity-signals [store counts]
  (local entity (store:create-entity {:target-key "a"}))
  (store:update-entity entity.id {:target-key "b"})
  (store:retire-entity! entity.id)
  (assert (= counts.created 1) "created signal should emit once")
  (assert (= counts.updated 1) "updated signal should emit once")
  (assert (= counts.deleted 1) "deleted signal should emit once"))

(fn identity-store-creates-entities []
  (with-temp-store
    (fn [store _dir]
      (local entity (store:create-entity {:target-key "string-entity:a"}))
      (assert entity "entity should be created")
      (assert entity.id "entity should have id")
      (assert (= entity.target-key "string-entity:a") "entity should have target-key")
      (assert entity.created-at "entity should have created-at")
      (assert entity.updated-at "entity should have updated-at"))))

(fn identity-store-updates-target-key []
  (with-temp-store
    (fn [store _dir]
      (local entity (store:create-entity {:target-key "a"}))
      (store:update-entity entity.id {:target-key "b"})
      (local loaded (store:get-entity entity.id))
      (assert (= loaded.target-key "b") "target-key should be updated"))))

(fn identity-store-emits-signals []
  (with-temp-store
    (fn [store _dir]
      (local counts {:created 0 :updated 0 :deleted 0})
      (local created-handler (fn [_] (set counts.created (+ counts.created 1))))
      (local updated-handler (fn [_] (set counts.updated (+ counts.updated 1))))
      (local deleted-handler (fn [_] (set counts.deleted (+ counts.deleted 1))))
      (store.identity-created:connect created-handler)
      (store.identity-updated:connect updated-handler)
      (store.identity-deleted:connect deleted-handler)
      (local cleanup-records [{:signal store.identity-created :handler created-handler}
                              {:signal store.identity-updated :handler updated-handler}
                              {:signal store.identity-deleted :handler deleted-handler}])
      (local (ok result) (pcall exercise-identity-signals store counts))
      (local (cleanup-ok cleanup-result) (pcall disconnect-signal-handlers cleanup-records))
      (if (not ok)
          (error result)
          (not cleanup-ok)
          (error cleanup-result)))))

(fn identity-store-finds-entity-by-target-key []
  (with-temp-store
    (fn [store _dir]
      (store:create-entity {:target-key "node-a"})
      (store:create-entity {:target-key "node-b"})
      (local entity (store:find-by-target-key "node-b"))
      (assert entity "find-by-target-key should return an entity")
      (assert (= entity.target-key "node-b")
              "find-by-target-key should return entity with matching target key"))))

(table.insert tests {:name "identity store creates entities"
                     :fn identity-store-creates-entities})
(table.insert tests {:name "identity store updates target key"
                     :fn identity-store-updates-target-key})
(table.insert tests {:name "identity store emits signals"
                     :fn identity-store-emits-signals})
(table.insert tests {:name "identity store finds entity by target key"
                     :fn identity-store-finds-entity-by-target-key})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "identity-entities"
                       :tests tests})))

{:name "identity-entities"
 :tests tests
 :main main}
