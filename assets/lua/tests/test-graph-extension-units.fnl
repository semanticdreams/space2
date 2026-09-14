(local fs (require :fs))
(local tempfile (require :tempfile))
(local Graph (require :graph/init))
(local GraphMapManager (require :graph/map-manager))
(local GraphExtensionRegistry (require :graph/extension-registry))
(local Morphs (require :morphs/init))
(local Units (require :units))
(local UnitManager (require :unit-manager))
(local HotReload (require :hot-reload))

(local tests [])
(var fallback-now-ms 10000)

(fn fallback-engine-now-ms [_self]
  (set fallback-now-ms (+ fallback-now-ms 250))
  fallback-now-ms)

(fn count-root-reload [_ctx]
  (when (= app.__graph_extension_unit_root_reload_count nil)
    (set app.__graph_extension_unit_root_reload_count 0))
  (set app.__graph_extension_unit_root_reload_count
       (+ app.__graph_extension_unit_root_reload_count 1)))

(fn noop-unload [_ctx]
  true)

(fn make-temp-dir []
  (tempfile.TemporaryDirectory {:prefix "graph-extension-units-test-"}))

(fn demo-unit-source [version]
  (local v (tostring version))
  (.. "(local Graph (require :graph/init))\n"
      "(local KeyLoaderUtils (require :graph/key-loader-utils))\n"
      "(var extension-handle nil)\n"
      "(fn require-build-ctx [ctx name]\n"
      "  (assert ctx (.. name \" requires build context\"))\n"
      "  ctx)\n"
      "(fn demo-preview [node opts]\n"
      "  (local options (or opts {}))\n"
      "  (local target (or node options.node))\n"
      "  (fn build [ctx]\n"
      "    (require-build-ctx ctx \"demo-preview\")\n"
      "    {:layout-name (.. \"preview-" v "-\" target.demo-id)\n"
      "     :node-key target.key}))\n"
      "(fn demo-view [node opts]\n"
      "  (local options (or opts {}))\n"
      "  (local target (or node options.node))\n"
      "  (fn build [ctx]\n"
      "    (require-build-ctx ctx \"demo-view\")\n"
      "    {:layout-name (.. \"view-" v "-\" target.demo-id)\n"
      "     :node-key target.key}))\n"
      "(fn make-node [key]\n"
      "  (local id (KeyLoaderUtils.extract-id \"demo-node\" key))\n"
      "  (when id\n"
      "    (local node (Graph.GraphNode {:key key\n"
      "                                  :label (.. \"Demo " v " \" id)\n"
      "                                  :preview demo-preview\n"
      "                                  :view demo-view}))\n"
      "    (set node.demo-id id)\n"
      "    (set node.demo-version \"" v "\")\n"
      "    node))\n"
      "(fn demo-morph [ctx]\n"
      "  (local source (assert ctx.source-node \"demo morph requires source node\"))\n"
      "  {:key (.. source.key \"-morphed-" v "\")})\n"
      "(fn init []\n"
      "  (assert app.graph-extension-registry \"demo extension requires app.graph-extension-registry\")\n"
      "  (set extension-handle\n"
      "       (app.graph-extension-registry:register-extension\n"
      "         {:id \"demo-extension\"\n"
      "          :unit-id \"user-demo-extension\"\n"
      "          :schemes [\"demo-node\"]\n"
      "          :install-loaders\n"
      "          (fn [graph ctx]\n"
      "            [(graph:register-key-loader \"demo-node\" make-node\n"
      "                                        {:owner-id ctx.owner-id\n"
      "                                         :extension-id ctx.extension-id})])\n"
      "          :install-morphs\n"
      "          (fn [morphs ctx]\n"
      "            [(morphs:register \"demo-node\" \"demo-node\" demo-morph\n"
      "                              {:label \"Demo self morph\"}\n"
      "                              {:owner-id ctx.owner-id\n"
      "                               :extension-id ctx.extension-id})])}))\n"
      "  true)\n"
      "(fn drop []\n"
      "  (when extension-handle\n"
      "    (extension-handle:unregister)\n"
      "    (set extension-handle nil))\n"
      "  true)\n"
      "{:init init :drop drop}\n"))

(fn write-demo-unit! [root version]
  (local unit-dir (fs.join-path root "demo_extension"))
  (fs.create-dirs unit-dir)
  (local init-path (fs.join-path unit-dir "init.fnl"))
  (fs.write-file init-path (demo-unit-source version))
  init-path)

(fn make-runtime []
  (local graph (Graph {:with-start false :morphs (Morphs.Morphs {})}))
  (local graph-map-manager (GraphMapManager.GraphMapManager {:graph graph}))
  {:graph graph
   :graph-map-manager graph-map-manager
   :drop (fn [self]
           (self.graph-map-manager:drop)
           (self.graph:drop))})

(fn make-demo-unit [root init-path]
  (Units.ModuleUnit {:id "user-demo-extension"
                     :module-name "demo_extension"
                     :module-paths (.. root "/?.fnl;" root "/?/init.fnl")
                     :source :user
                     :owned-paths [(fs.parent init-path)]
                     :suppress-run-main? false}))

(fn build-layout-name [builder node]
  (local build (builder node))
  (local built (build {:test-build-context true}))
  built.layout-name)

(fn assert-demo-node-version [node version id context]
  (assert (= node.label (.. "Demo " version " " id))
          (.. context " should have v" version " label"))
  (assert (= (build-layout-name node.preview node) (.. "preview-" version "-" id))
          (.. context " should have v" version " preview"))
  (assert (= (build-layout-name node.view node) (.. "view-" version "-" id))
          (.. context " should have v" version " view")))

(fn setup-demo-runtime! [root]
  (local saved-registry app.graph-extension-registry)
  (local saved-manager app.unit-manager)
  (local saved-root-count app.__graph_extension_unit_root_reload_count)
  (local runtime (make-runtime))
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {:app app}))
  (local manager (UnitManager {}))
  (set app.graph-extension-registry registry)
  (set app.unit-manager manager)
  (registry:install-runtime runtime)
  (local init-path (write-demo-unit! root "v1"))
  (local unit (make-demo-unit root init-path))
  (manager:register unit)
  (unit:load {})
  {:runtime runtime
   :registry registry
   :manager manager
   :unit unit
   :init-path init-path
   :drop (fn [self]
           (self.manager:clear)
           (self.registry:uninstall-runtime self.runtime)
           (self.runtime:drop)
           (set app.graph-extension-registry saved-registry)
           (set app.unit-manager saved-manager)
           (set app.__graph_extension_unit_root_reload_count saved-root-count)
           true)})

(fn assert-reload-refresh-results [graph graph-map node-a node-b root-reload-count]
  (local refreshed-a (graph-map:lookup "demo-node:a"))
  (local refreshed-b (graph-map:lookup "demo-node:b"))
  (assert (not (= refreshed-a node-a)) "reload should replace visible node a adapter")
  (assert (not (= refreshed-b node-b)) "reload should replace visible node b adapter")
  (assert-demo-node-version refreshed-a "v2" "a" "node a after reload")
  (assert-demo-node-version refreshed-b "v2" "b" "node b after reload")
  (assert (= root-reload-count 0) "unit reload must not reload app root")
  (assert (= (. (. graph-map.edges 1) :source) refreshed-a) "edge source should point at refreshed adapter")
  (assert (= (. (. graph-map.edges 1) :target) refreshed-b) "edge target should point at refreshed adapter")
  (assert (= (. graph-map.selected_node_keys 1) "demo-node:a") "selection key should survive refresh")
  (assert (= graph-map.focused_node_key "demo-node:b") "focus key should survive refresh")
  refreshed-a)

(fn assert-v2-morph-and-unload-cleanup [ctx graph]
  (local targets (graph.morphs:target-items {:key "demo-node:a"}))
  (assert (= (length targets) 1) "reload should install exactly one self morph")
  (assert (= (. (. (. targets 1) 1) :to-scheme) "demo-node") "morph target should remain demo-node")
  (local morph-result (graph.morphs:apply {:key "demo-node:a"} {:to-scheme "demo-node"} {}))
  (assert (= morph-result.key "demo-node:a-morphed-v2") "morph should use v2 target key")
  (local morphed-node (graph:create-node-by-key morph-result.key))
  (assert morphed-node "morphed v2 target should load")
  (assert-demo-node-version morphed-node "v2" "a-morphed-v2" "morphed node")
  (ctx.manager:unregister "user-demo-extension")
  (assert (= (graph:create-node-by-key "demo-node:c") nil) "unload should remove demo loader")
  (assert (= (length (graph.morphs:target-items {:key "demo-node:b"})) 0)
          "unload should remove demo morph"))

(fn run-unit-reload-vertical-assertions [ctx]
  (set app.__graph_extension_unit_root_reload_count 0)
  (local root-unit (Units.Unit {:id "app-root"
                                :load count-root-reload
                                :unload noop-unload}))
  (ctx.manager:register root-unit)
  (local graph ctx.runtime.graph)
  (local graph-map (ctx.runtime.graph-map-manager:get-active-map))
  (local node-a (graph-map:load-by-key "demo-node:a"))
  (local node-b (graph-map:load-by-key "demo-node:b"))
  (graph-map:add-edge (Graph.GraphEdge {:source node-a :target node-b :label "a -> b"}))
  (set graph-map.selected_node_keys ["demo-node:a"])
  (set graph-map.focused_node_key "demo-node:b")
  (assert-demo-node-version node-a "v1" "a" "node a before reload")
  (assert-demo-node-version node-b "v1" "b" "node b before reload")
  (fs.write-file ctx.init-path (demo-unit-source "v2"))
  (ctx.manager:reload-unit "user-demo-extension" {:source :test})
  (assert-reload-refresh-results graph graph-map node-a node-b app.__graph_extension_unit_root_reload_count)
  (assert-v2-morph-and-unload-cleanup ctx graph))

(fn perform-hot-controller-reload-and-assert [state]
  (fs.write-file state.ctx.init-path (demo-unit-source "v2"))
  (assert (state.controller:reload-now! {:changes [{:path state.ctx.init-path :action "modified"}]})
          "hot reload should succeed")
  (local refreshed-a (state.graph-map:lookup "demo-node:a"))
  (assert (not (= refreshed-a state.node-a)) "hot reload should replace visible adapter")
  (assert-demo-node-version refreshed-a "v2" "a" "node after hot reload")
  (assert (= app.__graph_extension_unit_root_reload_count 0)
          "hot reload should not reconstruct root graph runtime")
  true)

(fn run-hot-reload-refresh-assertions [root ctx]
  (local saved-engine app.engine)
  (set fallback-now-ms 10000)
  (when (not app.engine)
    (set app.engine {:now-ms fallback-engine-now-ms}))
  (local graph-map (ctx.runtime.graph-map-manager:get-active-map))
  (local node-a (graph-map:load-by-key "demo-node:a"))
  (assert-demo-node-version node-a "v1" "a" "node before hot reload")
  (set app.__graph_extension_unit_root_reload_count 0)
  (local root-unit (Units.Unit {:id "app-root"
                                :owned-paths [root]
                                :load count-root-reload
                                :unload noop-unload}))
  (local controller
    (HotReload.HotReloadController
      {:unit root-unit
       :units [ctx.unit]
       :root-unit-id "app-root"
       :watch-paths [root]
       :preserve-modules ["hot-reload" "units" "tests.test-graph-extension-units"]
       :debounce-ms 0
       :startup-ignore-ms 0
       :generic? true}))
  (local (ok result)
    (pcall perform-hot-controller-reload-and-assert
           {:ctx ctx :controller controller :graph-map graph-map :node-a node-a}))
  (controller:drop)
  (set app.engine saved-engine)
  (if ok result (error result)))

(fn reloadable-demo-graph-extension-unit-refreshes-visible-node-without-root-reload []
  (local handle (make-temp-dir))
  (local ctx (setup-demo-runtime! handle.path))
  (local (ok result) (pcall run-unit-reload-vertical-assertions ctx))
  (ctx:drop)
  (handle:drop)
  (if ok result (error result)))

(fn hot-reload-controller-refreshes-demo-extension-unit []
  (local handle (make-temp-dir))
  (local ctx (setup-demo-runtime! handle.path))
  (local (ok result) (pcall run-hot-reload-refresh-assertions handle.path ctx))
  (ctx:drop)
  (handle:drop)
  (if ok result (error result)))

(table.insert tests {:name "reloadable-demo-graph-extension-unit-refreshes-visible-node-without-root-reload"
                     :fn reloadable-demo-graph-extension-unit-refreshes-visible-node-without-root-reload})
(table.insert tests {:name "hot-reload-controller-refreshes-demo-extension-unit"
                     :fn hot-reload-controller-refreshes-demo-extension-unit})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-extension-units"
                       :tests tests})))

{:name "graph-extension-units"
 :tests tests
 :main main}
