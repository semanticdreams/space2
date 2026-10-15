(local Main (require :main))
(local Activities (require :activities))
(local ThemeActions (require :theme-actions))
(local Intersectables (require :intersectables))
(local Clickables (require :clickables))
(local Hoverables (require :hoverables))
(local AppViewport (require :app-viewport))
(local AppProjection (require :app-projection))
(local InputState (require :input-state-router))
(local StateSystemBindings (require :state-system-bindings))
(local Units (require :units))
(local UnitManager (require :unit-manager)) (local Signal (require :signal)) (local {: Layout} (require :layout))
(local reset-engine-events
  (fn []
    (when _G.reset-engine-events
      (_G.reset-engine-events))))

(local tests [])

(local minimal-renderers
  {:update (fn [_] nil)
   :on-viewport-changed (fn [_ _] nil)
   :drop (fn [_] nil)})

(fn with-minimal-renderers [f]
  (local original-renderers app.renderers)
  (set app.renderers minimal-renderers)
  (local (ok result) (pcall f))
  (set app.renderers original-renderers)
  (when (not ok) (error result))
  result)

(fn ensure-built-in-activities! []
  (local registry (Activities.ensure-registry))
  (when (not (. registry.activities "graph"))
    (Activities.register-activity {:id "graph"
                                :label "Graph"
                                :icon "account_tree"
                                :button-name "graph-activity"
                                :show-in-switcher? true
                                :activate (fn [_ctx] nil)}))
  (when (not (. registry.activities "drawing"))
    (Activities.register-activity {:id "drawing"
                                :label "Draw"
                                :icon "draw"
                                :button-name "drawing-activity"
                                :show-in-switcher? true
                                :activate (fn [_ctx] nil)}))
  true)

(local bind-state-keys
  [:__active-activation-count
   :active-activity-id
   :active-interaction-surface
   :active-pointer-controls
   :active-world-entry
   :active-world-hud-contrib
   :active-world-hud-overlay
   :active-world-runtime
   :bind-active-world-runtime
   :board
   :board-registry
   :board-view
    :camera
    :canvas
    :canvas-controls
    :canvas-focus-scope
    :canvas-interactive?
    :canvas-surface-interactive?
   :activity-activate-focused
   :activity-command-hints-provider
   :activity-context-enricher
   :activity-delete-selection
   :activity-drawing-enabled?
   :activity-input-handlers
   :activity-left-dock-builder
   :activity-target-enabled?
   :activity-update
   :activity-units
   :activity-registry
   :activity-root-actions
   :activity-selection-actions
    :activities-changed :activity-dock-changed
    :workspace-shell-changed
   :canvas-visible?
   :drawing-controller
   :drawing-render
   :first-person-controls
    :graph
    :graph-view
    :hud
    :install-app-shell!
    :layout-root
    :mark-active-world-hud-dirty
    :object-selector
    :physics-containment-config
    :physics-containment-scene
    :pointer-target-enabled?
    :preferred-interaction-surface
    :projection
    :renderers
    :reset-projection
    :scene
    :settings
    :scene-focus-scope
    :scene-interactive?
     :suppress-workspace-shell-change?
     :set-active-activity
    :set-active-interaction-surface
    :set-canvas-visible
    :sync-interaction-surface-state
     :terrain-paint-previous-state
    :terrain-paint-session
    :terrain-rect-pick-previous-state
    :terrain-rect-pick-session
    :themes
    :toggle-active-interaction-surface
    :world-manager])

(fn capture-app-fields [keys]
  (local snapshot {})
  (each [_ key (ipairs keys)]
    (set (. snapshot key) (. app key)))
  snapshot)

(fn restore-app-fields [keys snapshot]
  (each [_ key (ipairs keys)]
    (set (. app key) (. snapshot key)))
  true)

(fn with-restored-app-fields [keys f]
  (local snapshot (capture-app-fields keys))
  (local (ok result) (pcall f))
  (restore-app-fields keys snapshot)
  (if ok
      result
      (error result)))

(local reset-state
  (fn []
    (reset-engine-events)
    (when (and app.window-resized-handler app.engine.events app.engine.events.window-resized)
      (app.engine.events.window-resized:disconnect app.window-resized-handler true)
      (set app.window-resized-handler nil))
    (when (and app.window-pixel-size-handler app.engine.events app.engine.events.window-pixel-size-changed)
      (app.engine.events.window-pixel-size-changed:disconnect app.window-pixel-size-handler true)
      (set app.window-pixel-size-handler nil))
    (when (and app.engine.events app.engine.events.window-resized)
      (set app.window-resized-handler
           (app.engine.events.window-resized:connect
             (fn [e]
               (local width (or (and app.engine (. app.engine "pixel-width")) e.width))
               (local height (or (and app.engine (. app.engine "pixel-height")) e.height))
               (app.set-viewport {:width width :height height})
               (app.reset-projection)))))
    (when (and app.engine.events app.engine.events.window-pixel-size-changed)
      (set app.window-pixel-size-handler
           (app.engine.events.window-pixel-size-changed:connect
             (fn [_e]
               (local width (or (and app.engine (. app.engine "pixel-width")) 0))
               (local height (or (and app.engine (. app.engine "pixel-height")) 0))
               (app.set-viewport {:width width :height height})
               (app.reset-projection)))))
    (when (not app.set-viewport)
      (set app.set-viewport AppViewport.set-viewport))
    (when (not app.create-default-projection)
      (set app.create-default-projection AppProjection.create-default-projection))
    (when (not app.reset-projection)
      (set app.reset-projection (fn [] (set app.projection (app.create-default-projection)))))
    (app.set-viewport {:width 0 :height 0})
    (set app.layout-root nil)))

(fn activity-policy-can-show-noninteractive-canvas []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (pcall (fn [] (Activities.unregister-activity "surface-policy-test")))
      (local first-person-controls {:id :scene-controls})
      (local canvas-controls {:id :canvas-controls})
      (set app.canvas {:build-context {}})
      (set app.first-person-controls first-person-controls)
      (set app.canvas-controls canvas-controls)
      ;; Stub app.presentation-input-controls so sync-interaction-surface-state
      ;; resolves through the presentation API during the test. The real function
      ;; requires a full runtime with a presentation provider; this test creates
      ;; a minimal stub that routes to the expected controls.
      (local saved-app-pic app.presentation-input-controls)
      (set app.presentation-input-controls
           (fn []
             (if app.canvas-interactive?
                 canvas-controls
                 first-person-controls)))
      (set app.preferred-interaction-surface :scene)
      (set app.active-interaction-surface :scene)
      (set app.scene-interactive? true)
      (set app.canvas-interactive? false)
      (set app.canvas-surface-interactive? true)
      (set app.canvas-visible? false)
      (local (ok result)
        (pcall
          (fn []
            (Activities.register-activity
              {:id "surface-policy-test"
               :activate (fn [ctx _retained]
                           (ctx:set-surface-state! {:canvas {:visible? true
                                                             :interactive? false}})
                           (ctx:set-preferred-interaction-surface! :canvas)
                           {})})
            (Activities.activate-activity "surface-policy-test")
            (assert (= app.canvas-visible? true)
                    "Activity policy should be able to show the canvas")
            (assert (= app.preferred-interaction-surface :canvas)
                    "Activity policy should preserve the preferred canvas surface")
            (assert (= app.active-interaction-surface :scene)
                    "Noninteractive canvas policy should keep input on the scene")
             (assert (= app.canvas-interactive? false)
                     "Noninteractive canvas policy should disable canvas input")
             (assert (= app.active-pointer-controls first-person-controls)
                     "Noninteractive canvas policy should keep scene pointer controls active")
             true)))
       (pcall (fn [] (Activities.unregister-activity "surface-policy-test")))
       (set app.presentation-input-controls saved-app-pic)
       (if ok result (error result)))))

(fn window-resize-updates-viewport-and-layout-root []
  (reset-state)
  (with-minimal-renderers
    (fn []
      (set (. app.engine "pixel-width") 960)
      (set (. app.engine "pixel-height") 540)
      (app.engine.events.window-resized.emit {:width 640 :height 360})
      (assert (= app.viewport.width 960))
      (assert (= app.viewport.height 540)))))

(fn drop-keeps-engine-events-and-clears-layout-root []
  (reset-state)
  (var fired false)
  ;; Restore composition and interaction fixtures even when teardown assertions fail.
  (with-restored-app-fields
    [:renderers :intersectables :clickables :hoverables
     :graph-extension-registry :builtin-graph-extension-handles :entity-type-catalog]
    (fn []
      (set app.renderers minimal-renderers)
      (set app.graph-extension-registry nil)
      (set app.builtin-graph-extension-handles nil)
      (set app.entity-type-catalog {:list-types (fn list-types [_self] [])
                                   :get-type (fn get-type [_self _id] (error "unknown type"))})
      (app.engine.events.key-down.connect (fn [_] (set fired true)))
      (set app.layout-root {:mark-measure-dirty (fn [_])})
      (set app.active-world-runtime {:id :stale-runtime})
      (Main.drop)
      (assert (= app.entity-type-catalog nil) "app.drop must release the app catalog reference")
      (assert (= app.layout-root nil))
      (assert (= app.active-world-runtime nil)
              "app.drop should clear stale active-world-runtime")
      (app.engine.events.key-down.emit {:key 10})
      (assert fired))))

(fn other-events-leave-viewport-untouched []
  (reset-state)
  (with-minimal-renderers
    (fn []
      (app.set-viewport {:width 111 :height 222})
      (app.engine.events.key-down.emit {:key 97})
      (assert (= app.viewport.width 111))
      (assert (= app.viewport.height 222)))))

(fn window-pixel-size-change-updates-viewport []
  (reset-state)
  (with-minimal-renderers
    (fn []
      (set (. app.engine "pixel-width") 2560)
      (set (. app.engine "pixel-height") 1440)
      (app.engine.events.window-pixel-size-changed.emit {:width 2560 :height 1440})
      (assert (= app.viewport.width 2560))
      (assert (= app.viewport.height 1440)))))

(fn bind-active-world-runtime-restores-runtime-interaction-surface []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (ensure-built-in-activities!)
      (var restored false)
      (var active-activity-id nil)
      (var preferred-surface nil)
      (var active-surface nil)
      (var canvas-visible? nil)
      (var canvas-interactive? nil)
        (set app.preferred-interaction-surface :scene)
        (set app.active-interaction-surface :scene)
        (set app.canvas-visible? false)
        (set app.scene-interactive? true)
        (set app.canvas-interactive? false)
        (set app.world-manager {:active-world (fn [_self]
                                                {:world {:get-hud-contrib (fn [_world] {})}})})
        (set app.hud {:build-context {}
                      :build-default (fn [_self _opts] true)
                      :add-overlay-child (fn [_self _opts] :overlay)
                      :remove-overlay-child (fn [_self _overlay] true)
                      :on-viewport-changed (fn [_self _viewport] true)})
        (local canvas-controls {:id :canvas-controls})
        (local first-person-controls {:id :scene-controls})
        (set app.reset-projection (fn [] true))
        (Main.bind-active-world-runtime
          {:id "world-a"}
          {:active-activity-id "drawing"
           :preferred-interaction-surface :canvas
           :restore-surface-state (fn [_self _canvas _hud]
                                    (set restored true))
           :first-person-controls first-person-controls
           :canvas-controls canvas-controls
           :scene nil
           :canvas {:build-context {}
                    :restore-state (fn [_self _state] true)}})
        (set active-activity-id app.active-activity-id)
        (set preferred-surface app.preferred-interaction-surface)
        (set active-surface app.active-interaction-surface)
        (set canvas-visible? app.canvas-visible?)
        (set canvas-interactive? app.canvas-interactive?)
      (assert restored "bind-active-world-runtime should restore target surface state before shell sync")
      (assert (= active-activity-id "drawing")
              "bind-active-world-runtime should restore active activity id from runtime")
      (assert (= preferred-surface :canvas)
              "bind-active-world-runtime should adopt runtime interaction surface preference")
      (assert (= active-surface :canvas)
              "bind-active-world-runtime should restore canvas as the active interaction surface")
      (assert (= canvas-visible? true)
              "bind-active-world-runtime should restore canvas visibility when activity was persisted")
      (assert (= canvas-interactive? true)
              "bind-active-world-runtime should re-enable canvas interaction when activity was persisted")
      true)))

(fn bind-active-world-runtime-preserves-explicit-nil-activity-id []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (ensure-built-in-activities!)
      (Activities.activate-activity "drawing")
      (local runtime
        {:requested-activity-id nil
         :requested-activity-known? true
         :active-activity-id "drawing"
         :preferred-interaction-surface :canvas
         :restore-surface-state (fn [_self _canvas _hud] true)})
      (app.bind-active-world-runtime {:id "test-world"} runtime)
      (assert (= app.active-activity-id nil)
              "bind-active-world-runtime should preserve an explicit nil requested activity id")
      (assert (= runtime.active-activity-id nil)
              "bind-active-world-runtime should clear stale runtime active activity when requested is nil")
      true)))

(fn bind-active-world-runtime-clears-inactive-retained-presentations []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (local retained-graph-view {:id :graph-view})
      (local retained-board {:id :board})
      (local retained-board-view {:id :board-view})
      (local retained-drawing-render {:id :drawing-render})
      (local runtime {:requested-activity-id nil
                      :requested-activity-known? true
                      :active-activity-id nil
                      :graph-view retained-graph-view
                      :board retained-board
                      :board-view retained-board-view
                      :drawing-render retained-drawing-render
                      :restore-surface-state (fn [_self _canvas _hud] true)})
      (set app.graph-view retained-graph-view)
      (set app.board retained-board)
      (set app.board-view retained-board-view)
      (set app.drawing-render retained-drawing-render)
      (app.bind-active-world-runtime {:id "test-world"} runtime)
      (assert (= app.graph-view nil)
              "bind-active-world-runtime should not expose inactive retained graph view")
      (assert (= app.board nil)
              "bind-active-world-runtime should not expose inactive retained board")
      (assert (= app.board-view nil)
              "bind-active-world-runtime should not expose inactive retained board view")
      (assert (= app.drawing-render nil)
              "bind-active-world-runtime should not expose inactive retained drawing render")
      true)))

(fn bind-active-world-runtime-defers-activity-id-without-canvas []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (Activities.clear-activity-runtime-hooks!)
      (var activated? false)
      (Activities.register-activity
        {:id "graph"
         :label "Graph"
         :icon "account_tree"
         :button-name "graph-activity"
         :show-in-switcher? true
         :activate (fn [_ctx]
                     (set activated? true)
                     (assert (and app.active-world-runtime app.active-world-runtime.canvas)
                              "test graph activity requires runtime.canvas"))})
      (local runtime {:requested-activity-id "graph"
                      :requested-activity-known? true
                      :active-activity-id "graph"
                      :preferred-interaction-surface :canvas
                      :restore-surface-state (fn [_self _canvas _hud] true)})
      (app.bind-active-world-runtime {:id "test-world"} runtime)
      (assert (not activated?)
              "bind-active-world-runtime should not activate activities without runtime.canvas")
      (assert (= app.active-activity-id nil)
              "bind-active-world-runtime should clear active activity while canvas is absent")
      (assert (= runtime.active-activity-id nil)
              "bind-active-world-runtime should clear stale runtime active activity while canvas is absent")
      (assert (= runtime.requested-activity-id "graph")
               "bind-active-world-runtime should preserve requested activity for later canvas reload")
      true)))

(fn bind-active-world-runtime-preserves-active-activity-id-as-requested []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (Activities.clear-activity-runtime-hooks!)
      (var activated? false)
      (Activities.register-activity
        {:id "graph"
         :label "Graph"
         :icon "account_tree"
         :button-name "graph-activity"
         :show-in-switcher? true
         :activate (fn [_ctx]
                     (set activated? true)
                     (assert (and app.active-world-runtime app.active-world-runtime.canvas)
                              "test graph activity requires runtime.canvas"))})
      (local runtime {:active-activity-id "graph"
                      :preferred-interaction-surface :canvas
                      :restore-surface-state (fn [_self _canvas _hud] true)})
      (app.bind-active-world-runtime {:id "test-world"} runtime)
      (assert (not activated?)
              "bind-active-world-runtime should not activate activities without runtime.canvas")
      (assert (= app.active-activity-id nil)
              "bind-active-world-runtime should clear active activity while canvas is absent")
      (assert (= runtime.active-activity-id nil)
              "bind-active-world-runtime should clear stale runtime active activity while canvas is absent")
      (assert (= runtime.requested-activity-id "graph")
              "bind-active-world-runtime should promote active-activity-id to requested-activity-id")
      (assert (= runtime.requested-activity-known? true)
              "bind-active-world-runtime should mark requested activity as known when preserving it")
      true)))

(fn bind-active-world-runtime-preserves-previous-runtime-requested-activity []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (Activities.clear-activity-runtime-hooks!)
      (var activation-count 0)
      (Activities.register-activity
        {:id "graph"
         :label "Graph"
         :icon "account_tree"
         :button-name "graph-activity"
         :show-in-switcher? true
         :activate (fn [_ctx]
                     (set activation-count (+ activation-count 1))
                     {})})
      (set app.world-manager {:active-world (fn [_self]
                                              {:world {:get-hud-contrib (fn [_world] {})}})})
      (set app.hud {:build-context {}
                    :build-default (fn [_self _opts] true)
                    :add-overlay-child (fn [_self _opts] :overlay)
                    :remove-overlay-child (fn [_self _overlay] true)
                    :on-viewport-changed (fn [_self _viewport] true)})
      (set app.reset-projection (fn [] true))
      (local runtime-a {:requested-activity-id "graph"
                        :requested-activity-known? true
                        :preferred-interaction-surface :canvas
                        :first-person-controls {:id :scene-controls-a}
                        :canvas-controls {:id :canvas-controls-a}
                        :scene nil
                        :canvas {:build-context {}
                                 :restore-state (fn [_self _state] true)
                                 :restore-shell-state (fn [_self _state] true)}
                        :restore-workspace-shell-state (fn [_self _canvas] true)
                        :restore-surface-state (fn [_self _canvas _hud] true)})
      (local runtime-b {:requested-activity-id nil
                        :requested-activity-known? true
                        :preferred-interaction-surface :scene
                        :first-person-controls {:id :scene-controls-b}
                        :canvas-controls {:id :canvas-controls-b}
                        :scene nil
                        :canvas {:build-context {}
                                 :restore-state (fn [_self _state] true)
                                 :restore-shell-state (fn [_self _state] true)}
                        :restore-workspace-shell-state (fn [_self _canvas] true)
                        :restore-surface-state (fn [_self _canvas _hud] true)})
      (app.bind-active-world-runtime {:id "world-a"} runtime-a)
      (assert (= app.active-activity-id "graph")
              "Initial runtime bind should activate its requested activity")
      (app.bind-active-world-runtime {:id "world-b"} runtime-b)
      (assert (= runtime-a.requested-activity-id "graph")
              "Switching away should preserve the previous runtime requested activity")
      (assert (= runtime-a.requested-activity-known? true)
              "Switching away should preserve previous runtime requested activity knowledge")
      (assert (= runtime-a.active-activity-id nil)
              "Switching away should still clear previous runtime active activity")
      (app.bind-active-world-runtime {:id "world-a"} runtime-a)
      (assert (= app.active-activity-id "graph")
              "Rebinding the retained runtime should restore its requested activity")
      (assert (= activation-count 2)
              "Retained runtime activity should reactivate after switching away and back")
      true)))

(fn bind-active-world-runtime-restores-panels-after-activity-activation []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (local saved-registry app.activity-registry)
      (set app.activity-registry nil)
      (Activities.ensure-registry)
      (var activation-log [])
      (Activities.register-activity
        {:id "graph"
         :label "Graph"
         :icon "account_tree"
         :button-name "graph-activity"
         :show-in-switcher? true
         :activate (fn [_ctx]
                     (table.insert activation-log :activate)
                     {:activity-id "graph"})})
      (set app.preferred-interaction-surface :scene)
      (set app.active-interaction-surface :scene)
      (set app.canvas-visible? false)
      (set app.scene-interactive? true)
      (set app.canvas-interactive? false)
      (set app.world-manager {:active-world (fn [_self]
                                               {:world {:get-hud-contrib (fn [_world] {})}})})
      (set app.hud {:build-context {}
                    :build-default (fn [_self _opts] true)
                    :add-overlay-child (fn [_self _opts] :overlay)
                    :remove-overlay-child (fn [_self _overlay] true)
                    :on-viewport-changed (fn [_self _viewport] true)
                    :restore-state (fn [_self _state] true)})
      (set app.reset-projection (fn [] true))
      (local runtime {:active-activity-id "graph"
                      :preferred-interaction-surface :canvas
                      :first-person-controls {:id :scene-controls}
                      :canvas-controls {:id :canvas-controls}
                      :scene nil
                      :canvas {:build-context {}
                               :restore-state (fn [_self _state] true)
                               :restore-shell-state (fn [_self _state] true)}
                      :restore-workspace-shell-state (fn [_self _canvas]
                                                    (table.insert activation-log :shell))
                      :restore-surface-state (fn [_self _canvas _hud]
                                               (table.insert activation-log :panels)
                                                (assert app.active-activity-id
                                                        "Active activity should be set before panel restore"))})
      (local (ok result)
        (pcall
          (fn []
            (app.bind-active-world-runtime {:id "test-world"} runtime)
            (assert (= app.active-activity-id "graph")
                    "bind-active-world-runtime should activate the activity")
            (assert (= (. activation-log 1) :shell)
                    "Workspace shell state should be restored before activity activation")
            (assert (= (. activation-log 2) :activate)
                    "Activity should activate after shell restore")
            (assert (= (. activation-log 3) :panels)
                    "Panel state should be restored after activity activation")
            true)))
      (set app.activity-registry saved-registry)
      (when (not ok)
        (error result))
      result)))

(fn set-active-activity-rejects-unknown []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (local (ok err)
        (pcall
          (fn []
            (app.set-active-activity "bogus"))))
      (assert (not ok)
              "set-active-activity should reject unknown activities")
      (assert (and err (string.find err "Unknown activity"))
              "set-active-activity should report the invalid activity id clearly")
      true)))

(fn activities-ordered-specs-preserve-registration-order []
  (local original-registry app.activity-registry)
  (set app.activity-registry nil)
  (Activities.register-activity {:id "graph"
                              :label "Graph"
                              :icon "account_tree"
                              :button-name "graph-activity"
                              :show-in-switcher? true
                              :activate (fn [_ctx] nil)})
  (Activities.register-activity {:id "drawing"
                              :label "Draw"
                              :icon "draw"
                              :button-name "drawing-activity"
                              :show-in-switcher? true
                              :activate (fn [_ctx] nil)})
  (local specs (Activities.activity-specs-in-order))
  (assert (= (length specs) 2)
          "Activity registry should preserve both registered activity specs")
  (assert (= (. (. specs 1) :id) "graph")
          "Activity registry should preserve registration order for the first activity")
  (assert (= (. (. specs 2) :id) "drawing")
          "Activity registry should preserve registration order for the second activity")
  (set app.activity-registry original-registry)
  true)

(fn invalid-persisted-activity-id-clears-to-nil []
  (local (normalized repaired? reason)
    (Activities.normalize-persisted-activity-id 42))
  (assert (= normalized nil)
          "Activities.normalize-persisted-activity-id should clear invalid persisted activity values to nil")
  (assert repaired?
          "Activities.normalize-persisted-activity-id should report repaired invalid persisted activity values")
  (assert (and reason (string.find reason "clearing to nil"))
          "Activities.normalize-persisted-activity-id should report that invalid persisted activity values were cleared")
  true)

(fn activity-activation-failure-restores-previous-activity []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (set app.activity-registry nil)
      (Activities.clear-activity-runtime-hooks!)
      (Activities.register-activity
        {:id "graph"
         :label "Graph"
         :icon "account_tree"
         :button-name "graph-activity"
         :show-in-switcher? true
         :activate (fn [ctx]
                     (ctx:set-root-actions! (fn [_context] []))
                     {:activity-id "graph"})})
      (Activities.register-activity
        {:id "broken"
         :label "Broken"
         :icon "draw"
         :button-name "broken-activity"
         :show-in-switcher? true
         :activate (fn [ctx]
                     (set app.__broken-mode-side-effect "armed")
                     (ctx:defer-cleanup! (fn []
                                           (set app.__broken-mode-side-effect nil)))
                     (ctx:set-root-actions! (fn [_context]
                                              [{:name "broken"}]))
                     (error "boom"))})
      (Activities.activate-activity "graph")
      (local previous-root-actions app.activity-root-actions)
      (local (ok err)
        (pcall
          (fn []
            (Activities.activate-activity "broken"))))
      (assert (not ok)
              "Activities.activate-activity should fail loudly when the new activity activation throws")
      (assert (and err (string.find err "Activity activation failed for broken"))
              "Activities.activate-activity should report the failing activity id")
      (assert (= (Activities.active-activity-id) "graph")
              "Activities.activate-activity should restore the previous active activity on failure")
      (assert (= app.active-activity-id "graph")
              "Activity activation rollback should restore app.active-activity-id")
      (assert (= (type app.activity-root-actions) :function)
              "Activity activation rollback should restore a root action hook")
      (assert (not (= app.activity-root-actions previous-root-actions nil))
              "Activity activation rollback should not leave the root action hook cleared")
      (assert (= (length (app.activity-root-actions {})) 0)
              "Activity activation rollback should restore the previous root action behavior")
      (assert (= app.__broken-mode-side-effect nil)
              "Activity activation rollback should run deferred cleanup for failed activation side effects")
      true)))

(fn direct-activity-activation-emits-workspace-shell-change []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (set app.active-activity-id nil)
      (set app.active-world-runtime {})
      (var events [])
      (local handler
        (app.workspace-shell-changed:connect
          (fn [payload]
            (table.insert events payload))))
      (local (ok result)
        (pcall
          (fn []
            (Activities.register-activity
              {:id "direct-test"
               :label "Direct Test"
               :activate (fn [_ctx] {})})
            (Activities.register-activity
              {:id "direct-two"
               :label "Direct Two"
               :activate (fn [_ctx] {})})
            (Activities.activate-activity "direct-test")
            (assert (= (# events) 1)
                    "Direct Activities.activate-activity should emit workspace-shell-changed")
            (local event (. events 1))
            (assert (= event.reason "activity")
                    "Direct activity activation shell event should identify the activity reason")
            (assert (= event.previous.activity nil)
                    "Direct activity activation shell event should include previous activity")
            (assert (= event.current.activity "direct-test")
                    "Direct activity activation shell event should include current activity")
            (assert (= app.active-world-runtime.requested-activity-id "direct-test")
                    "Direct activity activation should sync runtime requested activity")
            (set events [])
            (Activities.activate-activity "direct-two")
            (assert (= (# events) 1)
                    "Direct activity switching should emit one final workspace-shell-changed event")
            (local switch-event (. events 1))
            (assert (= switch-event.previous.activity "direct-test")
                    "Direct activity switching should not emit an intermediate nil activity event")
            (assert (= switch-event.current.activity "direct-two")
                    "Direct activity switching should emit the final active activity")
            true)))
      (app.workspace-shell-changed:disconnect handler true)
      (pcall (fn [] (Activities.unregister-activity "direct-test")))
      (pcall (fn [] (Activities.unregister-activity "direct-two")))
      (if ok result (error result)))))

(fn direct-activity-deactivation-emits-one-shell-change []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (set app.canvas {:build-context {}})
      (set app.canvas-visible? false)
      (set app.preferred-interaction-surface :scene)
      (set app.active-interaction-surface :scene)
      (var events [])
      (local handler
        (app.workspace-shell-changed:connect
          (fn [payload]
            (table.insert events payload))))
      (local (ok result)
        (pcall
          (fn []
            (Activities.register-activity
              {:id "direct-deactivate"
               :label "Direct Deactivate"
               :activate (fn [ctx]
                           (ctx:set-surface-state! {:canvas {:visible? true
                                                             :interactive? true}})
                           (ctx:set-preferred-interaction-surface! :canvas)
                           {})})
            (Activities.activate-activity "direct-deactivate")
            (set events [])
            (Activities.deactivate-active-activity)
            (assert (= (# events) 1)
                    "Direct activity deactivation should emit one final workspace-shell-changed event")
            (local event (. events 1))
            (assert (= event.previous.activity "direct-deactivate")
                    "Direct activity deactivation event should include previous activity")
            (assert (= event.current.activity nil)
                    "Direct activity deactivation event should include nil current activity")
            true)))
      (app.workspace-shell-changed:disconnect handler true)
      (pcall (fn [] (Activities.unregister-activity "direct-deactivate")))
      (if ok result (error result)))))

(fn active-activity-unregister-emits-one-shell-change []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (set app.canvas {:build-context {}})
      (set app.canvas-visible? false)
      (set app.preferred-interaction-surface :scene)
      (set app.active-interaction-surface :scene)
      (var events [])
      (local handler
        (app.workspace-shell-changed:connect
          (fn [payload]
            (table.insert events payload))))
      (local (ok result)
        (pcall
          (fn []
            (Activities.register-activity
              {:id "unregister-active"
               :label "Unregister Active"
               :activate (fn [ctx]
                           (ctx:set-surface-state! {:canvas {:visible? true
                                                             :interactive? true}})
                           (ctx:set-preferred-interaction-surface! :canvas)
                           {})})
            (Activities.activate-activity "unregister-active")
            (set events [])
            (Activities.unregister-activity "unregister-active")
            (assert (= (# events) 1)
                    "Unregistering the active activity should emit one final workspace-shell-changed event")
            (local event (. events 1))
            (assert (= event.previous.activity "unregister-active")
                    "Active unregister event should include previous activity")
            (assert (= event.current.activity nil)
                    "Active unregister event should include nil current activity")
            true)))
      (app.workspace-shell-changed:disconnect handler true)
      (pcall (fn [] (Activities.unregister-activity "unregister-active")))
      (if ok result (error result)))))

(fn failed-activity-deactivate-restores-shell-suppression []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (set app.suppress-workspace-shell-change? false)
      (Activities.register-activity
        {:id "active"
         :label "Active"
         :activate (fn [_ctx]
                     (set app.__active-activation-count
                          (+ (or app.__active-activation-count 0) 1))
                     {})
         :deactivate (fn [_ctx _session]
                       (error "deactivate boom"))})
      (Activities.register-activity
        {:id "next"
         :label "Next"
         :activate (fn [_ctx] {})})
      (Activities.activate-activity "active")
      (local registry app.activity-registry)
      (local (ok _err)
        (pcall
          (fn []
            (Activities.activate-activity "next"))))
      (assert (not ok)
              "Activity switch should fail when previous activity deactivation fails")
      (assert (= app.suppress-workspace-shell-change? false)
              "Failed previous deactivation should restore global shell suppression")
      (assert (= registry.suppress-workspace-shell-change? false)
              "Failed previous deactivation should restore registry shell suppression")
      (assert (= app.active-activity-id "active")
              "Failed previous deactivation should leave the previous activity active")
      (assert (= app.__active-activation-count 1)
              "Failed previous deactivation should not reactivate an activity that never deactivated")
      true)))

(fn theme-reapply-does-not-emit-transient-activity-events []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (set app.suppress-workspace-shell-change? false)
      (set app.themes {:set-theme (fn [_theme] true) :get-active-theme (fn [] {})})
      (set app.mark-active-world-hud-dirty (fn [] true)) (set app.activity-dock-changed (Signal))
      (var events []) (var dock-events [])
      (local handler (app.workspace-shell-changed:connect (fn [payload] (table.insert events payload))))
      (local dock-handler (app.activity-dock-changed:connect (fn [payload] (table.insert dock-events payload))))
      (local dock-builder (fn [_dock-ctx] (local layout (Layout {:name "test-graph-dock"})) {:layout layout :drop (fn [_self] (layout:drop) true)}))
      (local activate (fn [ctx] (ctx:set-left-dock-builder! dock-builder) {}))
      (Activities.register-activity {:id "graph" :label "Graph" :activate activate})
      (Activities.activate-activity "graph")
      (set events [])
      (ThemeActions.apply-theme :dark)
      (app.workspace-shell-changed:disconnect handler true) (app.activity-dock-changed:disconnect dock-handler true)
      (assert (= (# events) 0)
              "Theme reapply should suppress transient activity nil/reactivate shell events when final shell is unchanged")
      (assert (> (# dock-events) 0)
              "Theme reapply should emit activity-dock-changed for dock hook restoration")
      (assert app.activity-left-dock-builder
              "Theme reapply should restore graph activity left dock builder")
      (assert (= app.active-activity-id "graph")
              "Theme reapply should restore the previously active graph activity")
      true)))

(fn failed-activity-cleanup-restores-shell-suppression []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (set app.suppress-workspace-shell-change? false)
      (var earlier-cleanup-ran? false)
      (Activities.register-activity
        {:id "active"
         :label "Active"
         :activate (fn [_ctx] {})})
      (Activities.register-activity
        {:id "broken"
         :label "Broken"
         :activate (fn [ctx]
                     (ctx:defer-cleanup! (fn []
                                           (set earlier-cleanup-ran? true)))
                     (ctx:defer-cleanup! (fn []
                                           (error "cleanup boom")))
                     (error "activate boom"))})
      (Activities.activate-activity "active")
      (local registry app.activity-registry)
      (local (ok _err)
        (pcall
          (fn []
            (Activities.activate-activity "broken"))))
      (assert (not ok)
              "Activity switch should fail when failed activation cleanup fails")
      (assert (= app.suppress-workspace-shell-change? false)
              "Failed activation cleanup should restore global shell suppression")
      (assert (= registry.suppress-workspace-shell-change? false)
              "Failed activation cleanup should restore registry shell suppression")
      (assert (= app.active-activity-id "active")
              "Failed activation cleanup should still roll back to the previous activity")
      (assert earlier-cleanup-ran?
              "Failed activation cleanup should continue running older cleanup callbacks after one throws")
      true)))

(fn failed-activity-prepare-restores-previous-activity []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (set app.suppress-workspace-shell-change? false)
      (Activities.register-activity
        {:id "active"
         :label "Active"
         :activate (fn [ctx]
                     (ctx:set-root-actions! (fn [_context] []))
                     {})})
      (Activities.register-activity
        {:id "next"
         :label "Next"
         :activate (fn [_ctx] {})})
      (Activities.activate-activity "active")
      (set app.sync-interaction-surface-state
           (fn [_reason _previous]
             (error "prepare boom")))
      (local (ok err)
        (pcall
          (fn []
            (Activities.activate-activity "next"))))
      (assert (not ok)
              "Activity switch should fail when prepare-time hook clearing throws")
      (assert (and err (string.find err "prepare boom"))
              "Prepare failure should report the original failure")
      (assert (= app.suppress-workspace-shell-change? false)
              "Prepare failure should restore global shell suppression")
      (assert (= app.active-activity-id "active")
              "Prepare failure should roll back to previous app activity")
      (assert (= (Activities.active-activity-id) "active")
              "Prepare failure should roll back to previous registry activity")
      (assert (= (type app.activity-root-actions) :function)
              "Prepare failure should restore previous activity hooks")
      true)))

(fn failed-activity-commit-restores-previous-activity []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (set app.suppress-workspace-shell-change? false)
      (Activities.register-activity
        {:id "active"
         :label "Active"
         :activate (fn [ctx]
                     (ctx:set-root-actions! (fn [_context] []))
                     {})})
      (Activities.register-activity
        {:id "broken"
         :label "Broken"
         :activate (fn [ctx]
                     (ctx:set-root-actions! (fn [_context]
                                              [{:name "broken"}]))
                     (ctx:set-preferred-interaction-surface! :canvas)
                     {})})
      (Activities.activate-activity "active")
      (local registry app.activity-registry)
      (var events [])
      (local handler
        (app.workspace-shell-changed:connect
          (fn [payload]
            (table.insert events payload))))
      (set app.set-active-interaction-surface
           (fn [_surface _opts]
             (error "surface boom")))
      (local (ok err)
        (pcall
          (fn []
            (Activities.activate-activity "broken"))))
      (app.workspace-shell-changed:disconnect handler true)
      (assert (not ok)
              "Activity switch should fail when commit-time surface policy throws")
      (assert (and err (string.find err "surface boom"))
              "Activity switch commit failure should report the original failure")
      (assert (= app.suppress-workspace-shell-change? false)
              "Commit failure should restore global shell suppression")
      (assert (= registry.suppress-workspace-shell-change? false)
              "Commit failure should restore registry shell suppression")
      (assert (= app.active-activity-id "active")
              "Commit failure should roll back to the previous app activity")
      (assert (= (Activities.active-activity-id) "active")
              "Commit failure should roll back to the previous registry activity")
      (assert (= (type app.activity-root-actions) :function)
              "Commit failure should restore previous activity hooks")
      (assert (= (length (app.activity-root-actions {})) 0)
              "Commit failure should restore previous root action behavior")
      (assert (= (# events) 0)
              "Commit failure should not emit workspace-shell-changed")
      true)))

(fn failed-retained-activity-reactivation-invalidates-target-session []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (set app.suppress-workspace-shell-change? false)
      (var retained-arg-on-retry :unset)
      (var retained-resource nil)
      (Activities.register-activity
        {:id "active"
         :label "Active"
         :activate (fn [_ctx] {})})
      (Activities.register-activity
        {:id "retained"
         :label "Retained"
         :activate (fn [ctx retained]
                     (set retained-arg-on-retry retained)
                     (local resource (or retained {:valid? true}))
                     (set retained-resource resource)
                     (ctx:defer-cleanup! (fn []
                                           (set resource.valid? false)))
                     (ctx:set-preferred-interaction-surface! :canvas)
                     resource)})
      (Activities.activate-activity "retained")
      (local first-resource retained-resource)
      (Activities.activate-activity "active")
      (set app.set-active-interaction-surface
           (fn [_surface _opts]
             (error "surface boom")))
      (local (ok _err)
        (pcall
          (fn []
            (Activities.activate-activity "retained"))))
      (assert (not ok)
              "Retained activity reactivation should fail when commit-time surface policy throws")
      (assert (= (. app.activity-registry.sessions "retained") nil)
              "Failed retained reactivation should invalidate the retained target session after cleanup")
      (assert (= first-resource.valid? false)
              "Failed retained reactivation cleanup should mark the retained resource invalid")
      (set app.set-active-interaction-surface nil)
      (Activities.activate-activity "retained")
      (assert (= retained-arg-on-retry nil)
              "Retry after failed retained reactivation should not receive the invalidated retained session")
      (assert (not (= retained-resource first-resource))
              "Retry after failed retained reactivation should create a fresh retained resource")
      true)))

(fn bind-active-world-runtime-emits-shell-once-for-surface-sync []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (set app.canvas {:build-context {}})
      (set app.preferred-interaction-surface :scene)
      (set app.active-interaction-surface :scene)
      (set app.canvas-visible? false)
      (var event-count 0)
      (local handler
        (app.workspace-shell-changed:connect
          (fn [_payload]
            (set event-count (+ event-count 1)))))
      (app.bind-active-world-runtime {:id "test-world"}
                                     {:requested-activity-id nil
                                      :requested-activity-known? true
                                      :preferred-interaction-surface :canvas
                                      :canvas {:build-context {}}
                                      :restore-surface-state (fn [_self _canvas _hud] true)})
      (app.workspace-shell-changed:disconnect handler true)
      (assert (= event-count 1)
              "bind-active-world-runtime should not duplicate shell events for interaction surface sync")
      true)))

(fn bind-active-world-runtime-respects-shell-suppression []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (set app.canvas {:build-context {}})
      (set app.preferred-interaction-surface :scene)
      (set app.active-interaction-surface :scene)
      (set app.canvas-visible? false)
      (set app.suppress-workspace-shell-change? true)
      (var event-count 0)
      (local handler
        (app.workspace-shell-changed:connect
          (fn [_payload]
            (set event-count (+ event-count 1)))))
      (app.bind-active-world-runtime {:id "test-world"}
                                     {:requested-activity-id nil
                                      :requested-activity-known? true
                                      :preferred-interaction-surface :canvas
                                      :canvas {:build-context {}}
                                      :restore-surface-state (fn [_self _canvas _hud] true)})
      (app.workspace-shell-changed:disconnect handler true)
      (assert (= event-count 0)
              "bind-active-world-runtime should respect global shell suppression")
      true)))

(fn failed-pending-activity-restore-does-not-emit-shell-change []
  (with-restored-app-fields bind-state-keys
    (fn []
      (reset-state)
      (Main.install-app-shell!)
      (set app.activity-registry nil)
      (set app.active-world-runtime {:activity-session-state {:restore-test {:value 1}}})
      (set app.suppress-workspace-shell-change? false)
      (var events [])
      (local handler
        (app.workspace-shell-changed:connect
          (fn [payload]
            (table.insert events payload))))
      (Activities.register-activity
        {:id "restore-test"
         :label "Restore Test"
         :activate (fn [_ctx] {})
         :restore (fn [_ctx _session _state]
                    (error "restore boom"))})
      (local (ok _err)
        (pcall
          (fn []
            (Activities.activate-activity "restore-test"))))
      (app.workspace-shell-changed:disconnect handler true)
      (assert (not ok)
              "Activity activation should fail when pending session restore fails")
      (assert (= (# events) 0)
              "Failed pending activity restore should not emit workspace-shell-changed")
      (assert (= app.suppress-workspace-shell-change? false)
              "Failed pending activity restore should restore global shell suppression")
      (assert (= app.active-activity-id nil)
              "Failed pending activity restore should roll back active app activity")
      (assert (= (Activities.active-activity-id) nil)
              "Failed pending activity restore should roll back registry active activity")
      (assert (= (. app.activity-registry.sessions "restore-test") nil)
              "Failed pending activity restore should drop the newly-created failed session")
      (assert app.active-world-runtime.activity-session-state.restore-test
              "Failed pending activity restore should leave pending restore state available for retry")
      true)))

(table.insert tests {:name "Window resize updates viewport and layout root" :fn window-resize-updates-viewport-and-layout-root})
(table.insert tests {:name "Window pixel size change updates viewport" :fn window-pixel-size-change-updates-viewport})
(table.insert tests {:name "app.drop keeps engine events and clears layout root" :fn drop-keeps-engine-events-and-clears-layout-root})
(table.insert tests {:name "Non-resize events leave viewport unchanged" :fn other-events-leave-viewport-untouched})
(table.insert tests {:name "bind-active-world-runtime restores runtime interaction surface"
                     :fn bind-active-world-runtime-restores-runtime-interaction-surface})
(table.insert tests {:name "Activity policy can show noninteractive canvas"
                     :fn activity-policy-can-show-noninteractive-canvas})
(table.insert tests {:name "bind-active-world-runtime preserves explicit nil activity id"
                     :fn bind-active-world-runtime-preserves-explicit-nil-activity-id})
(table.insert tests {:name "bind-active-world-runtime clears inactive retained presentations"
                     :fn bind-active-world-runtime-clears-inactive-retained-presentations})
(table.insert tests {:name "bind-active-world-runtime defers activity id without canvas"
                      :fn bind-active-world-runtime-defers-activity-id-without-canvas})
(table.insert tests {:name "bind-active-world-runtime promotes active-activity-id to requested"
                       :fn bind-active-world-runtime-preserves-active-activity-id-as-requested})
(table.insert tests {:name "bind-active-world-runtime preserves previous runtime requested activity"
                       :fn bind-active-world-runtime-preserves-previous-runtime-requested-activity})
(table.insert tests {:name "bind-active-world-runtime restores panels after activity activation"
                      :fn bind-active-world-runtime-restores-panels-after-activity-activation})
(table.insert tests {:name "set-active-activity rejects unknown activities"
                     :fn set-active-activity-rejects-unknown})
(table.insert tests {:name "Activities ordered specs preserve registration order"
                     :fn activities-ordered-specs-preserve-registration-order})
(table.insert tests {:name "Invalid persisted activity id clears to nil"
                     :fn invalid-persisted-activity-id-clears-to-nil})
(table.insert tests {:name "Activity activation failure restores previous activity"
                      :fn activity-activation-failure-restores-previous-activity})
(table.insert tests {:name "Direct activity activation emits workspace shell change"
                     :fn direct-activity-activation-emits-workspace-shell-change})
(table.insert tests {:name "Direct activity deactivation emits one shell change"
                     :fn direct-activity-deactivation-emits-one-shell-change})
(table.insert tests {:name "Active activity unregister emits one shell change"
                     :fn active-activity-unregister-emits-one-shell-change})
(table.insert tests {:name "Failed activity deactivate restores shell suppression" :fn failed-activity-deactivate-restores-shell-suppression})
(table.insert tests {:name "Theme reapply does not emit transient activity events" :fn theme-reapply-does-not-emit-transient-activity-events})
(table.insert tests {:name "Failed activity cleanup restores shell suppression" :fn failed-activity-cleanup-restores-shell-suppression})
(table.insert tests {:name "Failed activity prepare restores previous activity" :fn failed-activity-prepare-restores-previous-activity})
(table.insert tests {:name "Failed activity commit restores previous activity" :fn failed-activity-commit-restores-previous-activity})
(table.insert tests {:name "Failed retained activity reactivation invalidates target session" :fn failed-retained-activity-reactivation-invalidates-target-session})
(table.insert tests {:name "Failed pending activity restore does not emit shell change" :fn failed-pending-activity-restore-does-not-emit-shell-change})
(table.insert tests {:name "bind-active-world-runtime emits shell once for surface sync" :fn bind-active-world-runtime-emits-shell-once-for-surface-sync})
(table.insert tests {:name "bind-active-world-runtime respects shell suppression" :fn bind-active-world-runtime-respects-shell-suppression})

(fn app-drop-active-input-before-state-teardown-body []
  (var last-state nil)
  (local states-host
    {:active-name (fn [_self] "normal")
     :set-state (fn [_self name] (set last-state name))
     :drop (fn [_self] nil)})
  (StateSystemBindings.bind-states-host states-host)
  (set app.states states-host)
  (var disconnected? false)
  (local input
    {:on-state-connected (fn [_self _payload] true)
     :on-state-disconnected (fn [_self _payload] (set disconnected? true))
     :on-key-down (fn [_self _payload] false)})
  (InputState.connect-input input)
  (assert (= (InputState.active-input) input)
          "Input should be active before drop")
  (local unit (Units.Unit
                {:id "test-drop-unit"
                 :load (fn [_ctx] nil)
                 :unload (fn [_ctx]
                           (InputState.disconnect-input input))}))
  (set app.unit-manager (if app.unit-manager app.unit-manager (UnitManager)))
  (app.unit-manager:register unit)
  (unit:load {})
  (assert (= (InputState.active-input) input)
          "Input must remain active after unit load")
  (Main.drop)
  (assert disconnected? "Input should have been disconnected during drop")
  (assert (not (InputState.active-input)) "No input should be active after drop"))

(fn app-drop-releases-active-input-before-state-teardown []
  (reset-state)
  (local original-renderers app.renderers)
  (local saved-intersectables app.intersectables)
  (local saved-clickables (assert app.clickables "test requires app.clickables"))
  (local saved-hoverables (assert app.hoverables "test requires app.hoverables"))
  (set app.renderers minimal-renderers)
  (local saved-movables app.movables)
  (local saved-resizables app.resizables)
  (local saved-system-cursors app.system-cursors)
  (local saved-states app.states)
  (local saved-composition (capture-app-fields [:graph-extension-registry :builtin-graph-extension-handles :entity-type-catalog]))
  (set app.builtin-graph-extension-handles nil)
  (local (ok err) (pcall app-drop-active-input-before-state-teardown-body))
  (restore-app-fields [:graph-extension-registry :builtin-graph-extension-handles :entity-type-catalog] saved-composition)
  (set app.renderers original-renderers)
  (when (not app.intersectables)
    (set app.intersectables saved-intersectables))
  (when (not app.clickables)
    (set app.clickables saved-clickables))
  (when (not app.hoverables)
    (set app.hoverables saved-hoverables))
  (when (not app.movables) (set app.movables saved-movables))
  (when (not app.resizables) (set app.resizables saved-resizables))
  (when (not app.system-cursors) (set app.system-cursors saved-system-cursors))
  (set app.states saved-states)
  (InputState.reset)
  (StateSystemBindings.bind-states-host saved-states)
  (when (not ok) (error err)))
(table.insert tests {:name "app.drop releases active input before state teardown" :fn app-drop-releases-active-input-before-state-teardown})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "main-events"
                       :tests tests})))

{:name "main-events"
 :tests tests
 :main main}
