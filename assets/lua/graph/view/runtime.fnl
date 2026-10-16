(local GraphViewNodeViews (require :graph/view/node-views))
(local GraphViewPersistence (require :graph/view/persistence))
(local ActivityCameraState (require :activity-camera-state))
(local appdirs (require :appdirs))
(local R (require :reference-lifecycle/record-utils))
(local ReferenceState (require :graph/reference-state))

(fn clone-array [items]
    (when items
        (icollect [_idx value (ipairs items)] value)))

(fn clone-camera-state [state]
    (when state
        (local cloned {:position (clone-array state.position)})
        (when state.rotation
            (set cloned.rotation (clone-array state.rotation)))
        cloned))

(fn clone-table [source]
    (local cloned {})
    (when source
        (each [key value (pairs source)]
            (set (. cloned key) value)))
    cloned)

(fn clone-mode-states [source]
    (local cloned {})
    (when source
        (each [mode state (pairs source)]
            (set (. cloned mode) (clone-table state))))
    cloned)

(fn assert-runtime-live [runtime context]
    (assert (not runtime.dropped?)
            (.. "GraphViewRuntime " context " called after drop")))

(fn init! [view opts projection]
    (assert view "GraphViewRuntime.init! requires view")
    (local options (assert opts "GraphViewRuntime.init! requires options"))
    (local graph-map (assert options.graph-map "GraphViewRuntime.init! requires options.graph-map"))
    (local ctx (assert options.ctx "GraphViewRuntime.init! requires options.ctx"))
    (local adapter (assert projection "GraphViewRuntime.init! requires projection"))
    (local mode (assert adapter.mode "GraphViewRuntime.init! requires projection.mode"))
    (assert adapter.capture-projection-state! "GraphViewRuntime.init! requires projection.capture-projection-state!")
    (assert adapter.restore-projection-state! "GraphViewRuntime.init! requires projection.restore-projection-state!")
    (assert adapter.drop-projection! "GraphViewRuntime.init! requires projection.drop-projection!")
    (assert adapter.apply-initial-camera-policy! "GraphViewRuntime.init! requires projection.apply-initial-camera-policy!")
    (local data-dir (or options.data-dir
                        (and appdirs (appdirs.user-data-dir "space"))))
    (local persistence (or options.persistence
                           (and data-dir
                                (GraphViewPersistence {:data-dir data-dir
                                                       :map-id (or graph-map.id "main")}))))
    (local node-views (or options.node-views
                          (GraphViewNodeViews {:graph-map graph-map
                                               :ctx ctx
                                               :view-target options.view-target
                                               :view-context (or options.view-context
                                                                 (and options.view-target options.view-target.build-context)
                                                                 ctx)})))
    {:view view
     :graph-map graph-map
     :ctx ctx
     :mode mode
     :camera options.camera
     :node-views node-views
     :persistence persistence
     :mode-states (clone-mode-states options.mode-states)
     :connections []
     :dropped? false})

(fn snapshot-reference-state [view state adapter]
    (assert-runtime-live state "snapshot-reference-state")
    (local modes (R.clone state.mode-states))
    (local capture (or adapter.snapshot-projection-state adapter.capture-projection-state!))
    (assert capture "reference snapshot requires projection capture")
    (local projection (R.clone (or (. modes state.mode) {})))
    (each [key value (pairs (capture view state))] (tset projection key (R.clone value)))
    (when state.camera (set projection.camera (ActivityCameraState.capture-camera state.camera)))
    (tset modes state.mode projection)
    (when modes.outline (set modes.outline.selected_node_keys nil))
    {:mode_states modes
     :views (and state.node-views state.node-views.capture-state (R.clone (state.node-views:capture-state)))
     :selected_node_keys (R.clone state.graph-map.selected_node_keys)
     :focused_node_key_present? (not (= state.graph-map.focused_node_key nil))
     :focused_node_key state.graph-map.focused_node_key})

(fn install! [view runtime projection]
    (assert view "GraphViewRuntime.install! requires view")
    (local state (assert runtime "GraphViewRuntime.install! requires runtime"))
    (local adapter (assert projection "GraphViewRuntime.install! requires projection"))
    (set view.runtime state)
    (set view.snapshot-reference-state
         (fn [self] (snapshot-reference-state self state adapter)))
    (set view.install-reference-state!
         (fn [self incoming]
             (assert-runtime-live state "install-reference-state!")
             (local metadata (state.persistence:snapshot-state))
             (self:restore-state (R.clone incoming))
             ;; Native callbacks may touch the cache; the supplied owning AFTER
             ;; image, already installed by WorldOwner, remains authoritative.
             (state.persistence:install-state! metadata)))
    (set view.assert-not-dropped
         (fn [_self context]
             (assert-runtime-live state context)))
    (set view.saved-camera-state
         (fn [_self]
             (assert-runtime-live state "saved-camera-state")
             (if (and (. state.mode-states state.mode)
                      (. state.mode-states state.mode :camera))
                 (. state.mode-states state.mode :camera)
                 (and state.persistence
                      state.persistence.saved-mode-camera-state
                      (state.persistence:saved-mode-camera-state state.mode)))))
    (set view.capture-camera-state!
         (fn [_self]
             (assert-runtime-live state "capture-camera-state!")
              (when (and state.persistence
                         state.persistence.set-mode-camera-state)
                  (local camera-state (ActivityCameraState.capture-camera state.camera))
                  (when (= (. state.mode-states state.mode) nil)
                      (set (. state.mode-states state.mode) {}))
                  (set (. state.mode-states state.mode :camera) camera-state)
                  (state.persistence:set-mode-camera-state state.mode camera-state)
                  camera-state)))
    (set view.apply-initial-camera-policy!
         (fn [self]
             (assert-runtime-live state "apply-initial-camera-policy!")
             (adapter.apply-initial-camera-policy! self state)))
     (set view.capture-state
          (fn [self]
              (assert-runtime-live state "capture-state")
              (local selected-node-keys state.graph-map.selected_node_keys)
              (local focused-node-key state.graph-map.focused_node_key)
              (local mode-states (clone-mode-states state.mode-states))
              (local retained-camera (and (. state.mode-states state.mode)
                                          (. state.mode-states state.mode :camera)))
               (local mode-state (clone-table (. mode-states state.mode)))
               (each [key value (pairs (adapter.capture-projection-state! self state))] (tset mode-state key value))
              (when retained-camera
                  (set mode-state.camera (clone-camera-state retained-camera)))
               (set (. mode-states state.mode) mode-state)
               (when mode-states.outline (set mode-states.outline.selected_node_keys nil))
              (local restored-selected-node-keys (if selected-node-keys selected-node-keys []))
              (if state.graph-map.set-selected-node-keys
                  (state.graph-map:set-selected-node-keys restored-selected-node-keys)
                  (set state.graph-map.selected_node_keys selected-node-keys))
              (set state.graph-map.focused_node_key focused-node-key)
               (set state.mode-states mode-states)
               {:mode_states mode-states
                :views (and state.node-views state.node-views.capture-state (state.node-views:capture-state))
                :selected_node_keys selected-node-keys
                :focused_node_key_present? (not (= focused-node-key nil))
                :focused_node_key focused-node-key}))
    (set view.restore-views-state
         (fn [_self views-state]
             (assert-runtime-live state "restore-views-state")
             (when (and state.node-views state.node-views.restore-state views-state)
                 (state.node-views:restore-state views-state))
             true))
    (set view.restore-graph-state
         (fn [_self graph-state]
             (assert-runtime-live state "restore-graph-state")
             (when (and state.graph-map state.graph-map.restore-state graph-state)
                 (state.graph-map:restore-state graph-state))
             true))
    (set view.restore-state
         (fn [self incoming]
             (assert-runtime-live state "restore-state")
             (local payload (if incoming incoming {}))
             (when payload.mode_states
                 (set state.mode-states (clone-mode-states payload.mode_states)))
              (when payload.selected_node_keys
                  (if state.graph-map.set-selected-node-keys
                      (state.graph-map:set-selected-node-keys payload.selected_node_keys)
                      (set state.graph-map.selected_node_keys payload.selected_node_keys)))
              (if (= payload.focused_node_key_present? false)
                  (set state.graph-map.focused_node_key nil)
                  (when (not (= payload.focused_node_key nil))
                      (set state.graph-map.focused_node_key payload.focused_node_key)))
             (when payload.views
                 (self:restore-views-state payload.views))
             (adapter.restore-projection-state! self state (. state.mode-states state.mode))
             true))
    (set view.drop
         (fn [self]
             (assert-runtime-live state "drop")
             (adapter.drop-projection! self state)
             (each [_ connection (ipairs state.connections)]
                 (when (and connection.signal connection.handler)
                     (connection.signal:disconnect connection.handler true)))
             (for [idx (length state.connections) 1 -1]
                 (table.remove state.connections idx))
             (when (and state.node-views state.node-views.drop-all)
                 (state.node-views:drop-all))
             (set state.dropped? true)
             true))
    view)

(fn restore-spatial-state [view state]
    (assert-runtime-live view.runtime "restore-state")
    (assert view._runtime-restore-state "spatial restore requires installed runtime")
    (local payload (or state {}))
    (set view._spatial-runtime-selected-keys-present? (not (= payload.selected_node_keys nil)))
    (if (and payload.extra_panels (not (and payload.mode_states payload.mode_states.spatial)))
        (do
            (local modes (or payload.mode_states {}))
            (tset modes :spatial {:extra_panels payload.extra_panels})
            (local merged (clone-table payload))
            (set merged.mode_states modes)
            (view._runtime-restore-state view merged))
        (view._runtime-restore-state view payload)))

(fn restore-spatial-projection! [view runtime projection-state]
    (assert view._spatial-restore-state "spatial projection requires installed view")
    (local state (or projection-state {}))
    (local legacy-state (clone-table state))
    (when view._spatial-runtime-selected-keys-present?
        (set legacy-state.selected_node_keys runtime.graph-map.selected_node_keys))
    (when (and (= runtime.graph-map.focused_node_key nil) state.focused_node_key)
        (set runtime.graph-map.focused_node_key state.focused_node_key))
    (view._spatial-restore-state view legacy-state)
    (view:_spatial-apply-focused-key! runtime.graph-map.focused_node_key))

(fn spatial-node-view-adapter [views]
    (assert views "spatial runtime requires node views")
    {:capture-state (fn [_self] (and views.capture-state (views:capture-state)))
     :restore-state (fn [_self state] (when views.restore-state (views:restore-state state)))
     :drop-all (fn [_self] true)})

(fn spatial-projection-state [legacy-state]
    (local projection-state {})
    (local source-state (if legacy-state legacy-state {}))
    (each [key value (pairs source-state)]
        (when (and (not= key :selected_node_keys) (not= key :focused_node_key) (not= key :views))
            (set (. projection-state key) value)))
    projection-state)

(fn snapshot-spatial-panels [view]
    (local panels (R.clone view.extra-panels))
    (each [_ runtime (ipairs view.extra-panel-runtimes)]
        (when (and runtime.target runtime.element runtime.target.capture-panel-element-state)
            (each [_ panel (ipairs panels)]
                (when (and (= panel.kind runtime.kind) (= panel.node-key runtime.node-key)
                           (= panel.graph-map-id runtime.graph-map-id))
                    (set panel.panel (runtime.target:capture-panel-element-state runtime.element))))))
    panels)

(fn snapshot-spatial-metadata [view]
    (view:assert-not-dropped "snapshot-reference-metadata")
    (local metadata (view.persistence:snapshot-state))
    (local positions (view.persistence:capture-positions view.points))
    (when (not metadata.positions) (set metadata.positions {}))
    (each [key position (pairs positions)] (tset metadata.positions key position))
    (local views (view.views:capture-state))
    (set metadata.panels (ReferenceState.merge-view-panels (R.field metadata :panels :table []) views.open-views))
    (set metadata.extra_panels (snapshot-spatial-panels view))
    (when view.camera
        (local camera (ActivityCameraState.capture-camera view.camera))
        (set metadata.camera camera)
        (when (not metadata.view_modes) (set metadata.view_modes {}))
        (when (not metadata.view_modes.spatial) (set metadata.view_modes.spatial {}))
        (set metadata.view_modes.spatial.camera camera))
    metadata)

{:init! init!
 :spatial-projection-state spatial-projection-state
 :restore-spatial-state restore-spatial-state
 :restore-spatial-projection! restore-spatial-projection!
 :spatial-node-view-adapter spatial-node-view-adapter
 :snapshot-spatial-panels snapshot-spatial-panels
 :snapshot-spatial-metadata snapshot-spatial-metadata
 :install! install!
 :assert-runtime-live assert-runtime-live
 :clone-camera-state clone-camera-state}
