(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local BuiltinGraphTestHelpers (require :tests/graph-builtin-extension-helpers))
(local GraphView (require :graph/view))
(local BuildContext (require :build-context))
(local ObjectSelector (require :object-selector))
(local GraphViewLayout (require :graph/view/layout))
(local GraphViewPersistence (require :graph/view/persistence))
(local GraphViewNodeViews (require :graph/view/node-views))
(local {: Layout : LayoutRoot} (require :layout))
(local {:FsNode FsNode} (require :graph/nodes/fs))
(local CodeDirNode (require :graph/nodes/code-dir))
(local FnlModuleNode (require :graph/nodes/fnl-module))
(local TextModuleNode (require :graph/nodes/text-module))
(local LlmConversationNode (require :graph/nodes/llm-conversation))
(local LlmConversationsNode (require :graph/nodes/llm-conversations))
(local LlmMessageNode (require :graph/nodes/llm-message))
(local LlmNode (require :graph/nodes/llm))
(local {:TableNode TableNode} (require :graph/nodes/table))
(local Movables (require :movables))
(local Intersectables (require :intersectables))
(local {:FocusManager FocusManager} (require :focus))
(local Signal (require :signal))
(local LightSystemModule (require :light-system))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local fs (require :fs))
(local PathUtils (require :tests.path-utils))
(local TestSupport (require :tests/test-support))
(local StateSystemBindings (require :state-system-bindings))
(local SkyboxState (require :skybox-state))
(local BackgroundState (require :background-state))

(local tests [])
(local appdirs (require :appdirs))
(local MathUtils (require :math-utils))
(local TextUtils (require :text-utils))
(local viewport-utils (require :viewport-utils))

(local {:ForceLayout ForceLayout :ForceLayoutSignal ForceLayoutSignal} (require :force-layout))
(fn assert-codepoints-eq [actual expected message]
    (assert (= (# actual) (# expected))
            (or message "codepoints length mismatch"))
    (for [i 1 (# expected)]
        (assert (= (. actual i) (. expected i))
                (or message "codepoints mismatch"))))

(local paths-eq PathUtils.paths-eq)

(fn ensure-command-hints-hud! [states]
    (local hud (and states states.get-hud (states:get-hud)))
    (when (and states states.set-hud-provider (not (and hud hud.command-hints)))
        (states:set-hud-provider
            (fn [_self]
                {:command-hints
                 {:handle-toggle-key (fn [_manager _payload] true)
                  :close-on-handled-event (fn [_manager _route-key _payload] false)}})))
    states)

(fn set-app-states! [states]
    (ensure-command-hints-hud! states)
    (StateSystemBindings.bind-states-host states)
    (set app.states states)
    states)

(fn find-fs-node-by-path [graph target-path]
    (var matched nil)
    (each [_ node (pairs (or graph.nodes {}))]
        (when (and (not matched)
                   node
                   node.path
                   (paths-eq node.path target-path))
            (set matched node)))
    matched)

(fn make-icons-stub []
    (local glyph {:advance 1})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {65533 glyph
                             4242 glyph}})
    (local stub {:font font
                 :codepoints {:refresh 4242
                              :table 4242
                              :code 4242
                              :edit 4242
                              :close 4242
                              :cancel 4242
                               :move_item 4242
                               :select 4242
                               :arrow_drop_down 4242
                                :open_in_full 4242
                                :open_in_new 4242 :content_copy 4242
                                :close_fullscreen 4242
                               :more_vert 4242
                               :terminal 4242
                              :settings 4242
                              :contrast 4242
                              :apps 4242
                              :wallet 4242
                              :volume_mute 4242
                              :volume_down 4242
                              :volume_up 4242
                              :volume_off 4242}})
    (set stub.get
         (fn [self name]
             (local value (. self.codepoints name))
             (assert value (.. "Missing icon " name))
             value))
  (set stub.resolve
       (fn [self name]
         (local code (self:get name))
         {:type :font
          :codepoint code
          :font self.font}))
  stub)

(local default-icons (make-icons-stub))

(fn make-ctx [opts]
    (local options (or opts {}))
    (local focus-manager (FocusManager {:root-name "test-graph"}))
    (local focus-scope (focus-manager:create-scope {:name "test-graph-view"}))
    (local layout-root (or options.layout-root (LayoutRoot {:log-dirt? false})))
    (local theme {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
                          :label-color (glm.vec4 1 1 1 1)
                          :label-target-pixels 13.0
                          :label-min-scale 4.0
                          :edge-color (glm.vec4 0.6 0.6 0.6 1)}
                  :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}})
    (local ctx (BuildContext {:layout-root layout-root
                              :clickables (or options.clickables
                                              (assert app.clickables "test requires app.clickables"))
                              :hoverables (assert app.hoverables "test requires app.hoverables")
                              :theme theme
                              :focus-manager focus-manager
                              :focus-scope focus-scope}))
    (set ctx.icons (or options.icons default-icons))
    ctx)

(fn register-graph-map-test-loaders [graph keys]
    (local seen {})
    (each [_ key (ipairs (or keys []))]
        (local key-str (tostring key))
        (local (colon-at _end) (string.find key-str ":" 1 true))
        (local scheme (if colon-at (string.sub key-str 1 (- colon-at 1)) key-str))
        (when (and (> (string.len scheme) 0)
                   (not (. seen scheme))
                   (not (graph:has-key-loader-for-key key-str)))
            (set (. seen scheme) true)
            (graph:register-key-loader scheme
                (fn [loaded-key]
                    (Graph.GraphNode {:key loaded-key})))))
    graph)

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "graph-fs-node-tmp"))

(fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "fs-node-" (os.time) "-" temp-counter)))

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

(fn with-data-dir [dir f]
    (assert appdirs "appdirs module must be available")
    (local original appdirs.user-data-dir)
    (set appdirs.user-data-dir (fn [_appname] (fs.absolute dir)))
    (local (ok result) (pcall f))
    (set appdirs.user-data-dir original)
    (if ok
        result
        (error result)))

(fn with-temp-data-dir [f]
    (with-temp-dir
        (fn [root]
            (with-data-dir root
                (fn [] (f root))))))

(fn make-heightfield-terrain-record [opts]
    (local options (or opts {}))
    (local chunk-samples (or options.chunk-samples [5 5]))
    {:id (or options.id "terrain-a")
     :kind "heightfield-terrain"
     :options {:position (or options.position [0 0 0])
               :rotation (or options.rotation [1 0 0 0])
               :opacity 1.0
               :physics true
               :sample-spacing (or options.sample-spacing [1 1])
               :chunk-samples chunk-samples
               :default-height (or options.default-height 0.0)}
     :chunks (or options.chunks
                 [{:coord [0 0]
                   :size chunk-samples
                   :heights [0 0 0 0 0
                             0 0 0 0 0
                             0 0 0 0 0
                             0 0 0 0 0
                             0 0 0 0 0]}])})

(fn make-skybox-state [opts]
    (local options (or opts {}))
    (SkyboxState.normalize-complete-state
      {:enabled? (if (= options.enabled? nil) true options.enabled?)
       :default {:name (or options.name "lake")
                 :brightness (or options.brightness 0.1)}
       :by-theme (or options.by-theme {})}
      "test-graph-view skybox state"))

(fn make-background-state [opts]
    (local options (or opts {}))
    (BackgroundState.normalize-complete-state
      {:color (or options.color [0.0 0.0 0.0])}
      "test-graph-view background state"))

(fn make-world-entry [opts]
    (local options (or opts {}))
    (local runtime (or options.runtime nil))
    (local state (or options.state {:scene {:panels []
                                            :terrains []
                                            :lights (LightSystemModule.default-state)
                                            :skybox (make-skybox-state)
                                            :background (make-background-state)}
                                    :hud {:panels []}}))
    ;; Populate canonical sandbox session scene state when absent,
    ;; preserving any existing activity metadata and keeping legacy
    ;; scene keys populated for tests that still reference them directly.
    ;; Arrays (panels, terrains) shared by reference with legacy scene.
    ;; Lights, skybox, background use their own references to avoid
    ;; inadvertently materializing state when a test passes nil.
    (local has-complete-sandbox-scene?
      (and (= (type state.activity) :table)
           (= (type state.activity.sessions) :table)
           (= (type state.activity.sessions.sandbox) :table)
           (= (type state.activity.sessions.sandbox.scene) :table)))
    (when (not has-complete-sandbox-scene?)
      ;; Ensure intermediate tables exist, defaulting active_id if nil.
      (when (not (= (type state.activity) :table))
        (set state.activity {}))
      (when (= state.activity.active_id nil)
        (set state.activity.active_id "sandbox"))
      (when (not (= (type state.activity.sessions) :table))
        (set state.activity.sessions {}))
      (when (not (= (type state.activity.sessions.sandbox) :table))
        (set state.activity.sessions.sandbox {}))
      (local sandbox-lights (or state.scene.lights
                                (LightSystemModule.default-state)))
      (local sandbox-skybox (or state.scene.skybox
                                (make-skybox-state)))
      (local sandbox-background (or state.scene.background
                                    (make-background-state)))
      (set state.activity.sessions.sandbox.scene
           {:panels state.scene.panels
            :terrains state.scene.terrains
            :lights sandbox-lights
            :skybox sandbox-skybox
            :background sandbox-background
            :containment {:enabled? false}}))
    {:id (or options.id "world-a")
     :name (or options.name "World A")
     :world {:state state
             :get-runtime (fn [_self] runtime)
             :save-state (fn [_self] true)}})

(fn make-world-manager [opts]
    (local options (or opts {}))
    (local entry (assert options.entry "make-world-manager requires :entry"))
    {:changed (or options.changed (Signal))
     :get-world-entry (fn [_self world-id]
                        (if (= world-id entry.id) entry nil))
     :active-world-id (fn [_self] (or options.active-world-id entry.id))
     :active-world (fn [_self] entry)})

(fn unwrap-element [item]
    (or (and item item.element) item))

(fn edge-produces-triangles []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (local a (Graph.GraphNode {:key "a" :color (glm.vec4 0.2 0.6 1.0 1)}))
            (local b (Graph.GraphNode {:key "b" :color (glm.vec4 1 0.4 0.2 1)}))
            (graph:add-node a {:position (glm.vec3 0 0 0)})
            (graph:add-node b {:position (glm.vec3 50 0 0)})
            (graph:add-edge (Graph.GraphEdge {:source a :target b}))
            (view:update 0.016)
            (assert (= (graph:node-count) 2))
            (assert (= (graph:edge-count) 1))
            (assert (= (ctx.triangle-vector:length) (* 3 8))
                    "Triangle edge should emit exactly one wedge (3 vertices)")
            (view:drop)
            (graph:drop))))

(fn graph-view-does-not-subscribe-to-raw-engine-updates []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local node (Graph.GraphNode {:key "a" :label "Alpha"}))
            (local raw-updated-signal (and app.engine app.engine.events app.engine.events.updated))
            (assert raw-updated-signal "GraphView test requires app.engine.events.updated")
            (local original-connect raw-updated-signal.connect)
            (var raw-update-connect-count 0)
            (set raw-updated-signal.connect
                 (fn [signal handler]
                     (set raw-update-connect-count (+ raw-update-connect-count 1))
                     (original-connect signal handler)))
            (local view
                (GraphView {:graph-map graph :ctx ctx}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (set raw-updated-signal.connect original-connect)
            (assert (= raw-update-connect-count 0)
                    "GraphView should not subscribe directly to app.engine.events.updated")
            (assert (. view.labels.labels node)
                    "GraphView should still create labels from graph changes")
            (view:drop)
            (graph:drop))))

(fn graph-view-update-after-drop-errors []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (view:drop)
            (local (ok err)
                (pcall (fn []
                         (view:update 0.016))))
            (assert (not ok)
                    "GraphView update after drop should fail fast")
            (assert (string.find (tostring err) "GraphView update called after drop" 1 true))
            (graph:drop))))

(fn graph-view-double-drop-errors []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (view:drop)
            (local (ok err)
                (pcall (fn []
                         (view:drop))))
            (assert (not ok)
                    "GraphView drop should fail fast on repeated calls")
            (assert (string.find (tostring err) "GraphView drop called after drop" 1 true))
            (graph:drop))))

(fn graph-view-public-api-errors-after-drop []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local node (Graph.GraphNode {:key "a" :label "Alpha"}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (view:drop)
            (local checks
                [{:name "remove-nodes"
                  :expected "GraphView remove-nodes called after drop"
                  :call (fn [] (view:remove-nodes []))}
                 {:name "remove-selected-nodes"
                  :expected "GraphView remove-selected-nodes called after drop"
                  :call (fn [] (view:remove-selected-nodes))}
                 {:name "open-focused-node"
                  :expected "GraphView open-focused-node called after drop"
                  :call (fn [] (view:open-focused-node))}
                 {:name "get-position"
                  :expected "GraphView get-position called after drop"
                  :call (fn [] (view:get-position node))}
                 {:name "start-layout"
                  :expected "GraphView start-layout called after drop"
                  :call (fn [] (view:start-layout))}
                 {:name "capture-state"
                  :expected "GraphView capture-state called after drop"
                  :call (fn [] (view:capture-state))}
                 {:name "restore-graph-state"
                  :expected "GraphView restore-graph-state called after drop"
                  :call (fn [] (view:restore-graph-state {}))}
                 {:name "restore-views-state"
                  :expected "GraphView restore-views-state called after drop"
                  :call (fn [] (view:restore-views-state {}))}
                 {:name "restore-state"
                  :expected "GraphView restore-state called after drop"
                  :call (fn [] (view:restore-state {}))}])
            (each [_ check (ipairs checks)]
                (local (ok err)
                    (pcall (fn []
                             ((. check :call)))))
                (assert (not ok)
                        (.. "GraphView " check.name " should fail fast after drop"))
                (assert (string.find (tostring err) check.expected 1 true)
                        (.. "GraphView " check.name " should report a use-after-drop error")))
            (graph:drop))))

(fn start-node-view-adds-quit-node []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {}))
            (local start ((require :graph/nodes/start))) (graph:add-node start {:auto-focus? true})
            (local builder (start.view start))
            (local view (builder ctx))
            (view:refresh-items)
            (var quit-node nil)
            (each [_ pair (ipairs view.search.items)]
                (when (= (. pair 2) "quit")
                    (set quit-node (. pair 1))))
            (assert quit-node "Start view should list quit node")
            (view:add-edge quit-node)
            (assert (graph:lookup "quit"))
            (assert (= (graph:edge-count) 1))
            (view:drop)
            (graph:drop))))

(fn start-node-view-adds-fs-node []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {}))
            (local start ((require :graph/nodes/start))) (graph:add-node start {:auto-focus? true})
            (local builder (start.view start))
            (local view (builder ctx))
            (view:refresh-items)
            (local cwd (fs.cwd))
            (local expected-key (.. "fs:" cwd))
            (var fs-node nil)
            (each [_ pair (ipairs view.search.items)]
                (local candidate (. pair 1))
                (when (and candidate (= candidate.key expected-key))
                    (set fs-node candidate)))
            (assert fs-node "Start view should list fs node")
            (view:add-edge fs-node)
            (assert (graph:lookup expected-key))
            (assert (= (graph:edge-count) 1))
            (view:drop)
            (graph:drop))))

(fn start-node-view-adds-table-node []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {}))
            (local start ((require :graph/nodes/start))) (graph:add-node start {:auto-focus? true})
            (local builder (start.view start))
            (local view (builder ctx))
            (view:refresh-items)
            (var table-node nil)
            (each [_ pair (ipairs view.search.items)]
                (local candidate (. pair 1))
                (when (and candidate (= candidate.key "table:_G"))
                    (set table-node candidate)))
            (assert table-node "Start view should list table node for _G")
            (view:add-edge table-node)
            (assert (graph:lookup "table:_G"))
            (assert (= (graph:edge-count) 1))
            (view:drop)
            (graph:drop))))

(fn code-dir-node-view-adds-subdir-and-module-nodes []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local subdir (fs.join-path root "sub"))
                    (local fnl-file (fs.join-path root "main.fnl"))
                    (local cpp-file (fs.join-path root "main.cpp"))
                    (local txt-file (fs.join-path root "ignore.txt"))
                    (fs.create-dirs subdir)
                    (fs.write-file fnl-file "(local x 1)\n")
                    (fs.write-file cpp-file "#include \"sub/dep.h\"\n")
                    (fs.write-file txt-file "skip")
                    (local ctx (make-ctx))
                    (local graph (Graph {:with-start false}))
                    (local node (CodeDirNode {:path root :root root}))
                    (graph:add-node node {:position (glm.vec3 0 0 0)})
                    (local builder (node.view node))
                    (local view (builder ctx))
                    (view:refresh-items)
                    (var dir-entry nil)
                    (var fnl-entry nil)
                    (var cpp-entry nil)
                    (var txt-entry nil)
                    (each [_ pair (ipairs view.search.items)]
                        (local entry (. pair 1))
                        (when (paths-eq entry.path subdir)
                            (set dir-entry entry))
                        (when (paths-eq entry.path fnl-file)
                            (set fnl-entry entry))
                        (when (paths-eq entry.path cpp-file)
                            (set cpp-entry entry))
                        (when (paths-eq entry.path txt-file)
                            (set txt-entry entry)))
                    (assert dir-entry "CodeDir should include subdirectories")
                    (assert fnl-entry "CodeDir should include .fnl files")
                    (assert cpp-entry "CodeDir should include cpp files")
                    (assert txt-entry "CodeDir should include text files")
                    (view:open-entry dir-entry)
                    (view:open-entry fnl-entry)
                    (view:open-entry cpp-entry)
                    (view:open-entry txt-entry)
                    (local subdir-key (.. "code-dir:" (fs.absolute subdir)))
                    (local fnl-key (.. "fnl-module:" (fs.absolute fnl-file)))
                    (local cpp-key (.. "cpp-module:" (fs.absolute cpp-file)))
                    (local text-key (.. "text-module:" (fs.absolute txt-file)))
                    (assert (graph:lookup subdir-key) "Opening dir entry should add code-dir child")
                    (assert (graph:lookup fnl-key) "Opening fnl entry should add fnl-module child")
                    (assert (graph:lookup cpp-key) "Opening cpp entry should add cpp-module child")
                    (assert (graph:lookup text-key) "Opening text entry should add text-module child")
                    (assert (= (graph:edge-count) 4))
                    (view:drop)
                    (graph:drop))))))

(fn fs-node-actions-open-code-dir-for-directories []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local child-dir (fs.join-path root "sub"))
                    (fs.create-dirs child-dir)
                    (local graph (Graph {:with-start false}))
                    (local node (FsNode {:path root}))
                    (graph:add-node node {:position (glm.vec3 0 0 0)})
                    (local actions (node:actions))
                    (var code-action nil)
                    (each [_ action (ipairs actions)]
                        (when (= action.name "Open as Code Graph")
                            (set code-action action)))
                    (assert code-action
                            "FsNode directory actions should include Open as Code Graph")
                    (code-action.fn nil {})
                    (local code-key (.. "code-dir:" (fs.absolute root)))
                    (assert (graph:lookup code-key)
                            "Open as Code Graph should add a code-dir node")
                    (assert (= (graph:edge-count) 1))
                    (graph:drop))))))

(fn fs-node-actions-open-fnl-module-for-fnl-files []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local path (fs.join-path root "main.fnl"))
                    (fs.write-file path "(local x 1)\n")
                    (local graph (Graph {:with-start false}))
                    (local node (FsNode {:path path}))
                    (graph:add-node node {:position (glm.vec3 0 0 0)})
                    (local actions (node:actions))
                    (var module-action nil)
                    (each [_ action (ipairs actions)]
                        (when (= action.name "Open as Fennel Module")
                            (set module-action action)))
                    (assert module-action
                            "FsNode .fnl actions should include Open as Fennel Module")
                    (module-action.fn nil {})
                    (local module-key (.. "fnl-module:" (fs.absolute path)))
                    (assert (graph:lookup module-key)
                            "Open as Fennel Module should add fnl-module node")
                    (assert (= (graph:edge-count) 1))
                    (graph:drop))))))

(fn graph-map-fs-code-actions-use-loader-backed-nodes []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local fnl-file (fs.join-path root "main.fnl"))
                    (fs.write-file fnl-file "(local x 1)\n")
                    (local graph (Graph {:with-start false}))
                    (local builtins (BuiltinGraphTestHelpers.install-builtins! graph {}))
                    (local graph-map (GraphMap.GraphMap {:graph graph :id "code-actions"}))
                    (local dir-key (.. "fs:" (fs.absolute root)))
                    (local dir-node (graph-map:load-by-key dir-key))
                    (assert dir-node "GraphMap should load fs directory node")
                    (var code-action nil)
                    (each [_ action (ipairs (dir-node:actions))]
                        (when (= action.name "Open as Code Graph")
                            (set code-action action)))
                    (assert code-action "FsNode directory should expose Open as Code Graph")
                    (code-action.fn nil {})
                    (local code-key (.. "code-dir:" (fs.absolute root)))
                    (assert (graph-map:lookup code-key)
                            "Open as Code Graph should add code-dir node to GraphMap")
                    (local file-key (.. "fs:" (fs.absolute fnl-file)))
                    (local file-node (graph-map:load-by-key file-key))
                    (assert file-node "GraphMap should load fs file node")
                    (var module-action nil)
                    (each [_ action (ipairs (file-node:actions))]
                        (when (= action.name "Open as Fennel Module")
                            (set module-action action)))
                    (assert module-action "FsNode .fnl should expose Open as Fennel Module")
                    (module-action.fn nil {})
                    (local module-key (.. "fnl-module:" (fs.absolute fnl-file)))
                    (assert (graph-map:lookup module-key)
                            "Open as Fennel Module should add fnl-module node to GraphMap")
                    (graph-map:drop)
                    (builtins:drop)
                    (graph:drop))))))

(fn fnl-module-node-view-adds-required-module-node []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local subdir (fs.join-path root "sub"))
                    (local main-file (fs.join-path root "main.fnl"))
                    (local dep-file (fs.join-path subdir "dep.fnl"))
                    (fs.create-dirs subdir)
                    (fs.write-file main-file "(local dep (require :sub/dep))\n")
                    (fs.write-file dep-file "(local x 1)\n")
                    (local ctx (make-ctx))
                    (local graph (Graph {:with-start false}))
                    (local node (FnlModuleNode {:path main-file :lua-root root}))
                    (graph:add-node node {:position (glm.vec3 0 0 0)})
                    (local actions (node:actions))
                    (var has-edit false)
                    (each [_ action (ipairs actions)]
                        (when (= action.name "Edit")
                            (set has-edit true)))
                    (assert has-edit "FnlModuleNode should expose Edit action")
                    (local builder (node.view node))
                    (local view (builder ctx))
                    (view:refresh-items)
                    (assert (> (length view.search.items) 0)
                            "FnlModule should list resolvable requires")
                    (local entry (. (. view.search.items 1) 1))
                    (view.search.submitted:emit [entry "sub/dep"])
                    (local dep-key (.. "fnl-module:" (fs.absolute dep-file)))
                    (assert (graph:lookup dep-key)
                            "Submitting dependency should add fnl-module node")
                    (assert (= (graph:edge-count) 1))
                    (view:drop)
                    (graph:drop))))))

(fn cpp-module-node-view-adds-included-module-node []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local subdir (fs.join-path root "sub"))
                    (local main-file (fs.join-path root "main.cpp"))
                    (local dep-file (fs.join-path subdir "dep.h"))
                    (fs.create-dirs subdir)
                    (fs.write-file main-file "#include \"sub/dep.h\"\n")
                    (fs.write-file dep-file "#pragma once\n")
                    (local ctx (make-ctx))
                    (local graph (Graph {:with-start false}))
                    (local code-dir (CodeDirNode {:path root :root root}))
                    (graph:add-node code-dir {:position (glm.vec3 0 0 0)})
                    (local code-dir-view ((code-dir.view code-dir) ctx))
                    (code-dir-view:refresh-items)
                    (var cpp-entry nil)
                    (each [_ pair (ipairs code-dir-view.search.items)]
                        (local entry (. pair 1))
                        (when (paths-eq entry.path main-file)
                            (set cpp-entry entry)))
                    (assert cpp-entry "CodeDir should include cpp module entries")
                    (code-dir-view:open-entry cpp-entry)
                    (local main-key (.. "cpp-module:" (fs.absolute main-file)))
                    (local main-node (graph:lookup main-key))
                    (assert main-node "Opening cpp entry should add cpp-module node")
                    (local actions (main-node:actions))
                    (var has-edit false)
                    (each [_ action (ipairs actions)]
                        (when (= action.name "Edit")
                            (set has-edit true)))
                    (assert has-edit "CppModuleNode should expose Edit action")
                    (local main-view ((main-node.view main-node) ctx))
                    (main-view:refresh-items)
                    (assert (> (length main-view.search.items) 0)
                            "CppModule should list resolvable includes")
                    (local include-entry (. (. main-view.search.items 1) 1))
                    (main-view:open-entry include-entry)
                    (local dep-key (.. "cpp-module:" (fs.absolute dep-file)))
                    (assert (graph:lookup dep-key)
                            "Opening include should add included cpp-module node")
                    (main-view:drop)
                    (code-dir-view:drop)
                    (graph:drop))))))

(fn text-module-node-view-exposes-edit-and-open-parent-actions []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local docs (fs.join-path root "docs"))
                    (local path (fs.join-path docs "note.txt"))
                    (fs.create-dirs docs)
                    (fs.write-file path "See [README](../README.md)\n")
                    (fs.write-file (fs.join-path root "README.md") "# title\n")
                    (local ctx (make-ctx))
                    (local graph (Graph {:with-start false}))
                    (local node (TextModuleNode {:path path :project-root root}))
                    (graph:add-node node {:position (glm.vec3 0 0 0)})
                    (local view ((node.view node) ctx))
                    (view:refresh-items)
                    (assert (= (length view.search.items) 1)
                            "TextModule should list local text references")
                    (local ref-entry (. (. view.search.items 1) 1))
                    (view:open-entry ref-entry)
                    (local ref-key (.. "text-module:" (fs.absolute (fs.join-path root "README.md"))))
                    (assert (graph:lookup ref-key)
                            "Opening text reference should add text-module node")
                    (local actions (node:actions))
                    (var has-edit false)
                    (var has-open-parent false)
                    (each [_ action (ipairs actions)]
                        (when (= action.name "Edit")
                            (set has-edit true))
                        (when (= action.name "Open Parent Dir")
                            (set has-open-parent true)))
                    (assert has-edit "TextModuleNode should expose Edit action")
                    (assert has-open-parent "TextModuleNode should expose Open Parent Dir action")
                    (var open-parent-action nil)
                    (each [_ action (ipairs actions)]
                        (when (= action.name "Open Parent Dir")
                            (set open-parent-action action)))
                    (assert open-parent-action "TextModuleNode should provide Open Parent Dir action")
                    (open-parent-action.fn nil {})
                    (local parent-key (.. "code-dir:" (fs.absolute docs)))
                    (local parent-node (graph:lookup parent-key))
                    (assert parent-node "Open Parent Dir should add parent code-dir node")
                    (assert (= (graph:edge-count) 2)
                            "Open Parent Dir should add one more graph edge")
                    (var saw-parent-edge false)
                    (each [_ edge (ipairs graph.edges)]
                        (when (and (= edge.source parent-node)
                                   (= edge.target node))
                            (set saw-parent-edge true)))
                    (assert saw-parent-edge
                            "Open Parent Dir edge should flow downward from parent code-dir to module")
                    (view:drop)
                    (graph:drop))))))

(fn nodes-default-to-center-position []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (local center (glm.vec3 15 25 0))
            (view.layout:set-center-position center)
            (local node (Graph.GraphNode {:key "centered"}))
            (graph:add-node node {})
            (local pos (view:get-position node))
            (assert pos "GraphView should expose node position after add-node")
            (local dx (- pos.x center.x))
            (local dy (- pos.y center.y))
            (assert (and (>= dx 0) (<= dx 100))
                    (string.format "Default X offset should be in [0, 100] (got %.3f)" dx))
            (assert (and (>= dy 0) (<= dy 100))
                    (string.format "Default Y offset should be in [0, 100] (got %.3f)" dy))
            (assert (= pos.z center.z))
            (view:drop)
            (graph:drop))))

(fn fs-node-view-adds-child-nodes-for-entries []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local ctx (make-ctx))
                    (local graph (Graph {:with-start false}))
                    (local child-dir (fs.join-path root "child"))
                    (local file (fs.join-path root "note.txt"))
                    (fs.create-dirs child-dir)
                    (fs.write-file file "hello")
                    (local node (FsNode {:path root}))
                    (graph:add-node node {:position (glm.vec3 0 0 0)})
                    (local builder (node.view node))
                    (local view (builder ctx))
                    (view:refresh-items)
                    (var dir-entry nil)
                    (var file-entry nil)
                    (each [_ item (ipairs view.search.items)]
                        (local entry (. item 1))
                        (when (paths-eq entry.path child-dir)
                            (set dir-entry entry))
                        (when (paths-eq entry.path file)
                            (set file-entry entry)))
                    (assert dir-entry "Fs node view should list directories")
                    (assert file-entry "Fs node view should list files")
                    (view:open-entry dir-entry)
                    (assert (= (graph:edge-count) 1)
                            (string.format "Fs node should create one edge after opening dir (got %s)"
                                           (graph:edge-count)))
                    (view:open-entry file-entry)
                    (assert (find-fs-node-by-path graph child-dir)
                            "Dir node should be added to graph")
                    (assert (find-fs-node-by-path graph file)
                            "File node should be added to graph")
                    (local edge-count (graph:edge-count))
                    (assert (= edge-count 2)
                            (string.format "Fs node edges should match spawned children (got %s)"
                                           edge-count))
                    (view:drop)
                    (graph:drop))))))

(fn fs-node-view-ripgrep-button-opens-ripgrep-view-with-prefilled-path []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                     (local original-hud app.hud)
                     (local original-canvas app.canvas)
                     (local original-graph-view app.graph-view)
                    (local added-opts [])
                    (local panel-target
                      {:add-panel-child (fn [_self opts]
                                          (table.insert added-opts opts)
                                          {:layout {:position (glm.vec3 0 0 0)}
                                           :drop (fn [_] nil)})})
       (set app.hud nil)
      (set app.canvas nil)
      (set app.graph-view {:extra-panels []
                           :register-extra-panel! (fn [self entry _target _element]
                                                     (table.insert self.extra-panels entry)
                                                     entry)
                           :remove-extra-panel-entry! (fn [self kind node-key graph-map-id]
                                                        (for [i (length self.extra-panels) 1 -1]
                                                          (local entry (. self.extra-panels i))
                                                          (when (and (= entry.kind kind)
                                                                     (= entry.node-key node-key)
                                                                     (= entry.graph-map-id graph-map-id))
                                                            (table.remove self.extra-panels i))))})
      (local (ok err)
                      (pcall
                        (fn []
                          (local ctx (make-ctx))
                          (set ctx.panel-target panel-target)
                          (local graph (Graph {:with-start false}))
                          (local node (FsNode {:path root}))
                          (graph:add-node node {:position (glm.vec3 0 0 0)})
                          (local builder (node.view node))
                          (local view (builder ctx))
                          (local ripgrep-button view.ripgrep-button)
                          (assert ripgrep-button "Fs node view should expose a ripgrep-button handle")
                          (ripgrep-button:on-click {:button 1})
                          (assert (= (length added-opts) 1)
                                  "Ripgrep button should open one panel child")
                          (local opts (. added-opts 1))
                          (assert (and opts opts.builder) "Ripgrep panel add should include a builder")
                          (assert (= (and opts.builder-options opts.builder-options.path)
                                     (fs.absolute root))
                                  "Ripgrep panel should prefill FsNode absolute path")
                          (view:drop)
                          (graph:drop))))
       (set app.hud original-hud)
      (set app.canvas original-canvas)
      (set app.graph-view original-graph-view)
                    (when (not ok)
                        (error err)))))))

(fn llm-conversation-view-opens-messages-panel-using-context-target []
  (with-temp-data-dir
    (fn [_root]
      (local original-hud app.hud)
      (local original-canvas app.canvas)
      (local original-graph-view app.graph-view)
      (local added-opts [])
      (local panel-target
        {:add-panel-child (fn [_self opts]
                            (table.insert added-opts opts)
                            {:layout {:position (glm.vec3 0 0 0)}
                             :drop (fn [_] nil)})})
       (set app.hud nil)
      (set app.canvas nil)
      (set app.graph-view {:extra-panels []
                           :register-extra-panel! (fn [self entry _target _element]
                                                     (table.insert self.extra-panels entry)
                                                     entry)
                           :remove-extra-panel-entry! (fn [self kind node-key graph-map-id]
                                                        (for [i (length self.extra-panels) 1 -1]
                                                          (local entry (. self.extra-panels i))
                                                          (when (and (= entry.kind kind)
                                                                     (= entry.node-key node-key)
                                                                     (= entry.graph-map-id graph-map-id))
                                                            (table.remove self.extra-panels i))))})
      (local (ok err)
        (pcall
          (fn []
            (local ctx (make-ctx))
            (set ctx.panel-target panel-target)
            (local graph (Graph {:with-start false}))
            (local conversation (LlmConversationNode {}))
            (graph:add-node conversation {:position (glm.vec3 0 0 0)})
            (local builder (conversation.view conversation))
            (local view (builder ctx))
            (view:open-messages-view)
            (assert (= (length added-opts) 1)
                    "LlmConversationView should open one messages panel")
            (local opts (. added-opts 1))
            (assert (= (and opts opts.persistence opts.persistence.kind)
                       "llm-conversation-messages-view-dialog")
                    "Messages panel should carry target-level persistence for transfer sync")
            (assert (= (and opts opts.persistence opts.persistence.node-key)
                       conversation.key)
                    "Messages panel persistence should identify the conversation node")
            (assert (and app.graph-view app.graph-view.extra-panels
                         (> (length app.graph-view.extra-panels) 0))
                    "Messages panel should register in graph-view extra-panels")
            (assert (= (. (. app.graph-view.extra-panels 1) :node-key)
                       conversation.key)
                    "Extra-panels entry should reference the conversation node key")
            (view:drop)
            (graph:drop))))
      (set app.hud original-hud)
      (set app.canvas original-canvas)
      (set app.graph-view original-graph-view)
      (when (not ok)
        (error err))
      true)))

(fn table-node-view-adds-child-nodes []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local target {:one 1 :nested {:two 2}})
            (local node (TableNode {:table target
                                    :label "root"
                                    :key "table:root"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local builder (node.view node))
            (local view (builder ctx))
            (view:refresh-items)
            (var nested-entry nil)
            (var value-entry nil)
            (each [_ pair (ipairs view.search.items)]
                (local entry (. pair 1))
                (when (= entry.key :nested)
                    (set nested-entry entry))
                (when (= entry.key :one)
                    (set value-entry entry)))
            (assert nested-entry "Table view should include nested table entry")
            (assert value-entry "Table view should include value entry")
            (view:open-entry nested-entry)
            (view:open-entry value-entry)
            (local nested-key (node:child-key nested-entry))
            (local value-key (node:child-key value-entry))
            (assert (graph:lookup nested-key) "Nested table node should be added")
            (assert (graph:lookup value-key) "Value node should be added")
            (local edge-count (graph:edge-count))
            (assert (= edge-count 2)
                    (string.format "Table node edges should match spawned entries (got %s)"
                                   edge-count))
            (view:drop)
            (graph:drop))))

(fn graph-removes-selected-nodes-and-edges []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local graph (Graph {:with-start false}))
            (register-graph-map-test-loaders graph ["a" "b" "c"])
            (local map (GraphMap.GraphMap {:graph graph :id "test-remove-selected"}))
            (local view (GraphView {:graph-map map
                                    :ctx ctx
                                    :selector selector}))
            (local a (Graph.GraphNode {:key "a"}))
            (local b (Graph.GraphNode {:key "b"}))
            (local c (Graph.GraphNode {:key "c"}))
            (map:add-node a {:position (glm.vec3 0 0 0)})
            (map:add-node b {:position (glm.vec3 10 0 0)})
            (map:add-node c {:position (glm.vec3 20 0 0)})
            (map:add-edge (Graph.GraphEdge {:source a :target b}))
            (map:add-edge (Graph.GraphEdge {:source b :target c}))
            (selector:set-selected [(. view.points b)])
            (local removed (view:remove-selected-nodes))
            (assert (= removed 1) "GraphView should report the number of removed nodes")
            (assert (not (map:lookup "b")) "Removed node should be cleared from map lookup")
            (assert (= (map:edge-count) 0) "Edges connected to removed nodes should be dropped from map")
            (local remaining-points (icollect [_ point (pairs view.points)] point))
            (assert (= (length remaining-points) 2)
                    (string.format "GraphView should retain two point records (got %s)"
                                   (length remaining-points)))
            (assert (= (length selector.selectables) 2)
                    (string.format "Selector should retain only remaining points (got %s)"
                                   (length selector.selectables)))
            (assert (= (length view.selected-nodes) 0) "Graph selection should clear after removal")
            (view:drop)
            (map:drop)
            (graph:drop)
            (selector:drop))))

(fn graph-removing-node-closes-live-scene-cube-panel []
    (with-temp-data-dir
        (fn [_root]
            (local original-scene app.scene)
            (local removed [])
            (local scene {:scene-children []})
            (set scene.remove-panel-child
                 (fn [self element]
                     (table.insert removed element)
                     (for [i (length self.scene-children) 1 -1]
                         (when (= (. self.scene-children i :element) element)
                             (table.remove self.scene-children i)))))
            (local (ok err)
                (pcall
                    (fn []
                        (set app.scene scene)
                        (local ctx (make-ctx))
                        (local graph (Graph {:with-start false}))
                        (register-graph-map-test-loaders graph ["test:cube-node"])
                        (local graph-map (GraphMap.GraphMap {:graph graph :id "cube-map"}))
                        (local view (GraphView {:graph-map graph-map :ctx ctx}))
                        (local node (graph-map:load-by-key "test:cube-node"))
                        (local element {:layout (Layout {:name "live-cube-panel"})})
                        (table.insert scene.scene-children
                                      {:element element
                                       :persistence {:kind "graph-node-cube"
                                                     :node-key "test:cube-node"
                                                     :graph-map-id "cube-map"}})
                        (graph-map:remove-nodes [node])
                        (assert (= (length removed) 1)
                                "Removing a map node should close its live scene cube panel")
                        (assert (= (. removed 1) element)
                                "Removed scene panel should be the matching cube element")
                        (assert (= (length scene.scene-children) 0)
                                "Scene should not retain the removed cube panel")
                        (view:drop)
                        (graph-map:drop)
                        (graph:drop))))
            (set app.scene original-scene)
            (when (not ok)
                (error err)))))

(fn quit-node-view-invokes-handler []
    (local ctx (make-ctx))
    (local original-quit app.engine.quit)
    (var quit-calls 0)
    (set app.engine.quit (fn [] (set quit-calls (+ quit-calls 1))))
    (local quit-node ((require :graph/nodes/quit) {}))
    (local builder (quit-node.view quit-node))
    (local view (builder ctx))
    (view:perform-quit)
    (assert (= quit-calls 1) "Quit view should call app.engine.quit")
    (view:drop)
    (set app.engine.quit original-quit))

(fn llm-conversation-view-adds-message-node []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local conversation (LlmConversationNode {}))
            (graph:add-node conversation {:position (glm.vec3 0 0 0)})
            (local builder (conversation.view conversation))
            (local view (builder ctx))
            (local message (view:add-message))
            (assert message "LlmConversationView should create a message node")
            (assert message.llm-id "Llm conversation should assign an llm id")
            (local expected-key (.. "llm-message:" message.llm-id))
            (assert (= message.key expected-key)
                    "Llm conversation should key messages by llm id")
            (assert (graph:lookup message.key)
                    "Graph should register message node created from conversation")
            (assert (= (graph:edge-count) 1)
                    "Conversation should add an edge for new message")
            (view:drop)
            (graph:drop))))

(fn llm-message-view-updates-node-fields []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local node (LlmMessageNode {:key "llm-message:test"
                                         :role "assistant"
                                         :content "Hello"
                                         :tool-name "picker"
                                         :tool-call-id "call-1"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local builder (node.view node))
            (local view (builder ctx))
            (local inputs view.inputs)
            (assert inputs "LlmMessageView should expose inputs")
            (local tool-name-input (. inputs :tool-name))
            (local tool-call-input (. inputs :tool-call-id))
            (assert (= (inputs.role:get-value) "assistant"))
            (assert (= (inputs.content:get-text) "Hello"))
            (assert (= (tool-name-input:get-text) "picker"))
            (assert (= (tool-call-input:get-text) "call-1"))
            (inputs.role:set-value "user")
            (inputs.content:set-text "Updated")
            (tool-name-input:set-text "search")
            (tool-call-input:set-text "call-2")
            (assert (= node.role "user"))
            (assert (= node.content "Updated"))
            (assert (= (. node :tool-name) "search"))
            (assert (= (. node :tool-call-id) "call-2"))
            (view:drop)
            (graph:drop))))

(fn llm-node-view-adds-conversations []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local node (LlmNode))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local builder (node.view node))
            (local view (builder ctx))
            (view:refresh-items)
            (var conversations-node nil)
            (each [_ pair (ipairs view.search.items)]
                (when (= (. pair 2) "llm conversations")
                    (set conversations-node (. pair 1))))
            (assert conversations-node "Llm node view should list conversations")
            (view:add-edge conversations-node)
            (assert (graph:lookup "llm-conversations"))
            (assert (= (graph:edge-count) 1))
            (view:drop)
            (graph:drop))))

(fn llm-conversations-view-builds []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local node (LlmConversationsNode {}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local builder (node.view node))
            (local view (builder ctx))
            (assert view "LlmConversationsView should build")
            (view:drop)
            (graph:drop))))

(fn graph-expands-node-inline-on-double-click []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local graph (Graph {}))
            (local start ((require :graph/nodes/start))) (graph:add-node start {:position (glm.vec3 0 0 0)})
            (local view-controller (GraphView {:graph-map graph
                                                 :ctx ctx
                                                 :selector selector}))
            (local point (. view-controller.points start))
            (assert point.on-double-click "GraphView should attach double click handler to node point")
            (point:on-double-click {})
            (local card (. view-controller.points start))
            (assert (not (= card point)) "Double-clicking node should replace compact point with expanded card")
            (assert card._card-size "Expanded node should expose card bounds")
            (assert card.view-widget "Expanded node should build the node view inline")
            (assert (not (. view-controller.labels.labels start))
                    "Expanded node should not keep a compact label")
            (local collapse-button (. card.header-bar.children 3 :element))
            (collapse-button:on-click {})
            (local compact (. view-controller.points start))
            (assert (not compact._card-size) "Collapse button should restore compact point")
            (view-controller:drop)
            (graph:drop)
            (selector:drop))))

(fn tracked-preview [state]
    (fn [node _opts]
        (fn [_ctx]
            (set state.built-node node)
            (local widget {:node node})
            (fn measurer [self]
                (set state.measured? true)
                (set self.measure (or state.measure (glm.vec3 72 36 0))))
            (fn constrained-measurer [self constraints]
                (set state.constrained constraints)
                (set self.measure (or state.constrained-measure state.measure (glm.vec3 70 32 0))))
            (fn layouter [self]
                (set state.laid-out? true)
                (set state.laid-out-size self.size)
                (set state.laid-out-position self.position)
                (set state.depth-offset-index self.depth-offset-index))
            (local layout (Layout {:name "tracked-graph-preview"
                                   :measurer measurer
                                   :constrained-measurer constrained-measurer
                                   :layouter layouter}))
            (set widget.layout layout)
            (set widget.drop (fn [_self]
                                 (set state.dropped? true)
                                 (layout:drop)))
            widget)))

(fn graph-expanded-card-uses-preview-and-measures-child []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx}))
            (local state {:measure (glm.vec3 73 37 0)
                          :constrained-measure (glm.vec3 70 32 0)})
            (var full-view-called? false)
            (local node (Graph.GraphNode {:key "preview-card"
                                          :view (fn [_node _opts]
                                                    (set full-view-called? true)
                                                    (fn [_ctx]
                                                        (error "Expanded card should use preview, not full view")))
                                          :preview (tracked-preview state)}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local point (. view.points node))
            (point:on-double-click {:mod 256})
            (assert (not (. (. view.points node) :_card-size))
                    "Alt+double-click should not toggle inline expansion")
            (point:on-double-click {})
            (local card (. view.points node))
            (assert card._card-size "Plain double-click should expand node inline")
            (assert (= card.layout.depth-offset-index 2)
                    "Expanded card should render above graph edges")
            (assert (= state.built-node node) "Expanded card should build the node preview")
            (assert (not full-view-called?) "Expanded card should not build the full node view")
            (assert card.header-bar "Expanded card should have a header bar") (assert (= card.header-title.style.scale 1.6) "Expanded card header title should use the normal default text scale")
            (ctx.layout-root:update)
            (assert state.constrained "Expanded card should measure child with constraints")
            (assert (= state.constrained.max.x 52.0)
                    "Expanded card should constrain child to max-size width")
            (assert (< state.constrained.max.y 34.0)
                    "Expanded card should constrain child height to less than full card height (header takes space)")
            (assert state.laid-out? "Expanded card should lay out child widget")
            (assert (= state.laid-out-size.x card._card-size.x)
                    "Expanded card child width should match card width")
            (assert (< state.laid-out-size.y card._card-size.y)
                    "Expanded card child height should be less than full card height")
            (assert (= state.depth-offset-index (+ card.layout.depth-offset-index 4))
                    "Expanded card child should render above header, background, focus, and selection outlines")
            (assert (= state.laid-out-position.y card.layout.position.y)
                    "Expanded card preview content should be at card origin (bottom)")
            (assert (< (math.abs (- card.header-bar.layout.position.y
                                    (+ card.layout.position.y (- card._card-size.y card._header-height))))
                       1e-4)
                    "Expanded card header should be at card top")
            (assert (. view.pinned node) "Expanded node should be pinned")
            (assert (and card.header-bar card.header-bar.children (= (length card.header-bar.children) 5))
                    "Expanded card header should have five children (title + spacer + three buttons)")
            (local spacer-layout (. (. card.header-bar.children 2 :element) :layout))
            (assert (> spacer-layout.size.x 0)
                    "Header flex spacer should fill remaining horizontal space")
            (local menu-button (. card.header-bar.children 5 :element))
            (local menu-right-edge (+ menu-button.layout.position.x menu-button.layout.size.x))
            (local card-right-edge (+ card.layout.position.x card._card-size.x))
            (assert (< (math.abs (- menu-right-edge card-right-edge)) 1e-3)
                    "Header buttons should be right-aligned in the card")
            (local collapse-button (. card.header-bar.children 3 :element))
            (collapse-button:on-click {})
            (assert (not (. view.points node :_card-size)) "Collapse button should collapse expanded card")
            (assert (not (. view.pinned node)) "Collapsing should restore unpinned state")
            (view:drop)
            (graph:drop))))

(fn graph-expanded-card-header-shows-truncated-node-label [] (local ctx (make-ctx)) (local long-label "This graph node label is long enough to be truncated in compact expanded card headers") (local node (Graph.GraphNode {:key "compact-title-node" :label long-label :preview (tracked-preview {})})) (local GraphNodePresentation (require :graph/view/presentation)) (local card-builder (GraphNodePresentation.card-builder {:node node :position (glm.vec3 0 0 0) :default-size (glm.vec3 32 18 0) :on-collapse (fn [] nil) :on-open (fn [_] nil) :on-menu (fn [_] nil)})) (local card (card-builder ctx)) (assert card.header-title "Expanded card should expose a title text widget") (assert card.header-title-text "Expanded card should expose the display title string") (assert (string.find card.header-title-text (string.char 46 46 46) 1 true) "Expanded card display title should truncate long labels with an ellipsis") (assert (= node.label long-label) "Truncation should not mutate the source node label") (assert (= (length card.header-bar.children) 5) "Expanded card header should have title, spacer, and three buttons") (card:drop))
(fn graph-expanded-toggle-preserves-selection []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx
                                    :selector selector}))
            (local node (Graph.GraphNode {:key "selected-toggle"
                                          :preview (tracked-preview {})}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local point (. view.points node))
            (selector:set-selected [point])
            (assert (= (. view.selected-nodes 1) node)
                    "Fixture should select graph node before toggling")
            (point:on-double-click {})
            (local card (. view.points node))
            (assert card._card-size "Plain double-click should expand selected node")
            (assert (= (. selector.selected 1) card)
                    "Expanded card should replace compact point in selector selection")
            (assert (= (. view.selected-nodes 1) node)
                    "GraphView selection should stay on node after expansion")
            (local collapse-button (. card.header-bar.children 3 :element))
            (collapse-button:on-click {})
            (local compact (. view.points node))
            (assert (not compact._card-size) "Second double-click should collapse selected node")
            (assert (= (. selector.selected 1) compact)
                    "Compact point should replace expanded card in selector selection")
            (assert (= (. view.selected-nodes 1) node)
                    "GraphView selection should stay on node after collapse")
            (view:drop)
            (graph:drop)
            (selector:drop))))
(fn graph-expanded-toggle-preserves-node-center []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx}))
            (local node (Graph.GraphNode {:key "center-toggle"
                                          :preview (tracked-preview {})}))
            (local center (glm.vec3 10 20 0))
            (graph:add-node node {:position center})
            (local point (. view.points node))
            (point:on-double-click {})
            (local card (. view.points node))
            (assert (= card.position.x center.x)
                    "Expanded card position should remain the graph node center")
            (assert (= card.position.y center.y)
                    "Expanded card position should remain the graph node center")
            (ctx.layout-root:update)
            (assert (= card.layout.position.x (- center.x (/ card._card-size.x 2.0)))
                    "Expanded card layout origin should be centered around graph node position")
            (assert (= card.layout.position.y (- center.y (/ card._card-size.y 2.0)))
                    "Expanded card layout origin should be centered around graph node position")
            (local expanded-pos (view:get-position node))
            (assert (= expanded-pos.x center.x)
                    "GraphView position should stay anchored at node center while expanded")
            (assert (= expanded-pos.y center.y)
                    "GraphView position should stay anchored at node center while expanded")
            (local collapse-button (. card.header-bar.children 3 :element))
            (collapse-button:on-click {})
            (local compact (. view.points node))
            (assert (not compact._card-size) "Fixture should collapse back to compact point")
            (assert (= compact.position.x center.x)
                    "Collapsed compact point should keep original center")
            (assert (= compact.position.y center.y)
                    "Collapsed compact point should keep original center")
            (view:drop)
            (graph:drop))))

(fn graph-remove-then-expand-keeps-selector-list-synchronized []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx
                                    :selector selector}))
            (local a (Graph.GraphNode {:key "sync-a"
                                       :preview (tracked-preview {})}))
            (local b (Graph.GraphNode {:key "sync-b"}))
            (local c (Graph.GraphNode {:key "sync-c"}))
            (graph:add-node a {:position (glm.vec3 0 0 0)})
            (graph:add-node b {:position (glm.vec3 10 0 0)})
            (graph:add-node c {:position (glm.vec3 20 0 0)})
            (local a-point (. view.points a))
            (local b-point (. view.points b))
            (selector:set-selected [b-point])
            (view:remove-selected-nodes)
            (assert (= (length selector.selectables) 2)
                    "Selector public list should contain remaining graph nodes after removal")
            (a-point:on-double-click {})
            (local a-card (. view.points a))
            (assert a-card._card-size "Remaining node should expand after a prior removal")
            (assert (= (length selector.selectables) 2)
                    "Selector public list should stay synchronized after remove then expand")
            (var saw-card? false)
            (var saw-old-point? false)
            (var saw-removed? false)
            (each [_ selectable (ipairs selector.selectables)]
                (when (= selectable a-card)
                    (set saw-card? true))
                (when (= selectable a-point)
                    (set saw-old-point? true))
                (when (= selectable b-point)
                    (set saw-removed? true)))
            (assert saw-card? "Expanded card should replace compact point in selector public list")
            (assert (not saw-old-point?) "Selector public list should not keep stale compact point")
            (assert (not saw-removed?) "Selector public list should not keep removed point")
            (view:drop)
            (graph:drop)
            (selector:drop))))

(fn graph-expanded-toggle-failure-keeps-compact-point []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (var removed-quads 0)
            (set ctx.get-rectangle-quad-batcher
                 (fn [_self]
                     {:upsert-quad (fn [_self _key _opts] nil)
                      :remove-quad (fn [_self _key]
                                       (set removed-quads (+ removed-quads 1)))}))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx
                                    :selector selector}))
            (fn assert-failed-expansion-keeps-compact-point [node expected-error]
                (graph:add-node node {:position (glm.vec3 0 0 0)})
                (local before-removed-quads removed-quads)
                (local point (. view.points node))
                (selector:set-selected [point])
                (local (ok err) (pcall (fn [] (point:on-double-click {}))))
                (assert (not ok) "Broken preview should make expansion fail loudly")
                (assert (string.find (tostring err) expected-error 1 true)
                        "Expansion failure should surface preview error")
                (assert (= (. view.points node) point)
                        "Failed expansion should keep the original compact point in registry")
                (assert point.on-double-click
                        "Failed expansion should keep compact point double-click handler")
                (assert (= (. view.node-by-point point) node)
                        "Failed expansion should keep compact point reverse mapping")
                (assert (= (. selector.selected 1) point)
                        "Failed expansion should preserve selector selection")
                (assert (= (. view.selected-nodes 1) node)
                        "Failed expansion should preserve GraphView selection")
                (assert (> removed-quads before-removed-quads)
                        "Failed expansion should drop partially built card background"))
            (local build-error-node
                   (Graph.GraphNode {:key "bad-preview-build"
                                     :preview (fn [_node _opts]
                                                  (fn [_ctx]
                                                      (error "preview build failed")))}))
            (assert-failed-expansion-keeps-compact-point build-error-node "preview build failed")
            (local bad-layout-node
                   (Graph.GraphNode {:key "bad-preview-layout"
                                     :preview (fn [_node _opts]
                                                  (fn [_ctx]
                                                      {:layout {}}))}))
            (assert-failed-expansion-keeps-compact-point bad-layout-node "set-root")
            (view:drop)
            (graph:drop)
            (selector:drop))))

(fn graph-expanded-card-rebuilds-preview-for-replacement []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx}))
            (local first-state {})
            (local second-state {})
            (local first (Graph.GraphNode {:key "swap"
                                           :preview (tracked-preview first-state)}))
            (local second (Graph.GraphNode {:key "swap"
                                            :preview (tracked-preview second-state)}))
            (graph:add-node first {:position (glm.vec3 0 0 0)})
            (local first-point (. view.points first))
            (first-point:on-double-click {})
            (assert (= (. view.points first :view-widget :node) first)
                    "Expanded card should initially belong to original node")
            (graph:add-node second)
            (local replacement-card (. view.points second))
            (assert replacement-card._card-size
                    "Replacement for expanded node should stay expanded")
            (assert (= replacement-card.view-widget.node second)
                    "Replacement expanded card should rebuild for replacement node")
            (assert first-state.dropped?
                    "Replacing expanded node should drop stale preview widget")
            (assert (not (. view.points first))
                    "GraphView should remove old node point mapping after replacement")
            (view:drop)
            (graph:drop))))

(fn graph-compact-replacement-refreshes-focus-binding []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local target {:children []
                           :add-panel-child (fn [self opts]
                                                (table.insert self.children opts)
                                                opts)
                           :remove-panel-child (fn [_self _element] nil)})
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx
                                    :view-target target}))
            (var first-opened 0)
            (var second-opened 0)
            (local first (Graph.GraphNode {:key "focus-swap"
                                           :view (fn [_node]
                                                     (set first-opened (+ first-opened 1))
                                                     (fn [_ctx]
                                                         {:layout (Layout {:name "first-focus-view"})}))}))
            (local second (Graph.GraphNode {:key "focus-swap"
                                            :view (fn [_node]
                                                      (set second-opened (+ second-opened 1))
                                                      (fn [_ctx]
                                                          {:layout (Layout {:name "second-focus-view"})}))}))
            (graph:add-node first {:position (glm.vec3 10 20 0)})
            (local focus-node (. view.focus-nodes first))
            (assert focus-node "Fixture should create focus node for original graph node")
            (focus-node:request-focus)
            (graph:add-node second)
            (assert (= (. view.focus-nodes second) focus-node)
                    "Replacement should keep the existing focus node")
            (local bounds (focus-node:get-focus-bounds))
            (assert bounds "Replacement focus bounds should resolve through replacement node")
            (assert (= bounds.position.x 6.0)
                    "Compact focus bounds should be based on replacement point position and size")
            (ctx.focus.manager:activate-focused {})
            (assert (= first-opened 0)
                    "Replacement focus activation should not open stale original node")
            (assert (= second-opened 1)
                    "Replacement focus activation should open replacement node")
            (view:drop)
            (graph:drop))))

(fn graph-node-view-replacement-preserves-panel-placement []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (var captured-element nil)
            (var captured-state nil)
            (var last-add-opts nil)
            (var last-removed nil)
            (local resolved-panel {:location :float
                                   :position [55 65 0]
                                   :size [420 340 0]
                                   :rotation [1 0 0 0]})
            (local target {:children []
                           :panel-placement-options (fn [_self entry]
                                                       {:location (or entry.location ":float")
                                                        :position (or entry.position resolved-panel.position)
                                                        :size (or entry.size resolved-panel.size)
                                                        :rotation (or entry.rotation resolved-panel.rotation)})
                           :add-panel-child (fn [self opts]
                                               (set last-add-opts opts)
                                               (table.insert self.children opts)
                                               opts)
                           :remove-panel-child (fn [self element]
                                                (set last-removed element)
                                                (for [i (length self.children) 1 -1]
                                                    (when (= (. self.children i) element)
                                                        (table.remove self.children i))))
                           :capture-panel-element-state (fn [_self element]
                                                           (set captured-element element)
                                                           (set captured-state {:location :float
                                                                                 :position [50 60 0]
                                                                                 :size [400 300 0]})
                                                           captured-state)})
            (local graph (Graph {:with-start false}))
            (register-graph-map-test-loaders graph ["panel-swap"])
            (local map (GraphMap.GraphMap {:graph graph :id "test-panel-placement"}))
            (local first (Graph.GraphNode {:key "panel-swap"
                                           :view (fn [_node]
                                                     (fn [_ctx]
                                                         {:layout (Layout {:name "first-panel-view"})}))}))
            (local second (Graph.GraphNode {:key "panel-swap"
                                            :view (fn [_node]
                                                      (fn [_ctx]
                                                          {:layout (Layout {:name "second-panel-view"})}))}))
            (local view (GraphView {:graph-map map
                                    :ctx ctx
                                    :view-target target}))
            (map:add-node first {:position (glm.vec3 0 0 0)})
            (view.views:open first)
            (assert (= (length target.children) 1)
                    "Opening node view should add a panel child")
            (local first-element (. target.children 1))
            (assert first-element "First node should have a panel element")
            ;; Replace the node to trigger node-replaced -> move-view (via GraphMap)
            (map:add-node second)
            (assert captured-element
                    "Node replacement should capture panel element state from old node")
            (assert (= captured-element first-element)
                    "Captured element should be the old node's panel element")
            (assert captured-state "Node replacement should produce captured state")
            (assert (= (. captured-state :position 1) 50)
                    "Captured state should preserve panel position x")
            (assert last-removed
                    "Node replacement should remove the old panel child")
            (assert (= last-removed first-element)
                    "Removed element should be the old node's panel element")
            (assert (= (length target.children) 1)
                    "Replacement node should have exactly one panel child")
            (local second-element (. target.children 1))
            (assert second-element "Replacement node should have a panel element")
            (assert (not (= second-element first-element))
                    "Replacement node should create a new panel element, not reuse the old one")
            (assert last-add-opts "Replacement node should call add-panel-child")
            ;; Verify the captured placement was forwarded through to add-panel-child opts
            (assert (= (. last-add-opts :position 1) 50)
                    "add-panel-child opts position.x should be from captured state")
            (assert (= (. last-add-opts :position 2) 60)
                    "add-panel-child opts position.y should be from captured state")
            (assert (= (. last-add-opts :size 1) 400)
                    "add-panel-child opts size.x should be from captured state")
            (view:drop)
            (map:drop)
            (graph:drop))))

(fn graph-expanded-card-replacement-preserves-selection []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx
                                    :selector selector}))
            (local first-state {})
            (local second-state {})
            (local first (Graph.GraphNode {:key "swap-selected"
                                           :preview (tracked-preview first-state)}))
            (local second (Graph.GraphNode {:key "swap-selected"
                                            :preview (tracked-preview second-state)}))
            (graph:add-node first {:position (glm.vec3 0 0 0)})
            (local first-point (. view.points first))
            (first-point:on-double-click {})
            (local first-card (. view.points first))
            (selector:set-selected [first-card])
            (assert (= (. view.selected-nodes 1) first)
                    "Fixture should select the expanded original node before replacement")
            (graph:add-node second)
            (local replacement-card (. view.points second))
            (assert replacement-card._card-size
                    "Selected replacement should stay expanded")
            (assert (= (. view.selected-nodes 1) second)
                    "Replacing selected node should move GraphView selection to replacement")
            (assert (= (. selector.selected 1) replacement-card)
                    "Replacing selected expanded node should replace selector selection with replacement card")
            (assert (> (or (rawget replacement-card "_selection-layer-size") 0) 0)
                    "Replacement card should show selected visual state")
            (assert first-state.dropped?
                    "Replacing selected expanded node should drop stale preview widget")
            (view:drop)
            (graph:drop)
            (selector:drop))))

(fn graph-expanded-card-replacement-failure-collapses-to-compact []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx}))
            (local first-state {})
            (local first (Graph.GraphNode {:key "swap-fail"
                                           :preview (tracked-preview first-state)}))
            (local second (Graph.GraphNode {:key "swap-fail"
                                            :preview (fn [_node _opts]
                                                        (fn [_ctx]
                                                            (error "replacement preview failed")))}))
            (graph:add-node first {:position (glm.vec3 0 0 0)})
            (local first-point (. view.points first))
            (first-point:on-double-click {})
            (local first-card (. view.points first))
            (assert first-card._card-size
                    "Fixture should expand original node before replacement")
            (local (ok err) (pcall (fn [] (graph:add-node second))))
            (assert (not ok) "Broken replacement preview should fail loudly")
            (assert (string.find (tostring err) "replacement preview failed" 1 true)
                    "Replacement failure should surface preview error")
            (assert (= (graph:lookup "swap-fail") second)
                    "Graph replacement should already point to replacement node after signal failure")
            (assert (not (. view.points first))
                    "Failed replacement should remove old node point mapping")
            (local fallback-point (. view.points second))
            (assert fallback-point
                    "Failed replacement should install a fallback presentation for replacement node")
            (assert (not (= fallback-point first-card))
                    "Failed replacement should not keep stale expanded card as replacement presentation")
            (assert (not fallback-point._card-size)
                    "Failed replacement should collapse replacement node to compact presentation")
            (assert (= (. view.node-by-point fallback-point) second)
                    "Failed replacement should map fallback point to replacement node")
            (assert (= (. view.node-by-point first-card) nil)
                    "Failed replacement should detach stale card reverse point mapping")
            (assert fallback-point.on-double-click
                    "Failed replacement should keep replacement node interactive")
            (assert first-state.dropped?
                    "Failed replacement should drop stale expanded widget")
            (view:drop)
            (graph:drop))))

(fn graph-removing-expanded-node-clears-persisted-presentation []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local presentations [])
            (local persistence {:saved-position (fn [_self _node] nil)
                                :saved-presentation (fn [_self _node] nil)
                                :saved-size (fn [_self _node] nil)
                                :set-size (fn [_self _node _size] nil)
                                :set-presentation (fn [_self node presentation]
                                                        (table.insert presentations [node.key presentation]))
                                :persist (fn [_self _points _force?] nil)
                                :schedule-save (fn [_self] nil)})
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx
                                    :persistence persistence}))
            (local node (Graph.GraphNode {:key "remove-expanded"
                                          :preview (tracked-preview {})}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local point (. view.points node))
            (point:on-double-click {})
            (assert (= (. presentations (length presentations) 2) :expanded)
                    "Expanding should persist expanded presentation")
            (graph:remove-nodes [node])
            (local last (. presentations (length presentations)))
            (assert (= (. last 1) "remove-expanded")
                    "Removing expanded node should update persisted presentation for node")
            (assert (= (. last 2) nil)
                    "Removing expanded node should clear persisted expanded presentation")
            (view:drop)
            (graph:drop))))

(fn graph-removing-expanded-node-unregisters-resizable []
    (local original-resizables app.resizables)
    (var unregistered nil)
    (set app.resizables
         {:register (fn [_self _target _opts] nil)
          :unregister (fn [_self key] (set unregistered key))
          :on-mouse-button-down (fn [_self _payload] false)
          :on-mouse-button-up (fn [_self _payload] nil)
          :on-mouse-motion (fn [_self _payload] nil)})
    (local (ok err) (pcall (fn []
                        (with-temp-data-dir
                            (fn [_root]
                                (local ctx (make-ctx))
                                (local graph (Graph {:with-start false}))
                                (local view (GraphView {:graph-map graph :ctx ctx}))
                                (local node (Graph.GraphNode {:key "remove-resize"
                                                              :preview (tracked-preview {})}))
                                (graph:add-node node {:position (glm.vec3 0 0 0)})
                                (local point (. view.points node))
                                (point:on-double-click {})
                                (local card (. view.points node))
                                (assert card._resize-target "Card should have a _resize-target")
                                (set unregistered nil)
                                (graph:remove-nodes [node])
                                (assert (= unregistered card._resize-target)
                                        "Removing expanded node should unregister its resize target")
                                (view:drop)
                                (graph:drop))))))
    (set app.resizables original-resizables)
    (when (not ok)
        (error err)))

(fn graph-removing-collapsed-node-clears-persisted-size []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local sizes [])
            (local persistence {:saved-position (fn [_self _node] nil)
                                :saved-presentation (fn [_self _node] nil)
                                :saved-size (fn [_self _node] nil)
                                :set-size (fn [_self node size]
                                                (table.insert sizes [node.key size]))
                                :set-presentation (fn [_self _node _presentation] nil)
                                :persist (fn [_self _points _force?] nil)
                                :schedule-save (fn [_self] nil)})
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx
                                    :persistence persistence}))
            (local node (Graph.GraphNode {:key "collapse-remove-size"
                                          :preview (tracked-preview {})}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local point (. view.points node))
            ;; Expand
            (point:on-double-click {})
            ;; Simulate a prior resize through persistence
            (persistence:set-size node (glm.vec3 50 30 0))
            ;; Collapse back via header bar collapse button
            (local card (. view.points node))
            (assert card._card-size "Should be expanded before collapse")
            (local collapse-button (. card.header-bar.children 3 :element))
            (collapse-button:on-click {})
            ;; Verify collapsed
            (local compact (. view.points node))
            (assert (not compact._card-size) "Should be collapsed")
            ;; Now remove - should still clear size even though collapsed
            (graph:remove-nodes [node])
            (local last-size (. sizes (length sizes)))
            (assert (= (. last-size 1) "collapse-remove-size")
                    "Removing collapsed node should clear persisted size for node")
            (assert (= (. last-size 2) nil)
                    "Removing collapsed node should set size to nil")
            (view:drop)
            (graph:drop))))

(fn expanded-card-header-buttons-work []
    (with-temp-data-dir
        (fn [_root]
            (local target {:children []
                           :add-panel-child (fn [self child]
                                               (table.insert self.children child)
                                               child)
                           :remove-panel-child (fn [_self _element] nil)})
            (local ctx (make-ctx))
            (var view nil)
            (local graph (Graph {:with-start false}))
            (register-graph-map-test-loaders graph ["header-button-test"])
            (local map (GraphMap.GraphMap {:graph graph :id "test-header-buttons"}))
            (var opened? false)
            (var menu-opened? false)
            (var menu-actions nil)
            (local original-menu-manager app.menu-manager)
            (set app.menu-manager {:open (fn [_self opts]
                                           (set menu-opened? true)
                                           (set menu-actions opts.actions))})
            (local (ok err)
                (pcall
                    (fn []
                        (local node (Graph.GraphNode {:key "header-button-test"
                                                      :view (fn [_node]
                                                                (set opened? true)
                                                                (fn [_ctx]
                                                                    {:layout (Layout {:name "header-open-test-view"})}))
                                                      :preview (tracked-preview {})}))
                        (set view (GraphView {:graph-map map
                                               :ctx ctx
                                               :view-target target}))
                        (map:add-node node {:position (glm.vec3 0 0 0)})
                        (local point (. view.points node))
                        (point:on-double-click {})
                        (local card (. view.points node))
                        (assert card._card-size "Should be expanded after double-click")
                        (assert card.header-bar "Expanded card should have a header bar")
                        (assert (= (length card.header-bar.children) 5)
                                "Header should have five children (title + spacer + three buttons)")
                        ;; Test open button
                        (local initial-children (length target.children))
                        (local open-button (. card.header-bar.children 4 :element))
                        (open-button:on-click {})
                        (assert opened? "Header open button should invoke node view builder")
                        (assert (> (length target.children) initial-children)
                                "Header open button should add node view to target")
                        (assert (= (ctx.focus.manager:get-focused-node) (. view.focus-nodes node))
                                "Header Open button should focus the graph node first")
                        ;; Test menu button
                        (local menu-button (. card.header-bar.children 5 :element))
                        (menu-button:on-click {})
                        (assert menu-opened? "Header menu button should open a menu")
                        (assert menu-actions "Header menu should include actions")
                        (assert (= (length menu-actions) 6) "Header menu should include Open, Copy key, Collapse, cube, Remove from Map, and separator")
                        (assert (= (. menu-actions 1 :name) "Open")) (assert (= (. menu-actions 2 :name) "Copy key"))
                        (assert (= (. menu-actions 3 :name) "Collapse")) (assert (= (. menu-actions 4 :name) "cube"))
                        (assert (= (. menu-actions 5 :name) "Remove from Map"))
                        (assert (= (. menu-actions 6 :type) :separator) "Header menu should keep a separator even without node-specific actions")
                        ;; Test collapse button
                        (local collapse-button (. card.header-bar.children 3 :element))
                        (collapse-button:on-click {})
                        (assert (not (. view.points node :_card-size))
                                "Header collapse button should collapse the card back to compact")
                        ;; Re-expand and test Remove from Map action
                        (local compact-after-collapse (. view.points node))
                        (compact-after-collapse:on-double-click {})
                        (assert (. view.points node :_card-size)
                                "Should be re-expanded after second double-click")
                        (local menu-button-2 (. (. view.points node :header-bar :children 5) :element))
                        (menu-button-2:on-click {})
                        (assert menu-actions "Re-expanded header menu should include actions")
                        ((. menu-actions 5 :fn) nil {})
                        (assert (not (map:lookup "header-button-test"))
                                "Remove from Map should remove the node from the map"))))
            (set app.menu-manager original-menu-manager)
            (when view (view:drop))
            (map:drop)
            (graph:drop)
            (when (not ok)
                (error err)))))

(fn expanded-card-skips-double-click-and-right-click-registration []
    (with-temp-data-dir
        (fn [_root]
            (local registrations {:left []
                                  :right []
                                  :double []})
            (local instrumented-clickables
              {:register (fn [_self obj] (table.insert registrations.left obj))
               :unregister (fn [_self obj] nil)
               :register-right-click (fn [_self obj] (table.insert registrations.right obj))
               :unregister-right-click (fn [_self obj] nil)
               :register-double-click (fn [_self obj] (table.insert registrations.double obj))
               :unregister-double-click (fn [_self obj] nil)})
            (local ctx (make-ctx {:clickables instrumented-clickables}))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (local node (Graph.GraphNode {:key "reg-test"
                                          :preview (tracked-preview {})}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local point (. view.points node))
            (point:on-double-click {})
            (local card (. view.points node))
            (assert card._card-size "Should be expanded")
            (var card-in-left? false)
            (var card-in-right? false)
            (var card-in-double? false)
            (each [_ obj (ipairs registrations.left)]
                (when (= obj card) (set card-in-left? true)))
            (each [_ obj (ipairs registrations.right)]
                (when (= obj card) (set card-in-right? true)))
            (each [_ obj (ipairs registrations.double)]
                (when (= obj card) (set card-in-double? true)))
            (assert card-in-left? "Expanded card should be registered for left-click (focus)")
            (assert (not card-in-right?) "Expanded card should NOT be registered for right-click")
            (assert (not card-in-double?) "Expanded card should NOT be registered for double-click")
            (view:drop)
            (graph:drop))))

(fn graph-point-right-click-opens-node-actions-menu []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (register-graph-map-test-loaders graph ["menu-node"])
            (local map (GraphMap.GraphMap {:graph graph :id "test-menu"}))
            (var opened nil)
            (var custom-invoked 0)
            (var cube-invoked 0) (var copied nil) (local gl (require :gl))
            (local original-menu-manager app.menu-manager)
            (local original-scene app.scene) (local original-clipboard-set gl.clipboard-set)
            (set app.menu-manager {:open (fn [_self opts]
                                            (set opened opts))})
            (set app.scene {:add-graph-node-cube (fn [_self opts]
                                                    (set cube-invoked (+ cube-invoked 1))
                                                    (assert (and opts opts.node
                                                                 (= opts.node.key "menu-node"))
                                                            "Cube action should forward the selected graph node"))})
            (set gl.clipboard-set (fn [value] (set copied value)))
            (local node (Graph.GraphNode {:key "menu-node"
                                          :actions [{:name "Custom Action"
                                                     :icon "build"
                                                     :fn (fn [_button _event]
                                                             (set custom-invoked (+ custom-invoked 1)))}]}))
            (local view (GraphView {:graph-map map
                                    :ctx ctx}))
            (map:add-node node {:position (glm.vec3 10 12 0)})
            (local point (. view.points node))
            (assert point.on-right-click "GraphView should attach right click handler to node point")
            (point:on-right-click {:point (glm.vec3 3 4 0)})
            (assert opened "Right click should open a menu")
            (assert (= (length opened.actions) 7) "Node menu should include Open, Copy key, Expand, cube, Remove from Map, separator, and custom actions")
            (assert (= (. opened.actions 1 :name) "Open")) (assert (= (. opened.actions 2 :name) "Copy key"))
            (assert (= (. opened.actions 3 :name) "Expand")) (assert (= (. opened.actions 4 :name) "cube"))
            (assert (= (. opened.actions 5 :name) "Remove from Map")) (assert (= (. opened.actions 6 :type) :separator) "Node menu should separate graph actions from node-specific actions")
            (assert (= (. opened.actions 7 :name) "Custom Action")) ((. opened.actions 2 :fn) nil {})
            (assert (= copied "menu-node") "Copy key action should copy the selected graph node key")
            ((. opened.actions 4 :fn) nil {})
            (assert (= cube-invoked 1)
                    "Cube action should create one scene graph-node cube")
            ((. opened.actions 7 :fn) nil {})
            (assert (= custom-invoked 1)
                    "Custom node action should be callable from the context menu after separator")
            ((. opened.actions 5 :fn) nil {})
            (assert (not (map:lookup "menu-node"))
                    "Remove from Map action should remove the node from the map")
            (view:drop)
            (map:drop)
            (graph:drop)
            (set app.menu-manager original-menu-manager)
            (set app.scene original-scene) (set gl.clipboard-set original-clipboard-set))))

(fn graph-point-right-click-uses-menu-manager-created-later []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (var opened nil)
            (local original-menu-manager app.menu-manager)
            (set app.menu-manager nil)
            (local node (Graph.GraphNode {:key "late-menu-node"}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx}))
            (graph:add-node node {:position (glm.vec3 1 1 0)})
            (set app.menu-manager {:open (fn [_self opts]
                                           (set opened opts))})
            (local point (. view.points node))
            (point:on-right-click {:point (glm.vec3 7 8 0)})
            (assert opened
                    "GraphView should resolve app.menu-manager at click time")
            (view:drop)
            (graph:drop)
            (set app.menu-manager original-menu-manager))))

(fn fs-node-actions-include-edit-only-for-files []
    (with-temp-data-dir
        (fn [_root]
            (with-temp-dir
                (fn [root]
                    (local file-path (fs.join-path root "note.txt"))
                    (local dir-path (fs.join-path root "child"))
                    (fs.create-dirs dir-path)
                    (fs.write-file file-path "hello")
                    (local file-node (FsNode {:path file-path}))
                    (local dir-node (FsNode {:path dir-path}))
                    (local file-actions (file-node:actions))
                    (local dir-actions (dir-node:actions))
                    (local has-edit
                           (fn [actions]
                               (var found false)
                               (each [_ action (ipairs (or actions []))]
                                   (when (= action.name "Edit")
                                       (set found true)))
                               found))
                    (assert (has-edit file-actions)
                            "FsNode actions should include Edit for files")
                    (assert (not (has-edit dir-actions))
                            "FsNode actions should omit Edit for directories"))))))

(fn graph-node-view-dialog-table-action-adds-table-node []
    (with-temp-data-dir
        (fn [_root]
            (local unwrap-element
                   (fn [item]
                       (or (and item item.element) item)))
            (local ctx (make-ctx))
            (local target {:build-context ctx
                           :children []
                           :add-panel-child (fn [self opts]
                                              (local builder (and opts opts.builder))
                                              (assert builder "builder required")
                                              (local dialog (builder self.build-context {}))
                                              (table.insert self.children dialog)
                                              dialog)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))})
            (local graph (Graph {}))
            (local node ((require :graph/nodes/start))) (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local views (GraphViewNodeViews {:ctx ctx
                                              :view-target target}))
            (views:open node)
            (assert (= (length target.children) 1)
                    "Node view should attach a dialog")
            (local dialog (. target.children 1))
            (local titlebar (unwrap-element (. dialog.children 1)))
            (local title-flex (unwrap-element (. titlebar.children 2)))
            (local action-row (unwrap-element (. title-flex.children (length title-flex.children))))
            (assert (= (length action-row.children) 3)
                    "Node view dialog should include table, code, and close actions")
            (local table-button (unwrap-element (. action-row.children 1)))
            (local code-button (unwrap-element (. action-row.children 2)))
            (assert (= table-button.icon "table")
                    "Table action should be first")
            (assert (= code-button.icon "code")
                    "Code action should be second")
            (table-button:on-click {:button 1})
            (local table-key (.. "table:node-view-dialog:" (tostring dialog)))
            (local table-node (graph:lookup table-key))
            (assert table-node
                    "Table action should add a table node for the node view module")
            (assert (= table-node.table dialog)
                    "Table action should use the actual node view dialog table")
            (assert (= (graph:edge-count) 1)
                    "Table action should add one edge")
            (views:drop-all)
            (graph:drop))))

(fn graph-selection-emits-changed []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx
                                    :selector selector}))
            (local node (Graph.GraphNode {:key "n"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local point (. view.points node))
            (var changes 0)
            (local handler (view.selected-nodes-changed:connect (fn [_]
                                                                    (set changes (+ changes 1)))))
            (selector:set-selected [point])
            (assert (= (length view.selected-nodes) 1)
                    "GraphView should mirror selector selection")
            (assert (= changes 1)
                    "Selection change should emit through selected-nodes-changed")
            (selector:set-selected [])
            (view.selected-nodes-changed:disconnect handler true)
            (view:drop)
            (graph:drop)
            (selector:drop))))

(fn graph-view-rebuilds-from-double-click []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local selector (ObjectSelector {:project (fn [position _opts] position)
                                             :ctx ctx
                                             :enabled? true}))
            (local target {:children []
                           :add-panel-child (fn [self opts]
                                              (table.insert self.children opts)
                                              opts)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))})
            (local graph (Graph {:with-start false}))
            (local view-controller (GraphView {:graph-map graph
                                               :view-target target
                                               :ctx ctx
                                               :selector selector}))
            (local node (Graph.GraphNode {:key "n"
                                           :view (fn [_node]
                                                     (fn [_ctx]
                                                         {:layout {:position (glm.vec3 0 0 0)
                                                                   :size (glm.vec2 0 0)
                                                                   :rotation (glm.quat 1 0 0 0)}}))
                                           :preview (tracked-preview {})}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local point (. view-controller.points node))
            (assert point.on-double-click "GraphView should attach double click handler to node point")
            (point:on-double-click {})
            (local card (. view-controller.points node))
            (assert card._card-size "Double click should expand the graph node inline")
            (assert card.view-widget "Expanded graph node should build its view widget")
            (view-controller:drop)
            (assert (= (length target.children) 0)
                    "Inline node expansion should not open target panel views")
            (local view-controller-2 (GraphView {:graph-map graph
                                                  :view-target target
                                                  :ctx ctx
                                                  :selector selector}))
            (local point-2 (. view-controller-2.points node))
            (assert point-2._card-size "Recreating view controller should restore expanded inline node")
            (assert point-2.view-widget "Restored expanded node should rebuild its view widget")
            (view-controller-2:drop)
            (graph:drop)
            (selector:drop))))

(fn graph-view-node-views-hosts-heightfield-perlin-tool-dialog [] (assert app.clickables "heightfield dialog test requires app.clickables") (assert app.hoverables "heightfield dialog test requires app.hoverables")
    (with-temp-data-dir
        (fn [_root]
            (local {:HeightfieldPerlinToolNode HeightfieldPerlinToolNode}
                   (require :graph/nodes/heightfield-perlin-tool))
            (local States (require :states))
            (local TerrainRectPickState (require :terrain-rect-pick-state))
            (local Clickables (require :clickables))
            (local Hoverables (require :hoverables))
            (local original-hud app.hud)
            (local original-scene app.scene)
            (local original-clickables (assert app.clickables "heightfield dialog test requires app.clickables"))
            (local original-hoverables (assert app.hoverables "heightfield dialog test requires app.hoverables"))
            (local original-intersectables app.intersectables)
            (local original-screen-pos-ray app.screen-pos-ray)
            (local original-movables app.movables)
            (local original-resizables app.resizables)
            (local original-fpc app.first-person-controls)
            (local original-terrain-rect-pick-session app.terrain-rect-pick-session)
            (local original-states app.states)
            (var suspended-state nil)
            (local terrain-record (make-heightfield-terrain-record))
            (local scene
              {:screen-pos-terrain-domain-hit
               (fn [_self pos _opts]
                 (if (< pos.x 20)
                     {:terrain-id "terrain-a"
                      :terrain-kind "heightfield-terrain"
                      :terrain-record terrain-record
                      :local-point (glm.vec3 1 0 2)}
                     {:terrain-id "terrain-a"
                      :terrain-kind "heightfield-terrain"
                      :terrain-record terrain-record
                      :local-point (glm.vec3 3 0 4)}))
               :screen-rect-terrain-target
               (fn [_self _terrain-id start-pos end-pos _opts]
                 (if (and (< start-pos.x 20) (< end-pos.x 20))
                     {:terrain-id "terrain-a"
                      :terrain-kind "heightfield-terrain"
                      :terrain-record terrain-record
                      :target {:mode :samples :shape :rect :x0 1 :z0 2 :x1 1 :z1 2 :sample-count 1 :width 1 :length 1}}
                     {:terrain-id "terrain-a"
                      :terrain-kind "heightfield-terrain"
                      :terrain-record terrain-record
                      :target {:mode :samples :shape :rect :x0 1 :z0 2 :x1 3 :z1 4 :sample-count 12 :width 3 :length 4}}))})
            (local runtime {:scene scene})
            (local entry (make-world-entry {:id "world-a"
                                            :runtime runtime
                                            :state {:scene {:panels []
                                                            :terrains [terrain-record]}
                                                    :hud {:panels []}}}))
            (local manager (make-world-manager {:entry entry}))
            (set app.intersectables (Intersectables))
            (set app.clickables (Clickables {:intersectables app.intersectables}))
            (set app.hoverables (Hoverables {:intersectables app.intersectables}))
            (set app.screen-pos-ray
                 (fn [pointer]
                     {:origin (glm.vec3 (or pointer.x 0) (or pointer.y 0) 10)
                      :direction (glm.vec3 0 0 -1)}))
            (set app.movables {:on-mouse-button-down (fn [_self _payload] nil)
                               :on-mouse-button-up (fn [_self _payload] nil)
                               :on-mouse-motion (fn [_self _payload] nil)
                               :drag-active? (fn [_self] false)})
            (set app.resizables {:on-mouse-button-down (fn [_self _payload] false)
                                 :on-mouse-button-up (fn [_self _payload] nil)
                                 :on-mouse-motion (fn [_self _payload] nil)
                                 :drag-active? (fn [_self] false)})
            (set app.first-person-controls {:on-mouse-button-down (fn [_self _payload] nil)
                                            :on-mouse-button-up (fn [_self _payload] nil)
                                            :on-mouse-motion (fn [_self _payload] nil)
                                            :drag-active? (fn [_self] false)})
            (local ctx (make-ctx))
            (local target {:build-context ctx
                           :world-units-per-pixel 1
                           :children []
                           :add-panel-child (fn [self opts]
                                              (local builder (and opts opts.builder))
                                              (assert builder "builder required")
                                              (local dialog (builder self.build-context {}))
                                              (table.insert self.children dialog)
                                              dialog)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))})
            (set app.hud target)
            (set app.scene scene)
            (local states (States))
            (states:add-state :normal {})
            (states:add-state :terrain-rect-pick (TerrainRectPickState))
            (states:set-state :normal)
            (set suspended-state (TestSupport.suspend-active-state original-states))
            (set-app-states! states)
            (local graph (Graph {:with-start false}))
            (local node (HeightfieldPerlinToolNode {:world-id "world-a"
                                                    :activity-id "sandbox"
                                                    :world-manager manager
                                                    :terrain-id "terrain-a"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local views (GraphViewNodeViews {:graph-map graph
                                              :ctx ctx
                                              :view-target target}))
            (views:open node)
            (assert (= (length target.children) 1)
                    "GraphViewNodeViews should host the terrain tool in a dialog")
            (local dialog (. target.children 1))
            (local body-card (unwrap-element (. dialog.children 2)))
            (local body-content (unwrap-element (. body-card.children 2)))
            (local tool-view (or (and body-content body-content.child) body-content))
            (assert tool-view "Expected terrain tool view inside hosted dialog")
            (assert tool-view.pick-button "Hosted terrain tool should expose pick button")
            (tool-view.pick-button:on-click {})
            (assert (= (app.states:active-name) :terrain-rect-pick)
                    "Hosted terrain tool pick should enter the terrain rectangle pick state")
            (assert app.terrain-rect-pick-session
                    "Hosted terrain tool pick should register the active terrain rectangle pick session")
            (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
            (app.engine.events.mouse-motion.emit {:x 40 :y 60})
            (app.engine.events.mouse-button-up.emit {:button 1 :x 40 :y 60})
            (local draft (and tool-view.form (tool-view.form:get-draft)))
            (local picked-target (and draft draft.picked-target))
            (assert picked-target)
            (assert (= picked-target.x0 1))
            (assert (= picked-target.z0 2))
            (assert (= picked-target.x1 3))
            (assert (= picked-target.z1 4))
            (assert-codepoints-eq (tool-view.selection-label:get-codepoints)
                                  (TextUtils.codepoints-from-text "12 samples across [1, 2] to [3, 4]"))
            (assert (= (app.states:active-name) :normal)
                    "Hosted terrain tool pick should restore the previous state after completion")
            (views:drop-all)
            (graph:drop)
            (set app.hud original-hud)
            (set app.scene original-scene)
            (set app.clickables original-clickables)
            (set app.hoverables original-hoverables)
            (set app.intersectables original-intersectables)
            (set app.screen-pos-ray original-screen-pos-ray)
            (set app.movables original-movables)
            (set app.resizables original-resizables)
            (set app.first-person-controls original-fpc)
            (set-app-states! original-states)
            (TestSupport.resume-active-state suspended-state)
            (set app.terrain-rect-pick-session original-terrain-rect-pick-session))))


(fn graph-view-node-views-clickables-drive-heightfield-perlin-tool-pick [] (assert app.clickables "heightfield clickables test requires app.clickables") (assert app.hoverables "heightfield clickables test requires app.hoverables")
    (with-temp-data-dir
        (fn [_root]
            (local {:HeightfieldPerlinToolNode HeightfieldPerlinToolNode}
                   (require :graph/nodes/heightfield-perlin-tool))
            (local States (require :states))
            (local TerrainRectPickState (require :terrain-rect-pick-state))
            (local Clickables (require :clickables))
            (local Hoverables (require :hoverables))
            (local original-hud app.hud)
            (local original-scene app.scene)
            (local original-clickables (assert app.clickables "heightfield clickables test requires app.clickables"))
            (local original-hoverables (assert app.hoverables "heightfield clickables test requires app.hoverables"))
            (local original-intersectables app.intersectables)
            (local original-screen-pos-ray app.screen-pos-ray)
            (local original-movables app.movables)
            (local original-resizables app.resizables)
            (local original-fpc app.first-person-controls)
            (local original-terrain-rect-pick-session app.terrain-rect-pick-session)
            (local original-states app.states)
            (var suspended-state nil)
            (local terrain-record (make-heightfield-terrain-record))
            (local scene
              {:screen-pos-terrain-domain-hit
               (fn [_self pos _opts]
                 (if (< pos.x 20)
                     {:terrain-id "terrain-a"
                      :terrain-kind "heightfield-terrain"
                      :terrain-record terrain-record
                      :local-point (glm.vec3 1 0 2)}
                     {:terrain-id "terrain-a"
                      :terrain-kind "heightfield-terrain"
                      :terrain-record terrain-record
                      :local-point (glm.vec3 3 0 4)}))
               :screen-rect-terrain-target
               (fn [_self _terrain-id start-pos end-pos _opts]
                 (if (and (< start-pos.x 20) (< end-pos.x 20))
                     {:terrain-id "terrain-a"
                      :terrain-kind "heightfield-terrain"
                      :terrain-record terrain-record
                      :target {:mode :samples :shape :rect :x0 1 :z0 2 :x1 1 :z1 2 :sample-count 1 :width 1 :length 1}}
                     {:terrain-id "terrain-a"
                      :terrain-kind "heightfield-terrain"
                      :terrain-record terrain-record
                      :target {:mode :samples :shape :rect :x0 1 :z0 2 :x1 3 :z1 4 :sample-count 12 :width 3 :length 4}}))})
            (local runtime {:scene scene})
            (local entry (make-world-entry {:id "world-a"
                                            :runtime runtime
                                            :state {:scene {:panels []
                                                            :terrains [terrain-record]}
                                                    :hud {:panels []}}}))
            (local manager (make-world-manager {:entry entry}))
            (set app.intersectables (Intersectables))
            (set app.clickables (Clickables {:intersectables app.intersectables}))
            (set app.hoverables (Hoverables {:intersectables app.intersectables}))
            (set app.screen-pos-ray
                 (fn [pointer]
                     {:origin (glm.vec3 (or pointer.x 0) (or pointer.y 0) 10)
                      :direction (glm.vec3 0 0 -1)}))
            (set app.movables {:on-mouse-button-down (fn [_self _payload] nil)
                               :on-mouse-button-up (fn [_self _payload] nil)
                               :on-mouse-motion (fn [_self _payload] nil)
                               :drag-active? (fn [_self] false)})
            (set app.resizables {:on-mouse-button-down (fn [_self _payload] false)
                                 :on-mouse-button-up (fn [_self _payload] nil)
                                 :on-mouse-motion (fn [_self _payload] nil)
                                 :drag-active? (fn [_self] false)})
            (set app.first-person-controls {:on-mouse-button-down (fn [_self _payload] nil)
                                            :on-mouse-button-up (fn [_self _payload] nil)
                                            :on-mouse-motion (fn [_self _payload] nil)
                                            :drag-active? (fn [_self] false)})
            (local ctx (make-ctx))
            (local target {:build-context ctx
                           :world-units-per-pixel 1
                           :children []
                           :add-panel-child (fn [self opts]
                                              (local builder (and opts opts.builder))
                                              (assert builder "builder required")
                                              (local dialog (builder self.build-context {}))
                                              (table.insert self.children dialog)
                                              dialog)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))})
            (set app.hud target)
            (set app.scene scene)
            (local states (States))
            (states:add-state :normal {})
            (states:add-state :terrain-rect-pick (TerrainRectPickState))
            (states:set-state :normal)
            (set suspended-state (TestSupport.suspend-active-state original-states))
            (set-app-states! states)
            (local graph (Graph {:with-start false}))
            (local node (HeightfieldPerlinToolNode {:world-id "world-a"
                                                    :activity-id "sandbox"
                                                    :world-manager manager
                                                    :terrain-id "terrain-a"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local views (GraphViewNodeViews {:graph-map graph
                                              :ctx ctx
                                              :view-target target}))
            (views:open node)
            (local dialog (. target.children 1))
            (local body-card (unwrap-element (. dialog.children 2)))
            (local body-content (unwrap-element (. body-card.children 2)))
            (local tool-view (or (and body-content body-content.child) body-content))
            (local button tool-view.pick-button)
            (assert button "Expected terrain tool pick button")
            (local original-intersect button.intersect)
            (set button.intersect
                 (fn [_self _ray]
                     (values true (glm.vec3 0 0 0) 0.0)))
            (app.clickables:on-mouse-button-down {:button 1 :x 5 :y 5 :timestamp 10})
            (app.clickables:on-mouse-button-up {:button 1 :x 5 :y 5 :timestamp 10})
            (assert (= (app.states:active-name) :terrain-rect-pick)
                    "clickables-driven pick button should enter the terrain rectangle pick state")
            (assert app.terrain-rect-pick-session
                    "clickables-driven pick button should register the active terrain rectangle pick session")
            (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
            (app.engine.events.mouse-motion.emit {:x 40 :y 60})
            (app.engine.events.mouse-button-up.emit {:button 1 :x 40 :y 60})
            (local draft (and tool-view.form (tool-view.form:get-draft)))
            (local picked-target (and draft draft.picked-target))
            (assert picked-target)
            (assert (= picked-target.x0 1))
            (assert (= picked-target.z0 2))
            (assert (= picked-target.x1 3))
            (assert (= picked-target.z1 4))
            (assert-codepoints-eq (tool-view.selection-label:get-codepoints)
                                  (TextUtils.codepoints-from-text "12 samples across [1, 2] to [3, 4]"))
            (set button.intersect original-intersect)
            (views:drop-all)
            (graph:drop)
            (set app.hud original-hud)
            (set app.scene original-scene)
            (set app.clickables original-clickables)
            (set app.hoverables original-hoverables)
            (set app.intersectables original-intersectables)
            (set app.screen-pos-ray original-screen-pos-ray)
            (set app.movables original-movables)
            (set app.resizables original-resizables)
            (set app.first-person-controls original-fpc)
            (set-app-states! original-states)
            (TestSupport.resume-active-state suspended-state)
            (set app.terrain-rect-pick-session original-terrain-rect-pick-session))))


(fn graph-view-node-views-engine-events-drive-heightfield-perlin-tool-pick [] (assert app.clickables "heightfield engine-events test requires app.clickables") (assert app.hoverables "heightfield engine-events test requires app.hoverables")
    (with-temp-data-dir
        (fn [_root]
            (local {:HeightfieldPerlinToolNode HeightfieldPerlinToolNode}
                   (require :graph/nodes/heightfield-perlin-tool))
            (local States (require :states))
            (local TerrainRectPickState (require :terrain-rect-pick-state))
            (local NormalState (require :normal-state))
            (local Clickables (require :clickables))
            (local Hoverables (require :hoverables))
            (local original-hud app.hud)
            (local original-scene app.scene)
            (local original-clickables (assert app.clickables "heightfield engine-events test requires app.clickables"))
            (local original-hoverables (assert app.hoverables "heightfield engine-events test requires app.hoverables"))
            (local original-intersectables app.intersectables)
            (local original-screen-pos-ray app.screen-pos-ray)
            (local original-movables app.movables)
            (local original-resizables app.resizables)
            (local original-fpc app.first-person-controls)
            (local original-terrain-rect-pick-session app.terrain-rect-pick-session)
            (local original-states app.states)
            (var suspended-state nil)
            (local terrain-record (make-heightfield-terrain-record))
            (local scene
              {:screen-pos-terrain-domain-hit
               (fn [_self pos _opts]
                 (if (< pos.x 20)
                     {:terrain-id "terrain-a"
                      :terrain-kind "heightfield-terrain"
                      :terrain-record terrain-record
                      :local-point (glm.vec3 1 0 2)}
                     {:terrain-id "terrain-a"
                      :terrain-kind "heightfield-terrain"
                      :terrain-record terrain-record
                      :local-point (glm.vec3 3 0 4)}))
               :screen-rect-terrain-target
               (fn [_self _terrain-id start-pos end-pos _opts]
                 (if (and (< start-pos.x 20) (< end-pos.x 20))
                     {:terrain-id "terrain-a"
                      :terrain-kind "heightfield-terrain"
                      :terrain-record terrain-record
                      :target {:mode :samples :shape :rect :x0 1 :z0 2 :x1 1 :z1 2 :sample-count 1 :width 1 :length 1}}
                     {:terrain-id "terrain-a"
                      :terrain-kind "heightfield-terrain"
                      :terrain-record terrain-record
                      :target {:mode :samples :shape :rect :x0 1 :z0 2 :x1 3 :z1 4 :sample-count 12 :width 3 :length 4}}))})
            (local runtime {:scene scene})
            (local entry (make-world-entry {:id "world-a"
                                            :runtime runtime
                                            :state {:scene {:panels []
                                                            :terrains [terrain-record]}
                                                    :hud {:panels []}}}))
            (local manager (make-world-manager {:entry entry}))
            (set app.intersectables (Intersectables))
            (set app.clickables (Clickables {:intersectables app.intersectables}))
            (set app.hoverables (Hoverables {:intersectables app.intersectables}))
            (set app.screen-pos-ray
                 (fn [pointer]
                     {:origin (glm.vec3 (or pointer.x 0) (or pointer.y 0) 10)
                      :direction (glm.vec3 0 0 -1)}))
            (set app.movables {:on-mouse-button-down (fn [_self _payload] nil)
                               :on-mouse-button-up (fn [_self _payload] nil)
                               :on-mouse-motion (fn [_self _payload] nil)
                               :drag-active? (fn [_self] false)})
            (set app.resizables {:on-mouse-button-down (fn [_self _payload] false)
                                 :on-mouse-button-up (fn [_self _payload] nil)
                                 :on-mouse-motion (fn [_self _payload] nil)
                                 :drag-active? (fn [_self] false)})
            (set app.first-person-controls {:on-mouse-button-down (fn [_self _payload] nil)
                                            :on-mouse-button-up (fn [_self _payload] nil)
                                            :on-mouse-motion (fn [_self _payload] nil)
                                            :drag-active? (fn [_self] false)})
            (local ctx (make-ctx))
            (local target {:build-context ctx
                           :world-units-per-pixel 1
                           :children []
                           :add-panel-child (fn [self opts]
                                              (local builder (and opts opts.builder))
                                              (assert builder "builder required")
                                              (local dialog (builder self.build-context {}))
                                              (table.insert self.children dialog)
                                              dialog)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))})
            (set app.hud target)
            (set app.scene scene)
            (local states (States))
            (states:add-state :normal (NormalState))
            (states:add-state :terrain-rect-pick (TerrainRectPickState))
            (states:set-state :normal)
            (set suspended-state (TestSupport.suspend-active-state original-states))
            (set-app-states! states)
            (local graph (Graph {:with-start false}))
            (local node (HeightfieldPerlinToolNode {:world-id "world-a"
                                                    :activity-id "sandbox"
                                                    :world-manager manager
                                                    :terrain-id "terrain-a"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local views (GraphViewNodeViews {:graph-map graph
                                              :ctx ctx
                                              :view-target target}))
            (views:open node)
            (local dialog (. target.children 1))
            (local body-card (unwrap-element (. dialog.children 2)))
            (local body-content (unwrap-element (. body-card.children 2)))
            (local tool-view (or (and body-content body-content.child) body-content))
            (local button tool-view.pick-button)
            (assert button "Expected terrain tool pick button")
            (local original-intersect button.intersect)
            (set button.intersect
                 (fn [_self _ray]
                     (values true (glm.vec3 0 0 0) 0.0)))
            (app.engine.events.mouse-button-down.emit {:button 1 :x 5 :y 5 :timestamp 10})
            (app.engine.events.mouse-button-up.emit {:button 1 :x 5 :y 5 :timestamp 10})
            (assert (= (app.states:active-name) :terrain-rect-pick)
                    "engine-event click should enter terrain rect pick state")
            (assert app.terrain-rect-pick-session
                    "engine-event click should register active terrain pick session")
            (app.engine.events.mouse-button-down.emit {:button 1 :x 10 :y 20})
            (app.engine.events.mouse-motion.emit {:x 40 :y 60})
            (app.engine.events.mouse-button-up.emit {:button 1 :x 40 :y 60})
            (local draft (and tool-view.form (tool-view.form:get-draft)))
            (local picked-target (and draft draft.picked-target))
            (assert picked-target)
            (assert (= picked-target.x0 1))
            (assert (= picked-target.z0 2))
            (assert (= picked-target.x1 3))
            (assert (= picked-target.z1 4))
            (assert-codepoints-eq (tool-view.selection-label:get-codepoints)
                                  (TextUtils.codepoints-from-text "12 samples across [1, 2] to [3, 4]"))
            (set button.intersect original-intersect)
            (views:drop-all)
            (graph:drop)
            (set app.hud original-hud)
            (set app.scene original-scene)
            (set app.clickables original-clickables)
            (set app.hoverables original-hoverables)
            (set app.intersectables original-intersectables)
            (set app.screen-pos-ray original-screen-pos-ray)
            (set app.movables original-movables)
            (set app.resizables original-resizables)
            (set app.first-person-controls original-fpc)
            (set-app-states! original-states)
            (TestSupport.resume-active-state suspended-state)
            (set app.terrain-rect-pick-session original-terrain-rect-pick-session))))

(fn graph-layout-module-updates-lines-and-labels []
    (with-temp-data-dir
        (fn [_root]
            (local a (Graph.GraphNode {:key "a"}))
            (local b (Graph.GraphNode {:key "b"}))
            (local point-a {:position (glm.vec3 0 0 0)})
            (local point-b {:position (glm.vec3 10 0 0)})
            (local points {})
            (set (. points a) point-a)
            (set (. points b) point-b)
            (local nodes {})
            (set (. nodes a.key) a)
            (set (. nodes b.key) b)
            (local layout (ForceLayout))
            (local nodes-by-index [])
            (local indices {})
            (local edges [])
            (local edge-map {})
            (var line-updates 0)
            (var last-line nil)
            (local make-line
                  (fn [_ctx _opts]
                      {:update (fn [_self start end]
                                    (set line-updates (+ line-updates 1))
                                    (set last-line {:start start :end end}))}))
            (var set-point-calls 0)
            (local set-point-position
                  (fn [node pos]
                      (set set-point-calls (+ set-point-calls 1))
                      (local point (. points node))
                      (assert point "GraphViewLayout test missing point")
                      (set point.position pos)))
            (var label-updates 0)
            (var label-refreshes 0)
            (local layout-module
                  (GraphViewLayout {:layout layout
                                          :nodes-by-index nodes-by-index
                                          :indices indices
                                          :nodes nodes
                                          :points points
                                          :edges edges
                                          :edge-map edge-map
                                          :make-line make-line
                                          :set-point-position set-point-position
                                          :update-labels (fn [_nodes _opts]
                                                             (set label-updates (+ label-updates 1)))
                                          :refresh-label-positions (fn [_nodes]
                                                                        (set label-refreshes (+ label-refreshes 1)))
                                          :get-position (fn [_self node]
                                                            (local point (. points node))
                                                            (and point point.position))}))
            (layout-module:add-node a (glm.vec3 0 0 0) false)
            (layout-module:add-node b (glm.vec3 10 0 0) false)
            (layout-module:add-edge (Graph.GraphEdge {:source a :target b}))
            (assert (= line-updates 1)
                    "GraphViewLayout should update lines after adding edge")
            (layout-module:set-node-position a (glm.vec3 5 0 0))
            (assert (= set-point-calls 1)
                    "GraphViewLayout should set point position when moving node")
            (assert (= line-updates 2)
                    "GraphViewLayout should update lines after moving node")
            (assert (= label-updates 1)
                    "GraphViewLayout should refresh labels when moving node")
            (assert (= label-refreshes 1)
                    "GraphViewLayout should refresh label positions when moving node")
            (assert last-line "GraphViewLayout should capture line updates")
            (assert (= (. last-line.start.x) 5)
                    "Line start should reflect moved node position")
            (layout:clear))))

(local light-card-background (glm.vec4 0.945 0.958 0.978 1))

(fn graph-expanded-card-uses-themed-background []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (set ctx.theme.card {:background light-card-background})
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (local node (Graph.GraphNode {:key "theme-card-node"
                                          :preview (tracked-preview {})}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local point (. view.points node))
            (point:on-double-click {})
            (local card (. view.points node))
            (assert card._card-size "Should be expanded")
            (assert card._background "Expanded card should have a background rectangle")
            (assert (= card._background.color.x light-card-background.x)
                    "Expanded card should use themed card background color (R)")
            (assert (= card._background.color.y light-card-background.y)
                    "Expanded card should use themed card background color (G)")
            (assert (= card._background.color.z light-card-background.z)
                    "Expanded card should use themed card background color (B)")
            (view:drop)
            (graph:drop))))

(fn graph-expanded-card-outlines-not-background-fill []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (set ctx.theme.card {:background light-card-background})
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (local node (Graph.GraphNode {:key "outline-node"
                                          :preview (tracked-preview {})}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local point (. view.points node))
            (point:on-double-click {})
            (local card (. view.points node))
            (assert card._card-size "Should be expanded")
            (assert card._focus-outline "Expanded card should have a focus outline")
            (assert card._selection-outline "Expanded card should have a selection outline")
            (local background-before card._background.color)
            (view.selection:set-selection [node])
            (assert (= card._background.color.x background-before.x)
                    "Selection should not change card background color (R)")
            (assert (= card._background.color.y background-before.y)
                    "Selection should not change card background color (G)")
            (assert (= card._background.color.z background-before.z)
                    "Selection should not change card background color (B)")
            (assert (> card._selection-layer-size 0)
                    "Selection should set selection layer size")
            (assert (card._selection-outline.visible?)
                    "Selection outline should be visible")
            (ctx.layout-root:update)
            (local sel-top (. card._selection-outline.strips 1))
            (assert (= sel-top.depth-offset-index
                       card.layout.depth-offset-index)
                    "Selection outline should be at card base depth")
            (assert (> sel-top.size.x 0)
                    "Selection outline top strip should have non-zero width")
            (assert (= sel-top.size.x
                       (+ (. card._background.layout.size 1) 1.0))
                    "Selection outline top strip should be 1.0 wider than background")
            (assert (< sel-top.position.x
                       card._background.layout.position.x)
                    "Selection outline top strip should be shifted left of background")
            (assert (< sel-top.depth-offset-index
                       card._background.layout.depth-offset-index)
                    "Selection outline should render behind card background")
            (local focus-node (. view.focus-nodes node))
            (assert focus-node "GraphView should create a focus node")
            (focus-node:request-focus)
            (assert (= card._background.color.x background-before.x)
                    "Focus should not change card background color (R)")
            (assert (> card._focus-layer-size 0)
                    "Focus should set focus layer size")
            (assert (card._focus-outline.visible?)
                    "Focus outline should be visible")
            (ctx.layout-root:update)
            (local foc-top (. card._focus-outline.strips 1))
            (assert (= foc-top.depth-offset-index
                       (+ card.layout.depth-offset-index 1))
                    "Focus outline should be above selection outline")
            (assert (> foc-top.size.x 0)
                    "Focus outline top strip should have non-zero width")
            (local sel-top-size (. (. card._selection-outline.strips 1) :size))
            (assert (< foc-top.size.x sel-top-size.x)
                    "Focus outline should be narrower than selection outline")
            (assert (< foc-top.depth-offset-index
                       card._background.layout.depth-offset-index)
                    "Focus outline should render behind card background")
            (assert (card._selection-outline.visible?)
                    "Selection outline should remain visible when focused")
            (assert (card._focus-outline.visible?)
                    "Focus outline should be visible when focused")
            (ctx.layout-root:update)
            (ctx.focus.manager:clear-focus)
            (ctx.layout-root:update)
            (assert (not (card._focus-outline.visible?))
                    "Focus outline should hide after focus released")
            (assert (card._selection-outline.visible?)
                    "Selection outline should remain visible after focus released")
            (view:drop)
            (graph:drop))))

(fn graph-expanded-card-custom-border-widths []
    (local ctx (make-ctx))
    (local node (Graph.GraphNode {:key "custom-border-node"
                                  :preview (tracked-preview {})}))
    (local GraphNodePresentation (require :graph/view/presentation))
    (local custom-focus-width 0.9)
    (local custom-selection-width 1.5)
    (local card-builder (GraphNodePresentation.card-builder
                         {:node node
                          :position (glm.vec3 0 0 0)
                          :size (glm.vec3 64.0 48.0 0)
                          :focus-border-width custom-focus-width
                          :selection-border-width custom-selection-width
                          :on-collapse (fn [] nil)
                          :on-open (fn [_] nil)
                          :on-menu (fn [_] nil)}))
    (local card (card-builder ctx))
    (assert card._card-size "Card should be built")
    (card:set-layer-size 2 1)
    (card:set-layer-size 1 1)
    (ctx.layout-root:update)
    (local sel-strip (. card._selection-outline.strips 1))
    (local foc-strip (. card._focus-outline.strips 1))
    (assert ((. MathUtils :approx) sel-strip.size.x
                   (+ (. card._background.layout.size 1) (* 2 custom-selection-width)))
            (.. "Selection outline should be " (* 2 custom-selection-width) " wider than background"))
    (assert ((. MathUtils :approx) foc-strip.size.x
                   (+ (. card._background.layout.size 1) (* 2 custom-focus-width)))
            (.. "Focus outline should be " (* 2 custom-focus-width) " wider than background"))
    (card:drop))

(fn graph-expanded-card-outline-strips-obey-clip-and-culling []
    (local ctx (make-ctx))
    (local {: Layout} (require :layout))
    (local node (Graph.GraphNode {:key "clip-cull-node"
                                  :preview (tracked-preview {})}))
    (local GraphNodePresentation (require :graph/view/presentation))
    (local card-builder (GraphNodePresentation.card-builder
                         {:node node
                          :position (glm.vec3 0 0 0)
                          :size (glm.vec3 64.0 48.0 0)
                          :on-collapse (fn [] nil)
                          :on-open (fn [_] nil)
                          :on-menu (fn [_] nil)}))
    (local card (card-builder ctx))
    (assert card._card-size "Card should be built")
    (card:set-layer-size 2 1)
    (ctx.layout-root:update)
    ;; clip-region propagation
    (local clip {:bounds {:position (glm.vec3 0 0 0) :size (glm.vec3 100 100 0)}})
    (set card.layout.clip-region clip)
    (card.layout:mark-layout-dirty)
    (ctx.layout-root:update)
    (local sel-strip (. card._selection-outline.strips 1))
    (assert sel-strip.clip-region
            "Selection outline strip should receive clip-region from card layout")
    (assert (= sel-strip.clip-region clip)
            "Selection outline strip clip-region should match card layout")
    ;; self-culling hides outlines
    (card.layout:set-self-culled true)
    (ctx.layout-root:update)
    (assert (not (card._selection-outline.visible?))
            "Selection outline strips should hide when card is self-culled")
    ;; uncull and verify outlines come back on next layout pass
    (card.layout:set-self-culled false)
    (card.layout:mark-layout-dirty)
    (ctx.layout-root:update)
    (assert (card._selection-outline.visible?)
            "Selection outline strips should reappear when card is unculled")
    (assert sel-strip.clip-region
            "Strip clip-region should be set after uncull re-layout")
    ;; parent culling also hides outlines
    (local parent-layout (Layout {:name "parent-cull-test"}))
    (parent-layout:set-root ctx.layout-root)
    (parent-layout:add-child card.layout)
    (set card.layout.clip-region clip)
    (card.layout:mark-layout-dirty)
    (ctx.layout-root:update)
    (assert (card._selection-outline.visible?)
            "Selection outline should be visible under unculled parent")
    (parent-layout:set-self-culled true)
    (ctx.layout-root:update)
    (assert (not (card._selection-outline.visible?))
            "Selection outline strips should hide when ancestor is culled")
    ;; when parent-culled, set-layer-size must not re-show outlines
    (card:set-layer-size 1 1)
    (ctx.layout-root:update)
    (assert (not (card._focus-outline.visible?))
            "Focus outline should stay hidden when layer set while parent-culled")
    ;; ancestor uncull restores outline visibility
    (parent-layout:set-self-culled false)
    (card.layout:mark-layout-dirty)
    (ctx.layout-root:update)
    (assert (card._selection-outline.visible?)
            "Selection outline strips should reappear when ancestor is unculled")
    (assert sel-strip.clip-region
            "Clip-region should be propagated after ancestor uncull re-layout")
    (parent-layout:clear-children)
    (parent-layout:drop)
    (card:drop))

(fn graph-expanded-card-auto-sizes []
    (local ctx (make-ctx))
    (local node (Graph.GraphNode {:key "auto-size-node"
                                  :preview (tracked-preview {})}))
    (local GraphNodePresentation (require :graph/view/presentation))
    (local card-builder (GraphNodePresentation.card-builder
                         {:node node
                          :position (glm.vec3 0 0 0)
                          :default-size (glm.vec3 28 16 0)
                          :min-size (glm.vec3 20 12 0)
                          :max-size (glm.vec3 40 26 0)
                          :on-collapse (fn [] nil)
                          :on-open (fn [_] nil)
                          :on-menu (fn [_] nil)}))
    (local card (card-builder ctx))
    (assert card._card-size "Card should be built")
    (ctx.layout-root:update)
    (assert (>= card._card-size.x card._min-size.x)
            "Card width should be at least min-size")
    (assert (<= card._card-size.x card._max-size.x)
            "Card width should be at most max-size")
    (assert (>= card._card-size.y card._min-size.y)
            "Card height should be at least min-size")
    (assert (<= card._card-size.y card._max-size.y)
            "Card height should be at most max-size")
    (card:drop))

(fn graph-expanded-card-set-size-overrides-auto []
    (local ctx (make-ctx))
    (local node (Graph.GraphNode {:key "set-size-node"
                                  :preview (tracked-preview {})}))
    (local GraphNodePresentation (require :graph/view/presentation))
    (local card-builder (GraphNodePresentation.card-builder
                         {:node node
                          :position (glm.vec3 0 0 0)
                          :default-size (glm.vec3 28 16 0)
                          :min-size (glm.vec3 20 12 0)
                          :max-size (glm.vec3 40 26 0)
                          :resize-max-size (glm.vec3 80 40 0)
                          :on-collapse (fn [] nil)
                          :on-open (fn [_] nil)
                          :on-menu (fn [_] nil)}))
    (local card (card-builder ctx))
    (assert card._card-size "Card should be built")
    (card:set-size (glm.vec3 60 30 0))
    (ctx.layout-root:update)
    (assert (= card._card-size.x 60.0)
            "Card width should respect set-size")
    (assert (= card._card-size.y 30.0)
            "Card height should respect set-size")
    ;; clamp to min
    (card:set-size (glm.vec3 10 5 0))
    (ctx.layout-root:update)
    (assert (= card._card-size.x card._min-size.x)
            "Card width should be clamped to min-size")
    (assert (= card._card-size.y card._min-size.y)
            "Card height should be clamped to min-size")
    ;; clamp to resize-max
    (card:set-size (glm.vec3 200 150 0))
    (ctx.layout-root:update)
    (assert (= card._card-size.x 80.0)
            "Card width should be clamped to resize-max-size")
    (assert (= card._card-size.y 40.0)
            "Card height should be clamped to resize-max-size")
    (card:drop))

(fn graph-expanded-card-resize-target-clamps-max-size []
    (local ctx (make-ctx))
    (local node (Graph.GraphNode {:key "max-clamp-node"
                                  :preview (tracked-preview {})}))
    (local GraphNodePresentation (require :graph/view/presentation))
    (local card-builder (GraphNodePresentation.card-builder
                         {:node node
                          :position (glm.vec3 40 30 0)
                          :default-size (glm.vec3 28 16 0)
                          :min-size (glm.vec3 20 12 0)
                          :max-size (glm.vec3 40 26 0)
                          :resize-max-size (glm.vec3 80 40 0)
                          :on-collapse (fn [] nil)
                          :on-open (fn [_] nil)
                          :on-menu (fn [_] nil)}))
    (local card (card-builder ctx))
    (ctx.layout-root:update)
    (local target card._resize-target)
    ;; Simulate right-edge resize: origin stays, size exceeds resize-max
    (local origin (glm.vec3 target.position.x target.position.y target.position.z))
    (target:set-transform {:size (glm.vec3 200 150 0) :position origin})
    (ctx.layout-root:update)
    (assert (<= target.size.x 80.0)
            "Target size.x should be clamped to resize-max-size.x")
    (assert (<= target.size.y 40.0)
            "Target size.y should be clamped to resize-max-size.y")
    (assert (= card._card-size.x target.size.x)
            "Card size should match clamped target size")
    ;; Position should not change for right-edge resize
    (assert (= target.position.x origin.x)
            "Target position.x should stay at origin for right-edge resize")
    (assert (= target.position.y origin.y)
            "Target position.y should stay at origin for right-edge resize")
    (card:drop))

(fn graph-expanded-card-registers-as-resizable []
    (local original-resizables app.resizables)
    (var registered-target nil)
    (var registered-opts nil)
    (set app.resizables
         {:register (fn [_self target opts]
                      (set registered-target target)
                      (set registered-opts opts))
          :unregister (fn [_self _key] nil)
          :on-mouse-button-down (fn [_self _payload] false)
          :on-mouse-button-up (fn [_self _payload] nil)
          :on-mouse-motion (fn [_self _payload] nil)})
    (local (ok err) (pcall (fn []
                        (with-temp-data-dir
                            (fn [_root]
                                (local ctx (make-ctx))
                                (local graph (Graph {:with-start false}))
                                (local view (GraphView {:graph-map graph :ctx ctx}))
                                (local node (Graph.GraphNode {:key "resizable-node"
                                                              :preview (tracked-preview {})}))
                                (graph:add-node node {:position (glm.vec3 0 0 0)})
                                (local point (. view.points node))
                                (point:on-double-click {})
                                (local card (. view.points node))
                                (assert card._card-size "Should be expanded")
                                (assert card._resize-target "Card should have a _resize-target")
                                (assert (= registered-target card._resize-target)
                                        "Resize target should be the card's _resize-target, not the card itself")
                                (assert (= (type registered-opts.target.size) :userdata)
                                        "Resize target size should be a vec3")
                                (assert registered-opts.on-resize-start "Should have on-resize-start callback")
                                (assert registered-opts.on-resize-end "Should have on-resize-end callback")
                                (view:drop)
                                (graph:drop))))))
    (set app.resizables original-resizables)
    (when (not ok)
        (error err)))

(local approx (. MathUtils :approx))

(fn graph-view-updates-selection-and-focus-borders []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (local node (Graph.GraphNode {:key "border-node" :size 8}))
            (graph:add-node node {:position (glm.vec3 0 0 0) :run-force? false})
            (local point (. view.points node))
            (assert point "GraphView should create a point for node")
            (local focus-layer (. point.layers 1))
            (local selection-layer (. point.layers 2))
            (local base-layer (. point.layers 3))
            (assert (approx focus-layer.size 0) "Focus border should start hidden")
            (assert (approx selection-layer.size 0) "Selection border should start hidden")
            (view.selection:set-selection [node])
            (assert (> selection-layer.size base-layer.size)
                    "Selection border should be larger than the base point")
            (local focus-node (. view.focus-nodes node))
            (assert focus-node "GraphView should create a focus node for each point")
            (focus-node:request-focus)
            (assert (> focus-layer.size selection-layer.size)
                    "Focus border should be outside selection border when both are active")
            (view:drop)
            (graph:drop))))

(fn graph-view-autofocus-updates-focus-ring []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local focus-manager (. ctx.focus :manager))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (local node (Graph.GraphNode {:key "auto-focus-node" :size 6}))
            (focus-manager:arm-auto-focus {:event {:mod 0}})
            (graph:add-node node {:position (glm.vec3 0 0 0) :run-force? false})
            (local point (. view.points node))
            (assert point "GraphView should create a point for auto-focused node")
            (local focus-layer (. point.layers 1))
            (assert (> focus-layer.size 0) "Auto-focused node should show focus ring")
            (local focus-node (. view.focus-nodes node))
            (assert focus-node "GraphView should create a focus node for auto-focused node")
            (assert (= (focus-manager:get-focused-node) focus-node)
                    "Auto-focused node should be the focused node")
            (view:drop)
            (graph:drop))))

(fn graph-view-click-focuses-node-under-logical-input-scaling [] (assert app.clickables "graph focus scaling test requires app.clickables") (assert app.hoverables "graph focus scaling test requires app.hoverables")
    (with-temp-data-dir
        (fn [_root]
            (local Clickables (require :clickables))
            (local Hoverables (require :hoverables))
            (local original-engine app.engine)
            (local original-viewport app.viewport)
            (local original-clickables (assert app.clickables "graph focus scaling test requires app.clickables"))
            (local original-hoverables (assert app.hoverables "graph focus scaling test requires app.hoverables"))
            (local original-intersectables app.intersectables)
            (var view nil)
            (var graph nil)
            (local (ok err)
                (pcall
                    (fn []
                        (set app.engine {:width 100 :height 50})
                        (set app.viewport {:x 0 :y 0 :width 200 :height 100})
                        (set app.intersectables (Intersectables))
                        (set app.clickables (Clickables {:intersectables app.intersectables}))
                        (set app.hoverables (Hoverables {:intersectables app.intersectables}))
                        (local pointer-target
                            {:screen-pos-ray (fn [_self pointer _opts]
                                                  (local viewport (viewport-utils.to-table app.viewport))
                                                  (local screen (viewport-utils.input-pos->viewport-pos pointer viewport app.engine))
                                                  {:origin (glm.vec3 (or (and screen screen.x) 0)
                                                                     (or (and screen screen.y) 0)
                                                                     10)
                                                   :direction (glm.vec3 0 0 -1)})})
                        (local ctx (make-ctx))
                        (local focus-manager (. ctx.focus :manager))
                        (set graph (Graph {:with-start false}))
                        (set view (GraphView {:graph-map graph
                                              :ctx ctx
                                              :pointer-target pointer-target}))
                        (local node (Graph.GraphNode {:key "logical-click-focus"
                                                      :size 8}))
                        (graph:add-node node {:position (glm.vec3 40 50 0)
                                              :run-force? false})
                        (local focus-node (. view.focus-nodes node))
                        (assert focus-node "GraphView should create a focus node for the clickable point")
                        (app.clickables:on-mouse-button-down {:button 1
                                                              :x 20
                                                              :y 25
                                                              :timestamp 10})
                        (app.clickables:on-mouse-button-up {:button 1
                                                            :x 20
                                                            :y 25
                                                            :timestamp 10})
                        (assert (= (focus-manager:get-focused-node) focus-node)
                                "GraphView point click should request focus after logical input is scaled into viewport space"))))
            (when view
                (view:drop))
            (when graph
                (graph:drop))
            (set app.engine original-engine)
            (set app.viewport original-viewport)
            (set app.clickables original-clickables)
            (set app.hoverables original-hoverables)
            (set app.intersectables original-intersectables)
            (when (not ok)
                (error err)))))

(fn graph-movables-module-registers-and-cleans-up []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local registered [])
            (local unregistered [])
            (var scheduled 0)
            (local persistence {:saved-position (fn [_self _node] nil)
                                :saved-presentation (fn [_self _node] nil)
                                :saved-size (fn [_self _node] nil)
                                :set-size (fn [_self _node _size] nil)
                                :set-presentation (fn [_self _node _presentation]
                                                        (set scheduled (+ scheduled 1)))
                                :persist (fn [_self _points _force?] nil)
                                :schedule-save (fn [_self]
                                                    (set scheduled (+ scheduled 1)))})
            (local movables {:register (fn [_self point opts]
                                          (table.insert registered {:point point :opts opts}))
                             :unregister (fn [_self node]
                                             (table.insert unregistered node))})
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx
                                    :movables movables
                                    :persistence persistence}))
            (local node (Graph.GraphNode {:key "movable"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (assert (= (length registered) 1)
                    "GraphView should register nodes with GraphViewMovables")
            (local opts (. (. registered 1) :opts))
            (assert opts "Movables registration should include options")
            (local on-drag-end (and opts opts.on-drag-end))
            (assert on-drag-end "Movables registration should include drag end handler")
            (on-drag-end {})
            (assert (= scheduled 1) "Drag end should schedule persistence save")
            (graph:remove-nodes [node])
            (assert (= (length unregistered) 1)
                    "GraphView should unregister movables when removing nodes")
            (assert (not (. view.movable-targets node))
                    "GraphView should clear movable targets after removal")
            (view:drop)
            (graph:drop))))

(fn graph-nodes-are-movable []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local intersector (Intersectables))
            (local movables (Movables {:intersectables intersector}))
            (local original-movables app.movables)
            (local original-ray app.screen-pos-ray)
            (local original-camera app.camera)
            (local original-active-surface app.active-interaction-surface)
            (local original-scene-interactive? app.scene-interactive?)
            (local original-canvas-interactive? app.canvas-interactive?)
            (set app.movables movables)
            (set app.screen-pos-ray
                 (fn [pointer]
                      {:origin (glm.vec3 (or (and pointer pointer.x) 0) 0 10)
                       :direction (glm.vec3 0 0 -1)}))
            (set app.camera nil)
            (set app.active-interaction-surface :scene)
            (set app.scene-interactive? true)
            (set app.canvas-interactive? false)
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx
                                    :movables movables}))
            (local node (Graph.GraphNode {:key "drag"}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (movables:on-mouse-button-down {:button 1 :x 0 :y 0})
            (movables:on-mouse-motion {:x 20 :y 0})
            (assert (movables:drag-active?) "Drag should start when clicking a graph node")
            (movables:on-mouse-button-up {:button 1 :x 20 :y 0})
            (local position (view:get-position node))
            (assert position "GraphView should expose node position after drag")
            (assert (> position.x 1.5) "Graph node should follow drag ray")
            (local idx (. view.indices node))
            (local positions (view.layout:get-positions))
            (when (and positions idx)
                (local layout-pos (. positions (+ idx 1)))
                (assert layout-pos "Force layout should store node position")
                (assert (approx layout-pos.x position.x)
                        "Force layout position should match dragged position"))
            (view:drop)
            (graph:drop)
            (movables:drop)
            (set app.movables original-movables)
            (set app.screen-pos-ray original-ray)
            (set app.camera original-camera)
            (set app.active-interaction-surface original-active-surface)
            (set app.scene-interactive? original-scene-interactive?)
            (set app.canvas-interactive? original-canvas-interactive?))))

(fn graph-drag-respects-force-layout-position []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local intersector (Intersectables))
            (local movables (Movables {:intersectables intersector}))
            (local original-movables app.movables)
            (local original-ray app.screen-pos-ray)
            (local original-active-surface app.active-interaction-surface)
            (local original-scene-interactive? app.scene-interactive?)
            (local original-canvas-interactive? app.canvas-interactive?)
            (set app.movables movables)
            (set app.screen-pos-ray
                 (fn [pointer]
                     {:origin (glm.vec3 (or (and pointer pointer.x) 0)
                                    (or (and pointer pointer.y) 0)
                                     10)
                       :direction (glm.vec3 0 0 -1)}))
            (set app.active-interaction-surface :scene)
            (set app.scene-interactive? true)
            (set app.canvas-interactive? false)
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph
                                    :ctx ctx
                                    :movables movables}))
            (local a (Graph.GraphNode {:key "a"}))
            (local b (Graph.GraphNode {:key "b"}))
            (view.layout:set-bounds (glm.vec3 -200 -200 0) (glm.vec3 200 200 0))
            (graph:add-node a {:position (glm.vec3 -120 0 0)})
            (graph:add-node b {:position (glm.vec3 120 0 0)})
            (graph:add-edge (Graph.GraphEdge {:source a :target b}))
            (view:update 40)
            (local before (view:get-position a))
            (assert before "GraphView should expose node position after layout update")
            (movables:on-mouse-button-down {:button 1 :x before.x :y before.y})
            (movables:on-mouse-motion {:x (+ before.x 20) :y before.y})
            (movables:on-mouse-button-up {:button 1 :x (+ before.x 20) :y before.y})
            (local after (view:get-position a))
            (assert after "GraphView should expose node position after drag")
            (assert (> after.x before.x) "Drag should move node forward from its current layout position")
            (movables:drop)
            (view:drop)
            (graph:drop)
            (set app.movables original-movables)
            (set app.screen-pos-ray original-ray)
            (set app.active-interaction-surface original-active-surface)
            (set app.scene-interactive? original-scene-interactive?)
            (set app.canvas-interactive? original-canvas-interactive?))))

(fn graph-persistence-rejects-unsafe-map-id []
    (with-temp-data-dir
        (fn [root]
            (local unsafe-ids ["." "/" ".." "a.b" "a/b" "a\\b"])
            (each [_ unsafe-id (ipairs unsafe-ids)]
                (var caught? false)
                (pcall (fn []
                           (GraphViewPersistence {:data-dir root :map-id unsafe-id})
                           (set caught? true)))
                (assert (not caught?)
                        (.. "GraphViewPersistence should reject unsafe map-id: " unsafe-id)))
            (var caught-empty? false)
            (pcall (fn []
                       (GraphViewPersistence {:data-dir root :map-id ""})
                       (set caught-empty? true)))
            (assert (not caught-empty?)
                    "GraphViewPersistence should reject empty map-id")
            (var caught-number? false)
            (pcall (fn []
                       (GraphViewPersistence {:data-dir root :map-id 123})
                       (set caught-number? true)))
            (assert (not caught-number?)
                    "GraphViewPersistence should reject numeric map-id"))))

(fn graph-persistence-class-saves-and-restores []
    (with-temp-data-dir
        (fn [root]
            (local persistence (GraphViewPersistence {:data-dir root}))
            (local node {:key "persist-me"})
            (local point {:position (glm.vec3 5 6 7)})
            (persistence:schedule-save)
            (persistence:persist {node point} false)
            (local reloaded (GraphViewPersistence {:data-dir root}))
            (local restored (reloaded:saved-position node))
            (assert restored "GraphViewPersistence should restore saved position")
            (assert (= restored.x 5))
            (assert (= restored.y 6))
            (assert (= restored.z 7))
            (set point.position (glm.vec3 8 9 10))
            (persistence:persist {node point} false)
            (local stale (GraphViewPersistence {:data-dir root}))
            (local stale-pos (stale:saved-position node))
            (assert (= stale-pos.x 5) "Persist should wait for schedule or force")
            (persistence:persist {node point} true)
            (local updated (GraphViewPersistence {:data-dir root}))
            (local updated-pos (updated:saved-position node))
            (assert (= updated-pos.x 8))
            (assert (= updated-pos.y 9))
            (assert (= updated-pos.z 10)))))

(fn graph-persistence-filters-wrong-map-panels []
    (with-temp-data-dir
        (fn [root]
            (local graph-dir (fs.join-path (fs.join-path (fs.join-path root "graph") "maps") "main"))
            (fs.create-dirs graph-dir)
            (local metadata-path (fs.join-path graph-dir "metadata.json"))
            (JsonUtils.write-json! metadata-path
                                   {:positions {}
                                    :panels [{:kind "graph-node-view"
                                              :node-key "keep"
                                              :graph-map-id "main"}
                                             {:kind "graph-node-view"
                                              :node-key "drop"
                                              :graph-map-id "other"}]
                                    :extra_panels [{:kind "graph-node-cube"
                                                    :node-key "cube-keep"
                                                    :graph-map-id "main"}
                                                   {:kind "graph-node-cube"
                                                    :node-key "cube-drop"
                                                    :graph-map-id "other"}]})
            (local persistence (GraphViewPersistence {:data-dir root :map-id "main"}))
            (local panels (persistence:saved-panels))
            (local extra-panels (persistence:saved-extra-panels))
            (assert (= (length panels) 1)
                    "GraphViewPersistence should filter wrong-map node-view panels")
            (assert (= (. panels 1 :node-key) "keep"))
            (assert (= (length extra-panels) 1)
                    "GraphViewPersistence should filter wrong-map extra panels")
            (assert (= (. extra-panels 1 :node-key) "cube-keep"))
            (local compacted (json.loads (fs.read-file metadata-path)))
            (assert (= (length compacted.panels) 1)
                    "GraphViewPersistence should compact wrong-map panels on disk")
            (assert (= (. compacted.panels 1 :node-key) "keep"))
            (assert (= (length compacted.extra_panels) 1)
                    "GraphViewPersistence should compact wrong-map extra panels on disk")
            (assert (= (. compacted.extra_panels 1 :node-key) "cube-keep")))))

(fn graph-view-accepts-transitional-graph-option []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph graph :ctx ctx}))
            (assert view "GraphView should accept documented transitional :graph option")
            (view:drop)
            (graph:drop))))

(fn graph-view-restores-extra-panel-size-and-rotation []
    (with-temp-data-dir
        (fn [_root]
            (local original-scene app.scene)
            (var captured nil)
            (local (ok err)
                (pcall
                    (fn []
                        (set app.scene {:add-graph-node-cube
                                        (fn [_self opts]
                                            (set captured opts)
                                            {:ok true})})
                        (local ctx (make-ctx))
                        (local graph (Graph {:with-start false}))
                        (local graph-map (GraphMap.GraphMap {:graph graph :id "cube-map"}))
                        (local view (GraphView {:graph-map graph-map :ctx ctx}))
                        (view:restore-state {:extra_panels [{:kind "graph-node-cube"
                                                             :node-key "cube-node"
                                                             :graph-map-id "cube-map"
                                                             :panel {:node-key "cube-node"
                                                                     :size [7 8 9]
                                                                     :rotation [0.5 0.5 0.5 0.5]}}]})
                        (assert captured "GraphView should call scene graph-node-cube restorer")
                        (assert (= captured.size.x 7)
                                "GraphView should restore extra panel size x")
                        (assert (= captured.size.y 8)
                                "GraphView should restore extra panel size y")
                        (assert (= captured.size.z 9)
                                "GraphView should restore extra panel size z")
                        (assert (= captured.rotation.w 0.5)
                                 "GraphView should restore extra panel rotation")
                        (assert (= (length view.extra-panels) 1)
                                "Restored cube extra panel should remain registered for capture")
                        (assert (= (length view.extra-panel-runtimes) 1)
                                "Restored cube extra panel should keep runtime target and element")
                        (local captured-state (view:capture-state))
                        (assert (= (length captured-state.extra_panels) 1)
                                "GraphView capture should preserve restored cube extra panel")
                        (assert (= (. captured-state.extra_panels 1 :node-key) "cube-node"))
                        (view:drop)
                        (graph-map:drop)
                        (graph:drop))))
            (set app.scene original-scene)
            (when (not ok)
                (error err)))))

(fn graph-view-extra-panel-restore-errors-on-missing-restorer []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local graph-map (GraphMap.GraphMap {:graph graph :id "main"}))
            (local view (GraphView {:graph-map graph-map :ctx ctx}))
            (local (ok err)
                (pcall (fn []
                         (view:restore-state
                           {:extra_panels [{:kind "missing-extra-panel"
                                            :node-key "missing-node"
                                            :graph-map-id "main"
                                            :restorer-module "graph/view/views/not-a-real-restorer"}]}))))
            (assert (not ok)
                    "GraphView extra panel restore should fail on missing restorer module")
            (assert (string.find (tostring err) "failed requiring extra panel restorer module" 1 true)
                    "GraphView extra panel restore error should identify bad restorer module")
            (view:drop)
            (graph-map:drop)
            (graph:drop))))

(fn graph-view-cube-extra-panel-restore-errors-without-scene-restorer []
    (with-temp-data-dir
        (fn [_root]
            (local original-scene app.scene)
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local graph-map (GraphMap.GraphMap {:graph graph :id "main"}))
            (local view (GraphView {:graph-map graph-map :ctx ctx}))
            (set app.scene nil)
            (local (ok err)
                (pcall (fn []
                         (view:restore-state
                           {:extra_panels [{:kind "graph-node-cube"
                                            :node-key "cube-node"
                                            :graph-map-id "main"}]}))))
            (set app.scene original-scene)
            (assert (not ok)
                    "GraphView graph-node-cube extra panel restore should fail without scene restorer")
            (assert (string.find (tostring err) "requires app.scene.add-graph-node-cube" 1 true)
                    "GraphView graph-node-cube extra panel restore error should identify missing scene restorer")
            (view:drop)
            (graph-map:drop)
            (graph:drop))))


(fn graph-restores-saved-node-position []
    (with-temp-data-dir
        (fn [root]
            (local graph-dir (fs.join-path root "graph-view"))
            (fs.create-dirs graph-dir)
            (local metadata-path (fs.join-path graph-dir "metadata.json"))
            (JsonUtils.write-json! metadata-path {:positions {:persisted [12 34 0]}})
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (local node (Graph.GraphNode {:key "persisted"}))
            (graph:add-node node {})
            (local pos (view:get-position node))
            (assert pos "GraphView should expose restored node position")
            (assert (= pos.x 12))
            (assert (= pos.y 34))
            (assert (= pos.z 0))
            (view:drop)
            (graph:drop))))

(fn graph-saves-positions-after-stabilizing []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (local a (Graph.GraphNode {:key "a"}))
            (local b (Graph.GraphNode {:key "b"}))
            (graph:add-node a {:position (glm.vec3 -60 0 0)})
            (graph:add-node b {:position (glm.vec3 60 0 0)})
            (graph:add-edge (Graph.GraphEdge {:source a :target b}))
            (local graph-dir (fs.join-path (fs.join-path (appdirs.user-data-dir "space") "graph" "maps") "main"))
            (local metadata-path (fs.join-path graph-dir "metadata.json"))
            (for [i 1 200]
                (view:update 0.016))
            (assert (fs.exists metadata-path)
                    "GraphView should persist positions after stabilizing force layout")
            (local saved (json.loads (fs.read-file metadata-path)))
            (assert (and saved saved.positions)
                    "Graph metadata should include positions table")
            (assert (. saved.positions "a")
                    "GraphView should save positions keyed by node key")
            (view:drop)
            (graph:drop))))

(fn graph-keeps-saved-positions-when-rebuilt []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (local node (Graph.GraphNode {:key "sticky"}))
            (graph:add-node node {:position (glm.vec3 7 9 0)})
            (view:drop)
            (graph:drop)
            (local graph2 (Graph {:with-start false}))
            (local view2 (GraphView {:graph-map graph2 :ctx (make-ctx)}))
            (local node2 (Graph.GraphNode {:key "sticky"}))
            (graph2:add-node node2 {})
            (local pos (view2:get-position node2))
            (assert pos "GraphView should restore position for rebuilt node")
            (assert (= pos.x 7))
            (assert (= pos.y 9))
            (assert (= pos.z 0))
            (view2:drop)
            (graph2:drop))))

(fn graph-view-batches-restore-graph-state []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (graph:register-key-loader
                "test"
                (fn [key]
                    (local id (string.match key "^test:(.+)$"))
                    (when id
                        (Graph.GraphNode {:key key
                                          :label id}))))
            (local graph-map (GraphMap.GraphMap {:graph graph}))
            (local view (GraphView {:graph-map graph-map :ctx ctx}))
            (local original-start view.graph-layout.start)
            (local original-label-update view.labels.update)
            (var start-count 0)
            (var label-update-count 0)
            (set view.graph-layout.start
                 (fn [self]
                     (set start-count (+ start-count 1))
                     (original-start self)))
            (set view.labels.update
                 (fn [self points nodes opts]
                     (set label-update-count (+ label-update-count 1))
                     (original-label-update self points nodes opts)))
            (view:restore-graph-state
                {:nodes ["test:a" "test:b"]
                 :edges [{:source "test:a"
                          :target "test:b"}]})
            (assert (= start-count 1)
                    "GraphView restore should start layout once for the whole batch")
            (assert (= label-update-count 1)
                    "GraphView restore should refresh labels once for the whole batch")
            (assert (= (graph-map:node-count) 2))
            (assert (= (graph-map:edge-count) 1))
            (assert (. view.points (graph-map:lookup "test:a")))
            (assert (. view.points (graph-map:lookup "test:b")))
            (view:drop)
            (graph-map:drop)
            (graph:drop))))

(fn graph-view-updates-node-labels-without-lod-change []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local camera {:position (glm.vec3 0 0 0)})
            (local view (GraphView {:graph-map graph
                                    :ctx ctx
                                    :camera camera}))
            (local node (Graph.GraphNode {:key "label-node"
                                          :label "first"}))
            (set node.changed (Signal))
            (graph:add-node node {:position (glm.vec3 0 0 0)
                                  :run-force? false})
            (local span (. view.labels.labels node))
            (assert span "GraphView should create a label for each node")
            (assert-codepoints-eq (span:get-codepoints)
                                  (TextUtils.codepoints-from-text "first")
                                  "Initial label should reflect node label")
            (set node.label "second")
            (node.changed:emit node)
            (local span-after (. view.labels.labels node))
            (assert (= span-after span) "GraphView should reuse the existing label widget")
            (assert-codepoints-eq (span-after:get-codepoints)
                                  (TextUtils.codepoints-from-text "second")
                                  "GraphView should update labels when node label changes")
            (view:drop)
            (graph:drop))))

(table.insert tests {:name "GraphView draws triangle edge between nodes" :fn edge-produces-triangles})
(table.insert tests {:name "Start node view adds quit node edge" :fn start-node-view-adds-quit-node})
(table.insert tests {:name "Start node view adds fs node edge" :fn start-node-view-adds-fs-node})
(table.insert tests {:name "Start node view adds table node edge" :fn start-node-view-adds-table-node})
(table.insert tests {:name "GraphView seeds new nodes at layout center" :fn nodes-default-to-center-position})
(table.insert tests {:name "Quit node view invokes handler" :fn quit-node-view-invokes-handler})
(table.insert tests {:name "Llm conversation view adds message node" :fn llm-conversation-view-adds-message-node})
(table.insert tests {:name "Llm message view updates node fields" :fn llm-message-view-updates-node-fields})
(table.insert tests {:name "Llm conversations view builds" :fn llm-conversations-view-builds})
(table.insert tests {:name "Llm node view adds conversations" :fn llm-node-view-adds-conversations})
(table.insert tests {:name "Fs node view adds edges for entries" :fn fs-node-view-adds-child-nodes-for-entries})
(table.insert tests {:name "Fs node view ripgrep button opens prefilled view"
                     :fn fs-node-view-ripgrep-button-opens-ripgrep-view-with-prefilled-path})
(table.insert tests {:name "Llm conversation view opens messages panel using context target"
                     :fn llm-conversation-view-opens-messages-panel-using-context-target})
(table.insert tests {:name "Fs node actions open code-dir for directories"
                     :fn fs-node-actions-open-code-dir-for-directories})
(table.insert tests {:name "Fs node actions open fnl-module for .fnl files"
                     :fn fs-node-actions-open-fnl-module-for-fnl-files})
(table.insert tests {:name "GraphMap fs code actions use loader-backed nodes"
                     :fn graph-map-fs-code-actions-use-loader-backed-nodes})
(table.insert tests {:name "Code dir node view adds edges for dir and module entries"
                     :fn code-dir-node-view-adds-subdir-and-module-nodes})
(table.insert tests {:name "Fnl module node view adds dependency module edge"
                     :fn fnl-module-node-view-adds-required-module-node})
(table.insert tests {:name "Cpp module node view adds included module edge"
                     :fn cpp-module-node-view-adds-included-module-node})
(table.insert tests {:name "Text module node view exposes actions and references"
                     :fn text-module-node-view-exposes-edit-and-open-parent-actions})
(table.insert tests {:name "Table node view adds edges for entries" :fn table-node-view-adds-child-nodes})
(table.insert tests {:name "GraphView removes selected nodes and related edges" :fn graph-removes-selected-nodes-and-edges})
(table.insert tests {:name "GraphView removing node closes live scene cube panel" :fn graph-removing-node-closes-live-scene-cube-panel})
(table.insert tests {:name "GraphView expands node inline on double click" :fn graph-expands-node-inline-on-double-click})
(table.insert tests {:name "GraphView expanded card uses preview and measures child"
                      :fn graph-expanded-card-uses-preview-and-measures-child})
(table.insert tests {:name "Graph expanded card header shows truncated node label" :fn graph-expanded-card-header-shows-truncated-node-label})
(table.insert tests {:name "GraphView expanded toggle preserves selection"
                      :fn graph-expanded-toggle-preserves-selection})
(table.insert tests {:name "GraphView expanded toggle preserves node center"
                     :fn graph-expanded-toggle-preserves-node-center})
(table.insert tests {:name "GraphView remove then expand keeps selector list synchronized"
                     :fn graph-remove-then-expand-keeps-selector-list-synchronized})
(table.insert tests {:name "GraphView failed expanded toggle keeps compact point"
                     :fn graph-expanded-toggle-failure-keeps-compact-point})
(table.insert tests {:name "GraphView expanded card rebuilds preview for replacement"
                      :fn graph-expanded-card-rebuilds-preview-for-replacement})
(table.insert tests {:name "GraphView compact replacement refreshes focus binding"
                      :fn graph-compact-replacement-refreshes-focus-binding})
(table.insert tests {:name "GraphView expanded replacement preserves selection"
                      :fn graph-expanded-card-replacement-preserves-selection})
(table.insert tests {:name "GraphView failed replacement collapses to compact"
                      :fn graph-expanded-card-replacement-failure-collapses-to-compact})
(table.insert tests {:name "GraphView node view replacement preserves panel placement"
                      :fn graph-node-view-replacement-preserves-panel-placement})
(table.insert tests {:name "GraphView removing expanded node clears persisted presentation"
                      :fn graph-removing-expanded-node-clears-persisted-presentation})
(table.insert tests {:name "GraphView removing expanded node unregisters resize target"
                      :fn graph-removing-expanded-node-unregisters-resizable})
(table.insert tests {:name "GraphView removing collapsed node clears persisted size"
                      :fn graph-removing-collapsed-node-clears-persisted-size})
(table.insert tests {:name "GraphView expanded card header buttons work"
                     :fn expanded-card-header-buttons-work})
(table.insert tests {:name "GraphView expanded card skips double-click and right-click registration"
                     :fn expanded-card-skips-double-click-and-right-click-registration})
(table.insert tests {:name "GraphView node point right-click opens node actions"
                     :fn graph-point-right-click-opens-node-actions-menu})
(table.insert tests {:name "GraphView right-click resolves late menu manager"
                     :fn graph-point-right-click-uses-menu-manager-created-later})
(table.insert tests {:name "FsNode actions include edit only for files"
                     :fn fs-node-actions-include-edit-only-for-files})
(table.insert tests {:name "Graph node view dialog table action adds table node"
                     :fn graph-node-view-dialog-table-action-adds-table-node})
(table.insert tests {:name "GraphView emits selection changes" :fn graph-selection-emits-changed})
(table.insert tests {:name "GraphView does not subscribe to raw engine updates"
                     :fn graph-view-does-not-subscribe-to-raw-engine-updates})
(table.insert tests {:name "GraphView update after drop errors"
                     :fn graph-view-update-after-drop-errors})
(table.insert tests {:name "GraphView double drop errors"
                     :fn graph-view-double-drop-errors})
(table.insert tests {:name "GraphView public API errors after drop"
                      :fn graph-view-public-api-errors-after-drop})
(table.insert tests {:name "GraphView updates selection and focus borders" :fn graph-view-updates-selection-and-focus-borders})
(table.insert tests {:name "GraphView auto-focus updates focus ring" :fn graph-view-autofocus-updates-focus-ring})
(table.insert tests {:name "GraphView point click focuses node under logical input scaling"
                     :fn graph-view-click-focuses-node-under-logical-input-scaling})
(table.insert tests {:name "Graph view rebuilds views from double click" :fn graph-view-rebuilds-from-double-click})
(table.insert tests {:name "GraphView node views host heightfield perlin tool dialog"
                     :fn graph-view-node-views-hosts-heightfield-perlin-tool-dialog})
(table.insert tests {:name "GraphView node views clickables drive heightfield perlin tool pick"
                     :fn graph-view-node-views-clickables-drive-heightfield-perlin-tool-pick})
(table.insert tests {:name "GraphView node views engine events drive heightfield perlin tool pick"
                     :fn graph-view-node-views-engine-events-drive-heightfield-perlin-tool-pick})
(table.insert tests {:name "GraphViewLayout updates lines and labels" :fn graph-layout-module-updates-lines-and-labels})
(table.insert tests {:name "GraphView expanded card uses themed background" :fn graph-expanded-card-uses-themed-background})
(table.insert tests {:name "GraphView expanded card outlines instead of background fill" :fn graph-expanded-card-outlines-not-background-fill})
(table.insert tests {:name "GraphView expanded card custom border widths" :fn graph-expanded-card-custom-border-widths})
(table.insert tests {:name "GraphView expanded card outline strips obey clip and culling" :fn graph-expanded-card-outline-strips-obey-clip-and-culling})
(table.insert tests {:name "GraphView expanded card auto-sizes within min and max" :fn graph-expanded-card-auto-sizes})
(table.insert tests {:name "GraphView expanded card set-size overrides auto size" :fn graph-expanded-card-set-size-overrides-auto})
(table.insert tests {:name "GraphView expanded card resize-target clamps max size" :fn graph-expanded-card-resize-target-clamps-max-size})
(table.insert tests {:name "GraphView expanded card registers as resizable" :fn graph-expanded-card-registers-as-resizable})
(table.insert tests {:name "Graph movables register and clean up drag targets" :fn graph-movables-module-registers-and-cleans-up})
(table.insert tests {:name "Graph nodes register with movables for dragging" :fn graph-nodes-are-movable})
(table.insert tests {:name "Graph drag respects latest force layout position" :fn graph-drag-respects-force-layout-position})
(table.insert tests {:name "GraphViewPersistence rejects unsafe map-id" :fn graph-persistence-rejects-unsafe-map-id})
(table.insert tests {:name "GraphViewPersistence saves and restores positions" :fn graph-persistence-class-saves-and-restores})
(table.insert tests {:name "GraphViewPersistence filters wrong-map panels" :fn graph-persistence-filters-wrong-map-panels})
(table.insert tests {:name "GraphView accepts transitional graph option" :fn graph-view-accepts-transitional-graph-option})
(table.insert tests {:name "GraphView restores extra panel size and rotation" :fn graph-view-restores-extra-panel-size-and-rotation})
(table.insert tests {:name "GraphView extra panel restore errors on missing restorer"
                      :fn graph-view-extra-panel-restore-errors-on-missing-restorer})
(table.insert tests {:name "GraphView cube extra panel restore requires scene restorer"
                     :fn graph-view-cube-extra-panel-restore-errors-without-scene-restorer})
(table.insert tests {:name "Graph restores saved node position" :fn graph-restores-saved-node-position})
(table.insert tests {:name "GraphView saves positions after force layout stabilizes" :fn graph-saves-positions-after-stabilizing})
(table.insert tests {:name "GraphView keeps saved positions when rebuilt" :fn graph-keeps-saved-positions-when-rebuilt})
(table.insert tests {:name "GraphView batches restore graph state" :fn graph-view-batches-restore-graph-state})
(table.insert tests {:name "GraphView updates node labels without LOD change" :fn graph-view-updates-node-labels-without-lod-change})
(fn graph-view-capture-restore-selected-node-keys []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local node (Graph.GraphNode {:key "a" :label "A"}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (graph:add-node node {:position (glm.vec3 0 0 0)})
            (local state (view:capture-state))
            (assert (= (type state.selected_node_keys) :table)
                    "capture-state should emit selected_node_keys")
            (assert (= (length state.selected_node_keys) 0)
                    "capture-state should emit empty selected_node_keys when nothing selected")
            (view:drop)
            (graph:drop))))

(fn graph-view-capture-restore-preserves-selection []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (local a (Graph.GraphNode {:key "a" :label "A"}))
            (local b (Graph.GraphNode {:key "b" :label "B"}))
            (local view (GraphView {:graph-map graph :ctx ctx}))
            (graph:add-node a {:position (glm.vec3 0 0 0)})
            (graph:add-node b {:position (glm.vec3 10 0 0)})
            (view.selection:set-selection [a b])
            (local captured (view:capture-state))
            (assert (= (length captured.selected_node_keys) 2)
                    "capture-state should include selected node keys")
            (view.selection:set-selection [])
            (assert (= (length view.selected-nodes) 0)
                    "selection should be cleared before restore")
            (view:restore-state captured)
            (assert (= (length view.selected-nodes) 2)
                    "restore-state should restore selection from captured selected_node_keys")
            (view:drop)
            (graph:drop))))

(fn graph-node-view-capture-includes-graph-map-id []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local target {:children []
                           :add-panel-child (fn [self opts]
                                               (table.insert self.children opts)
                                               opts)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))})
            (local graph (Graph {:with-start false}))
            (register-graph-map-test-loaders graph ["scoped-node"])
            (local graph-map (GraphMap.GraphMap {:graph graph :id "scoped-map"}))
            (local node (Graph.GraphNode {:key "scoped-node"
                                          :view (fn [_node]
                                                  (fn [_ctx]
                                                      {:layout (Layout {:name "scoped-node-view"})}))}))
            (local view (GraphView {:graph-map graph-map
                                    :ctx ctx
                                    :view-target target}))
            (graph-map:add-node node)
            (view.views:open node)
            (local state (view:capture-state))
            (local panel (. state.views.open-views 1))
            (assert (= panel.graph-map-id "scoped-map")
                    "Captured graph node panel should include graph-map-id")
            (view:drop)
            (graph-map:drop)
            (graph:drop))))

(fn graph-view-capture-persists-node-view-panels []
    (with-temp-data-dir
        (fn [root]
            (local ctx (make-ctx))
            (local target {:children []
                           :add-panel-child (fn [self opts]
                                               (table.insert self.children opts)
                                               opts)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))
                           :capture-panel-element-state (fn [_self _element]
                                                          {:position [11 12 0]
                                                           :size [40 20 0]})})
            (local graph (Graph {:with-start false}))
            (register-graph-map-test-loaders graph ["persist-node"])
            (local graph-map (GraphMap.GraphMap {:graph graph :id "persist-panels"}))
            (local node (Graph.GraphNode {:key "persist-node"
                                          :view (fn [_node]
                                                  (fn [_ctx]
                                                      {:layout (Layout {:name "persist-node-view"})}))}))
            (local view (GraphView {:graph-map graph-map
                                    :ctx ctx
                                    :view-target target}))
            (graph-map:add-node node)
            (view.views:open node)
            (view:capture-state)
            (local reloaded (GraphViewPersistence {:data-dir root :map-id "persist-panels"}))
            (local panels (reloaded:saved-panels))
            (local panel (. panels 1))
            (local panel-placement (and panel panel.panel))
            (assert (= (length panels) 1)
                    "GraphView capture-state should persist one node-view panel")
            (assert (= panel.node-key "persist-node")
                    "Persisted node-view panel should keep node-key")
            (assert (= panel.graph-map-id "persist-panels")
                    "Persisted node-view panel should keep graph-map-id")
            (assert (= (. panel-placement.position 1) 11)
                    "Persisted node-view panel should keep captured placement")
            (view:drop)
            (graph-map:drop)
            (graph:drop))))

(fn graph-view-restore-rejects-unscoped-node-view-panel []
    (with-temp-data-dir
        (fn [_root]
            (local ctx (make-ctx))
            (local graph (Graph {:with-start false}))
            (register-graph-map-test-loaders graph ["scoped-node"])
            (local graph-map (GraphMap.GraphMap {:graph graph :id "scoped-map"}))
            (local node (Graph.GraphNode {:key "scoped-node"
                                          :view (fn [_node]
                                                  (fn [_ctx]
                                                      {:layout (Layout {:name "scoped-node-view"})}))}))
            (local view (GraphView {:graph-map graph-map :ctx ctx}))
            (graph-map:add-node node)
            (local (ok _err)
                (pcall (fn []
                           (view:restore-views-state {:open-views [{:node-key "scoped-node"}]}))))
            (assert (not ok)
                    "GraphView should reject unscoped graph node panel restore state")
            (view:drop)
            (graph-map:drop)
            (graph:drop))))

(fn llm-message-extra-panel-drops-with-graph-view []
    (with-temp-data-dir
      (fn [_root]
        (local original-graph-view app.graph-view)
        (local original-graph-map app.graph-map)
        (var removed 0)
        (local target {:children []
                       :add-panel-child (fn [self opts]
                                           (table.insert self.children opts)
                                           opts)
                       :remove-panel-child (fn [self element]
                                             (set removed (+ removed 1))
                                             (for [i (length self.children) 1 -1]
                                                 (when (= (. self.children i) element)
                                                     (table.remove self.children i))))
                       :capture-panel-element-state (fn [_self _element]
                                                      {:position [1 2 0] :size [3 4 0]})})
        (local (ok err)
          (pcall
            (fn []
              (local ctx (make-ctx))
              (local graph (Graph {:with-start false}))
              (register-graph-map-test-loaders graph ["llm-conversation:conv-drop"])
              (local graph-map (GraphMap.GraphMap {:graph graph :id "llm-map"}))
              (local view (GraphView {:graph-map graph-map
                                      :ctx ctx
                                      :view-target target}))
              (set app.graph-view view)
              (set app.graph-map graph-map)
              (local conversation (LlmConversationNode {:conversation {:id "conv-drop"
                                                                       :title "Drop Test"
                                                                       :messages []}}))
              (graph-map:add-node conversation)
              (local dialog (require :graph/view/views/llm-conversation-messages-dialog))
              (dialog.open-panel {:target target
                                  :graph graph-map
                                  :node conversation
                                  :node-key conversation.key})
              (assert (= (length target.children) 1)
                      "LLM message panel should be live before GraphView drop")
              (assert (= (length view.extra-panels) 1)
                      "LLM message panel metadata should be registered")
              (view:drop)
              (assert (= removed 1)
                      "GraphView drop should remove live LLM message panel")
              (assert (= (length target.children) 0)
                      "Target should not retain LLM message panel after GraphView drop")
              (graph-map:drop)
              (graph:drop))))
        (set app.graph-view original-graph-view)
        (set app.graph-map original-graph-map)
        (when (not ok)
          (error err)))))

(fn llm-message-extra-panel-reopen-drops-previous-runtime []
    (with-temp-data-dir
      (fn [_root]
        (local original-graph-view app.graph-view)
        (local original-graph-map app.graph-map)
        (var removed 0)
        (local target {:children []
                       :add-panel-child (fn [self opts]
                                           (table.insert self.children opts)
                                           opts)
                       :remove-panel-child (fn [self element]
                                             (set removed (+ removed 1))
                                             (for [i (length self.children) 1 -1]
                                                 (when (= (. self.children i) element)
                                                     (table.remove self.children i))))
                       :capture-panel-element-state (fn [_self _element]
                                                      {:position [1 2 0] :size [3 4 0]})})
        (local (ok err)
          (pcall
            (fn []
              (local ctx (make-ctx))
              (local graph (Graph {:with-start false}))
              (register-graph-map-test-loaders graph ["llm-conversation:conv-reopen"])
              (local graph-map (GraphMap.GraphMap {:graph graph :id "llm-map"}))
              (local view (GraphView {:graph-map graph-map
                                      :ctx ctx
                                      :view-target target}))
              (set app.graph-view view)
              (set app.graph-map graph-map)
              (local conversation (LlmConversationNode {:conversation {:id "conv-reopen"
                                                                       :title "Reopen Test"
                                                                       :messages []}}))
              (graph-map:add-node conversation)
              (local dialog (require :graph/view/views/llm-conversation-messages-dialog))
              (dialog.open-panel {:target target
                                  :graph graph-map
                                  :node conversation
                                  :node-key conversation.key})
              (dialog.open-panel {:target target
                                  :graph graph-map
                                  :node conversation
                                  :node-key conversation.key})
              (assert (= removed 1)
                      "Reopening LLM messages should drop the previous live panel")
              (assert (= (length target.children) 1)
                      "Only the newest LLM messages panel should remain live")
              (assert (= (length view.extra-panels) 1)
                      "Only one LLM messages metadata entry should remain")
              (view:drop)
              (assert (= removed 2)
                      "GraphView drop should remove the remaining live LLM messages panel")
              (assert (= (length target.children) 0)
                      "No LLM messages panels should remain after GraphView drop")
              (graph-map:drop)
              (graph:drop))))
        (set app.graph-view original-graph-view)
        (set app.graph-map original-graph-map)
        (when (not ok)
          (error err)))))

(fn llm-message-extra-panel-capture-refreshes-placement []
    (with-temp-data-dir
      (fn [_root]
        (local original-graph-view app.graph-view)
        (local original-graph-map app.graph-map)
        (var panel-state {:position [1 2 0] :size [3 4 0]})
        (local target {:children []
                       :add-panel-child (fn [self opts]
                                           (table.insert self.children opts)
                                           opts)
                       :remove-panel-child (fn [self element]
                                             (for [i (length self.children) 1 -1]
                                                 (when (= (. self.children i) element)
                                                     (table.remove self.children i))))
                       :capture-panel-element-state (fn [_self _element]
                                                      panel-state)})
        (local (ok err)
          (pcall
            (fn []
              (local ctx (make-ctx))
              (local graph (Graph {:with-start false}))
              (register-graph-map-test-loaders graph ["llm-conversation:conv-placement"])
              (local graph-map (GraphMap.GraphMap {:graph graph :id "llm-map"}))
              (local view (GraphView {:graph-map graph-map
                                      :ctx ctx
                                      :view-target target}))
              (set app.graph-view view)
              (set app.graph-map graph-map)
              (local conversation (LlmConversationNode {:conversation {:id "conv-placement"
                                                                       :title "Placement Test"
                                                                       :messages []}}))
              (graph-map:add-node conversation)
              (local dialog (require :graph/view/views/llm-conversation-messages-dialog))
              (dialog.open-panel {:target target
                                  :graph graph-map
                                  :node conversation
                                  :node-key conversation.key})
              (set panel-state {:position [9 8 0] :size [7 6 0]})
              (local captured (view:capture-state))
              (local panel (. (. captured.extra_panels 1) :panel))
              (assert (= (. panel.position 1) 9)
                      "GraphView capture-state should refresh extra panel position")
              (assert (= (. panel.size 1) 7)
                      "GraphView capture-state should refresh extra panel size")
              (view:drop)
              (graph-map:drop)
              (graph:drop))))
        (set app.graph-view original-graph-view)
        (set app.graph-map original-graph-map)
        (when (not ok)
          (error err)))))

(fn llm-message-extra-panel-restore-preserves-stale-entry []
    (with-temp-data-dir
      (fn [_root]
        (local original-graph-view app.graph-view)
        (local original-graph-map app.graph-map)
        (local target {:children []
                       :add-panel-child (fn [self opts]
                                           (table.insert self.children opts)
                                           opts)
                       :remove-panel-child (fn [self element]
                                             (for [i (length self.children) 1 -1]
                                                 (when (= (. self.children i) element)
                                                     (table.remove self.children i))))})
        (local (ok err)
          (pcall
            (fn []
              (local ctx (make-ctx))
              (local graph (Graph {:with-start false}))
              (local graph-map (GraphMap.GraphMap {:graph graph :id "llm-map"}))
              (local view (GraphView {:graph-map graph-map
                                      :ctx ctx
                                      :view-target target}))
              (set app.graph-view view)
              (set app.graph-map graph-map)
              (local dialog (require :graph/view/views/llm-conversation-messages-dialog))
              (local result
                (dialog.open-panel {:target target
                                    :graph graph-map
                                    :node-key "llm-conversation:missing"
                                    :restore? true
                                    :panel {:node-key "llm-conversation:missing"
                                            :graph-map-id "llm-map"
                                            :panel {:position [4 5 0]
                                                    :size [6 7 0]}}}))
              (assert (not result)
                      "Missing restored LLM message panel should not open a live element")
              (assert (= (length target.children) 0)
                      "Missing restored LLM message panel should not add a panel child")
              (assert (= (length view.extra-panels) 1)
                      "Missing restored LLM message panel should remain in extra-panel persistence")
              (local entry (. view.extra-panels 1))
              (assert (= entry.node-key "llm-conversation:missing"))
              (assert (= entry.graph-map-id "llm-map"))
              (assert (= (. entry.panel.position 1) 4)
                      "Stale LLM extra panel should keep placement")
              (view:drop)
              (graph-map:drop)
              (graph:drop))))
        (set app.graph-view original-graph-view)
        (set app.graph-map original-graph-map)
        (when (not ok)
          (error err)))))

(fn llm-message-extra-panel-transfer-updates-target []
    (with-temp-data-dir
      (fn [_root]
        (local original-graph-view app.graph-view)
        (local original-graph-map app.graph-map)
        (local original-panel-transfer app.panel-transfer)
        (var dest-state {:position [11 12 0] :size [13 14 0]})
        (local source {:children []
                       :add-panel-child (fn [self opts]
                                           (table.insert self.children opts)
                                           opts)
                       :remove-panel-child (fn [self element]
                                             (for [i (length self.children) 1 -1]
                                                 (when (= (. self.children i) element)
                                                     (table.remove self.children i))))
                       :capture-panel-element-state (fn [_self _element]
                                                      {:position [1 2 0] :size [3 4 0]})})
        (local destination {:children []
                            :remove-panel-child (fn [self element]
                                                  (for [i (length self.children) 1 -1]
                                                      (when (= (. self.children i) element)
                                                          (table.remove self.children i))))
                            :capture-panel-element-state (fn [_self _element]
                                                           dest-state)})
        (local (ok err)
          (pcall
            (fn []
              (set app.panel-transfer {:panel-transferred (Signal)})
              (local ctx (make-ctx))
              (local graph (Graph {:with-start false}))
              (register-graph-map-test-loaders graph ["llm-conversation:conv-transfer"])
              (local graph-map (GraphMap.GraphMap {:graph graph :id "llm-map"}))
              (local view (GraphView {:graph-map graph-map
                                      :ctx ctx
                                      :view-target source}))
              (set app.graph-view view)
              (set app.graph-map graph-map)
              (local conversation (LlmConversationNode {:conversation {:id "conv-transfer"
                                                                       :title "Transfer Test"
                                                                       :messages []}}))
              (graph-map:add-node conversation)
              (local dialog (require :graph/view/views/llm-conversation-messages-dialog))
              (dialog.open-panel {:target source
                                  :graph graph-map
                                  :node conversation
                                  :node-key conversation.key})
              (local source-element (. source.children 1))
              (assert source-element "LLM message panel should open before transfer")
              (local destination-element {:layout {:name "dest-llm-panel"}})
              (table.insert destination.children destination-element)
              (app.panel-transfer.panel-transferred:emit {:target destination
                                                          :receiver-id "dest-receiver"
                                                          :new-element destination-element
                                                          :persistence source-element.persistence})
              (set dest-state {:position [21 22 0] :size [23 24 0]})
              (local captured (view:capture-state))
              (local entry (. captured.extra_panels 1))
              (assert (= entry.target-kind "receiver")
                      "Transferred LLM extra panel should persist receiver target-kind")
              (assert (= entry.target-receiver-id "dest-receiver")
                      "Transferred LLM extra panel should persist receiver id")
              (assert (= (. entry.panel.position 1) 21)
                      "Transferred LLM extra panel should capture placement from destination target")
              (view:drop)
              (graph-map:drop)
              (graph:drop))))
        (set app.graph-view original-graph-view)
        (set app.graph-map original-graph-map)
        (set app.panel-transfer original-panel-transfer)
        (when (not ok)
          (error err)))))

(fn graph-view-capture-persists-extra-panels []
    (with-temp-data-dir
        (fn [root]
            (local ctx (make-ctx))
            (local target {:children []
                           :add-panel-child (fn [self opts]
                                               (table.insert self.children opts)
                                               opts)
                           :remove-panel-child (fn [self element]
                                                 (for [i (length self.children) 1 -1]
                                                     (when (= (. self.children i) element)
                                                         (table.remove self.children i))))
                           :capture-panel-element-state (fn [_self _element]
                                                          {:position [21 22 0]
                                                           :size [50 25 0]})})
            (local graph (Graph {:with-start false}))
            (local graph-map (GraphMap.GraphMap {:graph graph :id "persist-extra"}))
            (local view (GraphView {:graph-map graph-map
                                    :ctx ctx
                                    :view-target target}))
            (local element (target:add-panel-child {}))
            (view:register-extra-panel! {:kind "test-extra-panel"
                                         :node-key "extra-node"
                                         :graph-map-id "persist-extra"
                                         :target-kind "canvas"
                                         :panel {:node-key "extra-node"
                                                 :graph-map-id "persist-extra"}}
                                        target
                                        element)
            (view:capture-state)
            (local reloaded (GraphViewPersistence {:data-dir root :map-id "persist-extra"}))
            (local panels (reloaded:saved-extra-panels))
            (local panel (. panels 1))
            (local panel-placement (and panel panel.panel))
            (assert (= (length panels) 1)
                    "GraphView capture-state should persist one extra panel")
            (assert (= panel.node-key "extra-node")
                    "Persisted extra panel should keep node-key")
            (assert (= panel.graph-map-id "persist-extra")
                    "Persisted extra panel should keep graph-map-id")
            (assert (= (. panel-placement.position 1) 21)
                    "Persisted extra panel should keep captured placement")
            (view:drop)
            (graph-map:drop)
            (graph:drop))))

(fn graph-view-extra-panel-receiver-restore-errors-without-panel-transfer []
    (with-temp-data-dir
        (fn [_root]
            (local original-panel-transfer app.panel-transfer)
            (set app.panel-transfer nil)
            (var view nil)
            (var graph-map nil)
            (var graph nil)
            (local (ok err)
                (pcall
                  (fn []
                    (local ctx (make-ctx))
                    (set graph (Graph {:with-start false}))
                    (set graph-map (GraphMap.GraphMap {:graph graph :id "receiver-map"}))
                    (set view (GraphView {:graph-map graph-map :ctx ctx}))
                    (local state {:extra_panels [{:kind "llm-conversation-messages-view-dialog"
                                                  :node-key "llm-conversation:missing"
                                                  :graph-map-id "receiver-map"
                                                  :restorer-module "graph/view/views/llm-conversation-messages-dialog"
                                                  :target-kind "receiver"
                                                  :target-receiver-id "missing-receiver"}]})
                    (view:restore-state state))))
            (set app.panel-transfer original-panel-transfer)
            (when view (view:drop))
            (when graph-map (graph-map:drop))
            (when graph (graph:drop))
            (assert (not ok)
                    "Receiver extra panel restore should fail without panel-transfer")
            (assert (string.find (tostring err) "requires app.panel-transfer" 1 true)
                    "Receiver extra panel restore error should mention missing panel-transfer"))))

(fn make-test-camera [position]
    (local camera {:position (if position position (glm.vec3 10 20 100))})
    (set camera.set-position
         (fn [self next-position]
             (set self.position next-position)))
    camera)

(fn graph-view-reveal-node-selects-focuses-and-centers []
    (local graph (Graph {:with-start false}))
    (local graph-map (GraphMap.GraphMap {:graph graph :id "main" :name "Main"}))
    (register-graph-map-test-loaders graph ["test:alpha"])
    (local node (Graph.GraphNode {:key "test:alpha" :label "Alpha"}))
    (graph-map:add-node node)
    (local camera (make-test-camera (glm.vec3 10 20 100)))
    (local ctx (make-ctx))
    (local view (GraphView {:graph-map graph-map
                            :ctx ctx
                            :camera camera
                            :data-dir "/tmp/space/tests/graph-view-reveal"}))
    (local point (. view.points node))
    (assert point "GraphView should create a presentation for the node")
    (point:set-position (glm.vec3 42 24 0))
    (view:reveal-node node)
    (assert (= (length view.selection.selected-nodes) 1)
            "reveal-node should select exactly one node")
    (assert (= (. view.selection.selected-nodes 1) node)
            "reveal-node should select the requested node")
    (assert (= (ctx.focus.manager:get-focused-node) (. view.focus-nodes node))
            "reveal-node should request focus for the requested node")
    (assert (= camera.position.x 42) "reveal-node should center camera x on compact node")
    (assert (= camera.position.y 24) "reveal-node should center camera y on compact node")
    (assert (= camera.position.z 100) "reveal-node should preserve camera z")
    (view:drop)
    (graph-map:drop)
    (graph:drop))

(fn graph-view-open-node-reveals-and-opens []
    (var opened-count 0)
    (fn TestNodeView [_node]
        (fn [_ctx]
            (set opened-count (+ opened-count 1))
            {:layout (Layout {:name "test-node-view"})
             :drop (fn [_self])}))
    (local graph (Graph {:with-start false}))
    (local graph-map (GraphMap.GraphMap {:graph graph :id "main" :name "Main"}))
    (register-graph-map-test-loaders graph ["test:open"])
    (local node (Graph.GraphNode {:key "test:open" :label "Open Me" :view TestNodeView}))
    (graph-map:add-node node)
    (local camera (make-test-camera (glm.vec3 0 0 75)))
    (local ctx (make-ctx))
    (local view (GraphView {:graph-map graph-map
                            :ctx ctx
                            :camera camera
                            :data-dir "/tmp/space/tests/graph-view-open"}))
    (local result (view:open-node "test:open"))
    (assert (= result true) "open-node should return true when it opens a node")
    (assert (= (length view.selection.selected-nodes) 1)
            "open-node should reveal/select the node before opening")
    (assert (= (. view.selection.selected-nodes 1) node)
            "open-node should select the opened node")
    (assert (= opened-count 1) "open-node should build the node view once")
    (view:drop)
    (graph-map:drop)
    (graph:drop))

(fn make-capturing-line-factory [state] (fn [_ctx opts] (table.insert state.colors opts.color) {:update (fn [_self _start _end] true) :drop (fn [_self] true)}))
(fn edge-color-approx [actual expected] (and actual expected (< (math.abs (- actual.x expected.x)) 1e-4) (< (math.abs (- actual.y expected.y)) 1e-4) (< (math.abs (- actual.z expected.z)) 1e-4) (< (math.abs (- actual.w expected.w)) 1e-4)))
(fn graph-edge-default-color-uses-layout-theme-color [] (local theme-color (glm.vec4 0.12 0.34 0.56 1)) (local explicit-color (glm.vec4 0.9 0.8 0.7 1)) (local state {:colors []}) (local positions {}) (local layout (GraphViewLayout {:ctx (make-ctx) :edge-color theme-color :make-line (make-capturing-line-factory state) :get-position (fn [_self node] (. positions node))})) (local a (Graph.GraphNode {:key "edge-theme-a"})) (local b (Graph.GraphNode {:key "edge-theme-b"})) (set (. positions a) (glm.vec3 0 0 0)) (set (. positions b) (glm.vec3 10 0 0)) (layout:add-node a (glm.vec3 0 0 0)) (layout:add-node b (glm.vec3 10 0 0)) (layout:add-edge (Graph.GraphEdge {:source a :target b})) (assert (edge-color-approx (. state.colors 1) theme-color) "Default graph edge should use the layout/theme edge color") (layout:add-edge (Graph.GraphEdge {:source a :target b :color explicit-color})) (assert (edge-color-approx (. state.colors 2) explicit-color) "Explicit graph edge color should override the layout/theme edge color"))

(table.insert tests {:name "GraphView capture-state emits selected_node_keys" :fn graph-view-capture-restore-selected-node-keys})
(table.insert tests {:name "GraphView capture/restore preserves node selection" :fn graph-view-capture-restore-preserves-selection})
(table.insert tests {:name "GraphView node-view panel capture includes graph-map-id" :fn graph-node-view-capture-includes-graph-map-id})
(table.insert tests {:name "GraphView capture-state persists node-view panels" :fn graph-view-capture-persists-node-view-panels})
(table.insert tests {:name "GraphView rejects unscoped node-view panel restore" :fn graph-view-restore-rejects-unscoped-node-view-panel})
(table.insert tests {:name "GraphView drops LLM extra panel runtimes" :fn llm-message-extra-panel-drops-with-graph-view})
(table.insert tests {:name "GraphView LLM extra panel reopen drops previous runtime" :fn llm-message-extra-panel-reopen-drops-previous-runtime})
(table.insert tests {:name "GraphView LLM extra panel capture refreshes placement" :fn llm-message-extra-panel-capture-refreshes-placement})
(table.insert tests {:name "GraphView LLM extra panel restore preserves stale entry"
                     :fn llm-message-extra-panel-restore-preserves-stale-entry})
(table.insert tests {:name "GraphView LLM extra panel transfer updates target"
                     :fn llm-message-extra-panel-transfer-updates-target})
(table.insert tests {:name "GraphView capture-state persists extra panels" :fn graph-view-capture-persists-extra-panels})
(table.insert tests {:name "GraphView receiver extra panel restore requires panel-transfer" :fn graph-view-extra-panel-receiver-restore-errors-without-panel-transfer})
(table.insert tests {:name "GraphView reveal-node selects focuses and centers"
                     :fn graph-view-reveal-node-selects-focuses-and-centers})
(table.insert tests {:name "GraphView open-node reveals and opens"
                     :fn graph-view-open-node-reveals-and-opens})
(table.insert tests {:name "Graph edge default color uses layout theme color" :fn graph-edge-default-color-uses-layout-theme-color})
(fn graph-titlebar-color= [a b] (and a b (< (math.abs (- a.x b.x)) 1e-4) (< (math.abs (- a.y b.y)) 1e-4) (< (math.abs (- a.z b.z)) 1e-4) (< (math.abs (- a.w b.w)) 1e-4))) (fn graph-expanded-card-titlebar-uses-tertiary-surface [] (local ctx (make-ctx)) (set ctx.theme ((require :light-theme))) (local expected-titlebar-color ctx.theme.button.variants.tertiary.background) (local body-color ctx.theme.card.background) (local node (Graph.GraphNode {:key "preview-titlebar-node" :preview (tracked-preview {})})) (local GraphNodePresentation (require :graph/view/presentation)) (local card-builder (GraphNodePresentation.card-builder {:node node :position (glm.vec3 0 0 0) :default-size (glm.vec3 32 18 0) :on-collapse (fn [] nil) :on-open (fn [_] nil) :on-menu (fn [_] nil)})) (local card (card-builder ctx)) (assert card.header-titlebar-background "Expanded card should expose a separate titlebar background surface") (assert (graph-titlebar-color= card.header-titlebar-background.color expected-titlebar-color) "Expanded card titlebar should use the light theme tertiary background") (assert (not (graph-titlebar-color= card.header-titlebar-background.color body-color)) "Expanded card titlebar background should be distinct from the card body") (card:drop))
(table.insert tests {:name "Graph expanded card titlebar uses tertiary surface" :fn graph-expanded-card-titlebar-uses-tertiary-surface})
(fn graph-expanded-card-header-actions-stay-inside-long-title-card [] (local ctx (make-ctx)) (local state {:measure (glm.vec3 8 6 0) :constrained-measure (glm.vec3 8 6 0)}) (local node (Graph.GraphNode {:key "long-title-narrow-preview" :label "This graph node label is long enough to overflow the compact preview header actions" :preview (tracked-preview state)})) (local GraphNodePresentation (require :graph/view/presentation)) (local card-builder (GraphNodePresentation.card-builder {:node node :position (glm.vec3 0 0 0) :default-size (glm.vec3 32 18 0) :min-size (glm.vec3 24 12 0) :max-size (glm.vec3 52 34 0) :on-collapse (fn [] nil) :on-open (fn [_] nil) :on-menu (fn [_] nil)})) (local card (card-builder ctx)) (ctx.layout-root:update) (assert (> card.header-bar.layout.measure.x 32) "Test fixture should require more than the compact default width") (local menu-button (. card.header-bar.children 5 :element)) (local menu-right-edge (+ menu-button.layout.position.x menu-button.layout.size.x)) (local card-right-edge (+ card.layout.position.x card._card-size.x)) (assert (<= menu-right-edge (+ card-right-edge 1e-3)) (.. "Rightmost header action should stay inside card; button edge " menu-right-edge " card edge " card-right-edge)) (card:drop)) (table.insert tests {:name "Graph expanded card header actions stay inside long-title card" :fn graph-expanded-card-header-actions-stay-inside-long-title-card})
(fn find-search-row [items label]
  (var found nil)
  (each [_ item (ipairs items)]
    (when (= (. item 2) label)
      (set found (. item 1))))
  found)

(fn search-labels [items]
  (icollect [_ item (ipairs items)]
    (. item 2)))

(fn finish-relative-fixture! [graph cleanup-fn ok err]
  (var final-err (if ok nil err))
  (when graph
    (local (drop-ok drop-err) (pcall (fn [] (graph:drop))))
    (when (and (not drop-ok) (not final-err))
      (set final-err drop-err)))
  (local (cleanup-ok cleanup-err) (pcall cleanup-fn))
  (when (and (not cleanup-ok) (not final-err))
    (set final-err cleanup-err))
  (when final-err
    (error final-err)))

(fn with-fs-interaction-test-dir [f]
  (with-temp-data-dir
    (fn [_root]
      (with-temp-dir f))))

(fn fs-node-file-view-renders-only-search-interactions []
  (with-fs-interaction-test-dir
    (fn [root]
      (local path (fs.join-path root "main.fnl"))
      (fs.write-file path "(local x 1)\n")
      (local ctx (make-ctx))
      (local graph (Graph {:with-start false}))
      (local node (FsNode {:path path}))
      (set node.list-directory
           (fn [_self _path]
             (error "file mode must not list directory entries")))
      (graph:add-node node {:position (glm.vec3 0 0 0)})
      (local view ((node.view node) ctx))
      (view:refresh-items)
      (assert (= view.action-row nil)
              "FsNode file view should not render the directory action row")
      (local external-row (find-search-row view.search.items "Edit externally"))
      (local viewer-row (find-search-row view.search.items "View text"))
      (local module-row (find-search-row view.search.items "Open as Fennel Module"))
      (assert external-row "FsNode file view should include external editor interaction")
      (assert viewer-row "FsNode file view should include text viewer interaction")
      (assert module-row "FsNode file view should include module interaction")
      (assert (= external-row.kind :external-editor))
      (assert (= viewer-row.kind :file-viewer))
      (assert (= module-row.kind :module))
      (view:drop)
      (graph:drop))))

(fn fs-node-external-editor-interaction-does-not-add-edge []
  (with-fs-interaction-test-dir
    (fn [root]
      (local ExternalEditor (require :external-editor))
      (local path (fs.join-path root "main.fnl"))
      (fs.write-file path "(local x 1)\n")
      (local graph (Graph {:with-start false}))
      (local node (FsNode {:path path}))
      (graph:add-node node {:position (glm.vec3 0 0 0)})
      (local interaction (find-search-row (node:emit-items) "Edit externally"))
      (local original-open-file ExternalEditor.open-file)
      (var opened-path nil)
      (set ExternalEditor.open-file
           (fn [external-path callback]
             (set opened-path external-path)
             (when callback (callback))
             true))
      (local (ok err)
        (pcall
          (fn []
            (local result (node:open-entry interaction))
            (assert (= result true)
                    "External editor interaction should return true"))))
      (set ExternalEditor.open-file original-open-file)
      (when (not ok)
        (error err))
      (assert (paths-eq opened-path (fs.absolute path))
              "External editor interaction should open absolute file path")
      (assert (= (graph:edge-count) 0)
              "External editor interaction should not add graph edges")
      (graph:drop))))

(fn fs-node-text-viewer-interaction-adds-viewer-node []
  (with-fs-interaction-test-dir
    (fn [root]
      (local path (fs.join-path root "note.md"))
      (fs.write-file path "# hello\n")
      (local graph (Graph {:with-start false}))
      (local node (FsNode {:path path}))
      (graph:add-node node {:position (glm.vec3 0 0 0)})
      (local interaction (find-search-row (node:emit-items) "View text"))
      (assert interaction "Text file should expose View text interaction")
      (local result (node:open-entry interaction))
      (local viewer-key (.. "fs-file-viewer:" (fs.absolute path)))
      (local viewer-node (graph:lookup viewer-key))
      (assert viewer-node "View text interaction should add fs-file-viewer node")
      (assert (= result viewer-node)
              "View text interaction should return the viewer node")
      (assert (= (graph:edge-count) 1))
      (graph:drop))))

(fn fs-node-relative-text-viewer-uses-absolute-key []
  (set temp-counter (+ temp-counter 1))
  (local relative-parent (fs.join-path ".tmp" "space-tests"))
  (local relative-path (fs.join-path relative-parent (.. "fs-node-relative-viewer-" (os.time) "-" temp-counter ".md")))
  (local absolute-path (fs.absolute relative-path))
  (var graph nil)
  (local (ok err) (pcall (fn []
    (fs.create-dirs relative-parent) (fs.write-file absolute-path "# relative viewer\n")
    (set graph (Graph {:with-start false})) (local node (FsNode {:path relative-path})) (graph:add-node node {:position (glm.vec3 0 0 0)})
    (local interaction (find-search-row (node:emit-items) "View text"))
    (assert interaction "Relative text file should expose View text interaction")
    (assert (= interaction.path absolute-path) "File interaction path should be absolute")
    (assert (= interaction.target-key (.. "fs-file-viewer:" absolute-path)) "File viewer target key should use absolute path")
    (local result (node:open-entry interaction)) (local viewer-key (.. "fs-file-viewer:" absolute-path))
    (assert (= result (graph:lookup viewer-key)) "Relative View text interaction should return absolute-key viewer node")
    (assert (= result.key viewer-key)) (assert (= (graph:edge-count) 1)))))
  (finish-relative-fixture! graph (fn [] (when (fs.exists absolute-path) (fs.remove absolute-path))) ok err))

(fn fs-node-module-interactions-preserve-key-formats []
  (with-fs-interaction-test-dir
    (fn [root]
      (local graph (Graph {:with-start false}))
      (local file-cases
        [{:name "main.fnl"
          :label "Open as Fennel Module"
          :prefix "fnl-module:"
          :content "(local x 1)\n"}
         {:name "main.cpp"
          :label "Open as C++ Module"
          :prefix "cpp-module:"
          :content "int main() { return 0; }\n"}
         {:name "note.md"
          :label "Open as Text Module"
          :prefix "text-module:"
          :content "# note\n"}])
      (each [_ file-case (ipairs file-cases)]
        (local path (fs.join-path root file-case.name))
        (fs.write-file path file-case.content)
        (local node (FsNode {:path path}))
        (graph:add-node node {:position (glm.vec3 0 0 0)})
        (local interaction (find-search-row (node:emit-items) file-case.label))
        (assert interaction (.. file-case.name " should expose module interaction"))
        (node:open-entry interaction)
        (local expected-key (.. file-case.prefix (fs.absolute path)))
        (assert (graph:lookup expected-key)
                (.. file-case.name " should add module node key " expected-key)))
      (assert (= (graph:edge-count) 3))
      (graph:drop))))

(fn fs-node-uppercase-module-interactions-restore-through-key-loaders []
  (with-fs-interaction-test-dir
      (fn [root]
      (local source-graph (Graph {:with-start false}))
      (local source-builtins (BuiltinGraphTestHelpers.install-builtins! source-graph {}))
      (local file-cases
        [{:name "MAIN.FNL"
          :label "Open as Fennel Module"
          :prefix "fnl-module:"
          :content "(local x 1)\n"}
         {:name "MAIN.CPP"
          :label "Open as C++ Module"
          :prefix "cpp-module:"
          :content "int main() { return 0; }\n"}])
      (each [_ file-case (ipairs file-cases)]
        (local path (fs.join-path root file-case.name))
        (fs.write-file path file-case.content)
        (local node (FsNode {:path path}))
        (source-graph:add-node node {:position (glm.vec3 0 0 0)})
        (local interaction (find-search-row (node:emit-items) file-case.label))
        (assert interaction (.. file-case.name " should expose module interaction"))
        (node:open-entry interaction)
        (local module-key (.. file-case.prefix (fs.absolute path)))
        (assert (source-graph:lookup module-key)
                (.. file-case.name " should add module node before persistence")))
      (local state (source-graph:capture-state))
      (local restored-graph (Graph {:with-start false}))
      (local restored-builtins (BuiltinGraphTestHelpers.install-builtins! restored-graph {}))
      (restored-graph:restore-state state)
      (each [_ file-case (ipairs file-cases)]
        (local module-key (.. file-case.prefix (fs.absolute (fs.join-path root file-case.name))))
        (assert (restored-graph:lookup module-key)
                (.. file-case.name " module key should restore through key loader")))
      (assert (= (restored-graph:edge-count) 2)
              "Restored uppercase module graph should preserve edges")
      (restored-builtins:drop)
      (restored-graph:drop)
      (source-builtins:drop)
      (source-graph:drop))))

(fn fs-node-relative-directory-open-entry-preserves-relative-child-key []
  (set temp-counter (+ temp-counter 1))
  (local relative-root (fs.join-path ".tmp" "space-tests" (.. "fs-node-relative-dir-" (os.time) "-" temp-counter)))
  (local absolute-root (fs.absolute relative-root))
  (local expected-child-path (fs.join-path relative-root "child.txt"))
  (var graph nil)
  (local (ok err)
    (pcall
      (fn []
        (when (fs.exists absolute-root) (fs.remove-all absolute-root)) (fs.create-dirs absolute-root) (fs.write-file (fs.join-path absolute-root "child.txt") "hello")
        (set graph (Graph {:with-start false})) (local node (FsNode {:path relative-root})) (graph:add-node node {:position (glm.vec3 0 0 0)})
        (local entry (find-search-row (node:emit-items) "child.txt"))
        (assert entry "Relative directory should list child file")
        (assert (not (= entry.path (fs.absolute expected-child-path))) "Directory entry path should remain relative by raw comparison") (assert (paths-eq entry.path expected-child-path) "Directory entry path should match expected relative child path") (assert (= entry.path expected-child-path) "Directory entry path should preserve relative parent style")
        (node:open-entry entry)
        (local expected-key (.. "fs:" expected-child-path))
        (assert (graph:lookup expected-key)
                (.. "Opening relative child should add " expected-key)))))
  (finish-relative-fixture! graph (fn [] (when (fs.exists absolute-root) (fs.remove-all absolute-root))) ok err))

(fn fs-node-view-requires-explicit-build-context []
  (with-fs-interaction-test-dir
    (fn [root]
      (local node (FsNode {:path root}))
      (local fallback-ctx (make-ctx))
      (local graph (Graph {:with-start false}))
      (set graph.ctx fallback-ctx)
      (graph:add-node node {:position (glm.vec3 0 0 0)})
      (local builder (node.view node))
      (local (ok err) (pcall builder))
      (assert (not ok) "FsNodeView should reject missing explicit build context")
      (assert (string.find (tostring err) "FsNodeView requires a build context" 1 true)
              (.. "Expected build context error, got: " (tostring err)))
      (local options-builder (node.view node {:ctx fallback-ctx}))
      (local (options-ok options-err) (pcall options-builder))
      (assert (not options-ok)
              "FsNodeView should reject options.ctx when builder ctx is missing")
      (assert (string.find (tostring options-err) "FsNodeView requires a build context" 1 true)
              (.. "Expected options.ctx build context error, got: " (tostring options-err)))
      (graph:drop))))

(fn fs-node-unknown-file-shows-only-external-editor []
  (with-fs-interaction-test-dir
    (fn [root]
      (local path (fs.join-path root "blob.bin"))
      (fs.write-file path "\001\002\003")
      (local node (FsNode {:path path}))
      (local labels (search-labels (node:emit-items)))
      (assert (= (length labels) 1)
              "Unknown file should expose exactly one interaction")
      (assert (= (. labels 1) "Edit externally"))
      (local interaction (find-search-row (node:emit-items) "Edit externally"))
      (assert (= interaction.kind :external-editor)))))

(fn fs-node-directory-listing-behavior-remains-unchanged []
  (with-fs-interaction-test-dir
    (fn [root]
      (local child-dir (fs.join-path root "child"))
      (local file (fs.join-path root "note.txt"))
      (fs.create-dirs child-dir)
      (fs.write-file file "hello")
      (local node (FsNode {:path root}))
      (local items (node:emit-items))
      (local dir-entry (find-search-row items "child/"))
      (local file-entry (find-search-row items "note.txt"))
      (assert dir-entry "Directory FsNode should still list child directories with slash")
      (assert file-entry "Directory FsNode should still list child files by name")
      (assert (= dir-entry.kind nil)
              "Directory entries should not be file interaction rows")
      (assert (= file-entry.kind nil)
              "Directory file entries should not be file interaction rows"))))

(table.insert tests {:name "FsNode file view renders only search interactions"
                     :fn fs-node-file-view-renders-only-search-interactions})
(table.insert tests {:name "FsNode external editor interaction does not add edge"
                     :fn fs-node-external-editor-interaction-does-not-add-edge})
(table.insert tests {:name "FsNode text viewer interaction adds viewer node"
                     :fn fs-node-text-viewer-interaction-adds-viewer-node})
(table.insert tests {:name "FsNode relative text viewer interaction uses absolute key"
                     :fn fs-node-relative-text-viewer-uses-absolute-key})
(table.insert tests {:name "FsNode module interactions preserve key formats"
                      :fn fs-node-module-interactions-preserve-key-formats})
(table.insert tests {:name "FsNode uppercase module interactions restore through key loaders"
                     :fn fs-node-uppercase-module-interactions-restore-through-key-loaders})
(table.insert tests {:name "FsNode relative directory open-entry preserves relative child key"
                     :fn fs-node-relative-directory-open-entry-preserves-relative-child-key})
(table.insert tests {:name "FsNodeView requires explicit build context"
                     :fn fs-node-view-requires-explicit-build-context})
(table.insert tests {:name "FsNode unknown file shows only external editor"
                      :fn fs-node-unknown-file-shows-only-external-editor})
(table.insert tests {:name "FsNode directory listing behavior remains unchanged"
                     :fn fs-node-directory-listing-behavior-remains-unchanged})

(local main
  (fn []
    (local runner (require :tests/runner))
    (table.insert tests 1
                  {:name "GraphView direct test suppresses expected selection info logs"
                   :fn (fn []
                         (assert ((. (require :logging) :set-level) "warn")
                                 "graph-view focused test requires logging level control"))})
    (runner.run-tests {:name "graph-view" :tests tests})))

{:name "graph-view" :tests tests :main main}
