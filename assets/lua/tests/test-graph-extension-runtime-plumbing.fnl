(local Main (require :main))
(local Graph (require :graph/init))
(local GraphMapManager (require :graph/map-manager))
(local GraphExtensionRegistry (require :graph/extension-registry))

(local tests [])

(fn with-restored-app-registry [f]
  (local saved-registry app.graph-extension-registry)
  (set app.graph-extension-registry nil)
  (local (ok result) (pcall f))
  (set app.graph-extension-registry saved-registry)
  (if ok result (error result)))

(fn main-ensures-graph-extension-registry []
  (with-restored-app-registry
    (fn []
      (local registry (Main.ensure-graph-extension-registry!))
      (assert registry "Main.ensure-graph-extension-registry! should return registry")
      (assert (= app.graph-extension-registry registry)
              "Main.ensure-graph-extension-registry! should store registry on app")
      (local state (registry:debug-state))
      (assert (= state.runtime-count 0)
              "app graph extension registry should start with no installed runtimes")
      true)))

(fn registry-installed-runtime-debug-state-is-visible []
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {:app app}))
  (local graph (Graph {:with-start false}))
  (local manager (GraphMapManager.GraphMapManager {:graph graph}))
  (local runtime {:graph graph :graph-map-manager manager})
  (local (ok result)
    (pcall
      (fn []
        (local initial-state (registry:debug-state))
        (assert (= initial-state.runtime-count 0)
                "registry should start with no runtimes")
        (registry:install-runtime runtime)
        (local installed-state (registry:debug-state))
        (assert (= installed-state.runtime-count 1)
                "install-runtime should increment debug runtime-count")
        (registry:uninstall-runtime runtime)
        (local uninstalled-state (registry:debug-state))
        (assert (= uninstalled-state.runtime-count 0)
                "uninstall-runtime should decrement debug runtime-count")
        true)))
  (manager:drop)
  (graph:drop)
  (if ok result (error result)))

(table.insert tests {:name "main-ensures-graph-extension-registry"
                     :fn main-ensures-graph-extension-registry})
(table.insert tests {:name "registry-installed-runtime-debug-state-is-visible"
                     :fn registry-installed-runtime-debug-state-is-visible})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-extension-runtime-plumbing"
                       :tests tests})))

{:name "graph-extension-runtime-plumbing"
 :tests tests
 :main main}
