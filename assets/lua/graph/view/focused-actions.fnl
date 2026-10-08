(fn resolve-keyboard-node-menu-position [deps node]
    (local graph-position ((assert deps.get-position "FocusedActions requires :get-position for menus") nil node))
    (local pointer-target deps.pointer-target)
    (local selector deps.selector)
    (local project (or (and pointer-target pointer-target.project) (and selector selector.project)))
    (assert (= (type project) :function)
            "GraphView focused node menu requires pointer target or selector project")
    (assert (and app.hud app.hud.screen-pos-ray)
            "GraphView focused node menu requires HUD screen-pos-ray")
    (local screen (project graph-position {}))
    (assert (and screen screen.x screen.y) "GraphView focused node menu project must return screen coordinates")
    (local viewport-utils (require :viewport-utils))
    (local input-pos (viewport-utils.viewport-pos->input-pos screen (viewport-utils.to-table app.viewport) app.engine))
    (assert (and input-pos input-pos.x input-pos.y) "GraphView focused node menu must convert projected viewport coordinates to logical input")
    (local ray (app.hud:screen-pos-ray {:x input-pos.x :y input-pos.y}))
    (assert (and ray ray.origin ray.direction)
            "GraphView focused node menu HUD screen-pos-ray must return a ray")
    (local dz (or ray.direction.z 0))
    (assert (not (= dz 0))
            "GraphView focused node menu HUD ray must intersect the HUD plane")
    (local t (/ (- 0 ray.origin.z) dz))
    (+ ray.origin (* ray.direction t)))

(fn install! [view deps]
    (assert view "FocusedActions.install! requires view")
    (local options (assert deps "FocusedActions.install! requires deps"))
    (assert options.focused-node "FocusedActions.install! requires :focused-node")
    (assert options.focused-node-actions "FocusedActions.install! requires :focused-node-actions")
    (assert options.run-focused-node-action-slot "FocusedActions.install! requires :run-focused-node-action-slot")
    (assert options.open-focused-node-menu "FocusedActions.install! requires :open-focused-node-menu")
    (assert options.copy-focused-node-key "FocusedActions.install! requires :copy-focused-node-key")
    (assert options.remove-focused-node-from-map "FocusedActions.install! requires :remove-focused-node-from-map")
    (assert options.reveal-focused-node "FocusedActions.install! requires :reveal-focused-node")
    (set view.focused-node (fn [self] (options.focused-node self)))
    (set view.has-focused-node? (fn [self] (if (self:focused-node) true false)))
    (set view.focused-node-actions (fn [self] (options.focused-node-actions self)))
    (set view.run-focused-node-action-slot (fn [self slot] (options.run-focused-node-action-slot self slot)))
    (set view.open-focused-node-menu (fn [self] (options.open-focused-node-menu self)))
    (set view.copy-focused-node-key (fn [self] (options.copy-focused-node-key self)))
    (set view.remove-focused-node-from-map (fn [self] (options.remove-focused-node-from-map self)))
    (set view.reveal-focused-node (fn [self opts] (options.reveal-focused-node self opts)))
    (when options.toggle-node-presentation
        (set view.toggle-focused-node-preview
             (fn [self] (options.toggle-node-presentation self))))
    view)

(fn spatial-deps [deps]
    (local options (assert deps "FocusedActions.spatial-deps requires deps"))
    {:focused-node (fn [_self] ((assert options.focused-node "FocusedActions.spatial-deps requires :focused-node")))
     :focused-node-actions (fn [self]
                             ((assert options.assert-not-dropped "FocusedActions.spatial-deps requires :assert-not-dropped") "focused-node-actions")
                             (local node ((assert options.focused-node "FocusedActions.spatial-deps requires :focused-node")))
                             (if node (self:node-actions node) []))
     :run-focused-node-action-slot (fn [self index]
                                     ((assert options.assert-not-dropped "FocusedActions.spatial-deps requires :assert-not-dropped") "run-focused-node-action-slot")
                                     (if (not (= (type index) :number))
                                         false
                                         (do
                                             (local action (. (self:focused-node-actions) index))
                                             (if (and action (= (type action.fn) :function))
                                                 (do
                                                     (action.fn nil {})
                                                     true)
                                                 false))))
     :open-focused-node-menu (fn [self]
                               ((assert options.assert-not-dropped "FocusedActions.spatial-deps requires :assert-not-dropped") "open-focused-node-menu")
                               (local node ((assert options.focused-node "FocusedActions.spatial-deps requires :focused-node")))
                               (local manager ((assert options.get-menu-manager "FocusedActions.spatial-deps requires :get-menu-manager")))
                               (if (and node manager)
                                   (do
                                       (manager:open {:actions (self:focused-node-actions)
                                                      :position (resolve-keyboard-node-menu-position options node)})
                                       true)
                                   false))
     :toggle-node-presentation (fn [_self]
                                 ((assert options.assert-not-dropped "FocusedActions.spatial-deps requires :assert-not-dropped") "toggle-focused-node-preview")
                                 (local node ((assert options.focused-node "FocusedActions.spatial-deps requires :focused-node")))
                                 (if node
                                     (do
                                         ((assert options.toggle-node-presentation "FocusedActions.spatial-deps requires :toggle-node-presentation") node)
                                         true)
                                     false))
     :copy-focused-node-key (fn [_self]
                              ((assert options.assert-not-dropped "FocusedActions.spatial-deps requires :assert-not-dropped") "copy-focused-node-key")
                              (local node ((assert options.focused-node "FocusedActions.spatial-deps requires :focused-node")))
                              (if node
                                  (do
                                      (local runtime-gl (require :gl))
                                      (runtime-gl.clipboard-set (tostring node.key))
                                      true)
                                  false))
     :remove-focused-node-from-map (fn [_self]
                                     ((assert options.assert-not-dropped "FocusedActions.spatial-deps requires :assert-not-dropped") "remove-focused-node-from-map")
                                     (local node ((assert options.focused-node "FocusedActions.spatial-deps requires :focused-node")))
                                     (if node
                                         (do
                                             (local graph-map options.graph-map)
                                             (> (graph-map:remove-nodes [node]) 0))
                                         false))
     :reveal-focused-node (fn [self _opts]
                            ((assert options.assert-not-dropped "FocusedActions.spatial-deps requires :assert-not-dropped") "reveal-focused-node")
                            (local node ((assert options.focused-node "FocusedActions.spatial-deps requires :focused-node")))
                            (if node
                                (do
                                    (self:reveal-node node {:select? true :focus? true :center? true})
                                    true)
                                false))})

{:install! install!
 :spatial-deps spatial-deps
 :resolve-keyboard-node-menu-position resolve-keyboard-node-menu-position}
