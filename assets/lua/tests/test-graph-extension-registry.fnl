(local Graph (require :graph/init))
(local GraphMapManager (require :graph/map-manager))
(local GraphExtensionRegistry (require :graph/extension-registry))
(local Morphs (require :morphs/init))

(local tests [])

(fn make-runtime []
  (local graph (Graph {:with-start false :morphs (Morphs.Morphs {})}))
  (local graph-map-manager (GraphMapManager.GraphMapManager {:graph graph}))
  {:graph graph
   :graph-map-manager graph-map-manager
   :drop (fn [self]
           (self.graph-map-manager:drop)
            (self.graph:drop))})

(fn make-demo-node-loader [version-ref]
  (fn [key]
    (Graph.GraphNode {:key key :label version-ref.value})))

(fn demo-morph [_morph-ctx]
  {:key "demo-target:a"})

(fn make-descriptor [version-ref opts]
  (local options (if opts opts {}))
  (var install-count 0)
  {:id (if options.id options.id "demo-extension")
   :unit-id (if options.unit-id options.unit-id "user-demo-extension")
   :schemes ["demo-node"]
   :install-loaders
   (fn [graph ctx]
     (set install-count (+ install-count 1))
     (when (and options.fail-on-install-count (= install-count options.fail-on-install-count))
       (error "intentional loader install failure"))
     [(graph:register-key-loader
        "demo-node"
        (make-demo-node-loader version-ref)
        {:owner-id ctx.owner-id :extension-id ctx.extension-id})])
   :install-morphs
   (fn [morphs ctx]
     [(morphs:register
         "demo-node"
         "demo-target"
         demo-morph
        {:label "Demo Target"}
        {:owner-id ctx.owner-id :extension-id ctx.extension-id})])})

(fn register-extension-that-fails-on-second-runtime [registry]
  (registry:register-extension
    (make-descriptor {:value "v1"} {:fail-on-install-count 2})))

(fn make-loader-that-throws-after-recording [version-ref]
  {:id "demo-extension"
   :unit-id "user-demo-extension"
   :schemes ["demo-node"]
   :install-loaders
   (fn [graph ctx]
     (local handle
       (graph:register-key-loader
         "demo-node"
         (make-demo-node-loader version-ref)
         {:owner-id ctx.owner-id :extension-id ctx.extension-id}))
      (ctx:record-handle handle)
      (error "intentional failure after loader registration"))})

(fn make-bare-handle-return-descriptor [version-ref]
  {:id "bare-handle-extension"
   :unit-id "user-bare-handle-extension"
   :schemes ["bare-node"]
   :install-loaders
   (fn [graph ctx]
     (graph:register-key-loader
       "bare-node"
       (make-demo-node-loader version-ref)
       {:owner-id ctx.owner-id :extension-id ctx.extension-id}))})

(fn extension-registry-installs-into-live-and-future-runtime []
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {}))
  (local runtime-a (make-runtime))
  (registry:install-runtime runtime-a)
  (registry:register-extension (make-descriptor {:value "v1"}))
  (local node-a (runtime-a.graph:create-node-by-key "demo-node:a"))
  (assert node-a "live runtime should load node after extension registration")
  (assert (= node-a.key "demo-node:a") "live runtime should load requested key")
  (local runtime-b (make-runtime))
  (registry:install-runtime runtime-b)
  (local node-b (runtime-b.graph:create-node-by-key "demo-node:a"))
  (assert node-b "future runtime should load node from existing extension")
  (assert (= node-b.key "demo-node:a") "future runtime should load requested key")
  (runtime-a:drop)
  (runtime-b:drop))

(fn extension-registry-unregister-cleans-loaders-and-morphs []
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {}))
  (local runtime (make-runtime))
  (registry:install-runtime runtime)
  (local handle (registry:register-extension (make-descriptor {:value "v1"})))
  (assert (runtime.graph:create-node-by-key "demo-node:c")
          "registered extension should install loader")
  (local before (runtime.graph.morphs:target-items {:key "demo-node:c"}))
  (assert (= (length before) 1) "registered extension should install morph")
  (assert (registry:unregister-extension handle)
          "unregistering extension handle should return true")
  (assert (= (runtime.graph:create-node-by-key "demo-node:c") nil)
          "unregistering extension should remove loader")
  (local after (runtime.graph.morphs:target-items {:key "demo-node:c"}))
  (assert (= (length after) 0) "unregistering extension should remove morph")
  (runtime:drop))

(fn extension-registry-rolls-back-partial-install []
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {}))
  (local runtime-a (make-runtime))
  (local runtime-b (make-runtime))
  (registry:install-runtime runtime-a)
  (registry:install-runtime runtime-b)
  (local (ok err) (pcall register-extension-that-fails-on-second-runtime registry))
  (assert (not ok) "failed install should rethrow installer error")
  (assert (string.find (tostring err) "intentional loader install failure" 1 true)
          "failed install should surface installer error")
  (assert (= (runtime-a.graph:create-node-by-key "demo-node:a") nil)
          "failed install should roll back loader from first runtime")
  (runtime-a:drop)
  (runtime-b:drop))

(fn extension-registry-rolls-back-same-installer-handle-before-throw []
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {}))
  (local runtime (make-runtime))
  (registry:install-runtime runtime)
  (local (ok _err)
    (pcall #(registry:register-extension
              (make-loader-that-throws-after-recording {:value "v1"}))))
  (assert (not ok) "installer throw should fail registration")
  (assert (= (runtime.graph:create-node-by-key "demo-node:a") nil)
          "same-installer failure should roll back the already registered loader")
  (runtime:drop))

(fn extension-registry-unregister-by-id-marks-handle-inactive []
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {}))
  (local runtime (make-runtime))
  (registry:install-runtime runtime)
  (local handle (registry:register-extension (make-descriptor {:value "v1"})))
  (assert (= handle.active? true) "registered extension handle should start active")
  (assert (registry:unregister-extension "demo-extension")
          "unregister by id should remove the extension")
  (assert (= handle.active? false)
          "unregister by id should mark the stored handle inactive")
  (assert (registry:unregister-extension handle)
           "re-unregistering original handle after id unregister should be idempotent")
  (runtime:drop))

(fn extension-registry-rejects-bare-handle-return-and-rolls-back []
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {}))
  (local runtime (make-runtime))
  (registry:install-runtime runtime)
  (local (ok err)
    (pcall #(registry:register-extension
              (make-bare-handle-return-descriptor {:value "v1"}))))
  (assert (not ok) "bare handle installer return should fail registration")
  (assert (string.find (tostring err) "must return a non-empty sequential table" 1 true)
          (.. "bare handle failure should explain sequential handle contract, got: " (tostring err)))
  (assert (= (runtime.graph:create-node-by-key "bare-node:a") nil)
          "rejected bare handle return should roll back registered loader")
  (runtime:drop))

(fn extension-registry-refreshes-visible-adapters-by-scheme []
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {}))
  (local runtime (make-runtime))
  (registry:install-runtime runtime)
  (local version {:value "v1"})
  (registry:register-extension (make-descriptor version))
  (local graph-map (runtime.graph-map-manager:get-active-map))
  (local node (graph-map:load-by-key "demo-node:a"))
  (assert (= node.label "v1") "initial visible adapter should use v1")
  (set version.value "v2")
  (local result (registry:refresh-extension "demo-extension"))
  (local refreshed (graph-map:lookup "demo-node:a"))
  (assert (= refreshed.label "v2") "refresh should rebuild visible adapter with v2")
  (assert (= refreshed.key "demo-node:a") "refresh should preserve key")
  (assert (= (length result) 1) "refresh should return one runtime result")
  (local runtime-result (. result 1))
  (local scheme-result (. runtime-result.results 1))
  (assert (= scheme-result.scheme "demo-node")
          "refresh result should include refreshed scheme")
  (runtime:drop))

(table.insert tests {:name "extension-registry-installs-into-live-and-future-runtime"
                     :fn extension-registry-installs-into-live-and-future-runtime})
(table.insert tests {:name "extension-registry-unregister-cleans-loaders-and-morphs"
                     :fn extension-registry-unregister-cleans-loaders-and-morphs})
(table.insert tests {:name "extension-registry-rolls-back-partial-install"
                     :fn extension-registry-rolls-back-partial-install})
(table.insert tests {:name "extension-registry-rolls-back-same-installer-handle-before-throw"
                     :fn extension-registry-rolls-back-same-installer-handle-before-throw})
(table.insert tests {:name "extension-registry-unregister-by-id-marks-handle-inactive"
                      :fn extension-registry-unregister-by-id-marks-handle-inactive})
(table.insert tests {:name "extension-registry-rejects-bare-handle-return-and-rolls-back"
                     :fn extension-registry-rejects-bare-handle-return-and-rolls-back})
(table.insert tests {:name "extension-registry-refreshes-visible-adapters-by-scheme"
                      :fn extension-registry-refreshes-visible-adapters-by-scheme})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-extension-registry"
                       :tests tests})))

{:name "graph-extension-registry"
 :tests tests
 :main main}
