(local fs (require :fs))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "code-entities"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "code-" (os.time) "-" temp-counter)))

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
      (local CodeEntityStore (require :entities/code))
      (local store (CodeEntityStore.CodeEntityStore {:base-dir root}))
      (f store root))))

(fn disconnect-signal-handlers [records]
  (each [_ record (ipairs records)]
    (record.signal:disconnect record.handler true)))

(fn exercise-code-entity-signals [store counts]
  (local entity (store:create-entity {:source ""}))
  (store:update-entity entity.id {:source "x"})
  (store:retire-entity! entity.id)
  (assert (= counts.created 1) "created signal should emit once")
  (assert (= counts.updated 1) "updated signal should emit once")
  (assert (= counts.deleted 1) "deleted signal should emit once"))

(fn code-entity-store-creates-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:source "(print :ok)"}))
      (assert entity "entity should be created")
      (assert entity.id "entity should have id")
      (assert (= entity.name "") "default name should be empty")
      (assert (= entity.language "fnl") "default language should be fnl")
      (assert (= entity.source "(print :ok)") "source should be stored")
      (assert (= entity.kernel 0) "default kernel should be id 0"))))

(fn code-entity-store-updates-entities []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:source ""}))
      (store:update-entity entity.id {:name "sample"
                                      :language "lua"
                                      :source "print('ok')"
                                      :kernel "python-default"})
      (local updated (store:get-entity entity.id))
      (assert (= updated.name "sample") "name should update")
      (assert (= updated.language "lua") "language should update")
      (assert (= updated.source "print('ok')") "source should update")
      (assert (= updated.kernel "python-default") "kernel should update"))))

(fn code-entity-store-emits-signals []
  (with-temp-store
    (fn [store _root]
      (local counts {:created 0 :updated 0 :deleted 0})
      (local created-handler (fn [_] (set counts.created (+ counts.created 1))))
      (local updated-handler (fn [_] (set counts.updated (+ counts.updated 1))))
      (local deleted-handler (fn [_] (set counts.deleted (+ counts.deleted 1))))
      (store.code-entity-created:connect created-handler)
      (store.code-entity-updated:connect updated-handler)
      (store.code-entity-deleted:connect deleted-handler)
      (local cleanup-records [{:signal store.code-entity-created :handler created-handler}
                              {:signal store.code-entity-updated :handler updated-handler}
                              {:signal store.code-entity-deleted :handler deleted-handler}])
      (local (ok result) (pcall exercise-code-entity-signals store counts))
      (local (cleanup-ok cleanup-result) (pcall disconnect-signal-handlers cleanup-records))
      (if (not ok)
          (error result)
          (not cleanup-ok)
          (error cleanup-result)))))

(fn code-entity-node-loads []
  (local {:CodeEntityNode CodeEntityNode} (require :graph/nodes/code-entity))
  (assert CodeEntityNode "CodeEntityNode should load")
  (assert (= (type CodeEntityNode) "function") "CodeEntityNode should be a function"))

(fn code-entity-node-creates-with-correct-properties []
  (with-temp-store
    (fn [store _root]
      (local entity (store:create-entity {:source "x"}))
      (local {:CodeEntityNode CodeEntityNode} (require :graph/nodes/code-entity))
      (local node (CodeEntityNode {:entity-id entity.id :store store}))
      (assert (= node.key (.. "code-entity:" entity.id)) "key should be prefixed entity id")
      (assert node.get-entity "node should expose get-entity")
      (assert node.update-name "node should expose update-name")
      (assert node.update-language "node should expose update-language")
      (assert node.update-source "node should expose update-source")
      (assert node.delete-entity "node should expose delete-entity")
      (node:drop))))

(fn code-entity-node-view-loads []
  (local CodeEntityNodeView (require :graph/view/views/code-entity))
  (assert CodeEntityNodeView "CodeEntityNodeView should load")
  (assert (= (type CodeEntityNodeView) "function") "CodeEntityNodeView should be a function"))

(table.insert tests {:name "code entity store creates entities"
                     :fn code-entity-store-creates-entities})
(table.insert tests {:name "code entity store updates entities"
                     :fn code-entity-store-updates-entities})
(table.insert tests {:name "code entity store emits signals"
                     :fn code-entity-store-emits-signals})
(table.insert tests {:name "code entity node loads"
                     :fn code-entity-node-loads})
(table.insert tests {:name "code entity node creates with correct properties"
                     :fn code-entity-node-creates-with-correct-properties})
(table.insert tests {:name "code entity node view loads"
                      :fn code-entity-node-view-loads})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "code-entities"
                       :tests tests})))

{:name "code-entities"
 :tests tests
 :main main}
