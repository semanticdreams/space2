(local glm (require :glm))
(local {: Layout} (require :layout))
(local Rectangle (require :rectangle))
(local Padding (require :padding))
(local Stack (require :stack))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local SearchView (require :search-view))
(local Text (require :text))
(local GraphViewUtils (require :graph/view/utils))
(local {: resolve-chrome-background} (require :widget-theme-utils))

(var compare-node-items nil)
(var active-map-change-handler nil)
(var map-switch-handler nil)
(var map-row-button-builder nil)
(var handle-new-map nil)
(var handle-delete-map nil)
(var action-flex-builder nil)
(var add-start-handler nil)
(var reveal-handler nil)
(var open-handler nil)
(var node-row-builder nil)
(var search-view-builder nil)
(var background-builder nil)
(var content-flex-builder nil)
(var content-children nil)

(local sidebar-width 14.0)
(local map-label-max-length 27)
(local finder-label-max-length 26)

(fn current-sidebar-width [state]
    (if state.resolved-sidebar-width state.resolved-sidebar-width sidebar-width))

(fn finder-content-width-provider [state]
    (fn [] (- (current-sidebar-width state) 0.5)))

(fn record-label [state label]
    (table.insert state.visible-labels label)
    label)

(fn current-selected-count [state]
    (if state.selected-count-provider
        (state.selected-count-provider)
        0))

(fn node-display-label [node]
    (tostring (if node.label node.label node.key)))

(fn active-node-items [state]
    (local items [])
    (when state.active-map
        (each [_ node (pairs state.active-map.nodes)]
            (when node
                (table.insert items [node (node-display-label node)]))))
    (table.sort items compare-node-items)
    items)

(set compare-node-items
     (fn [a b]
         (< (tostring (. a 2)) (tostring (. b 2)))))

(fn panel-bg [state]
    (resolve-chrome-background state.theme :panel))

(fn text-builder [state label color scale]
    (record-label state label)
    (fn [ic]
        ((Text {:text label :color color :scale (if scale scale 0.82)}) ic)))

(fn drop-content [state]
    (when state.content-entity
        (state.content-entity:drop)
        (set state.content-entity nil)))

(fn request-rebuild [state _payload]
    (set state.rebuild-requested? true))

(fn disconnect-active-map [state]
    (when state.active-map
        (when state.active-node-added-handler
            (state.active-map.node-added:disconnect state.active-node-added-handler true)
            (set state.active-node-added-handler nil))
        (when state.active-node-removed-handler
            (state.active-map.node-removed:disconnect state.active-node-removed-handler true)
            (set state.active-node-removed-handler nil))
        (when state.active-node-replaced-handler
            (state.active-map.node-replaced:disconnect state.active-node-replaced-handler true)
            (set state.active-node-replaced-handler nil))
        (when state.active-edge-added-handler
            (state.active-map.edge-added:disconnect state.active-edge-added-handler true)
            (set state.active-edge-added-handler nil))
        (when state.active-edge-removed-handler
            (state.active-map.edge-removed:disconnect state.active-edge-removed-handler true)
            (set state.active-edge-removed-handler nil))
        (set state.active-map nil)))

(fn sync-active-map [state]
    (local current (state.manager:get-active-map))
    (when (not (= current state.active-map))
        (disconnect-active-map state)
        (set state.active-map current)
        (when state.active-map
            (local handler (active-map-change-handler state))
            (set state.active-node-added-handler (state.active-map.node-added:connect handler))
            (set state.active-node-removed-handler (state.active-map.node-removed:connect handler))
            (set state.active-node-replaced-handler (state.active-map.node-replaced:connect handler))
            (set state.active-edge-added-handler (state.active-map.edge-added:connect handler))
            (set state.active-edge-removed-handler (state.active-map.edge-removed:connect handler)))))

(set active-map-change-handler
     (fn [state]
         (fn [payload]
             (request-rebuild state payload))))

(fn default-text-color [state]
    (local theme state.theme)
    (if (and theme theme.text theme.text.default)
        theme.text.default
        (glm.vec4 0.95 0.95 0.95 1.0)))

(fn accent-color [state]
    (local theme state.theme)
    (if (and theme theme.accent)
        theme.accent
        (glm.vec4 0.2 0.6 1.0 1.0)))

(fn build-padded-text [state label color scale insets]
    (fn [ic]
        ((Padding {:edge-insets insets
                   :child (text-builder state label color scale)})
         ic)))

(fn build-title [state muted-color]
    (build-padded-text state "Graph Maps" muted-color 0.85 [0.35 0.25 0.2 0.25]))

(fn build-switch-title [state muted-color]
    (build-padded-text state "Switch Map" muted-color 0.72 [0.05 0.25 0.1 0.25]))

(fn build-selected-count [state selected-count color]
    (build-padded-text state (.. "Selected: " selected-count) color 0.72 [0.05 0.25 0.2 0.25]))

(fn build-finder-title [state muted-color]
    (build-padded-text state "Find Node" muted-color 0.72 [0.05 0.25 0.1 0.25]))

(fn map-row-label [entry active-id]
    (local map-name (if entry.name entry.name entry.id))
    (local is-active? (= entry.id active-id))
    (local marker (if is-active? " *" ""))
    (.. map-name marker "  " entry.node-count "n/" entry.edge-count "e"))

(fn ellipsize [label max-length]
    (local safe-label (if label label ""))
    (GraphViewUtils.truncate-with-ellipsis (tostring safe-label) max-length))

(fn map-row-display-label [entry active-id]
    (ellipsize (map-row-label entry active-id) map-label-max-length))

(fn finder-display-label [label]
    (ellipsize label finder-label-max-length))

(fn build-map-row-button [state entry label is-active? ic]
    ((Button {:text label
              :padding [0.2 0.25]
              :enabled? (not is-active?)
              :focusable? true
              :variant :ghost
              :on-click (map-switch-handler state entry)})
     ic))

(set map-switch-handler
     (fn [state entry]
         (fn [_ _]
             (state.manager:switch-map! entry.id))))

(fn build-map-row [state entry active-id]
    (local label (record-label state (map-row-display-label entry active-id)))
    (local is-active? (= entry.id active-id))
    (fn [ic]
        ((Padding {:edge-insets [0.15 0.25 0.15 0.25]
                   :child (map-row-button-builder state entry label is-active?)})
         ic)))

(set map-row-button-builder
     (fn [state entry label is-active?]
         (fn [ic]
             (build-map-row-button state entry label is-active? ic))))

(fn build-separator []
    (fn [ic]
        ((Rectangle {:color (glm.vec4 0.25 0.25 0.3 1.0)
                     :size (glm.vec3 0 0 0)})
         ic)))

(fn action-enabled? [enabled?]
    (if (= enabled? nil) true enabled?))

(fn action-variant [variant]
    (if variant variant :secondary))

(fn build-action-button [state label on-click enabled? variant]
    (record-label state label)
    (fn [ic]
        ((Button {:text label
                  :padding [0.3 0.22]
                  :focusable? false
                  :enabled? (action-enabled? enabled?)
                  :on-click on-click
                  :variant (action-variant variant)})
         ic)))

(fn new-map-handler [state]
    (fn [_ _]
        (handle-new-map state)))

(fn rename-map-handler [state]
    (fn [_ _]
        (local current-name
            (if state.manager.active-map-name
                state.manager.active-map-name
                state.manager.active-map-id))
        (state.manager:rename-map! state.manager.active-map-id (.. current-name "*"))))

(fn delete-map-handler [state]
    (fn [_ _]
        (handle-delete-map state)))

(set handle-new-map
     (fn [state]
    (local sid (string.format "map-%d" (math.floor state.manager.next-map-id)))
    (state.manager:create-map! sid sid)
    (state.manager:switch-map! sid)))

(fn find-other-map-id [state target-id]
    (var other-id nil)
    (each [_ m (ipairs (state.manager:list-maps))]
        (when (and (not other-id) (not= m.id target-id))
            (set other-id m.id)))
    other-id)

(set handle-delete-map
     (fn [state]
    (local target-id state.manager.active-map-id)
    (local other-id (find-other-map-id state target-id))
    (when other-id
        (state.manager:switch-map! other-id)
        (state.manager:delete-map! target-id))))

(fn action-children [state maps-count]
    [(FlexChild (build-action-button state "New" (new-map-handler state) true nil) 0)
     (FlexChild (build-action-button state
                                     "Rename"
                                     (rename-map-handler state)
                                     true
                                     nil)
                0)
     (FlexChild (build-action-button state
                                     "Delete Map"
                                     (delete-map-handler state)
                                     (> maps-count 1)
                                     :danger)
                0)])

(fn build-action-flex [state maps-count ic]
    ((Flex {:direction :horizontal
            :gap 0.25
            :children (action-children state maps-count)})
     ic))

(fn build-actions [state maps-count]
    (fn [ic]
        ((Padding {:edge-insets [0.3 0.25 0.25 0.25]
                   :child (action-flex-builder state maps-count)})
         ic)))

(set action-flex-builder
     (fn [state maps-count]
         (fn [ic]
             (build-action-flex state maps-count ic))))

(fn handle-add-start [state]
    (local current-map (assert (state.manager:get-active-map)
                                "Add Start requires an active graph map"))
    (assert current-map.add-start-node! "Add Start requires GraphMap:add-start-node!")
    (current-map:add-start-node!)
    (request-rebuild state {:cause :add-start}))

(fn build-add-start [state]
    (build-action-button state "Add Start" (add-start-handler state) true nil))

(set add-start-handler
     (fn [state]
         (fn [_button _event]
             (handle-add-start state))))

(fn reveal-node [state node event]
    (when state.node-reveal-handler
        (state.node-reveal-handler node event)))

(fn open-node [state node event]
    (when state.node-open-handler
        (state.node-open-handler node event)))

(fn build-node-row [state item ic]
    (local node (. item 1))
    (local full-label (tostring (. item 2)))
    (local label (record-label state (finder-display-label full-label)))
    ((Button {:text label
              :padding [0.2 0.25]
              :focusable? true
              :variant :ghost
              :on-click (reveal-handler state node)
              :on-double-click (open-handler state node)})
     ic))

(set reveal-handler
     (fn [state node]
         (fn [_button event]
             (reveal-node state node event))))

(set open-handler
     (fn [state node]
         (fn [_button event]
             (open-node state node event))))

(set node-row-builder
     (fn [state]
         (fn [item row-ctx]
             (build-node-row state item row-ctx))))

(fn build-search-view [state ic]
    ((SearchView {:items (active-node-items state)
                  :placeholder "Find node"
                  :items-per-page 8
                  :show-head false
                  :builder (node-row-builder state)})
     ic))

(fn fixed-width-child [name width-provider child-builder]
    (fn [ic]
        (local child (child-builder ic))
        (fn measurer [self]
            (local width (width-provider))
            (child.layout:measurer)
            (set self.measure (glm.vec3 width child.layout.measure.y child.layout.measure.z)))
        (fn constrained-measurer [self constraints]
            (local width (width-provider))
            (if (and constraints constraints.max)
                (child.layout:measure-constrained
                    {:max (glm.vec3 width constraints.max.y constraints.max.z)})
                (child.layout:measurer))
            (set self.measure (glm.vec3 width child.layout.measure.y child.layout.measure.z)))
        (fn layouter [self]
            (local width (width-provider))
            (set child.layout.position self.position)
            (set child.layout.size (glm.vec3 width self.size.y self.size.z))
            (set child.layout.rotation self.rotation)
            (set child.layout.clip-region self.clip-region)
            (set child.layout.depth-offset-index self.depth-offset-index)
            (child.layout:layouter))
        (local layout (Layout {:name name
                               :measurer measurer
                               :constrained-measurer constrained-measurer
                               :layouter layouter
                               :children [child.layout]}))
        {:layout layout
         :drop (fn [_self]
                 (layout:drop)
                 (child:drop))}))

(fn build-finder [state]
    (fn [ic]
        ((Padding {:edge-insets [0.15 0.25 0.25 0.25]
                    :child (fixed-width-child "graph-map-sidebar-finder-width"
                                              (finder-content-width-provider state)
                                              (search-view-builder state))})
         ic)))

(set search-view-builder
     (fn [state]
         (fn [ic]
             (build-search-view state ic))))

(fn build-background [state ic]
    ((Rectangle {:color (panel-bg state)}) ic))

(fn build-content-flex [state maps selected-count ic]
    ((Flex {:axis 2
            :spacing 0.0
            :xalign :stretch
            :children (content-children state
                                        maps
                                        state.manager.active-map-id
                                        (length maps)
                                        selected-count)})
     ic))

(fn stack-children [state maps selected-count]
    [(background-builder state)
     (content-flex-builder state maps selected-count)])

(set background-builder
     (fn [state]
         (fn [ic]
             (build-background state ic))))

(set content-flex-builder
     (fn [state maps selected-count]
         (fn [ic]
             (build-content-flex state maps selected-count ic))))

(fn append-map-rows [state content-children maps active-id]
    (each [_ entry (ipairs maps)]
        (table.insert content-children (FlexChild (build-map-row state entry active-id) 0))))

(set content-children
     (fn [state maps active-id maps-count selected-count]
    (local muted-color (glm.vec4 0.55 0.55 0.55 1.0))
    (local children
        [(FlexChild (build-title state muted-color) 0)
         (FlexChild (build-actions state maps-count) 0)
         (FlexChild (build-switch-title state muted-color) 0)])
    (append-map-rows state children maps active-id)
    (table.insert children (FlexChild (build-separator) 0))
    (table.insert children (FlexChild (build-add-start state) 0))
    (table.insert children (FlexChild (build-selected-count state selected-count (default-text-color state)) 0))
    (table.insert children (FlexChild (build-finder-title state muted-color) 0))
    (table.insert children (FlexChild (build-finder state) 1))
    children))

(fn rebuild-children [state]
    (sync-active-map state)
    (drop-content state)
    (set state.visible-labels [])
    (local maps (state.manager:list-maps))
    (local selected-count (current-selected-count state))
    (set state.last-selected-count selected-count)
    (state.root-layout:clear-children)
    (set state.content-entity
         ((Stack {:children
                  (stack-children state maps selected-count)})
          state.ctx))
    (state.root-layout:add-child state.content-entity.layout))

(fn sidebar-height-constraint [self constraints]
    (if (and constraints constraints.max constraints.max.y (> constraints.max.y 0))
        constraints.max.y
        (if (and self.size self.size.y (> self.size.y 0))
            self.size.y
            nil)))

(fn measure-content [state max-height]
    (if max-height
        (state.content-entity.layout:measure-constrained
            {:max (glm.vec3 100000.0 max-height 0)})
        (state.content-entity.layout:measurer)))

(fn sidebar-measurer [state self constraints]
     (if state.content-entity
         (do
             (local max-height (sidebar-height-constraint self constraints))
             (set state.resolved-sidebar-width sidebar-width)
             (measure-content state max-height)
             (set state.resolved-sidebar-width
                  (math.max sidebar-width state.content-entity.layout.measure.x))
             (measure-content state max-height)
             (local measured-height
                    (if max-height
                        (math.min max-height state.content-entity.layout.measure.y)
                        state.content-entity.layout.measure.y))
             (set self.measure (glm.vec3 (current-sidebar-width state)
                                         measured-height
                                         state.content-entity.layout.measure.z)))
        (do
            (set state.resolved-sidebar-width sidebar-width)
            (set self.measure (glm.vec3 sidebar-width 0 0)))))

(fn sidebar-layouter [state self]
     (local self-size (if self.size self.size (glm.vec3 0 0 0)))
     (local resolved-width (current-sidebar-width state))
    (local allocated-size
        (glm.vec3 resolved-width
                  (if (> self-size.y 0) self-size.y self.measure.y)
                  (math.max self.measure.z self-size.z)))
    (set self.size allocated-size)
    (when state.content-entity
        (set state.content-entity.layout.position self.position)
        (set state.content-entity.layout.size allocated-size)
        (set state.content-entity.layout.rotation self.rotation)
        (set state.content-entity.layout.clip-region self.clip-region)
        (set state.content-entity.layout.depth-offset-index self.depth-offset-index)
        (state.content-entity.layout:layouter)))

(fn visible-labels [state]
    (icollect [_ label (ipairs state.visible-labels)] label))

(fn update-sidebar [state]
    (local selected-count (current-selected-count state))
    (when (not (= selected-count state.last-selected-count))
        (set state.rebuild-requested? true))
    (when state.rebuild-requested?
        (set state.rebuild-requested? false)
        (rebuild-children state)
        (state.root-layout:mark-measure-dirty)))

(fn drop-sidebar [state]
    (when state.maps-changed-handler
        (state.manager.maps-changed:disconnect state.maps-changed-handler true)
        (set state.maps-changed-handler nil))
    (disconnect-active-map state)
    (drop-content state)
    (state.root-layout:drop))

(fn layout-measurer [state]
     (fn [self]
         (sidebar-measurer state self nil)))

(fn layout-constrained-measurer [state]
     (fn [self constraints]
         (sidebar-measurer state self constraints)))

(fn layout-layouter [state]
    (fn [self]
        (sidebar-layouter state self)))

(fn maps-changed-listener [state]
    (fn [payload]
        (request-rebuild state payload)))

(fn entity-visible-labels [state]
    (fn [_self]
        (visible-labels state)))

(fn entity-update [state]
    (fn [_self]
        (update-sidebar state)))

(fn entity-drop [state]
    (fn [_self]
        (drop-sidebar state)))

(fn sidebar-entity [state]
    {:layout state.root-layout
     :visible-labels (entity-visible-labels state)
     :update (entity-update state)
     :drop (entity-drop state)})

(fn build-sidebar [options manager ctx]
    (assert ctx.clickables "GraphMapSidebar requires ctx.clickables")
    (local state {:ctx ctx
                  :manager manager
                  :selected-count-provider options.selected-count-provider
                  :node-reveal-handler options.node-reveal-handler
                  :node-open-handler options.node-open-handler
                  :theme (and ctx ctx.theme)
                  :content-entity nil
                  :resolved-sidebar-width sidebar-width
                  :rebuild-requested? false
                  :maps-changed-handler nil
                  :active-map nil
                  :active-node-added-handler nil
                  :active-node-removed-handler nil
                  :active-node-replaced-handler nil
                  :active-edge-added-handler nil
                  :active-edge-removed-handler nil
                  :visible-labels []
                  :last-selected-count nil})
    (set state.root-layout
          (Layout {:name "graph-map-sidebar"
                   :measurer (layout-measurer state)
                   :constrained-measurer (layout-constrained-measurer state)
                   :layouter (layout-layouter state)
                   :children []}))
    (set state.maps-changed-handler
         (manager.maps-changed:connect (maps-changed-listener state)))
    (rebuild-children state)
    (set state.rebuild-requested? false)
    (sidebar-entity state))

(fn sidebar-builder [options manager]
    (fn [ctx]
        (build-sidebar options manager ctx)))

(fn GraphMapSidebar [opts]
    (local options (if opts opts {}))
    (local manager (assert options.manager "GraphMapSidebar requires :manager"))
    (sidebar-builder options manager))

{:GraphMapSidebar GraphMapSidebar}
