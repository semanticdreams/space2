(local glm (require :glm))
(local {: Layout} (require :layout))
(local Rectangle (require :rectangle))
(local Text (require :text))
(local {: WidgetCuboid} (require :widget-cuboid))

(local board-background (glm.vec4 0.06 0.08 0.07 1))
(local empty-cell-color (glm.vec4 0.10 0.14 0.12 1))
(local snake-body-color (glm.vec4 0.20 0.78 0.33 1))
(local snake-head-color (glm.vec4 0.52 0.96 0.44 1))
(local food-color (glm.vec4 0.95 0.25 0.25 1))
(local text-color (glm.vec4 0.90 0.95 0.90 1))
(local panel-background (glm.vec4 0.09 0.11 0.10 1))
(local default-cell-size 1.0)
(local screen-padding 1.0)
(local screen-gap 0.4)
(local minimum-cell-size 0.2)

(fn darken [color factor]
  (local f (if (= factor nil) 0.65 factor))
  (glm.vec4 (* color.x f) (* color.y f) (* color.z f) color.w))

(fn kind-color [kind]
  (if (= kind "head") snake-head-color
      (= kind "snake") snake-body-color
      (= kind "food") food-color
      empty-cell-color))

(fn resolve-visible-face [face]
  (if (and face face.set-visible)
      face
      (and face face.child face.child.set-visible face.child)))

(fn collect-side-faces [widget]
  (local out [])
  (local faces (and widget widget.cuboid widget.cuboid.faces))
  (when faces
    (each [i face (ipairs faces)]
      (when (> i 1)
        (local target (resolve-visible-face face))
        (when target
          (table.insert out target)))))
  out)

(fn make-cell [ctx]
  (local front-builder (Rectangle {:color empty-cell-color}))
  (local builder
    (WidgetCuboid {:child front-builder
                   :side-color (darken empty-cell-color)
                   :depth-scale 0.25
                   :min-depth 0.05}))
  (local widget (builder ctx))
  (local front (if widget.front
                   widget.front
                   (and widget.cuboid widget.cuboid.__front_widget)))
  (local side-faces (collect-side-faces widget))

  (fn set-color [_self color]
    (local side-color (darken color))
    (when front
      (set front.color color)
      (when front.layout
        (front.layout:mark-layout-dirty)))
    (each [_ face (ipairs side-faces)]
      (set face.color side-color)
      (when face.layout
        (face.layout:mark-layout-dirty))))

  (fn set-visible [_self visible?]
    (when front
      (front:set-visible visible? {:mark-layout-dirty? false}))
    (each [_ face (ipairs side-faces)]
      (face:set-visible visible? {:mark-layout-dirty? false})))

  (set widget.set-color set-color)
  (set widget.set-visible set-visible)
  (widget:set-visible false)
  widget)

(fn board-natural-size [game cell-size]
  (glm.vec3 (* game.width cell-size)
            (* game.height cell-size)
            cell-size))

(fn board-size-for-layout [layout game cell-size fit-to-layout?]
  (if fit-to-layout?
      (glm.vec3 layout.size.x layout.size.y
                (math.min (/ layout.size.x game.width)
                          (/ layout.size.y game.height)))
      (board-natural-size game cell-size)))

(fn measure-board-layout [layout game cell-size]
  (set layout.measure (board-natural-size game cell-size)))

(fn layout-cell [board-layout cell col-index row-index game-height width height depth]
  (local local-position (glm.vec3 (* (- col-index 1) width)
                                  (* (- game-height row-index) height)
                                  0))
  (set cell.widget.layout.size (glm.vec3 width height depth))
  (set cell.widget.layout.position (+ board-layout.position (board-layout.rotation:rotate local-position)))
  (set cell.widget.layout.rotation board-layout.rotation)
  (set cell.widget.layout.depth-offset-index (+ board-layout.depth-offset-index 1))
  (set cell.widget.layout.clip-region board-layout.clip-region)
  (cell.widget.layout:layouter))

(fn layout-board [layout game background cells cell-size fit-to-layout?]
  (local board-size (board-size-for-layout layout game cell-size fit-to-layout?))
  (local actual-cell-width (/ board-size.x game.width))
  (local actual-cell-height (/ board-size.y game.height))
  (local actual-cell-depth (math.min actual-cell-width actual-cell-height))
  (set background.layout.size board-size)
  (set background.layout.position layout.position)
  (set background.layout.rotation layout.rotation)
  (set background.layout.depth-offset-index layout.depth-offset-index)
  (set background.layout.clip-region layout.clip-region)
  (background.layout:layouter)
  (each [row-index row (ipairs cells)]
    (each [col-index cell (ipairs row)]
      (layout-cell layout cell col-index row-index game.height actual-cell-width actual-cell-height actual-cell-depth))))

(fn screen-cell-size [options]
  (if (= options.cell-size nil)
      default-cell-size
      options.cell-size))

(fn measure-screen-layout [layout game options title board status controls]
  (title.layout:measurer)
  (board.layout:measurer)
  (status.layout:measurer)
  (controls.layout:measurer)
  (local cell-size (screen-cell-size options))
  (local natural-board-width (* game.width cell-size))
  (local natural-board-height (* game.height cell-size))
  (local natural-width (math.max title.layout.measure.x
                                 natural-board-width
                                 status.layout.measure.x
                                 controls.layout.measure.x))
  (local natural-height (+ title.layout.measure.y
                           natural-board-height
                           status.layout.measure.y
                           controls.layout.measure.y
                           (* 3 screen-gap)
                           (* 2 screen-padding)))
  (set layout.measure (glm.vec3 (+ natural-width (* 2 screen-padding))
                                natural-height
                                cell-size)))

(fn layout-screen-child [parent child size x y depth]
  (set child.layout.size size)
  (set child.layout.position (glm.vec3 x y 0))
  (set child.layout.rotation parent.rotation)
  (set child.layout.depth-offset-index (+ parent.depth-offset-index depth))
  (set child.layout.clip-region parent.clip-region)
  (child.layout:layouter))

(fn layout-screen-background [layout background]
  (set background.layout.size layout.size)
  (set background.layout.position layout.position)
  (set background.layout.rotation layout.rotation)
  (set background.layout.depth-offset-index layout.depth-offset-index)
  (set background.layout.clip-region layout.clip-region)
  (background.layout:layouter))

(fn layout-screen [layout game background title board status controls]
  (layout-screen-background layout background)
  (title.layout:measurer)
  (status.layout:measurer)
  (controls.layout:measurer)
  (local title-size title.layout.measure)
  (local status-size status.layout.measure)
  (local controls-size controls.layout.measure)
  (local available-width (math.max 1 (- layout.size.x (* 2 screen-padding))))
  (local available-height (math.max 1 (- layout.size.y
                                         title-size.y
                                         status-size.y
                                         controls-size.y
                                         (* 3 screen-gap)
                                         (* 2 screen-padding))))
  (local next-cell-size (math.max minimum-cell-size
                                  (math.min (/ available-width game.width)
                                            (/ available-height game.height))))
  (local board-size (glm.vec3 (* game.width next-cell-size)
                              (* game.height next-cell-size)
                              next-cell-size))
  (local stack-height (+ title-size.y board-size.y status-size.y controls-size.y (* 3 screen-gap)))
  (local base-y (+ layout.position.y (/ (math.max 0 (- layout.size.y stack-height)) 2)))
  (local stack-top (+ base-y stack-height))
  (local title-y (- stack-top title-size.y))
  (local board-y (- title-y screen-gap board-size.y))
  (local status-y (- board-y screen-gap status-size.y))
  (local controls-y (- status-y screen-gap controls-size.y))
  (layout-screen-child layout title title-size (+ layout.position.x (/ (- layout.size.x title-size.x) 2)) title-y 1)
  (layout-screen-child layout board board-size (+ layout.position.x (/ (- layout.size.x board-size.x) 2)) board-y 1)
  (layout-screen-child layout status status-size (+ layout.position.x (/ (- layout.size.x status-size.x) 2)) status-y 1)
  (layout-screen-child layout controls controls-size (+ layout.position.x (/ (- layout.size.x controls-size.x) 2)) controls-y 1))

(fn make-board-measurer [game cell-size]
  (fn measure-snake-board [layout]
    (measure-board-layout layout game cell-size)))

(fn make-board-layouter [game background cells cell-size fit-to-layout?]
  (fn layout-snake-board [layout]
    (layout-board layout game background cells cell-size fit-to-layout?)))

(fn make-screen-measurer [game options title board status controls]
  (fn measure-snake-screen [layout]
    (measure-screen-layout layout game options title board status controls)))

(fn make-screen-layouter [game background title board status controls]
  (fn layout-snake-screen [layout]
    (layout-screen layout game background title board status controls)))

(fn SnakeBoard [opts]
  (local options (or opts {}))
  (local game (assert options.game "SnakeBoard requires :game"))
  (local cell-size (screen-cell-size options))
  (local fit-to-layout? (not (not options.fit-to-layout?)))
  (fn build [ctx]
    (local background ((Rectangle {:color board-background}) ctx))
    (local cells [])

    (for [y 1 game.height]
      (local row [])
      (set (. cells y) row)
      (for [x 1 game.width]
        (local widget (make-cell ctx))
        (tset row x {:widget widget :kind "empty"})))

    (fn sync []
      (for [y 1 game.height]
        (for [x 1 game.width]
          (local cell (. (. cells y) x))
          (local kind (game:cell-kind x y))
          (set cell.kind kind)
          (cell.widget:set-color (kind-color kind))
          (cell.widget:set-visible (not (= kind "empty"))))))

    (local children [background.layout])
    (each [_ row (ipairs cells)]
      (each [_ cell (ipairs row)]
        (table.insert children cell.widget.layout)))

    (local layout
      (Layout {:name "snake-board"
                :children children
                :measurer (make-board-measurer game cell-size)
                :layouter (make-board-layouter game background cells cell-size fit-to-layout?)}))

    (local board
      {:layout layout
       :background background
       :cells cells
       :sync sync})
    (set board.drop
         (fn drop-board [self]
           (self.background:drop)
           (each [_ row (ipairs self.cells)]
             (each [_ cell (ipairs row)]
               (cell.widget:drop)))
           (self.layout:drop)))
    (board:sync)
    board))

(fn status-text [game]
  (if game.game-over?
      (string.format "Score: %d\nStatus: Game Over\nPress Space or Enter to restart" game.score)
      (string.format "Score: %d\nStatus: Playing" game.score)))

(fn SnakeScreen [opts]
  (local options (or opts {}))
  (local game (assert options.game "SnakeScreen requires :game"))
  (fn build [ctx]
    (local background ((Rectangle {:color panel-background}) ctx))
    (local cell-size (screen-cell-size options))
    (local board-builder
      (SnakeBoard {:game game
                   :cell-size cell-size
                   :fit-to-layout? true}))
    (local board (board-builder ctx))
    (local title-text ((Text {:text "Snake"
                             :color text-color
                             :scale 1.25}) ctx))
    (local status-text-entity ((Text {:text (status-text game)
                                      :color text-color}) ctx))
    (local controls-text
      ((Text {:text "Arrow keys or WASD to turn. Space/Enter restarts after game over."
              :color text-color}) ctx))

    (local layout
      (Layout {:name "snake-screen"
               :children [background.layout title-text.layout board.layout status-text-entity.layout controls-text.layout]
                :measurer (make-screen-measurer game options title-text board status-text-entity controls-text)
                :layouter (make-screen-layouter game background title-text board status-text-entity controls-text)}))

    (fn sync-screen [self]
      (self.board:sync)
      (local next-status (status-text game))
      (when (not (= next-status self.status-content))
        (set self.status-content next-status)
        (self.status-text:set-text next-status)))

    (local screen
      {:layout layout
       :background background
       :title-text title-text
       :board board
       :status-text status-text-entity
       :controls-text controls-text
       :status-content (status-text game)
       :sync sync-screen})
    (set screen.drop
         (fn drop-screen [self]
           (self.background:drop)
           (self.title-text:drop)
           (self.board:drop)
           (self.status-text:drop)
           (self.controls-text:drop)
           (self.layout:drop)))
    (screen:sync)
    screen))

{:SnakeBoard SnakeBoard
 :SnakeScreen SnakeScreen}
