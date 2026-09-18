(local Runner (require :tests/runner))
(local glm (require :glm))
(local BuildContext (require :build-context))
(local {: Layout} (require :layout))
(local Snake (require :snake/game))
(local SnakeSurface (require :snake/surface))
(local SnakeView (require :snake/view))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn assert-layout-size [layout width height label]
  (assert layout (.. label " should have layout"))
  (assert (= layout.size.x width)
          (string.format "%s width should be %.2f, got %.2f" label width layout.size.x))
  (assert (= layout.size.y height)
          (string.format "%s height should be %.2f, got %.2f" label height layout.size.y)))

(fn approx= [a b epsilon]
  (<= (math.abs (- a b)) (if (= epsilon nil) 1e-5 epsilon)))

(fn assert-approx [actual expected label]
  (assert (approx= actual expected 1e-4)
          (string.format "%s should be %.4f, got %.4f" label expected actual)))

(fn assert-centered-x [layout root-width label]
  (local center-x (+ layout.position.x (/ layout.size.x 2)))
  (assert-approx center-x (/ root-width 2) label))

(fn assert-surface-create-fails [opts label]
  (local (ok err) (pcall SnakeSurface.create opts))
  (assert (not ok) (.. label " should reject invalid surface options"))
  (assert (string.find (tostring err) "world-units-per-pixel" 1 true)
          (.. label " should report world-units-per-pixel error")))

(fn noop-update [_self]
  nil)

(fn drop-probe [self]
  (self.layout:drop))

(fn render-target-probe-builder [_ctx]
  {:layout nil
   :update noop-update
   :drop noop-update})

(fn layout-probe-builder [_ctx]
  {:layout (Layout {:name "snake-surface-probe"})
   :update noop-update
   :drop drop-probe})

(fn make-counting-set-text [original-set-text state]
  (fn counting-set-text [self text opts]
    (set state.count (+ state.count 1))
    (original-set-text self text opts)))

(fn test-board-builds-cells []
    (local game (Snake.create {:width 4 :height 3
                               :initial-snake [{:x 2 :y 2} {:x 1 :y 2}]
                               :initial-food {:x 4 :y 3}}))
    (local ctx (BuildContext {}))
    (local board ((SnakeView.SnakeBoard {:game game :cell-size 1.0}) ctx))
    (assert board "SnakeBoard should build a board")
    (assert board.layout "SnakeBoard should expose layout")
    (assert (= (length board.cells) 3) "SnakeBoard should create one row per y")
    (assert (= (length (. board.cells 1)) 4) "SnakeBoard should create one cell per x")
    (board:drop))

(add-test "snake board builds one cell per coordinate" test-board-builds-cells)

(fn test-board-sync-reflects-model []
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
    (board:drop))

(add-test "snake board sync reflects model cell kinds" test-board-sync-reflects-model)

(fn test-screen-sync-updates-status []
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
    (screen:drop))

(add-test "snake screen sync updates status text" test-screen-sync-updates-status)

(fn test-surface-presentation-target []
    (local surface (SnakeSurface.create {:viewport {:x 0 :y 0 :width 640 :height 480}}))
    (local entity (surface:build render-target-probe-builder))
    (assert entity "surface should return built entity")
    (surface:update)
    (local target (surface:presentation-target))
    (assert target "surface should expose presentation target")
    (assert (= target.kind :hud) "snake surface should render as a HUD-like orthographic target")
    (assert target.projection "surface target should expose projection")
    (assert (= (length (target:get-render-contexts)) 1)
            "surface target should expose one render context")
    (surface:drop))

(add-test "snake surface exposes render presentation target" test-surface-presentation-target)

(fn test-surface-scales-root-layout []
    (local surface (SnakeSurface.create {:viewport {:x 0 :y 0 :width 640 :height 480}}))
    (local entity (surface:build layout-probe-builder))
    (assert-layout-size entity.layout 32 24 "default snake surface root")
    (surface:update-viewport {:x 0 :y 0 :width 800 :height 600})
    (assert-layout-size entity.layout 40 30 "resized snake surface root")
    (surface:drop))

(add-test "snake surface scales root layout to HUD world units" test-surface-scales-root-layout)

(fn test-surface-projection-non-inverted []
    (local surface (SnakeSurface.create {:viewport {:x 0 :y 0 :width 640 :height 480}}))
    (local world-height 24)
    (local bottom (* surface.projection (glm.vec4 0 0 0 1)))
    (local top (* surface.projection (glm.vec4 0 world-height 0 1)))
    (assert (< bottom.y top.y)
            "non-inverted projection should map higher world y above lower world y")
    (assert-approx bottom.y -1 "projection bottom y")
    (assert-approx top.y 1 "projection top y")
    (surface:drop))

(add-test "snake surface projection uses non-inverted y for upright text" test-surface-projection-non-inverted)

(fn test-screen-centers-and-expands-board []
    (local game (Snake.create {:width 24 :height 16}))
    (local surface (SnakeSurface.create {:viewport {:x 0 :y 0 :width 800 :height 600}}))
    (local screen (surface:build (SnakeView.SnakeScreen {:game game})))
    (surface:update)
    (assert screen.board "SnakeScreen should expose board")
    (assert (> screen.board.layout.position.x 1)
            "board should not be anchored to the left edge")
    (assert (> screen.board.layout.position.y 1)
            "board should not be anchored to the bottom edge")
    (assert (> screen.board.layout.size.x 30)
            "board should use available viewport width")
    (assert (> screen.board.layout.size.y 20)
            "board should use available viewport height")
    (assert-centered-x screen.board.layout 40 "board center x")
    (surface:drop))

(add-test "snake screen centers and expands board within viewport" test-screen-centers-and-expands-board)

(fn layout-top [layout]
    (+ layout.position.y layout.size.y))

(fn test-screen-stack-order-non-inverted []
    (local game (Snake.create {:width 24 :height 16}))
    (local surface (SnakeSurface.create {:viewport {:x 0 :y 0 :width 800 :height 600}}))
    (local screen (surface:build (SnakeView.SnakeScreen {:game game})))
    (surface:update)
    (assert (> screen.title-text.layout.position.y (layout-top screen.board.layout))
            "title should render above the board on a non-inverted surface")
    (assert (> screen.board.layout.position.y (layout-top screen.status-text.layout))
            "status should render below the board on a non-inverted surface")
    (assert (> screen.status-text.layout.position.y (layout-top screen.controls-text.layout))
            "controls should render below status on a non-inverted surface")
    (surface:drop))

(add-test "snake screen stacks title board status and controls in visual order" test-screen-stack-order-non-inverted)

(fn test-board-game-up-renders-upward []
    (local game (Snake.create {:width 4 :height 3
                               :initial-snake [{:x 2 :y 2} {:x 2 :y 3}]
                               :initial-food {:x 4 :y 3}}))
    (local surface (SnakeSurface.create {:viewport {:x 0 :y 0 :width 800 :height 600}}))
    (local screen (surface:build (SnakeView.SnakeScreen {:game game})))
    (surface:update)
    (local current-row (. (. screen.board.cells 2) 2))
    (local up-row (. (. screen.board.cells 1) 2))
    (assert (> up-row.widget.layout.position.y current-row.widget.layout.position.y)
            "smaller game y from :up should render higher on the non-inverted surface")
    (surface:drop))

(add-test "snake board maps game up to higher rendered y" test-board-game-up-renders-upward)

(fn test-screen-sync-skips-unchanged-status []
    (local game (Snake.create {:width 4 :height 3
                               :initial-snake [{:x 2 :y 2} {:x 1 :y 2}]
                               :initial-food {:x 4 :y 3}}))
    (local surface (SnakeSurface.create {:viewport {:x 0 :y 0 :width 800 :height 600}}))
    (local screen (surface:build (SnakeView.SnakeScreen {:game game})))
    (surface:update)
    (local original-set-text screen.status-text.set-text)
    (local set-text-state {:count 0})
    (set screen.status-text.set-text (make-counting-set-text original-set-text set-text-state))
    (local board-x screen.board.layout.position.x)
    (local board-y screen.board.layout.position.y)
    (local status-x screen.status-text.layout.position.x)
    (local status-y screen.status-text.layout.position.y)
    (screen:sync)
    (surface:update)
    (assert (= set-text-state.count 0)
            "unchanged status sync should not call Text:set-text")
    (assert-approx screen.board.layout.position.x board-x "stable board x")
    (assert-approx screen.board.layout.position.y board-y "stable board y")
    (assert-approx screen.status-text.layout.position.x status-x "stable status x")
    (assert-approx screen.status-text.layout.position.y status-y "stable status y")
    (surface:drop))

(add-test "snake screen sync skips unchanged status text updates" test-screen-sync-skips-unchanged-status)

(fn test-surface-rejects-invalid-scale []
    (assert-surface-create-fails {:world-units-per-pixel false} "false world scale")
    (assert-surface-create-fails {:world-units-per-pixel 0} "zero world scale"))

(add-test "snake surface rejects invalid explicit world scale" test-surface-rejects-invalid-scale)

(fn main []
  (Runner.run-tests {:name "snake-view" :tests tests}))

{:main main :tests tests}
