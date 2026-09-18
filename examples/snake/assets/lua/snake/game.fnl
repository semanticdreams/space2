(local directions
  {:up {:x 0 :y -1}
   :down {:x 0 :y 1}
   :left {:x -1 :y 0}
   :right {:x 1 :y 0}})

(local opposites
  {:up :down
   :down :up
   :left :right
   :right :left})

(fn copy-cell [cell]
  {:x cell.x :y cell.y})

(fn copy-cells [cells]
  (local out [])
  (each [_ cell (ipairs cells)]
    (table.insert out (copy-cell cell)))
  out)

(fn same-cell? [a b]
  (and a b (= a.x b.x) (= a.y b.y)))

(fn occupied? [snake x y]
  (var found? false)
  (each [_ cell (ipairs snake)]
    (when (and (= cell.x x) (= cell.y y))
      (set found? true)))
  found?)

(fn default-snake [width height]
  (local head-x (math.max 2 (math.floor (/ width 2))))
  (local head-y (math.max 1 (math.floor (/ height 2))))
  [{:x head-x :y head-y}
   {:x (- head-x 1) :y head-y}
   {:x (- head-x 2) :y head-y}])

(fn scan-food [width height snake]
  (var food nil)
  (for [y 1 height]
    (for [x 1 width]
      (when (and (not food) (not (occupied? snake x y)))
        (set food {:x x :y y}))))
  food)

(fn create [opts]
  (local options (or opts {}))
  (local width (or options.width 24))
  (local height (or options.height 16))
  (local initial-snake (copy-cells (or options.initial-snake (default-snake width height))))
  (local initial-direction (or options.initial-direction :right))
  (local initial-food (when options.initial-food (copy-cell options.initial-food)))
  (local food-sequence (copy-cells (or options.food-sequence [])))
  (var food-index 1)

  (fn next-food [snake]
    (if (<= food-index (length food-sequence))
        (do
          (local food (copy-cell (. food-sequence food-index)))
          (set food-index (+ food-index 1))
          food)
        (scan-food width height snake)))

  (fn reset-state [self]
    (set food-index 1)
    (set self.width width)
    (set self.height height)
    (set self.score 0)
    (set self.game-over? false)
    (set self.direction initial-direction)
    (set self.snake (copy-cells initial-snake))
    (set self.food (or (and initial-food (copy-cell initial-food))
                       (next-food self.snake))))

  (fn turn [self direction-name]
    (assert (. directions direction-name) "unknown snake direction")
    (if (= direction-name (. opposites self.direction))
        false
        (do
          (set self.direction direction-name)
          true)))

  (fn hit-wall? [self cell]
    (or (< cell.x 1)
        (> cell.x self.width)
        (< cell.y 1)
        (> cell.y self.height)))

  (fn body-hit? [self cell growing?]
    (var hit? false)
    (local last-index (length self.snake))
    (each [index segment (ipairs self.snake)]
      (when (and (or growing? (< index last-index))
                 (same-cell? cell segment))
        (set hit? true)))
    hit?)

  (fn step [self]
    (if self.game-over?
        {:status :game-over :score self.score}
        (do
          (local vector (. directions self.direction))
          (local head (. self.snake 1))
          (local next-head {:x (+ head.x vector.x)
                            :y (+ head.y vector.y)})
          (local eating? (same-cell? next-head self.food))
          (if (hit-wall? self next-head)
              (do
                (set self.game-over? true)
                {:status :wall-hit :score self.score})
              (body-hit? self next-head eating?)
              (do
                (set self.game-over? true)
                {:status :self-hit :score self.score})
              (do
                (table.insert self.snake 1 next-head)
                (if eating?
                    (do
                      (set self.score (+ self.score 1))
                      (set self.food (next-food self.snake))
                      {:status :ate :score self.score})
                    (do
                      (table.remove self.snake)
                      {:status :moved :score self.score})))))))

  (fn cell-kind [self x y]
    (var kind "empty")
    (when (same-cell? (. self.snake 1) {:x x :y y})
      (set kind "head"))
    (when (= kind "empty")
      (each [index segment (ipairs self.snake)]
        (when (and (> index 1) (= segment.x x) (= segment.y y))
          (set kind "snake"))))
    (when (and (= kind "empty") (same-cell? self.food {:x x :y y}))
      (set kind "food"))
    kind)

  (fn board-lines [self]
    (local lines [])
    (table.insert lines (string.rep "#" (+ self.width 2)))
    (for [y 1 self.height]
      (local row ["#"])
      (for [x 1 self.width]
        (local kind (cell-kind self x y))
        (table.insert row (if (= kind "head") "@"
                              (= kind "snake") "o"
                              (= kind "food") "*"
                              " ")))
      (table.insert row "#")
      (table.insert lines (table.concat row "")))
    (table.insert lines (string.rep "#" (+ self.width 2)))
    lines)

  (fn restart [self]
    (reset-state self))

  (local self {:width width
               :height height
               :score 0
               :game-over? false
               :direction initial-direction
               :snake []
               :food nil
               :turn turn
               :step step
               :restart restart
               :cell-kind cell-kind
               :board-lines board-lines})
  (reset-state self)
  self)

{:directions directions
 :create create}
