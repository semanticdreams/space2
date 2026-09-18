(global app (or app {}))

(local EngineModule (require :engine))
(local Snake (require :snake/game))

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

(fn clear-screen []
  (io.write "\27[2J\27[H"))

(fn render [game]
  (clear-screen)
  (each [_ line (ipairs (game:board-lines))]
    (print line))
  (print (.. "Score: " (tostring game.score)))
  (if game.game-over?
      (print "Game over — press Space or Enter to restart, Q/Escape to quit.")
      (print "Move with arrows or WASD. Quit with Q or Escape.")))

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

(fn run []
  (local engine (EngineModule.Engine {:width 800 :height 600}))
  (set app.engine engine)
  (local game (Snake.create {}))
  (var elapsed 0)

  (fn quit []
    (when (and engine engine.quit)
      (engine.quit)))

  (fn handle-key-down [payload]
    (local key (and payload payload.key))
    (if (quit-key? key)
        (quit)
        (and game.game-over? (restart-key? key))
        (do
          (game:restart)
          (set elapsed 0)
          (render game))
        (direction-for-key key)
        (game:turn (direction-for-key key)))
    true)

  (fn handle-update [delta]
    (set elapsed (+ elapsed (if (finite-number? delta)
                               (math.max delta 0)
                               tick-interval)))
    (when (and (not game.game-over?) (>= elapsed tick-interval))
      (while (>= elapsed tick-interval)
        (set elapsed (- elapsed tick-interval))
        (game:step))
      (render game)))

  (when (and engine.events engine.events.key-down)
    (engine.events.key-down:connect handle-key-down))
  (if (and engine.events engine.events.updated)
      (engine.events.updated:connect handle-update)
      (and engine.events engine.events.engine-tick)
      (engine.events.engine-tick:connect (fn [_payload] (handle-update tick-interval))))

  (when (not (engine:start))
    (error "[snake] engine failed to start"))
  (render game)
  (engine:run)
  (when engine.shutdown
    (engine:shutdown))
  nil)

{:run run}
