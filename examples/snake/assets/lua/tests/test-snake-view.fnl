(local Runner (require :tests/runner))
(local BuildContext (require :build-context))
(local Snake (require :snake/game))
(local SnakeView (require :snake/view))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(add-test "snake board builds one cell per coordinate"
  (fn []
    (local game (Snake.create {:width 4 :height 3
                               :initial-snake [{:x 2 :y 2} {:x 1 :y 2}]
                               :initial-food {:x 4 :y 3}}))
    (local ctx (BuildContext {}))
    (local board ((SnakeView.SnakeBoard {:game game :cell-size 1.0}) ctx))
    (assert board "SnakeBoard should build a board")
    (assert board.layout "SnakeBoard should expose layout")
    (assert (= (length board.cells) 3) "SnakeBoard should create one row per y")
    (assert (= (length (. board.cells 1)) 4) "SnakeBoard should create one cell per x")
    (board:drop)))

(add-test "snake board sync reflects model cell kinds"
  (fn []
    (local game (Snake.create {:width 4 :height 3
                               :initial-snake [{:x 2 :y 2} {:x 1 :y 2}]
                               :initial-food {:x 4 :y 3}}))
    (local ctx (BuildContext {}))
    (local board ((SnakeView.SnakeBoard {:game game :cell-size 1.0}) ctx))
    (board:sync)
    (local head-cell (. (. board.cells 2) 2))
    (local body-cell (. (. board.cells 2) 1))
    (local food-cell (. (. board.cells 3) 4))
    (local empty-cell (. (. board.cells 1) 1))
    (assert (= head-cell.kind "head") "head cell should sync")
    (assert (= body-cell.kind "snake") "body cell should sync")
    (assert (= food-cell.kind "food") "food cell should sync")
    (assert (= empty-cell.kind "empty") "empty cell should sync")
    (board:drop)))

(add-test "snake screen sync updates status text"
  (fn []
    (local game (Snake.create {:width 4 :height 3
                               :initial-snake [{:x 4 :y 2} {:x 3 :y 2}]
                               :initial-food {:x 1 :y 1}}))
    (local ctx (BuildContext {}))
    (local screen ((SnakeView.SnakeScreen {:game game}) ctx))
    (assert screen.board "SnakeScreen should own a board")
    (assert screen.status-text "SnakeScreen should expose status text")
    (screen:sync)
    (game:step)
    (screen:sync)
    (assert (string.find screen.status-content "Game Over" 1 true)
            "screen status should show game over")
    (screen:drop)))

(fn main []
  (Runner.run-tests {:name "snake-view" :tests tests}))

{:main main :tests tests}
