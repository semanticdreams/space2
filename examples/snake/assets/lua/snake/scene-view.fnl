(local glm (require :glm))
(local Cuboid (require :cuboid))
(local Rectangle (require :rectangle))
(local Sized (require :sized))

(fn scene-view-error [message]
  (error (.. "[snake.scene-view] " message)))

(fn require-method [service method]
  (local value (. service method))
  (when (not (= (type value) :function))
    (scene-view-error (.. "scene missing method: " (tostring method))))
  value)

(fn color-for-role [role]
  (if (= role :head)
      (glm.vec4 0.2 1.0 0.25 1.0)
      (= role :body)
      (glm.vec4 0.1 0.55 0.15 1.0)
      (= role :food)
      (glm.vec4 1.0 0.15 0.1 1.0)
      (glm.vec4 1.0 1.0 1.0 1.0)))

(fn make-cuboid-builder [role]
  (local color (color-for-role role))
  (Sized {:size (glm.vec3 1 1 1)
          :child (Cuboid {:children [(Rectangle {:color color})
                                     (Rectangle {:color color})
                                     (Rectangle {:color color})
                                     (Rectangle {:color color})
                                     (Rectangle {:color color})
                                     (Rectangle {:color color})]})}))

(fn make-scene-object [role]
  (local object {})
  (set object.scene-object-options
       (fn [_self]
         {:builder (make-cuboid-builder role)
          :skip-cuboid true
          :skip-physics true}))
  object)

(fn option-number [value fallback label]
  (if (= value nil)
      fallback
      (= (type value) :number)
      value
      (scene-view-error (.. label " must be a number"))))

(fn origin-vector [origin]
  (if origin
      [(or (. origin 1) 0) (or (. origin 2) 0) (or (. origin 3) 0)]
      [0 0 0]))

(fn cell-key [role x y index]
  (if (= role :body)
      (.. "body-" (tostring index) "-" (tostring x) "-" (tostring y))
      (.. (tostring role) "-" (tostring x) "-" (tostring y))))

(fn cell-position [game origin cell-size cell]
  [(+ (. origin 1) (* (- cell.x (/ (+ game.width 1) 2)) cell-size))
   (+ (. origin 2) (/ cell-size 2))
   (+ (. origin 3) (* (- cell.y (/ (+ game.height 1) 2)) cell-size))])

(fn cell-size-vector [cell-size]
  [cell-size cell-size cell-size])

(fn collect-cells [game origin cell-size]
  (local cells [])
  (each [index segment (ipairs game.snake)]
    (local role (if (= index 1) :head :body))
    (table.insert cells {:key (cell-key role segment.x segment.y index)
                         :role role
                         :x segment.x
                         :y segment.y
                         :position (cell-position game origin cell-size segment)
                         :size (cell-size-vector cell-size)}))
  (when game.food
    (table.insert cells {:key (cell-key :food game.food.x game.food.y 1)
                         :role :food
                         :x game.food.x
                         :y game.food.y
                         :position (cell-position game origin cell-size game.food)
                         :size (cell-size-vector cell-size)}))
  cells)

(fn make-spawn-spec [cell]
  {:kind :custom
   :id cell.key
   :tags [:snake cell.role]
   :position cell.position
   :size cell.size
   :object (make-scene-object cell.role)
   :solid? true})

(fn create [opts]
  (when (not (= (type opts) :table))
    (scene-view-error "create requires opts table"))
  (local scene (or opts.scene (scene-view-error "create requires :scene")))
  (local game (or opts.game (scene-view-error "create requires :game")))
  (require-method scene :spawn)
  (require-method scene :despawn)
  (require-method scene :set-transform)
  (local cell-size (option-number opts.cell-size 1 "cell-size"))
  (local origin (origin-vector opts.origin))
  (local handles-by-key {})
  (var dropped? false)

  (fn despawn-key [key]
    (local entry (. handles-by-key key))
    (when entry
      (scene:despawn entry.handle)
      (set (. handles-by-key key) nil)))

  (fn sync [_self]
    (when dropped?
      (scene-view-error "sync after drop"))
    (local next-keys {})
    (each [_ cell (ipairs (collect-cells game origin cell-size))]
      (set (. next-keys cell.key) true)
      (local existing (. handles-by-key cell.key))
      (if existing
          (do
            (scene:set-transform existing.handle {:position cell.position :size cell.size})
            (set existing.cell cell))
          (do
            (local handle (scene:spawn (make-spawn-spec cell)))
            (set (. handles-by-key cell.key) {:handle handle :cell cell}))))
    (local stale [])
    (each [key _entry (pairs handles-by-key)]
      (when (not (. next-keys key))
        (table.insert stale key)))
    (each [_ key (ipairs stale)]
      (despawn-key key))
    true)

  (fn drop [_self]
    (when (not dropped?)
      (local keys [])
      (each [key _entry (pairs handles-by-key)]
        (table.insert keys key))
      (each [_ key (ipairs keys)]
        (despawn-key key))
      (set dropped? true))
    nil)

  {:sync sync :drop drop})

{:create create}
