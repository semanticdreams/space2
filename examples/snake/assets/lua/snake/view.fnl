(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local {: Layout} (require :layout))
(local Padding (require :padding))
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

(fn darken [color factor]
  (local f (or factor 0.65))
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
  (local front (or widget.front (and widget.cuboid widget.cuboid.__front_widget)))
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

(fn SnakeBoard [opts]
  (local options (or opts {}))
  (local game (assert options.game "SnakeBoard requires :game"))
  (local cell-size (or options.cell-size default-cell-size))
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
               :measurer (fn [self]
                           (set self.measure (glm.vec3 (* game.width cell-size)
                                                       (* game.height cell-size)
                                                       cell-size)))
               :layouter
               (fn [self]
                 (local board-size (glm.vec3 (* game.width cell-size)
                                             (* game.height cell-size)
                                             (. self.size 3)))
                 (set background.layout.size board-size)
                 (set background.layout.position self.position)
                 (set background.layout.rotation self.rotation)
                 (set background.layout.depth-offset-index self.depth-offset-index)
                 (set background.layout.clip-region self.clip-region)
                 (background.layout:layouter)
                 (each [row-index row (ipairs cells)]
                   (each [col-index cell (ipairs row)]
                     (local local-position (glm.vec3 (* (- col-index 1) cell-size)
                                                    (* (- row-index 1) cell-size)
                                                    0))
                     (set cell.widget.layout.size (glm.vec3 cell-size cell-size cell-size))
                     (set cell.widget.layout.position (+ self.position (self.rotation:rotate local-position)))
                     (set cell.widget.layout.rotation self.rotation)
                     (set cell.widget.layout.depth-offset-index (+ self.depth-offset-index 1))
                     (set cell.widget.layout.clip-region self.clip-region)
                     (cell.widget.layout:layouter))))}))

    (local board
      {:layout layout
       :background background
       :cells cells
       :sync sync
       :drop (fn [self]
               (self.background:drop)
               (each [_ row (ipairs self.cells)]
                 (each [_ cell (ipairs row)]
                   (cell.widget:drop)))
               (self.layout:drop))})
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
    (var board nil)
    (var status-text-entity nil)

    (local board-builder
      (SnakeBoard {:game game
                   :cell-size (or options.cell-size default-cell-size)}))
    (local board-capture-builder
      (fn [child-ctx]
        (set board (board-builder child-ctx))
        board))
    (local status-builder
      (fn [child-ctx]
        (set status-text-entity
             ((Text {:text (status-text game)
                     :color text-color}) child-ctx))
        status-text-entity))
    (local title-builder
      (Text {:text "Snake"
             :color text-color
             :scale 1.25}))
    (local controls-builder
      (Text {:text "Arrow keys or WASD to turn. Space/Enter restarts after game over."
             :color text-color}))
    (local content-builder
      (Padding {:edge-insets [0.5 0.5]
                :child
                (Flex {:axis 2
                       :xalign :stretch
                       :yspacing 0.4
                       :children [(FlexChild title-builder 0)
                                  (FlexChild board-capture-builder 0)
                                  (FlexChild status-builder 0)
                                  (FlexChild controls-builder 0)]})}))
    (local content (content-builder ctx))
    (assert board "SnakeScreen build requires board")
    (assert status-text-entity "SnakeScreen build requires status text")

    (local layout
      (Layout {:name "snake-screen"
               :children [background.layout content.layout]
               :measurer (fn [self]
                           (content.layout:measurer)
                           (set self.measure content.layout.measure))
               :layouter
               (fn [self]
                 (set background.layout.size self.size)
                 (set background.layout.position self.position)
                 (set background.layout.rotation self.rotation)
                 (set background.layout.depth-offset-index self.depth-offset-index)
                 (set background.layout.clip-region self.clip-region)
                 (background.layout:layouter)
                 (set content.layout.size self.size)
                 (set content.layout.position self.position)
                 (set content.layout.rotation self.rotation)
                 (set content.layout.depth-offset-index (+ self.depth-offset-index 1))
                 (set content.layout.clip-region self.clip-region)
                 (content.layout:layouter))}))

    (local screen
      {:layout layout
       :background background
       :content content
       :board board
       :status-text status-text-entity
       :status-content (status-text game)
       :sync (fn [self]
               (self.board:sync)
               (set self.status-content (status-text game))
               (self.status-text:set-text self.status-content))
       :drop (fn [self]
               (self.background:drop)
               (self.content:drop)
               (self.layout:drop))})
    (screen:sync)
    screen))

{:SnakeBoard SnakeBoard
 :SnakeScreen SnakeScreen}
