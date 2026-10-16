(global app (or app {}))

(local fs (require :fs))
(local runtime (require :runtime))
(local glm (require :glm))
(local Activities (require :activities))
(local {:Board Board} (require :board/core))
(local BoardView (require :board/view))
(local BuiltinStringEntity (require :board/builtin-string-entity))
(local BuiltinCodeEntity (require :board/builtin-code-entity))
(local StringEntityStore (require :entities/string))
(local HomeWorldCanvasRuntime (require :home-world-canvas-runtime))
(local ActivityCameraState (require :activity-camera-state))

(local owner {})

(fn board-activity-owned-paths []
  (local lua-root (fs.join-path runtime.assets-path "lua"))
  (local board-root (fs.join-path lua-root "board"))
  [(fs.join-path lua-root "board-activity-unit.fnl")
   board-root])

(fn ensure-board-state [world-runtime]
  (set world-runtime.board-state (or world-runtime.board-state {}))
  world-runtime.board-state)

(fn reconcile-stale-string-entity-items! [state]
  (local payload (assert state "Board string entity reconciliation requires board state"))
  (when (= payload.items nil)
    (set payload.items []))
  (when (= payload.connectors nil)
    (set payload.connectors []))
  (local store (StringEntityStore.get-default))
  (local pruned-item-ids {})
  (local items [])
  (each [_ item (ipairs payload.items)]
    (local entity-id (and (= item.type BuiltinStringEntity.item-type)
                          (BuiltinStringEntity.entity-id-from-subject item.subject-key)))
    (if (and entity-id (not (store:get-entity entity-id)))
        (set (. pruned-item-ids item.id) true)
        (table.insert items item)))
  (when (next pruned-item-ids)
    (local connectors [])
    (each [_ connector (ipairs payload.connectors)]
      (when (not (or (. pruned-item-ids connector.source-item-id)
                     (. pruned-item-ids connector.target-item-id)))
        (table.insert connectors connector)))
    (set payload.items items)
    (set payload.connectors connectors))
  payload)

(fn screen-world-position [event]
  (local canvas (assert app.canvas "Board screen-world-position requires app.canvas"))
  (assert event "Board screen-world-position requires pointer event")
  (local pointer (or event.screen
                     (and event.x event.y event)))
  (local ray
    (or event.ray
        (do
          (assert pointer
                  "Board screen-world-position requires event.ray, event.screen, or a pointer {x y}")
          (canvas:screen-pos-ray pointer))))
  (assert (and ray ray.origin ray.direction)
          "Board screen-world-position requires a ray with origin and direction")
  (local dz ray.direction.z)
  (assert (and dz (not (= dz 0)))
          "Board screen-world-position ray must intersect z=0 plane")
  (local t (/ (- 0 ray.origin.z) dz))
  (local point (+ ray.origin (* ray.direction t)))
  (glm.vec3 point.x point.y 0))

(fn activate-board-view! []
  (local world-runtime (assert app.active-world-runtime
                                 "Board activity requires app.active-world-runtime"))
  (local canvas (assert world-runtime.canvas
                           "Board activity requires runtime.canvas"))

  ;; Create or reuse a board canvas camera stored in runtime.activity-cameras.
  (local slot-camera
    (HomeWorldCanvasRuntime.ensure-activity-canvas-camera!
      world-runtime
      "board"
      {:position (glm.vec3 0 0 100)}))

  ;; Create or reuse canvas controls bound to the slot camera.
  (HomeWorldCanvasRuntime.ensure-activity-canvas-controls!
    world-runtime "board" slot-camera)

  ;; Ensure the slot has the camera before activation
  (canvas:ensure-activity-slot "board" {:camera slot-camera})
  (local slot (canvas:activate-activity-slot "board"))
  (slot:set-canvas-target-kind! :board)
  (slot:expose-render-target! {:layers [:geometry :text]})
  (BuiltinStringEntity.register owner)
  (BuiltinCodeEntity.register owner)
  (local retained-view? (not (= world-runtime.board-view nil)))
  (local board (or world-runtime.board (Board {})))
  (local selector (and world-runtime world-runtime.object-selector))
  (local view (or world-runtime.board-view
                  (BoardView {:board board
                               :canvas canvas :lifecycle world-runtime.reference-lifecycle
                               :ctx slot.ctx
                               :string-store (or world-runtime.string-store app.string-store)
                               :code-store (or world-runtime.code-store app.code-store)
                               :identity-store (or world-runtime.identity-store app.identity-store)
                               :link-store (or world-runtime.link-store app.link-store)
                              :selector selector})))
  (set slot.root view)
  (set world-runtime.board board)
  (set world-runtime.board-view view)
  (set app.board board)
  (set app.board-view view)
  (when (not retained-view?)
    (local (ok err)
      (pcall (fn []
               (board:restore-state (reconcile-stale-string-entity-items!
                                      (ensure-board-state world-runtime))))))
    (when (not ok)
      (view:drop)
      (set world-runtime.board nil)
      (set world-runtime.board-view nil)
      (set app.board nil)
      (set app.board-view nil)
      (error err)))
  view)

(fn capture-board-state! []
  (local world-runtime app.active-world-runtime)
  (local view (and world-runtime world-runtime.board-view))
  (when (and world-runtime view)
    (set world-runtime.board-state (view:capture-state)))
  (and world-runtime world-runtime.board-state))

(fn deactivate-board-view! []
  (capture-board-state!)
  (local world-runtime app.active-world-runtime)
  (local canvas (and world-runtime world-runtime.canvas))
  (when canvas
    (canvas:deactivate-activity-slot "board" {:boundary-internal? true}))
  (set app.board nil)
  (set app.board-view nil)
  true)

(fn drop-board-view! []
  (capture-board-state!)
  (local world-runtime app.active-world-runtime)
  (local view (or (and world-runtime world-runtime.board-view)
                   app.board-view))
  (local canvas (and world-runtime world-runtime.canvas))
  (local slot (and canvas (canvas:activity-slot "board")))
  (when slot
    (set slot.root nil))
  (when view
    (view:drop))
  (when canvas
    (canvas:deactivate-activity-slot "board" {:boundary-internal? true}))
  (when world-runtime
    (set world-runtime.board nil)
    (set world-runtime.board-view nil))
  (set app.board nil)
  (set app.board-view nil)
  true)

(fn board-activity-update [payload]
  (local view (and payload payload.runtime payload.runtime.board-view))
  (when view
    (view:update (and payload payload.delta)))
  nil)

(fn board-root-actions [context]
  (local root-event (and context context.event))
  [{:name "Create String Entity"
    :icon "note_add"
    :fn (fn [_button event]
           (local view (assert app.board-view "Create String Entity requires app.board-view"))
           (view:add-string-entity {:position (screen-world-position (or root-event event))}))}])

(fn connectable? [item]
  (and item item.subject-key
       (not (= (tostring item.subject-key) ""))))

(fn delete-selection []
  (local view app.board-view)
  (and view (> (view:remove-selected-items) 0)))

(fn board-selection-actions [context]
  (local view (or (and context context.board context.board.view)
                  app.board-view))
  (local selected (or (and view view.selected-items) []))
  (local actions [])
  (when (> (length selected) 0)
    (table.insert actions
                  {:name "Delete Selected"
                   :icon "delete"
                   :variant {:action :danger}
                   :fn (fn [_button _event]
                         (view:remove-selected-items))}))
  (when (and (= (length selected) 2)
              (connectable? (. selected 1))
              (connectable? (. selected 2)))
    (local source (. selected 1))
    (local target (. selected 2))
    (table.insert actions
                  {:name "Connect Items"
                   :icon "link"
                   :fn (fn [_button _event]
                         (view:connect-items source target))}))
  actions)

(fn enrich-board-context! [context]
  (local view (or app.board-view
                  (and context context.board context.board.view)))
  (set context.board {:board app.board
                      :view app.board-view
                      :selected-items (if view view.selected-items [])})
  context)

(fn board-target-enabled? [target]
  (local target-kind (and target target.canvas-target-kind))
  (or (= target-kind nil)
      (= target-kind :board)))

(fn activate-activity! [ctx]
  ;; Ensure and activate empty Scene slot before Canvas hooks
  ;; so Board does not inherit Sandbox content/environment/interaction.
  (let [runtime (assert app.active-world-runtime
                         "Board activity activation requires app.active-world-runtime")
        scene (assert runtime.scene
                       "Board activity activation requires runtime.scene")]
    (scene:ensure-activity-slot "board")
    (scene:activate-activity-slot "board"))
  (ctx:defer-cleanup! drop-board-view!)
  (local view (activate-board-view!))
  (ctx:set-root-actions! board-root-actions)
  (ctx:set-selection-actions! board-selection-actions)
  (ctx:set-delete-selection! delete-selection)
  (ctx:set-command-hints-provider! (fn [_payload] []))
  (ctx:set-context-enricher! enrich-board-context!)
  (ctx:set-target-enabled! board-target-enabled?)
  (ctx:set-update! board-activity-update)
  (ctx:set-surface-state! {:canvas {:visible? true :interactive? true}})
  (ctx:set-preferred-interaction-surface! :canvas)
  {:activity-id "board"
   :board-view view})

(fn deactivate-activity! [_ctx _session]
  (deactivate-board-view!)
  ;; Deactivate Scene slot after Canvas deactivation without dropping it
  (let [runtime (assert app.active-world-runtime
                         "Board activity deactivation requires app.active-world-runtime")
        scene (assert runtime.scene
                       "Board activity deactivation requires runtime.scene")]
    (scene:deactivate-activity-slot "board" {:boundary-internal? true})))

(fn snapshot-board-activity! []
  (let [runtime (assert app.active-world-runtime
                          "Board activity snapshot requires app.active-world-runtime")
        scene (assert runtime.scene
                        "Board activity snapshot requires runtime.scene")
        scene-state (scene:capture-activity-slot-state "board")
        canvas-camera (and runtime.activity-cameras
                           runtime.activity-cameras.canvas
                           (. runtime.activity-cameras.canvas "board"))
        camera-state (and canvas-camera
                          (ActivityCameraState.capture-camera canvas-camera))]
    (local result
      {:active? (= (Activities.active-activity-id) "board")
       :board-state (capture-board-state!)
       :scene scene-state})
    (when camera-state
      (set result.canvas-camera camera-state))
    result))

(fn restore-state-arg [first _session maybe-state]
  (if (and first (. first :activity))
      maybe-state
      first))

(fn restore-board-activity! [first session maybe-state]
  (local state (restore-state-arg first session maybe-state))
  (when (and app.active-world-runtime state state.board-state)
    (local board-state (reconcile-stale-string-entity-items! state.board-state))
    (set state.board-state board-state)
    (set app.active-world-runtime.board-state board-state))
  ;; Restore canvas camera position from persisted session state
  (when (and state state.canvas-camera
             app.active-world-runtime
             app.active-world-runtime.activity-cameras
             app.active-world-runtime.activity-cameras.canvas)
    (local camera (. app.active-world-runtime.activity-cameras.canvas "board"))
    (when camera
      (ActivityCameraState.restore-camera! camera state.canvas-camera)))
  (when (and state state.scene)
    (let [runtime (assert app.active-world-runtime
                            "Board activity restore requires app.active-world-runtime")
          scene (assert runtime.scene
                          "Board activity restore requires runtime.scene")]
      (scene:restore-activity-slot-state "board" state.scene)))
  (when (and state state.active?)
    (if (and state.board-state
              (= (Activities.active-activity-id) "board")
              app.active-world-runtime
              app.active-world-runtime.board)
        (app.active-world-runtime.board:restore-state app.active-world-runtime.board-state)
        (if app.set-active-activity
            (app.set-active-activity "board")
            (Activities.activate-activity "board"))))
  true)

(fn activity-registered? [activity-id]
  (local (ok _resolved) (pcall Activities.resolve activity-id))
  ok)

(fn load-board-activity! []
  (BuiltinStringEntity.register owner)
  (BuiltinCodeEntity.register owner)
  (when (not (activity-registered? "board"))
    (Activities.register-activity
      {:id "board"
       :label "Board"
       :icon "dashboard_customize"
       :button-name "board-activity"
       :show-in-switcher? true
       :activate activate-activity!
       :deactivate deactivate-activity!
       :snapshot snapshot-board-activity!
       :restore restore-board-activity!}))
  true)

(fn unload-board-activity! []
  (local registered? (activity-registered? "board"))
  (local active? (and registered?
                      (= (Activities.active-activity-id) "board")))
  (when active?
    (if app.set-active-activity
        (app.set-active-activity nil)
        (Activities.deactivate-active-activity)))
  (when registered?
    (Activities.unregister-activity "board"))
  (BuiltinStringEntity.unregister owner)
  (BuiltinCodeEntity.unregister owner)
  true)

{:board-activity-owned-paths board-activity-owned-paths
 :load-board-activity! load-board-activity!
 :unload-board-activity! unload-board-activity!
 :snapshot-board-activity! snapshot-board-activity!
 :restore-board-activity! restore-board-activity!}
