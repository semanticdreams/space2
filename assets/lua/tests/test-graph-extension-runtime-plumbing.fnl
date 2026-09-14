(local Main (require :main))
(local Graph (require :graph/init))
(local GraphMapManager (require :graph/map-manager))
(local GraphExtensionRegistry (require :graph/extension-registry))
(local HomeWorld (require :home-world))
(local Focus (require :focus))
(local tempfile (require :tempfile))

(local tests [])
(var runtime-install-graph-drop-count 0)

(fn identity-path [path]
  path)

(fn activate-world! [world ctx]
  (world:activate ctx))

(fn failing-runtime-install-loaders [graph _ctx]
  (local original-drop graph.drop)
  (set graph.drop
       (fn [self]
         (set runtime-install-graph-drop-count (+ runtime-install-graph-drop-count 1))
         (original-drop self)))
  (error "intentional runtime install failure"))

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

(fn failing-runtime-install-rolls-back-home-world-resources []
  (local saved-registry app.graph-extension-registry)
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {:app app}))
  (local temp-dir (tempfile.TemporaryDirectory {:prefix "home-world-runtime-install-failure-"}))
  (local focus-manager (Focus.FocusManager {:root-name "runtime-install-failure"}))
  (local saved-create-default-projection app.create-default-projection)
  (set runtime-install-graph-drop-count 0)
  (set app.graph-extension-registry registry)
  (set app.create-default-projection (fn [_viewport] {}))
  (registry:register-extension
    {:id "failing-runtime-extension"
     :unit-id "user-failing-runtime-extension"
     :schemes ["failing-runtime"]
     :install-loaders failing-runtime-install-loaders})
  (local world (HomeWorld {:id "world-a"
                          :name "home"
                          :type "home"
                          :dir temp-dir.path
                          :graph-world-manager {}
                          :asset-path-resolver identity-path}))
  (local ctx {:focus-manager focus-manager
              :focus-root (focus-manager:get-root-scope)})
  (local (ok err)
    (pcall activate-world! world ctx))
  (local registry-state (registry:debug-state))
  (local root-children (length (or focus-manager.root.children [])))
  (focus-manager:drop)
  (temp-dir:drop)
  (set app.create-default-projection saved-create-default-projection)
  (set app.graph-extension-registry saved-registry)
  (assert (not ok) "HomeWorld activation should rethrow runtime install failure")
  (assert (string.find (tostring err) "intentional runtime install failure" 1 true)
          (.. "HomeWorld activation should surface extension install failure, got: " (tostring err)))
  (assert (= registry-state.runtime-count 0)
          "failed runtime install should not leave a registered runtime")
  (assert (= runtime-install-graph-drop-count 1)
          "failed runtime install should drop the partially constructed graph")
  (assert (= root-children 0)
          "failed runtime install should detach the scene focus scope")
  (assert (= world.runtime nil)
          "failed runtime install should not assign world.runtime"))

(table.insert tests {:name "main-ensures-graph-extension-registry"
                     :fn main-ensures-graph-extension-registry})
(table.insert tests {:name "registry-installed-runtime-debug-state-is-visible"
                     :fn registry-installed-runtime-debug-state-is-visible})
(table.insert tests {:name "failing-runtime-install-rolls-back-home-world-resources"
                     :fn failing-runtime-install-rolls-back-home-world-resources})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-extension-runtime-plumbing"
                       :tests tests})))

{:name "graph-extension-runtime-plumbing"
 :tests tests
 :main main}
