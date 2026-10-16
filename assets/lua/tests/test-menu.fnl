(local glm (require :glm))
(local _ (require :main))
(local Menu (require :menu))
(local MenuManager (require :menu-manager))
(local Activities (require :activities))
(local RootContextMenuActions (require :root-context-menu-actions))
(local SandboxActivityActions (require :sandbox-activity-actions))
(local GraphActivityActions (require :graph-activity-actions))
(local DrawingActivityActions (require :drawing-activity-actions))
(local SceneTerrainRecovery (require :scene-terrain-recovery))
(local {: Layout} (require :layout))
(local fs (require :fs))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local LinkEntityStore (require :entities/link))

;; Capture the full activity-registry state before any menu test
;; stubs are registered.  After this module's tests complete the
;; captured state is restored so stub activities (sandbox, graph,
;; drawing), any active-activity state, sessions, and other mutable
;; fields do not leak into subsequent test modules.
(local _saved-registry-activities {})
(local _saved-registry-ordered-ids [])
(var _saved-active-activity-id nil)
(var _saved-active-activity-spec nil)
(var _saved-active-activity-session nil)
(local _saved-registry-sessions {})
(var _saved-registry-global-sessions nil)
(var _saved-suppress-workspace-shell-change? false)
(local _saved-registry-existed? (not (= app.activity-registry nil)))
(let [registry (if _saved-registry-existed? app.activity-registry
                   (Activities.ensure-registry))]
  (each [k v (pairs registry.activities)]
    (tset _saved-registry-activities k v))
  (each [_ id (ipairs registry.ordered-ids)]
    (table.insert _saved-registry-ordered-ids id))
  (set _saved-active-activity-id registry.active-activity-id)
  (set _saved-active-activity-spec registry.active-activity-spec)
  (set _saved-active-activity-session registry.active-activity-session)
  (each [k v (pairs registry.sessions)]
    (tset _saved-registry-sessions k v))
  (set _saved-registry-global-sessions registry.global-sessions)
  (set _saved-suppress-workspace-shell-change?
       registry.suppress-workspace-shell-change?))

(fn restore-activity-registry! []
  "Restore the full pre-module registry state so no stub or session leaks."
  (let [registry (Activities.ensure-registry)]
    ;; Remove activities registered by menu tests that were not in the
    ;; original state.
    (each [k _ (pairs registry.activities)]
      (when (not (. _saved-registry-activities k))
        (tset registry.activities k nil)))
    ;; Restore any activities that were replaced by menu test stubs.
    (each [k v (pairs _saved-registry-activities)]
      (tset registry.activities k v))
    ;; Restore ordered IDs.
    (set registry.ordered-ids [])
    (each [_ id (ipairs _saved-registry-ordered-ids)]
      (table.insert registry.ordered-ids id))
    ;; Restore active activity state.
    (set registry.active-activity-id _saved-active-activity-id)
    (set registry.active-activity-spec _saved-active-activity-spec)
    (set registry.active-activity-session _saved-active-activity-session)
    ;; Restore sessions: remove any session added by menu tests, then
    ;; bring back the original entries.
    (each [k _ (pairs registry.sessions)]
      (when (not (. _saved-registry-sessions k))
        (tset registry.sessions k nil)))
    (each [k v (pairs _saved-registry-sessions)]
      (tset registry.sessions k v))
    ;; Restore global-sessions and suppress flag.
    (set registry.global-sessions _saved-registry-global-sessions)
    (set registry.suppress-workspace-shell-change?
         _saved-suppress-workspace-shell-change?)
    ;; If the registry did not exist before the module loaded,
    ;; remove it so no newly-created object leaks to later modules.
    (when (not _saved-registry-existed?)
      (tset _G.app :activity-registry nil))
    true))

(local tests [])
(local reset-engine-events
  (fn []
    (when _G.reset-engine-events
      (_G.reset-engine-events))))

(fn make-icons-stub []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {65533 glyph
                           4242 glyph}})
  (local stub {:font font
               :codepoints {:note_add 4242
                            :add 4242
                            :delete 4242
                            :draw 4242
                            :brush 4242
                            :layers 4242
                            :link 4242
                             :playlist_add 4242
                             :tune 4242
                             :move_item 4242
                             :close 4242
                             :exit_to_app 4242}})
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

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "menu"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "menu-" (os.time) "-" temp-counter)))

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

(fn ensure-built-in-activities! []
  (local registry (Activities.ensure-registry))
  (when (and (. registry.activities "sandbox")
             (not (. (. registry.activities "sandbox") :menu-test?)))
    (Activities.unregister-activity "sandbox"))
  (when (not (. registry.activities "sandbox"))
    (Activities.register-activity
      {:id "sandbox"
       :menu-test? true
       :label "Sandbox"
       :icon "toys"
       :button-name "sandbox-activity"
       :show-in-switcher? true
       :activate (fn [ctx]
                   (ctx:set-root-actions! SandboxActivityActions.sandbox-root-actions)
                   (ctx:set-preferred-interaction-surface! :scene)
                   (ctx:set-surface-state! {:canvas {:visible? false :interactive? false}})
                   (ctx:set-target-enabled! (fn [target] true))
                   {:activity-id "sandbox"})
       :deactivate (fn [_ctx _session]
                     true)}))
  (when (and (. registry.activities "graph")
             (not (. (. registry.activities "graph") :menu-test?)))
    (Activities.unregister-activity "graph"))
  (when (not (. registry.activities "graph"))
    (Activities.register-activity
      {:id "graph"
       :menu-test? true
       :label "Graph"
       :icon "account_tree"
       :button-name "graph-activity"
       :show-in-switcher? true
       :activate (fn [ctx]
                    (ctx:set-context-enricher!
                      (fn [context]
                        (set context.graph
                             {:graph app.graph
                              :graph-map app.graph-map
                              :view app.graph-view
                              :selected-nodes (GraphActivityActions.selected-graph-nodes app.graph-view)})
                        context))
                    (ctx:set-root-actions! (. GraphActivityActions :graph-root-actions))
                    (ctx:set-selection-actions! nil)
                   {:activity-id "graph"})
       :deactivate (fn [_ctx _session]
                     true)}))
  (when (and (. registry.activities "drawing")
             (not (. (. registry.activities "drawing") :menu-test?)))
    (Activities.unregister-activity "drawing"))
  (when (not (. registry.activities "drawing"))
    (Activities.register-activity
      {:id "drawing"
       :menu-test? true
       :label "Draw"
       :icon "draw"
       :button-name "drawing-activity"
       :show-in-switcher? true
       :activate (fn [ctx]
                   (ctx:set-context-enricher!
                     (fn [context]
                       (local controller app.drawing-controller)
                       (local selection-count
                         (if (and controller controller.selection-count)
                             (controller:selection-count)
                             0))
                       (set context.drawing
                            {:controller controller
                             :active-layer (and controller controller.active-layer
                                                (controller:active-layer))
                             :selection-count selection-count
                             :layer-count (if (and controller controller.layer-count)
                                              (controller:layer-count)
                                              0)
                             :has-selection? (> selection-count 0)})
                       context))
                   (ctx:set-root-actions! (. DrawingActivityActions :drawing-root-actions))
                   (ctx:set-selection-actions! (. DrawingActivityActions :drawing-selection-actions))
                   (ctx:set-drawing-enabled! true)
                   {:activity-id "drawing"})
       :deactivate (fn [_ctx _session]
                     true)}))
  true)

(fn activate-activity! [mode-id]
  (ensure-built-in-activities!)
  (when (= (Activities.active-activity-id) mode-id)
    (Activities.deactivate-active-activity))
  (Activities.activate-activity mode-id)
  (set app.active-activity-id mode-id)
  (set app.active-interaction-surface :canvas)
  mode-id)

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate (fn [_self _count] 1))
  (set buffer.delete (fn [_self _handle] nil))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-clickables-stub []
  (local state {:right-void nil
                :left-void nil})
  (local stub {:state state})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  (set stub.register-right-click (fn [_self _obj] nil))
  (set stub.unregister-right-click (fn [_self _obj] nil))
  (set stub.register-double-click (fn [_self _obj] nil))
  (set stub.unregister-double-click (fn [_self _obj] nil))
  (set stub.unregister-left-click-void-callback (fn [_self cb]
                                                  (when (= state.left-void cb)
                                                    (set state.left-void nil))))
  (set stub.register-left-click-void-callback
       (fn [_self cb]
         (set state.left-void cb)))
  (set stub.register-right-click-void-callback
       (fn [_self cb]
         (set state.right-void cb)))
  (set stub.unregister-right-click-void-callback
       (fn [_self cb]
         (when (= state.right-void cb)
           (set state.right-void nil))))
  stub)

(fn make-hoverables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  stub)

(fn make-test-ctx [opts]
  (local options (or opts {}))
  (local triangle (make-vector-buffer))
  (local text-buffer (make-vector-buffer))
  (local ctx {:triangle-vector triangle
              :pointer-target options.pointer-target
              :clickables options.clickables
              :hoverables options.hoverables})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
  (set ctx.get-text-ssbo-batcher
       (fn [_self]
         {:upsert-text (fn [_batcher _key _opts] nil)
          :update-text-transform (fn [_batcher _key _opts] nil)
          :remove-text (fn [_batcher _key] nil)}))
  (set ctx.icons (or options.icons default-icons))
  ctx)

(fn make-hud-stub [ctx]
  (local overlay-layout
    (Layout {:name "test-overlay"
             :measurer (fn [self]
                         (set self.measure (glm.vec3 0 0 0)))
             :layouter (fn [_self] nil)}))
  (local overlay-root {:children [] :layout overlay-layout})
  (local hud {:build-context ctx
              :overlay-root overlay-root})
  (set hud.add-overlay-child
       (fn [_self opts]
         (local builder (and opts opts.builder))
         (when builder
           (local element (builder ctx (or opts.builder-options {})))
           (table.insert overlay-root.children {:element element
                                               :position (or opts.position (glm.vec3 0 0 0))})
           (overlay-layout:add-child element.layout)
           element)))
  (set hud.remove-overlay-child
       (fn [_self element]
         (var removed false)
         (each [idx metadata (ipairs overlay-root.children)]
           (when (and (not removed) (= metadata.element element))
             (set removed true)
             (overlay-layout:remove-child idx)
             (table.remove overlay-root.children idx)))
         (when (and removed element element.drop)
           (element:drop))
         removed))
  (set hud.screen-pos-ray
       (fn [_self pos]
         {:origin (glm.vec3 (or pos.x 0) (or pos.y 0) 10)
          :direction (glm.vec3 0 0 -1)}))
  (set ctx.pointer-target hud)
  hud)

(fn menu-actions-fire-and-increment-depth []
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local state {:calls 0})
  (local menu
    ((Menu {:actions [{:name "Alpha"
                       :on-click (fn [_button _event]
                                   (set state.calls (+ state.calls 1)))}
                      {:name "Beta"}]})
     ctx))
  (assert (= (length menu.buttons) 2) "Menu should build one button per action")
  (local button (. menu.buttons 1))
  (button:on-click {:button 1})
  (assert (= state.calls 1) "Menu should forward button clicks to action handlers")
  (menu.layout:measurer)
  (set menu.layout.size menu.layout.measure)
  (set menu.layout.position (glm.vec3 0 0 0))
  (set menu.layout.rotation (glm.quat 1 0 0 0))
  (set menu.layout.depth-offset-index 5)
  (menu.layout:layouter)
  (local layout (. button :layout))
  (assert (= layout.depth-offset-index 6) "Menu should bump depth offset index"))

(fn menu-grows-downward-from-click []
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local menu
    ((Menu {:actions [{:name "First"} {:name "Second"}]})
     ctx))
  (menu.layout:measurer)
  (set menu.layout.size menu.layout.measure)
  (set menu.layout.position (glm.vec3 0 0 0))
  (set menu.layout.rotation (glm.quat 1 0 0 0))
  (set menu.layout.depth-offset-index 0)
  (menu.layout:layouter)
  (local first-layout (. (. menu.buttons 1) :layout))
  (local second-layout (. (. menu.buttons 2) :layout))
  (assert (< second-layout.position.y first-layout.position.y)
          "Menu items should stack downward from click position"))

(fn menu-manager-opens-and-closes []
  (reset-engine-events)
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local hud (make-hud-stub ctx))
  (local state {:fired 0})
  (local manager
    (MenuManager {:clickables clickables
                  :hud hud
                  :root-actions [{:name "Action"
                                  :fn (fn [_button _event]
                                        (set state.fired (+ state.fired 1)))}]}))
  (local cb clickables.state.right-void)
  (local left-cb clickables.state.left-void)
  (assert cb "MenuManager should register a right-click void callback")
  (assert left-cb "MenuManager should register a left-click void callback")
  (cb {:screen {:x 1 :y 2}})
  (assert (= (length hud.overlay-root.children) 1) "Root menu should open on void right click")
  (local element (. (. hud.overlay-root.children 1) :element))
  (local button (. element.buttons 1))
  (button:on-click {:button 1})
  (assert (= state.fired 1) "Menu actions should invoke handlers")
  (assert (= (length hud.overlay-root.children) 0) "Menu should close after action click")
  (cb {:screen {:x 3 :y 4}})
  (assert (= (length hud.overlay-root.children) 1) "Menu should reopen after close")
  (left-cb {})
  (assert (= (length hud.overlay-root.children) 0) "Menu should close on void left click")
  (cb {:screen {:x 5 :y 6}})
  (assert (= (length hud.overlay-root.children) 1) "Menu should open again")
  (app.engine.events.key-down.emit {:key 27})
  (assert (= (length hud.overlay-root.children) 0) "Menu should close on escape")
  (manager:drop))

(fn find-button-by-name [menu name]
  (var found nil)
  (each [idx action (ipairs (or menu.actions []))]
    (when (and (not found) (= action.name name))
      (set found (. menu.buttons idx))))
  found)

(fn find-action-by-name [actions name]
  (var found nil)
  (each [_ action (ipairs (or actions []))]
    (when (and (not found) (= action.name name))
      (set found action)))
  found)

(fn find-dialog-action-row [dialog]
  (local titlebar-meta (. dialog.children 1))
  (local titlebar titlebar-meta.element)
  (local title-flex (. titlebar.children 2))
  (local action-row-meta (. title-flex.children (length title-flex.children)))
  action-row-meta.element)

(fn with-package-loaded-overrides [overrides f]
  (local originals {})
  (each [name value (pairs overrides)]
    (set (. originals name) (. package.loaded name))
    (set (. package.loaded name) value))
  (local (ok result) (pcall f))
  (each [name _value (pairs overrides)]
    (set (. package.loaded name) (. originals name)))
  (if ok
      result
      (error result)))

(fn menu-manager-root-show-link-entities-adds-related-nodes []
  (with-temp-dir
    (fn [root]
      (reset-engine-events)
      (ensure-built-in-activities!)
      (local clickables (make-clickables-stub))
      (local hoverables (make-hoverables-stub))
      (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
      (local hud (make-hud-stub ctx))

      (local store (LinkEntityStore.LinkEntityStore {:base-dir root}))
      (local original-get-default LinkEntityStore.get-default)
      (set LinkEntityStore.get-default (fn [_opts] store))

      (local graph (Graph {:with-start false
                            :link-store store :identity-store store.identity-store}))
      (local {:register-loader register-link-loader} (require :graph/nodes/link-entity))
      (register-link-loader graph {:store store})
      (local a (Graph.GraphNode {:key "node-a"}))
      (local b (Graph.GraphNode {:key "node-b"}))
      (graph:add-node a)
      (graph:add-node b)

      (local e1 (store:create-entity {:source-key "node-a" :target-key "node-b"}))
      (local e2 (store:create-entity {:source-key "node-c" :target-key "node-a"}))
      (local _e3 (store:create-entity {:source-key "node-d" :target-key "node-e"}))
      (local e4 (store:create-entity {:source-key "node-b" :target-key "node-x"}))

      (local original-graph app.graph)
      (local original-graph-map app.graph-map)
      (local original-view app.graph-view)
      (local original-surface app.active-interaction-surface)
      (local map (GraphMap.GraphMap {:graph graph :id "test-show-link-entities"}))
      (set app.graph graph)
      (set app.graph-map map)
      (set app.graph-view {:selection {:selected-nodes [a]}})
      (set app.active-interaction-surface :canvas)
      (activate-activity! "graph")

      (local manager
        (MenuManager {:clickables clickables
                      :hud hud}))

      (local (ok err)
        (pcall
          (fn []
            (local cb clickables.state.right-void)
            (assert cb "MenuManager should register a right-click void callback")

            (cb {:screen {:x 1 :y 2}})
            (local element (. (. hud.overlay-root.children 1) :element))
            (local button (find-button-by-name element "Show link entities"))
            (assert button "Root context menu should include 'Show link entities'")

            (local before (map:node-count))
            (button:on-click {:button 1})

            (assert (= (map:node-count) (+ before 2))
                    "Show link entities should add link entity nodes for selected endpoints")
            (local n1 (map:lookup (.. "link-entity:" (tostring e1.id))))
            (local n2 (map:lookup (.. "link-entity:" (tostring e2.id))))
            (assert n1 "Should add link entity node for e1")
            (assert n2 "Should add link entity node for e2")
            (assert (not (map:lookup (.. "link-entity:" (tostring e4.id))))
                    "Should not add link entity nodes unrelated to the selection")

            ;; Expanding selection to both a and b uses AND logic: only entities
            ;; whose source+target keys cover all selected keys are shown.
            ;; With [a b] selected, only e1 (node-a <-> node-b) matches;
            ;; e4 (node-b <-> node-x) does not because node-a is missing.
            (set app.graph-view {:selection {:selected-nodes [a b]}})
            (cb {:screen {:x 3 :y 4}})
            (local element-2 (. (. hud.overlay-root.children 1) :element))
            (local button-2 (find-button-by-name element-2 "Show link entities"))
            (assert button-2 "Root context menu should still include 'Show link entities'")
            (button-2:on-click {:button 1})
            (local n1-after (map:lookup (.. "link-entity:" (tostring e1.id))))
            (local n2-after (map:lookup (.. "link-entity:" (tostring e2.id))))
            (assert (= n1-after n1) "Action should not replace existing link entity nodes")
            (assert (= n2-after n2) "Existing link entity nodes from prior action should remain")
            (assert (not (map:lookup (.. "link-entity:" (tostring e4.id))))
                    "AND filtering should exclude entities not covering all selected keys"))))

      (manager:drop)
      (map:drop)
      (graph:drop)
      (set app.graph original-graph)
      (set app.graph-map original-graph-map)
      (set app.graph-view original-view)
      (set app.active-interaction-surface original-surface)
      (set LinkEntityStore.get-default original-get-default)

      (when (not ok)
        (error err)))))

(fn graph-root-add-to-map-loads-entered-key []
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local target {:children []})
  (var removed-count 0)
  (set target.add-panel-child
       (fn [self opts]
         (local builder (assert opts.builder "target.add-panel-child requires builder"))
         (var element nil)
         (local builder-options {})
         (each [key value (pairs (or opts.builder-options {}))]
           (set (. builder-options key) value))
         (set builder-options.on-close
              (fn [_dialog _button _event]
                (when element
                  (self:remove-panel-child element))))
         (set element (builder ctx builder-options))
         (table.insert self.children {:element element :opts opts})
         element))
  (set target.remove-panel-child
       (fn [self element]
         (var removed? false)
         (for [i (length self.children) 1 -1]
           (when (= (. self.children i :element) element)
             (table.remove self.children i)
             (set removed? true)))
         (when removed?
           (set removed-count (+ removed-count 1))
           (element:drop))
         removed?))

  (local graph (Graph {:with-start false}))
  (graph:register-key-loader "test"
                             (fn [key]
                               (Graph.GraphNode {:key key})))
  (local graph-map (GraphMap.GraphMap {:graph graph :id "test-add-to-map"}))
  (local actions (GraphActivityActions.graph-root-actions
                   {:graph {:graph-map graph-map}
                    :targets {:canvas target}}))
  (local action (find-action-by-name actions "Add to Map"))
  (assert action "Graph root actions should include Add to Map")
  (action.fn nil nil)
  (assert (= (length target.children) 1) "Add to Map should open a target panel")
  (local dialog (. (. target.children 1) :element))
  (assert dialog.input "Add to Map dialog should expose key input")
  (dialog.input:set-text "test:item")
  (local node (dialog:add-key-to-map))
  (assert node "Add to Map should return the loaded node")
  (assert (graph-map:lookup "test:item") "Add to Map should load the key into the active map")
  (local action-row (find-dialog-action-row dialog))
  (local close-button (. (. action-row.children 2) :element))
  (assert (= close-button.icon "close") "Add to Map dialog should keep DefaultDialog close button")
  (close-button:on-click {:button 1})
  (assert (= removed-count 1) "Add to Map close should remove the panel from its target")
  (assert (= (length target.children) 0) "Add to Map close should clear target panel metadata")
  (graph-map:drop)
  (graph:drop))

(fn graph-root-add-to-map-uses-current-map-after-switch []
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local target {:children []})
  (set target.add-panel-child
       (fn [self opts]
         (local builder (assert opts.builder "target.add-panel-child requires builder"))
         (local element (builder ctx {}))
         (table.insert self.children {:element element :opts opts})
         element))
  (set target.remove-panel-child
       (fn [self element]
         (var removed? false)
         (for [i (length self.children) 1 -1]
           (when (= (. self.children i :element) element)
             (table.remove self.children i)
             (set removed? true)))
         removed?))
  (local saved-graph-map app.graph-map)
  (local saved-runtime app.active-world-runtime)
  (local graph (Graph {:with-start false}))
  (graph:register-key-loader "test"
                             (fn [key]
                               (Graph.GraphNode {:key key})))
  (local first-map (GraphMap.GraphMap {:graph graph :id "first"}))
  (local second-map (GraphMap.GraphMap {:graph graph :id "second"}))
  (local (ok err)
    (pcall
      (fn []
        (set app.graph-map first-map)
        (set app.active-world-runtime {:graph-map first-map})
        (local actions (GraphActivityActions.graph-root-actions
                         {:graph {:graph-map first-map}
                          :targets {:canvas target}}))
        (local action (find-action-by-name actions "Add to Map"))
        (assert action "Graph root actions should include Add to Map")
        (action.fn nil nil)
        (local dialog (. (. target.children 1) :element))
        (assert dialog "Add to Map should open dialog")
        (set app.graph-map first-map)
        (set app.active-world-runtime {:graph-map first-map
                                       :graph-map-manager {:get-active-map (fn [_self] second-map)}})
        (dialog.input:set-text "test:item")
        (dialog:add-key-to-map)
        (assert (not (first-map:lookup "test:item"))
                "Stale Add to Map dialog should not mutate old active map")
        (assert (second-map:lookup "test:item")
                "Stale Add to Map dialog should mutate current active map"))))
  (set app.graph-map saved-graph-map)
  (set app.active-world-runtime saved-runtime)
  (first-map:drop)
  (second-map:drop)
  (graph:drop)
  (when (not ok)
    (error err)))

(fn graph-root-create-string-entity-uses-current-map-after-switch []
  (local saved-graph-map app.graph-map)
  (local saved-runtime app.active-world-runtime)
  (local graph (Graph {:with-start false}))
  (graph:register-key-loader "string-entity"
                             (fn [key]
                               (Graph.GraphNode {:key key})))
  (local first-map (GraphMap.GraphMap {:graph graph :id "first"}))
  (local second-map (GraphMap.GraphMap {:graph graph :id "second"}))
  (local (ok err)
    (pcall
      (fn []
        (set app.graph-map first-map)
        (set app.active-world-runtime {:graph-map first-map})
        (local actions (GraphActivityActions.graph-root-actions
                         {:graph {:graph-map first-map}
                          :targets {}}))
        (local action (find-action-by-name actions "Create String Entity"))
        (assert action "Graph root actions should include Create String Entity")
        (set app.active-world-runtime {:graph-map first-map
                                       :graph-map-manager {:get-active-map (fn [_self] second-map)}})
        (action.fn nil nil)
        (assert (= (first-map:node-count) 0)
                "Stale Create String Entity action should not mutate old active map")
        (assert (= (second-map:node-count) 1)
                "Stale Create String Entity action should mutate current active map"))))
  (set app.graph-map saved-graph-map)
  (set app.active-world-runtime saved-runtime)
  (first-map:drop)
  (second-map:drop)
  (graph:drop)
  (when (not ok)
    (error err)))

(fn menu-manager-root-add-cuboid-invokes-scene []
  (reset-engine-events)
  (ensure-built-in-activities!)
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local hud (make-hud-stub ctx))
  (local calls {:add-cuboid 0})
  (local original-scene app.scene)
  (local original-activity app.active-activity-id)
  (local original-surface app.active-interaction-surface)
  (set app.scene {:add-physics-body (fn [_self]
                                        (set calls.add-cuboid (+ calls.add-cuboid 1)))})
  (Activities.deactivate-active-activity)
  (Activities.activate-activity "sandbox")
  (set app.active-interaction-surface :scene)

  (local manager
    (MenuManager {:clickables clickables
                  :hud hud}))

  (local (ok err)
    (pcall
      (fn []
        (local cb clickables.state.right-void)
        (assert cb "MenuManager should register a right-click void callback")
        (cb {:screen {:x 10 :y 20}})
        (local element (. (. hud.overlay-root.children 1) :element))
        (local button (find-button-by-name element "add cuboid"))
        (assert button "Root context menu should include 'add cuboid'")
        (button:on-click {:button 1})
        (assert (= calls.add-cuboid 1)
                "add cuboid action should invoke scene:add-physics-body once"))))

  (manager:drop)
  (set app.scene original-scene)
  (set app.active-activity-id original-activity)
  (set app.active-interaction-surface original-surface)

  (when (not ok)
    (error err)))

(fn menu-manager-root-demo-video-player-opens-launchable []
  (reset-engine-events)
  (ensure-built-in-activities!)
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local hud (make-hud-stub ctx))
  (local calls {:open-panel 0
                :scene nil})
  (local original-scene app.scene)
  (local original-activity app.active-activity-id)
  (local original-surface app.active-interaction-surface)
  (set app.scene {:add-panel-child (fn [_self _opts] nil)})
  (Activities.deactivate-active-activity)
  (Activities.activate-activity "sandbox")
  (set app.active-interaction-surface :scene)

  (local manager
    (MenuManager {:clickables clickables
                  :hud hud}))

  (local overrides {})
  (set (. overrides "launchables/demo-video-cube")
       {:open-panel (fn [opts]
                      (set calls.open-panel (+ calls.open-panel 1))
                      (set calls.scene (and opts opts.scene))
                      nil)})

  (local run-test
    (fn []
      (local cb clickables.state.right-void)
      (assert cb "MenuManager should register a right-click void callback")
      (cb {:screen {:x 10 :y 20}})
      (local element (. (. hud.overlay-root.children 1) :element))
      (local button (find-button-by-name element "Demo Video Player"))
      (assert button "Root context menu should include 'Demo Video Player'")
      (button:on-click {:button 1})
      (assert (= calls.open-panel 1)
              "Demo Video Player action should invoke the launchable once")
      (assert (= calls.scene app.scene)
              "Demo Video Player action should pass app.scene to the launchable")))

  (local (ok err)
    (pcall
      (fn []
        (with-package-loaded-overrides overrides run-test))))

  (manager:drop)
  (set app.scene original-scene)
  (set app.active-activity-id original-activity)
  (set app.active-interaction-surface original-surface)

  (when (not ok)
    (error err)))

(fn menu-manager-root-demo-video-player-errors-loudly-when-unavailable []
  (reset-engine-events)
  (ensure-built-in-activities!)
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local hud (make-hud-stub ctx))
  (local original-scene app.scene)
  (local original-activity app.active-activity-id)
  (local original-surface app.active-interaction-surface)
  (set app.scene {:add-panel-child (fn [_self _opts] nil)})
  (Activities.deactivate-active-activity)
  (Activities.activate-activity "sandbox")
  (set app.active-interaction-surface :scene)

  (local manager
    (MenuManager {:clickables clickables
                  :hud hud}))

  (local overrides {})
  (set (. overrides "launchables/demo-video-cube") nil)
  (set (. overrides "video")
       {:available false
        :missing-reason "video disabled for test"})

  (local run-test
    (fn []
      (local cb clickables.state.right-void)
      (assert cb "MenuManager should register a right-click void callback")
      (cb {:screen {:x 10 :y 20}})
      (local element (. (. hud.overlay-root.children 1) :element))
      (local button (find-button-by-name element "Demo Video Player"))
      (assert button "Root context menu should include 'Demo Video Player'")
      (local (click-ok click-err)
        (pcall (fn []
                 (button:on-click {:button 1}))))
      (assert (not click-ok)
              "Demo Video Player should fail loudly when video support is unavailable")
      (assert (string.find (tostring click-err) "video disabled for test" 1 true)
              "Demo Video Player should surface the missing video reason")))

  (local (ok err)
    (pcall
      (fn []
        (with-package-loaded-overrides overrides run-test))))

  (manager:drop)
  (set app.scene original-scene)
  (set app.active-activity-id original-activity)
  (set app.active-interaction-surface original-surface)

  (when (not ok)
    (error err)))

(fn menu-manager-root-ball-invokes-scene []
  (reset-engine-events)
  (ensure-built-in-activities!)
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local hud (make-hud-stub ctx))
  (local calls {:add-object 0})
  (local original-scene app.scene)
  (local original-activity app.active-activity-id)
  (local original-surface app.active-interaction-surface)
  (set app.scene {:add-object (fn [_self _object]
                                (set calls.add-object (+ calls.add-object 1)))})
  (Activities.deactivate-active-activity)
  (Activities.activate-activity "sandbox")
  (set app.active-interaction-surface :scene)

  (local manager
    (MenuManager {:clickables clickables
                  :hud hud}))

  (local (ok err)
    (pcall
      (fn []
        (local cb clickables.state.right-void)
        (assert cb "MenuManager should register a right-click void callback")
        (cb {:screen {:x 10 :y 20}})
        (local element (. (. hud.overlay-root.children 1) :element))
        (local button (find-button-by-name element "ball"))
        (assert button "Root context menu should include 'ball'")
        (button:on-click {:button 1})
        (assert (= calls.add-object 1)
                "ball action should invoke scene:add-object once"))))

  (manager:drop)
  (set app.scene original-scene)
  (set app.active-activity-id original-activity)
  (set app.active-interaction-surface original-surface)

  (when (not ok)
    (error err)))

(fn menu-manager-root-light-ball-invokes-scene []
  (reset-engine-events)
  (ensure-built-in-activities!)
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local hud (make-hud-stub ctx))
  (local calls {:add-light-ball 0})
  (local original-scene app.scene)
  (local original-activity app.active-activity-id)
  (local original-surface app.active-interaction-surface)
  (set app.scene {:add-light-ball (fn [_self _opts]
                                    (set calls.add-light-ball (+ calls.add-light-ball 1)))})
  (Activities.deactivate-active-activity)
  (Activities.activate-activity "sandbox")
  (set app.active-interaction-surface :scene)

  (local manager
    (MenuManager {:clickables clickables
                  :hud hud}))

  (local (ok err)
    (pcall
      (fn []
        (local cb clickables.state.right-void)
        (assert cb "MenuManager should register a right-click void callback")
        (cb {:screen {:x 10 :y 20}})
        (local element (. (. hud.overlay-root.children 1) :element))
        (local button (find-button-by-name element "Add light ball"))
        (assert button "Root context menu should include 'Add light ball'")
        (button:on-click {:button 1})
        (assert (= calls.add-light-ball 1)
                "Add light ball action should invoke scene:add-light-ball once"))))

  (manager:drop)
  (set app.scene original-scene)
  (set app.active-activity-id original-activity)
  (set app.active-interaction-surface original-surface)

  (when (not ok)
    (error err)))

(fn menu-manager-root-recover-terrain-bound-objects-invokes-scene []
  (reset-engine-events)
  (ensure-built-in-activities!)
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local hud (make-hud-stub ctx))
  (local calls {:recover 0})
  (local original-scene app.scene)
  (local original-activity app.active-activity-id)
  (local original-surface app.active-interaction-surface)
  (local original-recover SceneTerrainRecovery.recover)
  (set app.scene {})
  (set SceneTerrainRecovery.recover
       (fn [_scene]
         (set calls.recover (+ calls.recover 1))))
  (Activities.deactivate-active-activity)
  (Activities.activate-activity "sandbox")
  (set app.active-interaction-surface :scene)

  (local manager
    (MenuManager {:clickables clickables
                  :hud hud}))

  (local (ok err)
    (pcall
      (fn []
        (local cb clickables.state.right-void)
        (assert cb "MenuManager should register a right-click void callback")
        (cb {:screen {:x 10 :y 20}})
        (local element (. (. hud.overlay-root.children 1) :element))
        (local button (find-button-by-name element "Recover Terrain-Bound Objects"))
        (assert button "Root context menu should include 'Recover Terrain-Bound Objects'")
        (button:on-click {:button 1})
        (assert (= calls.recover 1)
                "Recover Terrain-Bound Objects action should invoke scene recovery once"))))

  (manager:drop)
  (set app.scene original-scene)
  (set app.active-activity-id original-activity)
  (set app.active-interaction-surface original-surface)
  (set SceneTerrainRecovery.recover original-recover)

  (when (not ok)
    (error err)))

(fn menu-manager-root-drawing-actions-follow-activity []
  (reset-engine-events)
  (ensure-built-in-activities!)
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local hud (make-hud-stub ctx))
  (local calls {:add-vector 0
                :add-raster 0
                :duplicate 0
                :delete-layer 0})
  (local original-surface app.active-interaction-surface)
  (local original-mode app.active-activity-id)
  (local original-controller app.drawing-controller)
  (set app.active-interaction-surface :canvas)
  (activate-activity! "drawing")
  (set app.drawing-controller
       {:active-layer (fn [_self]
                        {:id "layer-1"
                         :name "Sketch"
                         :kind "vector"})
        :selection-count (fn [_self] 0)
        :layer-count (fn [_self] 2)
        :add-layer (fn [_self kind]
                     (if (= kind "vector")
                         (set calls.add-vector (+ calls.add-vector 1))
                         (set calls.add-raster (+ calls.add-raster 1))))
        :duplicate-active-layer (fn [_self]
                                  (set calls.duplicate (+ calls.duplicate 1))
                                  true)
        :delete-active-layer (fn [_self]
                               (set calls.delete-layer (+ calls.delete-layer 1))
                               true)})

  (local manager
    (MenuManager {:clickables clickables
                  :hud hud}))

  (local (ok err)
    (pcall
      (fn []
        (local cb clickables.state.right-void)
        (assert cb "MenuManager should register a right-click void callback")
        (cb {:screen {:x 5 :y 6}})
        (local element (. (. hud.overlay-root.children 1) :element))
        (assert (find-button-by-name element "Add Vector Layer")
                "Drawing root context menu should include Add Vector Layer")
        (assert (find-button-by-name element "Add Raster Layer")
                "Drawing root context menu should include Add Raster Layer")
        (local duplicate-button (find-button-by-name element "Duplicate Layer"))
        (assert duplicate-button
                "Drawing root context menu should include Duplicate Layer")
        (local delete-layer-button (find-button-by-name element "Delete Active Layer"))
        (assert delete-layer-button
                "Drawing root context menu should include Delete Active Layer when more than one layer exists")
        (assert (not (find-button-by-name element "Show link entities"))
                "Drawing root context menu should not reuse graph-only root actions")
        (duplicate-button:on-click {:button 1})
        (assert (= calls.duplicate 1)
                "Duplicate Layer should invoke drawing-controller:duplicate-active-layer")
        (cb {:screen {:x 5 :y 6}})
        (local reopened-element (. (. hud.overlay-root.children 1) :element))
        (local reopened-delete-layer-button (find-button-by-name reopened-element "Delete Active Layer"))
        (assert reopened-delete-layer-button
                "Drawing root context menu should rebuild Delete Active Layer after reopening")
        (reopened-delete-layer-button:on-click {:button 1})
        (assert (= calls.delete-layer 1)
                "Delete Active Layer should invoke drawing-controller:delete-active-layer"))))

  (manager:drop)
  (set app.active-interaction-surface original-surface)
  (set app.active-activity-id original-mode)
  (set app.drawing-controller original-controller)

  (when (not ok)
    (error err)))

(fn menu-manager-root-drawing-selection-actions-follow-selection-state []
  (reset-engine-events)
  (ensure-built-in-activities!)
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local hud (make-hud-stub ctx))
  (local calls {:delete-selection 0})
  (local original-surface app.active-interaction-surface)
  (local original-mode app.active-activity-id)
  (local original-controller app.drawing-controller)
  (set app.active-interaction-surface :canvas)
  (activate-activity! "drawing")
  (set app.drawing-controller
       {:active-layer (fn [_self]
                        {:id "layer-1"
                         :name "Sketch"
                         :kind "vector"})
        :selection-count (fn [_self] 2)
        :layer-count (fn [_self] 1)
        :add-layer (fn [_self _kind] nil)
        :duplicate-active-layer (fn [_self] true)
        :delete-active-layer (fn [_self] false)
        :on-delete-selection (fn [_self]
                               (set calls.delete-selection (+ calls.delete-selection 1))
                               true)})

  (local manager
    (MenuManager {:clickables clickables
                  :hud hud}))

  (local (ok err)
    (pcall
      (fn []
        (local cb clickables.state.right-void)
        (assert cb "MenuManager should register a right-click void callback")
        (cb {:screen {:x 9 :y 4}})
        (local element (. (. hud.overlay-root.children 1) :element))
        (local delete-selection-button (find-button-by-name element "Delete Selection"))
        (assert delete-selection-button
                "Drawing root context menu should include Delete Selection when something is selected")
        (assert (not (find-button-by-name element "Delete Active Layer"))
                "Drawing root context menu should omit Delete Active Layer when only one layer exists")
        (delete-selection-button:on-click {:button 1})
        (assert (= calls.delete-selection 1)
                "Delete Selection should invoke drawing-controller:on-delete-selection"))))

  (manager:drop)
  (set app.active-interaction-surface original-surface)
  (set app.active-activity-id original-mode)
  (set app.drawing-controller original-controller)

  (when (not ok)
    (error err)))

(fn root-context-menu-actions-normalize-partial-context []
  (ensure-built-in-activities!)
  (local original-surface app.active-interaction-surface)
  (local original-mode app.active-activity-id)
  (local original-controller app.drawing-controller)
  (local original-engine app.engine)
  (set app.active-interaction-surface :canvas)
  (activate-activity! "graph")
  (set app.engine {:quit (fn [] nil)})
  (set app.drawing-controller
       {:active-layer (fn [_self]
                        {:id "layer-1"
                         :name "Sketch"
                         :kind "vector"})
        :selection-count (fn [_self] 0)
        :layer-count (fn [_self] 2)
        :add-layer (fn [_self _kind] nil)
        :duplicate-active-layer (fn [_self] true)
        :delete-active-layer (fn [_self] true)})
  (local (ok actions)
    (pcall RootContextMenuActions.actions-for-context
           {:surface :canvas
            :activity "drawing"}))
  (set app.active-interaction-surface original-surface)
  (set app.active-activity-id original-mode)
  (set app.drawing-controller original-controller)
  (set app.engine original-engine)
  (assert ok
          "actions-for-context should normalize partial drawing contexts instead of crashing")
  (local has-action?
    (fn [name]
      (var found false)
      (each [_ action (ipairs actions)]
        (when (= action.name name)
          (set found true)))
      found))
  (assert (not (has-action? "Add Vector Layer"))
          "partial drawing contexts should not borrow drawing actions when drawing mode is not active")
  (assert (has-action? "Quit")
          "normalized partial drawing context should still include shared actions"))

(fn root-context-menu-actions-does-not-switch-active-mode-for_partial_context []
  (ensure-built-in-activities!)
  (local original-surface app.active-interaction-surface)
  (local original-mode app.active-activity-id)
  (local original-controller app.drawing-controller)
  (local original-set-active-activity app.set-active-activity)
  (var calls 0)
  (set app.active-interaction-surface :canvas)
  (activate-activity! "graph")
  (set app.set-active-activity
       (fn [_mode-id]
         (set calls (+ calls 1))
          (error "actions-for-context should not switch the active activity")))
  (set app.drawing-controller
       {:active-layer (fn [_self]
                        {:id "layer-1"
                         :name "Sketch"
                         :kind "vector"})
        :selection-count (fn [_self] 0)
        :layer-count (fn [_self] 2)
        :add-layer (fn [_self _kind] nil)
        :duplicate-active-layer (fn [_self] true)
        :delete-active-layer (fn [_self] true)})
  (local (ok actions)
    (pcall RootContextMenuActions.actions-for-context
           {:surface :canvas
            :activity "drawing"}))
  (set app.active-interaction-surface original-surface)
  (set app.active-activity-id original-mode)
  (set app.drawing-controller original-controller)
  (set app.set-active-activity original-set-active-activity)
  (assert ok
          "actions-for-context should build partial drawing context without switching the active activity")
  (assert (= calls 0)
          "actions-for-context should not call set-active-activity for a hypothetical context")
  (var found false)
  (each [_ action (ipairs actions)]
    (when (= action.name "Add Vector Layer")
      (set found true)))
  (assert (not found)
          "partial drawing context should not expose drawing actions without switching the active activity"))

(fn root-context-menu-actions-support-active-custom-activity []
  (local original-surface app.active-interaction-surface)
  (local original-mode app.active-activity-id)
  (local original-registry app.activity-registry)
  (local original-root-actions app.activity-root-actions)
  (local original-selection-actions app.activity-selection-actions)
  (local original-left-dock-builder app.activity-left-dock-builder)
  (local original-command-hints-provider app.activity-command-hints-provider)
  (local original-delete-selection app.activity-delete-selection)
  (local original-activate-focused app.activity-activate-focused)
  (local original-drawing-enabled app.activity-drawing-enabled?)
  (local original-target-enabled app.activity-target-enabled?)
  (local original-mode-update app.activity-update)
  (set app.activity-registry nil)
  (Activities.clear-activity-runtime-hooks!)
  (Activities.register-activity
    {:id "custom-note"
     :label "Custom"
     :icon "draw"
     :button-name "custom-note-activity"
     :show-in-switcher? true
     :activate (fn [ctx]
                 (ctx:set-root-actions!
                   (fn [_context]
                     [{:name "Custom Action"
                       :fn (fn [_button _event] true)}]))
                 {:activity-id "custom-note"})
     :deactivate (fn [_ctx _session]
                   true)})
  (Activities.activate-activity "custom-note")
  (set app.active-interaction-surface :canvas)
  (set app.active-activity-id "custom-note")
  (local (ok actions)
    (pcall RootContextMenuActions.actions-for-context
           {:surface :canvas
            :activity "custom-note"}))
  (set app.active-interaction-surface original-surface)
  (set app.active-activity-id original-mode)
  (set app.activity-registry original-registry)
  (set app.activity-root-actions original-root-actions)
  (set app.activity-selection-actions original-selection-actions)
  (set app.activity-left-dock-builder original-left-dock-builder)
  (set app.activity-command-hints-provider original-command-hints-provider)
  (set app.activity-delete-selection original-delete-selection)
  (set app.activity-activate-focused original-activate-focused)
  (set app.activity-drawing-enabled? original-drawing-enabled)
  (set app.activity-target-enabled? original-target-enabled)
  (set app.activity-update original-mode-update)
  (assert ok
          "actions-for-context should support active custom activities")
  (var found false)
  (each [_ action (ipairs actions)]
    (when (= action.name "Custom Action")
      (set found true)))
  (assert found
          "active custom activity should contribute its root actions"))

(table.insert tests {:name "Menu actions and depth offset" :fn menu-actions-fire-and-increment-depth})
(table.insert tests {:name "Menu grows downward from click" :fn menu-grows-downward-from-click})
(table.insert tests {:name "Menu manager opens and closes menu" :fn menu-manager-opens-and-closes})
(table.insert tests {:name "Menu root show link entities adds related nodes"
                     :fn menu-manager-root-show-link-entities-adds-related-nodes})
(table.insert tests {:name "Graph root Add to Map loads entered key"
                      :fn graph-root-add-to-map-loads-entered-key})
(table.insert tests {:name "Graph root Add to Map uses current map after switch"
                     :fn graph-root-add-to-map-uses-current-map-after-switch})
(table.insert tests {:name "Graph root Create String Entity uses current map after switch"
                     :fn graph-root-create-string-entity-uses-current-map-after-switch})
(table.insert tests {:name "Menu root add cuboid invokes scene"
                      :fn menu-manager-root-add-cuboid-invokes-scene})
(table.insert tests {:name "Menu root demo video player opens launchable"
                     :fn menu-manager-root-demo-video-player-opens-launchable})
(table.insert tests {:name "Menu root demo video player errors loudly when unavailable"
                     :fn menu-manager-root-demo-video-player-errors-loudly-when-unavailable})
(table.insert tests {:name "Menu root ball invokes scene"
                     :fn menu-manager-root-ball-invokes-scene})
(table.insert tests {:name "Menu root light ball invokes scene"
                     :fn menu-manager-root-light-ball-invokes-scene})
(table.insert tests {:name "Menu root recover terrain-bound objects invokes scene"
                     :fn menu-manager-root-recover-terrain-bound-objects-invokes-scene})
(table.insert tests {:name "Menu root drawing actions follow activity"
                     :fn menu-manager-root-drawing-actions-follow-activity})
(table.insert tests {:name "Menu root drawing selection actions follow selection state"
                     :fn menu-manager-root-drawing-selection-actions-follow-selection-state})
(table.insert tests {:name "Root context menu actions normalize partial context"
                     :fn root-context-menu-actions-normalize-partial-context})
(table.insert tests {:name "Root context menu actions stay side-effect free for partial activity context"
                     :fn root-context-menu-actions-does-not-switch-active-mode-for_partial_context})
(table.insert tests {:name "Root context menu actions support active custom activity"
                     :fn root-context-menu-actions-support-active-custom-activity})

;; Cleanup test: always runs last and restores the activity registry to
;; its pre-module state.  This prevents menu test stub activities from
;; contaminating later test modules (e.g. test-sandbox-activity).
(table.insert tests {:name "test-menu cleanup: restore activity registry state"
                     :fn restore-activity-registry!})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "menu"
                       :tests tests
                       :teardown restore-activity-registry!})))

{:name "menu"
 :tests tests
 :main main}
