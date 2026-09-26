(local Capabilities (require :app-host.capabilities))
(local Snake (require :snake/game))
(local OrthographicUiSurface (require :orthographic-ui-surface))
(local SceneView (require :snake/scene-view))
(local SnakeView (require :snake/view))

(local SDLK_ESCAPE 27)
(local SDLK_RETURN 13)
(local SDLK_SPACE 32)
(local SDLK_RIGHT 1073741903)
(local SDLK_LEFT 1073741904)
(local SDLK_DOWN 1073741905)
(local SDLK_UP 1073741906)
(local KEY_A (string.byte "a"))
(local KEY_A_UPPER (string.byte "A"))
(local KEY_D (string.byte "d"))
(local KEY_D_UPPER (string.byte "D"))
(local KEY_Q (string.byte "q"))
(local KEY_Q_UPPER (string.byte "Q"))
(local KEY_S (string.byte "s"))
(local KEY_S_UPPER (string.byte "S"))
(local KEY_W (string.byte "w"))
(local KEY_W_UPPER (string.byte "W"))

(local tick-interval 0.15)
(local metadata {:id "examples.snake" :title "Snake" :host-api 1})

(fn restart-key? [key]
  (if (= key SDLK_SPACE)
      true
      (= key SDLK_RETURN)
      true
      false))

(fn quit-key? [key]
  (if (= key SDLK_ESCAPE)
      true
      (= key KEY_Q)
      true
      (= key KEY_Q_UPPER)
      true
      false))

(fn direction-for-key [key]
  (if (= key SDLK_UP)
      :up
      (= key KEY_W)
      :up
      (= key KEY_W_UPPER)
      :up
      (= key SDLK_DOWN)
      :down
      (= key KEY_S)
      :down
      (= key KEY_S_UPPER)
      :down
      (= key SDLK_LEFT)
      :left
      (= key KEY_A)
      :left
      (= key KEY_A_UPPER)
      :left
      (= key SDLK_RIGHT)
      :right
      (= key KEY_D)
      :right
      (= key KEY_D_UPPER)
      :right
      nil))

(fn viewport-width [payload]
  (if (and payload payload.width)
      payload.width
      800))

(fn viewport-height [payload]
  (if (and payload payload.height)
      payload.height
      600))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn delta-ms->seconds [delta-ms]
  (/ (if (finite-number? delta-ms)
         (math.max delta-ms 0)
         (* tick-interval 1000))
     1000))

(fn advance-game [game delta-ms elapsed on-step]
  (var next-elapsed (+ elapsed (delta-ms->seconds delta-ms)))
  (var stepped? false)
  (when (and (not game.game-over?) (>= next-elapsed tick-interval))
    (while (and (not game.game-over?) (>= next-elapsed tick-interval))
      (set next-elapsed (- next-elapsed tick-interval))
      (game:step)
      (set stepped? true))
    (when (and stepped? on-step)
      (on-step game)))
  (values next-elapsed stepped?))

(fn update-surface-viewport [surface viewport]
  (when surface
    (surface:update-viewport viewport)))

(fn copy-point [point]
  (if point
      {:x point.x :y point.y}
      nil))

(fn copy-snake [snake]
  (local out [])
  (each [_ segment (ipairs snake)]
    (table.insert out (copy-point segment)))
  out)

(fn register-with [service facet]
  (service:register facet)
  facet)

(fn require-method [service capability method]
  (local value (. service method))
  (when (not (= (type value) :function))
    (error (.. "[snake] host capability " (tostring capability)
               " missing method: " (tostring method))))
  value)

(fn validate-registry [service capability]
  (require-method service capability :register)
  (require-method service capability :unregister)
  service)

(fn validate-viewport [viewport]
  (when (not (= (type viewport) :table))
    (error "[snake] host capability viewport must be a table"))
  (each [_ field (ipairs [:x :y :width :height])]
    (when (not (= (type (. viewport field)) :number))
      (error (.. "[snake] host capability viewport missing numeric field: " (tostring field)))))
  viewport)

(fn unregister-from [service facet]
  (when (and service (= (type service.unregister) :function))
    (service:unregister facet)))

(fn create [host]
  (local scheduler (Capabilities.require host :scheduler))
  (local input (Capabilities.require host :input))
  (local inspectors (Capabilities.require host :inspectors))
  (local lifecycle (Capabilities.require host :lifecycle))
  (local viewport (validate-viewport (Capabilities.require host :viewport)))
  (local scene (Capabilities.require host :scene))
  (local surfaces (and host host.surfaces))
  (validate-registry scheduler :scheduler)
  (validate-registry input :input)
  (validate-registry inspectors :inspectors)
  (require-method lifecycle :lifecycle :quit)
  (when surfaces
    (validate-registry surfaces :surfaces))
  (local game (Snake.create {}))
  (local scene-view (SceneView.create {:scene scene :game game}))
  (local surface (OrthographicUiSurface.create {:viewport viewport}))
  (local screen (surface:build (SnakeView.SnakeScreen {:game game})))
  (var elapsed 0)
  (var dropped? false)

  (fn sync-screen []
    (screen:sync)
    (surface:update)
    (scene-view:sync))

  (fn refresh-screen []
    (surface:update))

  (fn handle-key-down [payload]
    (local key (and payload payload.key))
    (local direction (direction-for-key key))
    (if (quit-key? key)
        (do
          (lifecycle:quit)
          true)
        (and game.game-over? (restart-key? key))
        (do
          (game:restart)
          (set elapsed 0)
          (sync-screen))
        direction
        (when (game:turn direction)
          (sync-screen)))
    true)

  (fn handle-update [delta]
    (when host.viewport
      (update-surface-viewport surface host.viewport))
    (local (next-elapsed stepped?) (advance-game game delta elapsed nil))
    (set elapsed next-elapsed)
    (if stepped?
        (sync-screen)
        (refresh-screen)))

  (fn handle-viewport [payload]
    (local next-viewport {:x 0
                          :y 0
                          :width (viewport-width payload)
                          :height (viewport-height payload)})
    (update-surface-viewport surface next-viewport)
    (refresh-screen))

  (fn read-inspector [_self]
    {:score game.score
     :head (copy-point (. game.snake 1))
     :snake (copy-snake game.snake)
     :food (copy-point game.food)
     :game-over? game.game-over?})

  (local scheduler-facet {:id :snake-simulation
                          :update (fn [_self delta-ms]
                                    (when (not dropped?)
                                      (handle-update delta-ms)))})
  (local input-facet {:id :snake-input
                      :key-down (fn [_self payload]
                                  (when (not dropped?)
                                    (handle-key-down payload)))
                      :window-resized (fn [_self payload]
                                        (when (not dropped?)
                                          (handle-viewport payload)))})
  (local inspector-facet {:id :snake-state
                          :title "Snake State"
                          :read read-inspector})

  (register-with scheduler scheduler-facet)
  (register-with input input-facet)
  (register-with inspectors inspector-facet)
  (when surfaces
    (register-with surfaces surface))

  (sync-screen)

  (fn render-targets [_self]
    (if dropped?
        []
        [(surface:presentation-target)]))

  (fn drop [_self]
    (when (not dropped?)
      (set dropped? true)
      (unregister-from scheduler scheduler-facet)
      (unregister-from input input-facet)
      (unregister-from inspectors inspector-facet)
      (unregister-from surfaces surface)
      (scene-view:drop)
      (when screen
        (screen:drop)
        (set surface.entity nil))
      (surface:drop))
    nil)

  {:metadata metadata
   :presentation {:render-targets render-targets}
   :lifecycle {:drop drop}})

{:metadata metadata
 :create create
 :test-utils {:advance-game advance-game
               :delta-ms->seconds delta-ms->seconds}}
