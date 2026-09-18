(local Runner (require :tests/runner))
(local Snake (require :snake/game))
(local SnakeApp (require :snake/app))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn test-moves-right-by-default []
  (local game (Snake.create {:width 8 :height 6
                             :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                             :initial-food {:x 6 :y 3}}))
  (local event (game:step))
  (local head (. game.snake 1))
  (assert (= event.status :moved) "first step should move")
  (assert (= head.x 4) "head x should advance right")
  (assert (= head.y 3) "head y should stay constant"))

(add-test "moves-right-by-default" test-moves-right-by-default)

(fn test-rejects-direct-reversal []
  (local game (Snake.create {:width 8 :height 6
                             :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                             :initial-food {:x 6 :y 3}}))
  (assert (= (game:turn :right) false) "same-direction turn should not report a change")
  (assert (= game.direction :right) "same-direction turn should keep direction")
  (assert (= (game:turn :left) false) "right-moving snake cannot reverse left")
  (assert (= game.direction :right) "direction should remain right")
  (assert (= (game:turn :up) true) "perpendicular turn should be accepted")
  (assert (= game.direction :up) "direction should change to up"))

(add-test "rejects-direct-reversal" test-rejects-direct-reversal)

(fn test-eats-food-and-grows []
  (local game (Snake.create {:width 8 :height 6
                             :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                             :initial-food {:x 4 :y 3}
                             :food-sequence [{:x 1 :y 1}]}))
  (local event (game:step))
  (assert (= event.status :ate) "step into food should eat")
  (assert (= game.score 1) "score should increment")
  (assert (= (length game.snake) 3) "snake should grow by one")
  (assert (= game.food.x 1) "next deterministic food x should be used")
  (assert (= game.food.y 1) "next deterministic food y should be used"))

(add-test "eats-food-and-grows" test-eats-food-and-grows)

(fn test-detects-wall-hit []
  (local game (Snake.create {:width 5 :height 5
                             :initial-snake [{:x 5 :y 3} {:x 4 :y 3}]
                             :initial-food {:x 1 :y 1}}))
  (local event (game:step))
  (assert (= event.status :wall-hit) "moving beyond width should hit wall")
  (assert game.game-over? "wall hit should end game"))

(add-test "detects-wall-hit" test-detects-wall-hit)

(fn test-detects-self-hit []
  (local game (Snake.create {:width 8 :height 8
                             :initial-snake [{:x 4 :y 4} {:x 4 :y 5} {:x 3 :y 5} {:x 3 :y 4} {:x 3 :y 3}]
                             :initial-direction :up
                             :initial-food {:x 8 :y 8}}))
  (game:turn :left)
  (local event (game:step))
  (assert (= event.status :self-hit) "head should collide with body")
  (assert game.game-over? "self hit should end game"))

(add-test "detects-self-hit" test-detects-self-hit)

(fn test-runtime-waits-for-150ms-before-step []
  (local utils SnakeApp.test-utils)
  (assert (= (type utils) :table) "snake app should expose focused runtime test helpers")
  (assert (= (type utils.advance-game) :function) "snake app should expose advance-game helper")
  (local game (Snake.create {:width 8 :height 6
                             :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                             :initial-food {:x 6 :y 3}}))
  (var render-count 0)
  (fn on-step [_game]
    (set render-count (+ render-count 1)))
  (var elapsed (utils.advance-game game 16 0 on-step))
  (local head-before (. game.snake 1))
  (assert (= head-before.x 3) "16 ms frame should not advance a 150 ms snake tick")
  (assert (= render-count 0) "sub-tick frame should not invoke sync callback")
  (set elapsed (utils.advance-game game 134 elapsed on-step))
  (local head-after (. game.snake 1))
  (assert (= head-after.x 4) "150 accumulated ms should advance exactly one step")
  (assert (= render-count 1) "one accumulated tick should invoke sync callback once"))

(add-test "runtime-waits-for-150ms-before-step" test-runtime-waits-for-150ms-before-step)

(fn fake-wall-hit-step [self]
  (set self.step-count (+ self.step-count 1))
  (set self.game-over? true)
  {:status :wall-hit})

(fn noop-step-callback [_game]
  nil)

(fn test-runtime-stops-catchup-after-game-over []
  (local utils SnakeApp.test-utils)
  (assert (= (type utils) :table) "snake app should expose focused runtime test helpers")
  (assert (= (type utils.advance-game) :function) "snake app should expose advance-game helper")
  (local fake-game {:game-over? false
                    :step-count 0
                    :step fake-wall-hit-step})
  (utils.advance-game fake-game 450 0 noop-step-callback)
  (assert (= fake-game.step-count 1) "catch-up loop should stop once a tick ends the game"))

(add-test "runtime-stops-catchup-after-game-over" test-runtime-stops-catchup-after-game-over)

(fn main []
  (Runner.run-tests {:name "snake-game" :tests tests}))

{:main main}
