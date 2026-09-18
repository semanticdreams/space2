(local Runner (require :tests/runner))
(local Snake (require :snake/game))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(add-test "moves-right-by-default"
  (fn []
    (local game (Snake.create {:width 8 :height 6
                               :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                               :initial-food {:x 6 :y 3}}))
    (local event (game:step))
    (local head (. game.snake 1))
    (assert (= event.status :moved) "first step should move")
    (assert (= head.x 4) "head x should advance right")
    (assert (= head.y 3) "head y should stay constant")))

(add-test "rejects-direct-reversal"
  (fn []
    (local game (Snake.create {:width 8 :height 6
                               :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                               :initial-food {:x 6 :y 3}}))
    (assert (= (game:turn :right) false) "same-direction turn should not report a change")
    (assert (= game.direction :right) "same-direction turn should keep direction")
    (assert (= (game:turn :left) false) "right-moving snake cannot reverse left")
    (assert (= game.direction :right) "direction should remain right")
    (assert (= (game:turn :up) true) "perpendicular turn should be accepted")
    (assert (= game.direction :up) "direction should change to up")))

(add-test "eats-food-and-grows"
  (fn []
    (local game (Snake.create {:width 8 :height 6
                               :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                               :initial-food {:x 4 :y 3}
                               :food-sequence [{:x 1 :y 1}]}))
    (local event (game:step))
    (assert (= event.status :ate) "step into food should eat")
    (assert (= game.score 1) "score should increment")
    (assert (= (length game.snake) 3) "snake should grow by one")
    (assert (= game.food.x 1) "next deterministic food x should be used")
    (assert (= game.food.y 1) "next deterministic food y should be used")))

(add-test "detects-wall-hit"
  (fn []
    (local game (Snake.create {:width 5 :height 5
                               :initial-snake [{:x 5 :y 3} {:x 4 :y 3}]
                               :initial-food {:x 1 :y 1}}))
    (local event (game:step))
    (assert (= event.status :wall-hit) "moving beyond width should hit wall")
    (assert game.game-over? "wall hit should end game")))

(add-test "detects-self-hit"
  (fn []
    (local game (Snake.create {:width 8 :height 8
                               :initial-snake [{:x 4 :y 4} {:x 4 :y 5} {:x 3 :y 5} {:x 3 :y 4} {:x 3 :y 3}]
                               :initial-direction :up
                               :initial-food {:x 8 :y 8}}))
    (game:turn :left)
    (local event (game:step))
    (assert (= event.status :self-hit) "head should collide with body")
    (assert game.game-over? "self hit should end game")))

(fn main []
  (Runner.run-tests {:name "snake-game" :tests tests}))

{:main main}
