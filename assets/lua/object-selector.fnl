(local glm (require :glm))
(local Signal (require :signal))
(local BoxSelector (require :box-selector))
(local viewport-utils (require :viewport-utils))
(local logging (require :logging))

(fn shallow-copy [items]
    (local copy [])
    (each [_ item (ipairs (or items []))]
        (table.insert copy item))
    copy)

(fn selection-equal? [a b]
    (if (not (= (length a) (length b)))
        false
        (do
            (var match-count 0)
            (each [_ item-a (ipairs a)]
                (each [_ item-b (ipairs b)]
                    (when (= item-a item-b)
                        (set match-count (+ match-count 1)))))
            (= match-count (length a)))))

(fn resolve-position [selectable]
    (or (and selectable selectable.position)
        (and selectable selectable.layout selectable.layout.position)))

(fn pointer-target-enabled? [target]
    (if (and target app app.pointer-target-enabled?)
        (app.pointer-target-enabled? target)
        true))

(fn selectable-enabled? [selectable]
    (pointer-target-enabled? (and selectable selectable.pointer-target)))

(fn replace-contents [target source]
    (for [i (length target) 1 -1]
        (table.remove target i))
    (each [_ item (ipairs (or source []))]
        (table.insert target item)))

(fn default-project [position opts]
    (local options (or opts {}))
    (local viewport (viewport-utils.to-table (or options.viewport app.viewport)))
    (assert viewport "ObjectSelector requires a viewport")
    (assert (> viewport.width 0) "ObjectSelector requires viewport width > 0")
    (assert (> viewport.height 0) "ObjectSelector requires viewport height > 0")
    (local view (or options.view
                    (and app.scene app.scene.get-view-matrix
                         (app.scene:get-view-matrix))
                    (let [cam (app.presentation-camera)]
                      (and cam cam.get-view-matrix (cam:get-view-matrix)))))
    (assert view "ObjectSelector requires a view matrix")
    (local projection (or options.projection
                           (and app.scene app.scene.projection)
                           app.projection))
    (assert projection "ObjectSelector requires a projection matrix")
    (assert (and glm glm.project) "ObjectSelector requires glm.project")
    (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
    (local projected (glm.project position view projection viewport-vec))
    (assert projected "glm.project returned nil")
    (glm.vec3 projected.x
          (- (+ viewport.height viewport.y) projected.y)
          projected.z))

(fn box->bounds [box]
    (local p1 (or box.p1 (. box 1)))
    (local p2 (or box.p2 (. box 2)))
    (when (and p1 p2)
        (local min-x (math.min p1.x p2.x))
        (local max-x (math.max p1.x p2.x))
        (local min-y (math.min p1.y p2.y))
        (local max-y (math.max p1.y p2.y))
        {:min-x min-x :max-x max-x :min-y min-y :max-y max-y}))

(fn default-box-point->screen [point opts]
    (local options (or opts {}))
    (local viewport (viewport-utils.to-table (or options.viewport app.viewport)))
    (viewport-utils.input-pos->viewport-pos point viewport app.engine))

(fn ObjectSelector [opts]
    (local options (or opts {}))
    (local provided-box (or options.box_selector
                            (rawget options "box-selector")
                            (BoxSelector {:ctx options.ctx
                                          :ctx-provider options.ctx-provider
                                          :color options.color
                                          :depth-offset-index options.depth-offset-index
                                          :plane-z options.plane-z
                                          :viewport options.viewport
                                          :view options.view
                                          :projection options.projection})))
    (local box (if (= (type provided-box) :function)
                   (provided-box)
                   provided-box))
    (local project (or options.project default-project))
    (local changed (Signal))
    (local exited (Signal))
    (local box-point->screen (or options.box-point->screen default-box-point->screen))
    (var selectables [])
    (local selected [])
    (var enabled? (not (= options.enabled? false)))

    (fn resolve-pointer-target []
        (local ctx (or (and options.ctx-provider (options.ctx-provider))
                       options.ctx))
        (or options.pointer-target
            (and ctx ctx.pointer-target)
            app.canvas))

    (fn format-selectable [item]
        (or (and item item.label)
            (and item item.key)
            (tostring item)))

    (fn format-labels [items]
        (local labels [])
        (each [_ item (ipairs (or items []))]
            (table.insert labels (format-selectable item)))
        (if (> (length labels) 0)
            (table.concat labels ", ")
            "none"))

    (fn log-selection [items]
        (logging.info (string.format "[selection] %s" (format-labels items))))

    (local on-box-changed
      (fn [box-bounds]
        (when enabled?
          (local raw-p1 (and box-bounds (or box-bounds.p1 (. box-bounds 1))))
          (local raw-p2 (and box-bounds (or box-bounds.p2 (. box-bounds 2))))
          (local normalized-bounds
            (box->bounds {:p1 (or (box-point->screen raw-p1 options) raw-p1)
                          :p2 (or (box-point->screen raw-p2 options) raw-p2)}))
          (local projected [])
          (when normalized-bounds
            (each [_ selectable (ipairs selectables)]
              (local position (resolve-position selectable))
              (when (and position (selectable-enabled? selectable))
                (local screen (project position options))
                (when (and screen
                           (>= screen.x normalized-bounds.min-x)
                           (<= screen.x normalized-bounds.max-x)
                           (>= screen.y normalized-bounds.min-y)
                           (<= screen.y normalized-bounds.max-y))
                  (table.insert projected selectable)))))
          (replace-contents selected projected)
          (log-selection selected)
          (changed:emit selected))))
    (box.changed.connect on-box-changed)
    (box.exited.connect (fn [_] (exited:emit)))

    (fn set-selectables [_self new-selectables]
        (local filtered (shallow-copy new-selectables))
        (replace-contents selectables filtered)
        (local intersection [])
        (each [_ item (ipairs selected)]
            (each [_ candidate (ipairs selectables)]
                (when (= item candidate)
                    (table.insert intersection item))))
        (when (not (selection-equal? selected intersection))
            (replace-contents selected intersection)
            (log-selection selected)
            (changed:emit selected)))

    (fn add-selectables [_self new-selectables]
        (each [_ selectable (ipairs (or new-selectables []))]
            (table.insert selectables selectable)))

    (fn replace-selectable [_self previous next-selectable]
        (assert previous "ObjectSelector.replace-selectable requires previous selectable")
        (assert next-selectable "ObjectSelector.replace-selectable requires replacement selectable")
        (for [i (length selectables) 1 -1]
            (when (and (= (. selectables i) next-selectable)
                       (not (= next-selectable previous)))
                (table.remove selectables i)))
        (var replaced? false)
        (for [i (length selectables) 1 -1]
            (when (= (. selectables i) previous)
                (if replaced?
                    (table.remove selectables i)
                    (do
                        (set (. selectables i) next-selectable)
                        (set replaced? true)))))
        (assert replaced? "ObjectSelector.replace-selectable previous selectable is not registered")
        (var selected-changed? false)
        (for [i (length selected) 1 -1]
            (when (and (= (. selected i) next-selectable)
                       (not (= next-selectable previous)))
                (table.remove selected i)
                (set selected-changed? true)))
        (each [i selectable (ipairs selected)]
            (when (= selectable previous)
                (set (. selected i) next-selectable)
                (set selected-changed? true)))
        (when selected-changed?
            (log-selection selected)
            (changed:emit selected)))

    (fn remove-selectables [_self removals]
        (local keep [])
        (each [_ selectable (ipairs selectables)]
            (var removed false)
            (each [_ target (ipairs (or removals []))]
                (when (= selectable target)
                    (set removed true)))
            (when (not removed)
                (table.insert keep selectable)))
        (replace-contents selectables keep)
        (local intersection [])
        (each [_ item (ipairs selected)]
            (each [_ candidate (ipairs selectables)]
                (when (= item candidate)
                    (table.insert intersection item))))
        (when (not (selection-equal? selected intersection))
            (replace-contents selected intersection)
            (changed:emit selected)))

    (fn unselect-all [_self]
        (when (> (length selected) 0)
            (replace-contents selected [])
            (log-selection selected)
            (changed:emit selected)))

    (fn set-selected [_self items emit-changed?]
        (local desired (or items []))
        (when (not (selection-equal? selected desired))
            (replace-contents selected desired)
            (when (not (= emit-changed? false))
                (log-selection selected)
                (changed:emit selected))))

    (fn on-mouse-button [self payload]
        (when enabled?
            (box:on-mouse-button payload)))

    (fn on-mouse-motion [self payload]
        (when enabled?
            (box:on-mouse-motion payload)))

    (fn on-key-down [self payload]
        (when enabled?
            (box:on-key-down payload)))

    (fn enable [_self]
        (set enabled? true)
        enabled?)

    (fn disable [self]
        (set enabled? false)
        (self:cancel-selection)
        enabled?)

    (fn toggle [self]
        (if enabled?
            (disable self)
            (enable self)))

    (fn cancel-selection [_self]
        (box:cancel))

    (fn drop [_self]
        (box:drop)
        (changed:clear)
        (exited:clear))

    {:selectables selectables
     :selected selected
     :changed changed
     :exited exited
     :box box
     :enable enable
     :disable disable
      :toggle toggle
      :enabled? (fn [_self] enabled?)
      :pointer-target (fn [_self] (resolve-pointer-target))
       :project project
      :active? (fn [_self] (box:active?))
      :set-selectables set-selectables
      :add-selectables add-selectables
      :replace-selectable replace-selectable
      :remove-selectables remove-selectables
     :set-selected set-selected
     :unselect-all unselect-all
     :on-mouse-button on-mouse-button
     :on-mouse-motion on-mouse-motion
     :on-key-down on-key-down
     :cancel-selection cancel-selection
     :drop drop})

ObjectSelector
