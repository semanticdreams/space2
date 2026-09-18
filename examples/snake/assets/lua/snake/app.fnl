(global app (or app {}))

(local AppBootstrap (require :app-bootstrap))
(local AppViewport (require :app-viewport))
(local EngineModule (require :engine))
(local Renderers (require :renderers))
(local Snake (require :snake/game))
(local OrthographicUiSurface (require :orthographic-ui-surface))
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
(local startup-viewport {:x 0 :y 0 :width 800 :height 600})

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

(fn run []
  (local engine (EngineModule.Engine {:width 800 :height 600
                                      :title "Snake"}))
  (set app.engine engine)
  (when (not (engine:start))
    (error "[snake] engine failed to start"))

  (set app.set-viewport AppViewport.set-viewport)
  (local viewport (app.set-viewport startup-viewport))
  (AppBootstrap.init-themes)
  (set app.renderers (AppBootstrap.init-renderers {:viewport viewport}))
  (when (not app.renderers)
    (set app.renderers (Renderers)))

  (local game (Snake.create {}))
  (local surface (OrthographicUiSurface.create {:viewport viewport}))
  (local screen (surface:build (SnakeView.SnakeScreen {:game game})))
  (var elapsed 0)

  (fn presentation-render-targets [_self]
    [(surface:presentation-target)])

  (set app.active-world-runtime
       {:presentation {:render-targets presentation-render-targets}})

  (fn sync-screen []
    (screen:sync)
    (surface:update)
    (app.renderers:update))

  (fn refresh-screen []
    (surface:update)
    (app.renderers:update))

  (fn quit []
    (when (and engine engine.quit)
      (engine.quit)))

  (fn handle-key-down [payload]
    (local key (and payload payload.key))
    (local direction (direction-for-key key))
    (if (quit-key? key)
        (quit)
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
    (local (next-elapsed stepped?) (advance-game game delta elapsed nil))
    (set elapsed next-elapsed)
    (if stepped?
        (sync-screen)
        (refresh-screen)))

  (fn handle-viewport [payload]
    (local next-viewport (app.set-viewport {:x 0
                                             :y 0
                                             :width (viewport-width payload)
                                             :height (viewport-height payload)}))
    (update-surface-viewport surface next-viewport)
    (refresh-screen))

  (fn handle-engine-tick [_payload]
    (handle-update (* tick-interval 1000)))

  (var key-down-connected? false)
  (var updated-connected? false)
  (var engine-tick-connected? false)
  (var window-resized-connected? false)

  (fn cleanup-engine-events []
    (when (and key-down-connected? engine.events engine.events.key-down)
      (engine.events.key-down:disconnect handle-key-down true))
    (when (and updated-connected? engine.events engine.events.updated)
      (engine.events.updated:disconnect handle-update true))
    (when (and engine-tick-connected? engine.events engine.events.engine-tick)
      (engine.events.engine-tick:disconnect handle-engine-tick true))
    (when (and window-resized-connected? engine.events engine.events.window-resized)
      (engine.events.window-resized:disconnect handle-viewport true)))

  (when (and engine.events engine.events.key-down)
    (engine.events.key-down:connect handle-key-down)
    (set key-down-connected? true))
  (if (and engine.events engine.events.updated)
      (do
        (engine.events.updated:connect handle-update)
        (set updated-connected? true))
      (and engine.events engine.events.engine-tick)
      (do
        (engine.events.engine-tick:connect handle-engine-tick)
        (set engine-tick-connected? true)))
  (when (and engine.events engine.events.window-resized)
    (engine.events.window-resized:connect handle-viewport)
    (set window-resized-connected? true))

  (sync-screen)
  (engine:run)

  (cleanup-engine-events)
  (when screen
    (screen:drop)
    (set surface.entity nil))
  (when surface
    (surface:drop))
  (when (and app.renderers app.renderers.drop)
    (app.renderers:drop))
  (when engine.shutdown
    (engine:shutdown))
  nil)

{:run run
 :test-utils {:advance-game advance-game
              :delta-ms->seconds delta-ms->seconds}}
