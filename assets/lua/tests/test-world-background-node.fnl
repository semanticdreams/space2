(local fs (require :fs))
(local Signal (require :signal))
(local Graph (require :graph/init))
(local BuiltinGraphTestHelpers (require :tests/graph-builtin-extension-helpers))
(local ValidationUtils (require :graph/validation-utils))
(local LightSystemModule (require :light-system))
(local SkyboxState (require :skybox-state))
(local BackgroundState (require :background-state))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "world-background-node"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "world-background-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok result (error result)))

(fn make-skybox-state []
  (SkyboxState.default-state))

(fn make-background-state [opts]
  (local options (or opts {}))
  (BackgroundState.normalize-complete-state
    {:color (or options.color [0.0 0.0 0.0])}
    "test-world-background-node background state"))

(fn make-world-entry [opts]
  (local options (or opts {}))
  (local runtime (or options.runtime nil))
  (local state (or options.state {:scene {:panels []
                                          :terrains []
                                          :lights (LightSystemModule.default-state)
                                          :skybox (make-skybox-state)
                                          :background (make-background-state)}
                                  :hud {:panels []}}))
  ;; Populate canonical activity session state.
  (when (not (= (type state.activity) :table))
    (local sandbox-scene
           {:panels state.scene.panels
            :terrains state.scene.terrains
            :lights state.scene.lights
            :skybox state.scene.skybox
            :background state.scene.background
            :containment {:enabled? false}})
    (set state.activity
         {:active_id "sandbox"
          :sessions {:sandbox {:scene sandbox-scene}}}))
  {:id (or options.id "test-world")
   :name (or options.name "Test World")
   :active? (or options.active? false)
   :world {:state state
           :get-runtime (fn [_self] runtime)
           :save-state (fn [_self]
                         (when options.on-save
                           (options.on-save state))
                         true)}})

(fn make-scene-runtime [opts]
  (local options (or opts {}))
  (var background (or options.background (make-background-state)))
  {:scene {:active-activity-slot-id "sandbox"
           :capture-state (fn [_self]
                            {:panels []
                             :terrains []
                             :lights (LightSystemModule.default-state)
                             :skybox (make-skybox-state)
                             :background background})
           :build-default (fn [_self _payload] true)
           :restore-state (fn [_self payload]
                            (assert payload.background "test scene runtime restore-state requires background")
                            (set background payload.background)
                            true)
           :set-background-state (fn [_self value]
                                   (set background value)
                                   (when options.on-set-background-state
                                     (options.on-set-background-state value))
                                   true)
           :get-background-state (fn [_self]
                                   background)}})

(fn make-world-manager [opts]
  (local options (or opts {}))
  (local changed (or options.changed (Signal)))
  (local entry (or options.entry (make-world-entry options)))
  (local active-world-id
    (or options.active-world-id
        (and (or options.active? entry.active?) entry.id)
        nil))
  {:changed changed
   :get-world-entry (fn [_self world-id]
                      (if (= world-id entry.id)
                          entry
                          nil))
   :active-world (fn [_self]
                   (if (= active-world-id entry.id) entry nil))
   :active-world-id (fn [_self] active-world-id)})

(fn make-icons-stub []
  {:get (fn [_self _name] 4242)
   :resolve (fn [_self _name]
              {:type :font
               :codepoint 4242
               :font {:metadata {:metrics {:ascender 1 :descender -1}
                                 :atlas {:width 1 :height 1}}
                      :glyph-map {65533 {:advance 1}
                                  4242 {:advance 1}}}})})

(fn make-background-node-view-harness [opts]
  (local options (or opts {}))
  (local BackgroundNodeView (require :graph/view/views/background))
  (local BuildContext (require :build-context))
  (local Intersectables (require :intersectables))
  (local Clickables (require :clickables))
  (local Hoverables (require :hoverables))
  (local intersectables (or app.intersectables (Intersectables)))
  (local clickables (or app.clickables (Clickables {:intersectables intersectables})))
  (local hoverables (or app.hoverables (Hoverables {:intersectables intersectables})))
  (local ctx (BuildContext {:clickables clickables
                            :hoverables hoverables}))
  (set ctx.icons (make-icons-stub))
  (local state {:scene {:panels []
                        :terrains []
                        :lights (LightSystemModule.default-state)
                        :skybox (make-skybox-state)
                        :background (or options.background (make-background-state))}
                :hud {:panels []}})
  (var saved-background nil)
  (var synced-background nil)
  (local runtime (make-scene-runtime {:background state.scene.background
                                       :on-set-background-state (fn [value]
                                                                  (set synced-background value))}))
  (local entry (make-world-entry {:id "test-world"
                                   :state state
                                   :runtime runtime
                                   :active? true
                                   :on-save (fn [saved-state]
                                              (set saved-background
                                                   (and saved-state
                                                        saved-state.activity
                                                        saved-state.activity.sessions
                                                        saved-state.activity.sessions.sandbox
                                                        saved-state.activity.sessions.sandbox.scene
                                                        saved-state.activity.sessions.sandbox.scene.background)))}))
  (local manager (make-world-manager {:id "test-world"
                                      :entry entry
                                      :active-world-id "test-world"}))
  (local {:BackgroundNode BackgroundNode} (require :graph/nodes/background))
  (local node (BackgroundNode {:world-id "test-world"
                               :activity-id "sandbox"
                               :world-manager manager}))
  (local builder (BackgroundNodeView node))
  (local view (builder ctx))
  {:state state
   :sandbox-scene (fn [self]
                    (and self.state.activity
                         self.state.activity.sessions
                         self.state.activity.sessions.sandbox
                         self.state.activity.sessions.sandbox.scene))
   :node node
   :view view
   :synced-background (fn [_self] synced-background)
   :saved-background (fn [_self] saved-background)
   :drop (fn [self]
           (self.view:drop)
           (self.node:drop))})

(fn background-node-module-exports []
  (local {:BackgroundNode BackgroundNode} (require :graph/nodes/background))
  (assert BackgroundNode "background module should export BackgroundNode")
  (assert (= (type BackgroundNode) "function") "BackgroundNode should be a function"))

(fn background-node-has-correct-key []
  (local {:BackgroundNode BackgroundNode} (require :graph/nodes/background))
  (local node (BackgroundNode {:world-id "test-world-123"
                               :activity-id "sandbox"
                               :world-manager (make-world-manager {:id "test-world-123"})}))
  (assert (= node.key "activity-background:test-world-123:sandbox") "BackgroundNode key should include world-id and activity-id")
  (assert (= node.label "background") "BackgroundNode label should be 'background'")
  (node:drop))

(fn built-in-graph-extensions-load-background-node []
  (with-temp-dir
    (fn [_dir]
      (local graph (Graph {:with-start false}))
      (local builtins (BuiltinGraphTestHelpers.install-builtins! graph {:world-manager (make-world-manager {:id "test-world"})}))
      (local result (graph:load-by-key "activity-background:test-world:sandbox"))
      (assert result "background loader should create node")
      (assert (= result.key "activity-background:test-world:sandbox") "background key should match")
      (result:drop)
      (builtins:drop)
      (graph:drop))))

(fn background-node-isolates-activity-state []
  (local {:BackgroundNode BackgroundNode} (require :graph/nodes/background))
  (local state {:scene {:panels [] :terrains []}
                :hud {:panels []}
                :activity {:active_id "sandbox"
                           :sessions {:sandbox {:scene {:panels []
                                                        :terrains []
                                                        :lights (LightSystemModule.default-state)
                                                        :skybox (make-skybox-state)
                                                        :background (make-background-state {:color [0.1 0.2 0.3]})
                                                        :containment {:enabled? false}}}
                                      :graph {:scene {:panels []
                                                      :terrains []
                                                      :lights (LightSystemModule.default-state)
                                                      :skybox (make-skybox-state)
                                                      :background (make-background-state {:color [0.7 0.8 0.9]})
                                                      :containment {:enabled? false}}}}}})
  (local manager (make-world-manager {:id "test-world"
                                      :entry (make-world-entry {:id "test-world" :state state})}))
  (local graph-node (BackgroundNode {:world-id "test-world" :activity-id "graph" :world-manager manager}))
  (local sandbox-node (BackgroundNode {:world-id "test-world" :activity-id "sandbox" :world-manager manager}))
  (assert (= (. (. (graph-node:get-record) :color) 1) 0.7) "graph background should read graph session")
  (assert (= (. (. (sandbox-node:get-record) :color) 1) 0.1) "sandbox background should read sandbox session")
  (graph-node:drop)
  (sandbox-node:drop))

(fn background-node-view-builds []
  (local harness (make-background-node-view-harness))
  (assert harness.view.layout "BackgroundNodeView should have layout")
  (assert harness.view.fields "BackgroundNodeView should expose fields")
  (assert harness.view.apply-button "BackgroundNodeView should expose apply button")
  (local parsed-color
    (ValidationUtils.parse-number-list (. (harness.view:get-draft) :color) 3))
  (assert parsed-color "BackgroundNodeView should initialize a parseable color draft")
  (assert (= (. parsed-color 1) 0.0) "BackgroundNodeView should initialize red from the current color")
  (assert (= (. parsed-color 2) 0.0) "BackgroundNodeView should initialize green from the current color")
  (assert (= (. parsed-color 3) 0.0) "BackgroundNodeView should initialize blue from the current color")
  (harness:drop))

(fn background-node-view-applies-changes []
  (local harness
    (make-background-node-view-harness {:background (make-background-state {:color [0.0 0.0 0.0]})}))
  (harness.view.fields.color:set-text "0.1, 0.2, 0.3")
  (harness.view.apply-button:on-click {})
  (local sandbox-scene (harness:sandbox-scene))
  (assert (= (. sandbox-scene.background.color 1) 0.1) "Background apply should persist red")
  (assert (= (. sandbox-scene.background.color 2) 0.2) "Background apply should persist green")
  (assert (= (. sandbox-scene.background.color 3) 0.3) "Background apply should persist blue")
  (local synced-background (harness:synced-background))
  (assert synced-background "Background apply should sync the active scene")
  (assert (= (. synced-background.color 2) 0.2) "Synced background should include updated green")
  (local saved-background (harness:saved-background))
  (assert saved-background "Background apply should persist world state")
  (assert (= (. saved-background.color 3) 0.3) "Saved background should include updated blue")
  (harness:drop))

(table.insert tests {:name "background node module exports"
                     :fn background-node-module-exports})
(table.insert tests {:name "background node has correct key"
                     :fn background-node-has-correct-key})
(table.insert tests {:name "built-in graph extensions load background node"
                       :fn built-in-graph-extensions-load-background-node})
(table.insert tests {:name "background node isolates activity state"
                     :fn background-node-isolates-activity-state})
(table.insert tests {:name "background node view builds"
                     :fn background-node-view-builds})
(table.insert tests {:name "background node view applies changes"
                     :fn background-node-view-applies-changes})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "world-background-node"
                       :tests tests})))

{:name "world-background-node"
 :tests tests
 :main main}
