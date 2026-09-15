(local Main (require :main))
(local fs (require :fs))
(local Graph (require :graph/init))
(local GraphMapManager (require :graph/map-manager))
(local GraphExtensionRegistry (require :graph/extension-registry))
(local HomeWorld (require :home-world))
(local Focus (require :focus))
(local Signal (require :signal))
(local tempfile (require :tempfile))
(local JsonUtils (require :json-utils))

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

(fn demo-runtime-install-loaders [graph ctx]
  [(graph:register-key-loader
     "demo-node"
     (fn [key] (Graph.GraphNode {:key key :label "restored demo"}))
     {:owner-id ctx.owner-id :extension-id ctx.extension-id})])

(fn write-world-state-with-demo-map! [dir]
  (JsonUtils.write-json!
    (fs.join-path dir "world.json")
    {:graph {:active_map_id "main"
             :next_map_id 2
             :maps [{:id "main"
                     :name "Main"
                     :nodes ["demo-node:a" "demo-node:b"]
                     :edges [{:source "demo-node:a" :target "demo-node:b"}]
                     :selected_node_keys ["demo-node:a"]
                     :focused_node_key "demo-node:b"}]}}))

(fn write-world-state-with-invalid-active-map! [dir]
  (JsonUtils.write-json!
    (fs.join-path dir "world.json")
    {:graph {:active_map_id "missing-map"
             :next_map_id 2
             :maps [{:id "main"
                     :name "Main"
                     :nodes ["demo-node:a"]
                      :edges []}]}}))

(fn write-world-state-with-built-in-map! [dir]
  (JsonUtils.write-json!
    (fs.join-path dir "world.json")
    {:graph {:active_map_id "main"
             :next_map_id 2
             :maps [{:id "main"
                     :name "Main"
                     :nodes ["start" "worlds"]
                     :edges [{:source "start" :target "worlds"}]
                     :selected_node_keys ["worlds"]
                     :focused_node_key "start"}]}}))

(fn fake-world-manager []
  {:changed (Signal)
   :list-tabs (fn [_self]
                [{:id "world-a" :name "home" :active? true}])})

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

(fn existing-extensions-install-before-home-world-graph-map-restore []
  (local saved-registry app.graph-extension-registry)
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {:app app}))
  (local temp-dir (tempfile.TemporaryDirectory {:prefix "home-world-runtime-existing-extension-"}))
  (local focus-manager (Focus.FocusManager {:root-name "runtime-existing-extension"}))
  (local saved-create-default-projection app.create-default-projection)
  (local saved-next-frame app.next-frame)
  (set app.graph-extension-registry registry)
  (set app.create-default-projection (fn [_viewport] {}))
  (set app.next-frame (fn [callback] (callback)))
  (fs.create-dirs temp-dir.path)
  (write-world-state-with-demo-map! temp-dir.path)
  (registry:register-extension
    {:id "demo-extension"
     :unit-id "user-demo-extension"
     :schemes ["demo-node"]
     :install-loaders demo-runtime-install-loaders})
  (local world (HomeWorld {:id "world-a"
                          :name "home"
                          :type "home"
                          :dir temp-dir.path
                          :graph-world-manager {}
                          :asset-path-resolver identity-path}))
  (local ctx {:focus-manager focus-manager
              :focus-root (focus-manager:get-root-scope)})
  (local (ok result)
    (pcall activate-world! world ctx))
  (when ok
    (local graph-map (world.runtime.graph-map-manager:get-active-map))
    (assert (graph-map:lookup "demo-node:a")
            "HomeWorld should hydrate extension-owned node after startup restore")
    (assert (graph-map:lookup "demo-node:b")
            "HomeWorld should hydrate second extension-owned node after startup restore")
    (assert (= (graph-map:edge-count) 1)
            "HomeWorld should hydrate extension-owned edge after startup restore")
    (assert (= (. graph-map.selected_node_keys 1) "demo-node:a")
            "HomeWorld should preserve extension-owned selection key")
    (assert (= graph-map.focused_node_key "demo-node:b")
            "HomeWorld should preserve extension-owned focus key")
    (when world.runtime
      (when world.runtime.unload-canvas-runtime
        (world.runtime:unload-canvas-runtime))
      (registry:uninstall-runtime world.runtime)
      (world.runtime.graph-map-manager:drop)
      (world.runtime.graph:drop)
      (world.runtime.scene:drop)
      (set world.runtime nil)))
  (focus-manager:drop)
  (temp-dir:drop)
  (set app.create-default-projection saved-create-default-projection)
  (set app.next-frame saved-next-frame)
  (set app.graph-extension-registry saved-registry)
  (if ok result (error result)))

(fn built-in-graph-extensions-install-before-homeworld-map-restore []
  (local saved-registry app.graph-extension-registry)
  (local saved-handles app.builtin-graph-extension-handles)
  (assert (= (type Main.ensure-built-in-graph-extensions!) "function")
          "Main should expose ensure-built-in-graph-extensions!")
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {:app app}))
  (local temp-dir (tempfile.TemporaryDirectory {:prefix "home-world-runtime-builtin-extension-"}))
  (local focus-manager (Focus.FocusManager {:root-name "runtime-builtin-extension"}))
  (local saved-create-default-projection app.create-default-projection)
  (local saved-next-frame app.next-frame)
  (local world-manager (fake-world-manager))
  (set app.graph-extension-registry registry)
  (set app.builtin-graph-extension-handles nil)
  (set app.create-default-projection (fn [_viewport] {}))
  (set app.next-frame (fn [callback] (callback)))
  (fs.create-dirs temp-dir.path)
  (write-world-state-with-built-in-map! temp-dir.path)
  (Main.ensure-built-in-graph-extensions! {:world-manager world-manager
                                           :asset-path-resolver identity-path})
  (local world (HomeWorld {:id "world-a"
                          :name "home"
                          :type "home"
                          :dir temp-dir.path
                          :graph-world-manager world-manager
                          :asset-path-resolver identity-path}))
  (local ctx {:focus-manager focus-manager
              :focus-root (focus-manager:get-root-scope)})
  (local (ok result)
    (pcall activate-world! world ctx))
  (when ok
    (local graph-map (world.runtime.graph-map-manager:get-active-map))
    (assert (graph-map:lookup "start")
            "HomeWorld should hydrate built-in start node before pruning")
    (assert (graph-map:lookup "worlds")
            "HomeWorld should hydrate built-in worlds node before pruning")
    (assert (= (graph-map:edge-count) 1)
            "HomeWorld should preserve built-in edge restored through registry loaders")
    (assert (= (. graph-map.selected_node_keys 1) "worlds")
            "HomeWorld should preserve built-in selected key")
    (assert (= graph-map.focused_node_key "start")
            "HomeWorld should preserve built-in focused key")
    (when world.runtime
      (when world.runtime.unload-canvas-runtime
        (world.runtime:unload-canvas-runtime))
      (registry:uninstall-runtime world.runtime)
      (world.runtime.graph-map-manager:drop)
      (world.runtime.graph:drop)
      (world.runtime.scene:drop)
      (set world.runtime nil)))
  (focus-manager:drop)
  (temp-dir:drop)
  (set app.create-default-projection saved-create-default-projection)
  (set app.next-frame saved-next-frame)
  (set app.graph-extension-registry saved-registry)
  (set app.builtin-graph-extension-handles saved-handles)
  (if ok result (error result)))

(fn homeworld-requires-graph-extension-registry-before-map-restore []
  (local saved-registry app.graph-extension-registry)
  (local saved-create-default-projection app.create-default-projection)
  (local saved-next-frame app.next-frame)
  (local temp-dir (tempfile.TemporaryDirectory {:prefix "home-world-missing-registry-"}))
  (local focus-manager (Focus.FocusManager {:root-name "missing-registry"}))
  (set app.graph-extension-registry nil)
  (set app.create-default-projection (fn [_viewport] {}))
  (set app.next-frame (fn [callback] (callback)))
  (fs.create-dirs temp-dir.path)
  (write-world-state-with-built-in-map! temp-dir.path)
  (local world-manager (fake-world-manager))
  (local world (HomeWorld {:id "world-a"
                          :name "home"
                          :type "home"
                          :dir temp-dir.path
                          :graph-world-manager world-manager
                          :asset-path-resolver identity-path}))
  (local ctx {:focus-manager focus-manager
              :focus-root (focus-manager:get-root-scope)})
  (local (ok err) (pcall activate-world! world ctx))
  (focus-manager:drop)
  (temp-dir:drop)
  (set app.create-default-projection saved-create-default-projection)
  (set app.next-frame saved-next-frame)
  (set app.graph-extension-registry saved-registry)
  (assert (not ok) "HomeWorld should fail when graph extension registry is missing")
  (assert (string.find (tostring err) "HomeWorld requires app.graph-extension-registry" 1 true)
          (.. "missing registry error should be explicit, got: " (tostring err))))

(fn temporary-pre-restore-runtime-uninstalls-when-map-restore-fails []
  (local saved-registry app.graph-extension-registry)
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {:app app}))
  (local temp-dir (tempfile.TemporaryDirectory {:prefix "home-world-runtime-map-restore-failure-"}))
  (local focus-manager (Focus.FocusManager {:root-name "runtime-map-restore-failure"}))
  (local saved-create-default-projection app.create-default-projection)
  (local saved-next-frame app.next-frame)
  (set app.graph-extension-registry registry)
  (set app.create-default-projection (fn [_viewport] {}))
  (set app.next-frame (fn [callback] (callback)))
  (fs.create-dirs temp-dir.path)
  (write-world-state-with-invalid-active-map! temp-dir.path)
  (registry:register-extension
    {:id "demo-extension"
     :unit-id "user-demo-extension"
     :schemes ["demo-node"]
     :install-loaders demo-runtime-install-loaders})
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
  (focus-manager:drop)
  (temp-dir:drop)
  (set app.create-default-projection saved-create-default-projection)
  (set app.next-frame saved-next-frame)
  (set app.graph-extension-registry saved-registry)
  (assert (not ok) "invalid graph map state should fail HomeWorld activation")
  (assert (string.find (tostring err) "active_map_id does not reference a map" 1 true)
          (.. "map restore failure should surface GraphMapManager error, got: " (tostring err)))
  (assert (= registry-state.runtime-count 0)
          "failed map restore should uninstall temporary pre-restore runtime"))

(table.insert tests {:name "main-ensures-graph-extension-registry"
                     :fn main-ensures-graph-extension-registry})
(table.insert tests {:name "registry-installed-runtime-debug-state-is-visible"
                     :fn registry-installed-runtime-debug-state-is-visible})
(table.insert tests {:name "failing-runtime-install-rolls-back-home-world-resources"
                      :fn failing-runtime-install-rolls-back-home-world-resources})
(table.insert tests {:name "existing-extensions-install-before-home-world-graph-map-restore"
                       :fn existing-extensions-install-before-home-world-graph-map-restore})
(table.insert tests {:name "built-in-graph-extensions-install-before-homeworld-map-restore"
                     :fn built-in-graph-extensions-install-before-homeworld-map-restore})
(table.insert tests {:name "homeworld-requires-graph-extension-registry-before-map-restore"
                     :fn homeworld-requires-graph-extension-registry-before-map-restore})
(table.insert tests {:name "temporary-pre-restore-runtime-uninstalls-when-map-restore-fails"
                     :fn temporary-pre-restore-runtime-uninstalls-when-map-restore-fails})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-extension-runtime-plumbing"
                       :tests tests})))

{:name "graph-extension-runtime-plumbing"
 :tests tests
 :main main}
