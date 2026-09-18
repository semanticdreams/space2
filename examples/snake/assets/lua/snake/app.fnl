(global app (or app {}))

(local AppBootstrap (require :app-bootstrap))
(local AppViewport (require :app-viewport))
(local EngineModule (require :engine))
(local Renderers (require :renderers))
(local Snake (require :snake/game))
(local SnakeSurface (require :snake/surface))
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
  (or (= key SDLK_SPACE) (= key SDLK_RETURN)))

(fn quit-key? [key]
  (or (= key SDLK_ESCAPE) (= key KEY_Q) (= key KEY_Q_UPPER)))

(fn direction-for-key [key]
  (if (or (= key SDLK_UP) (= key KEY_W) (= key KEY_W_UPPER))
      :up
      (or (= key SDLK_DOWN) (= key KEY_S) (= key KEY_S_UPPER))
      :down
      (or (= key SDLK_LEFT) (= key KEY_A) (= key KEY_A_UPPER))
      :left
      (or (= key SDLK_RIGHT) (= key KEY_D) (= key KEY_D_UPPER))
      :right
      nil))

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
  next-elapsed)

(fn update-surface-viewport [surface viewport]
  (when surface
    (surface:update-viewport viewport)))

(fn run []
  (local engine (EngineModule.Engine {:width 800 :height 600}))
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
  (local surface (SnakeSurface.create {:viewport viewport}))
  (local screen (surface:build (SnakeView.SnakeScreen {:game game})))
  (var elapsed 0)

  (set app.active-world-runtime
       {:presentation {:render-targets (fn [_self]
                                         [(surface:presentation-target)])}})

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
    (var stepped? false)
    (set elapsed (advance-game game delta elapsed
                               (fn [_game]
                                 (set stepped? true)
                                 (sync-screen))))
    (when (not stepped?)
      (refresh-screen)))

  (fn handle-viewport [payload]
    (local next-viewport (app.set-viewport {:x 0
                                            :y 0
                                            :width (or (and payload payload.width) 800)
                                            :height (or (and payload payload.height) 600)}))
    (update-surface-viewport surface next-viewport)
    (refresh-screen))

  (when (and engine.events engine.events.key-down)
    (engine.events.key-down:connect handle-key-down))
  (if (and engine.events engine.events.updated)
      (engine.events.updated:connect handle-update)
      (and engine.events engine.events.engine-tick)
      (engine.events.engine-tick:connect (fn [_payload]
                                           (handle-update (* tick-interval 1000)))))
  (when (and engine.events engine.events.window-resized)
    (engine.events.window-resized:connect handle-viewport))

  (sync-screen)
  (engine:run)

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
