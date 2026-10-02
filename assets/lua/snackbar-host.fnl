(local glm (require :glm))
(local {: Layout} (require :layout))
(local SnackbarTheme (require :snackbar-theme))
(local SnackbarContent (require :snackbar-content))

(fn table-index-of [items item]
  (var found nil)
  (each [idx value (ipairs items)]
    (when (and (not found) (= value item))
      (set found idx)))
  found)

(fn entry-id-set [entries]
  (local ids {})
  (each [_ entry (ipairs entries)]
    (set (. ids entry.id) true))
  ids)

(fn resolve-option [options theme key]
  (if (not (= (. options key) nil))
      (. options key)
      (. theme key)))

(fn value-or [value fallback]
  (if (not (= value nil)) value fallback))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn finite-positive-number? [value]
  (and (finite-number? value)
       (> value 0)))

(fn finite-nonnegative-number? [value]
  (and (finite-number? value)
       (>= value 0)))

(fn remove-child-layout [layout child]
  (local idx (table-index-of layout.children child.layout))
  (when idx
    (layout:remove-child idx)))

(fn drop-rendered-child [state child]
  (remove-child-layout state.layout child)
  (child:drop))

(fn find-rendered-index [children id]
  (var found nil)
  (each [idx child (ipairs children)]
    (when (and (not found) (= child.entry-id id))
      (set found idx)))
  found)

(fn make-entry-widget [state entry]
  (local handle (assert (state.manager:handle-for entry.id)
                        (.. "SnackbarHost missing handle for entry: " (tostring entry.id))))
  (local live-entry handle.entry)
  (local builder (if entry.content-builder
                     entry.content-builder
                     state.content-builder))
  (local child (builder state.ctx live-entry handle))
  (assert (and child child.layout) "SnackbarHost content-builder must return a widget with layout")
  (set child.entry-id entry.id)
  (set child.snackbar-entry live-entry)
  (set child.snackbar-handle handle)
  child)

(fn ensure-child-order [state entries]
  (local ordered [])
  (each [_ entry (ipairs entries)]
    (local idx (find-rendered-index state.children entry.id))
    (assert idx (.. "SnackbarHost missing rendered child for entry: " (tostring entry.id)))
    (table.insert ordered (. state.children idx)))
  (while (> (length state.children) 0)
    (table.remove state.children 1))
  (each [_ child (ipairs ordered)]
    (table.insert state.children child))
  (state.layout:set-children (icollect [_ child (ipairs ordered)] child.layout)))

(fn remove-missing-children [state ids]
  (var idx 1)
  (while (<= idx (length state.children))
    (local child (. state.children idx))
    (if (. ids child.entry-id)
        (set idx (+ idx 1))
        (do
          (table.remove state.children idx)
          (drop-rendered-child state child)))))

(fn remove-replaced-children [state entries]
  (local live-handles {})
  (each [_ entry (ipairs entries)]
    (set (. live-handles entry.id)
         (assert (state.manager:handle-for entry.id)
                 (.. "SnackbarHost missing handle for entry: " (tostring entry.id)))))
  (var idx 1)
  (while (<= idx (length state.children))
    (local child (. state.children idx))
    (local live-handle (. live-handles child.entry-id))
    (if (and live-handle (not (= child.snackbar-handle live-handle)))
        (do
          (table.remove state.children idx)
          (drop-rendered-child state child))
        (set idx (+ idx 1)))))

(fn add-new-children [state entries]
  (each [_ entry (ipairs entries)]
    (when (not (find-rendered-index state.children entry.id))
      (local child (make-entry-widget state entry))
      (table.insert state.children child)
      (state.layout:add-child child.layout))))

(fn mark-host-measure-dirty [state]
  (when state.layout
    (state.layout:mark-measure-dirty)))

(fn reconcile [state entries mark-dirty?]
  (when (not state.dropped?)
    (local visible (if entries entries (state.manager:visible-entries)))
    (local ids (entry-id-set visible))
    (remove-missing-children state ids)
    (remove-replaced-children state visible)
    (add-new-children state visible)
    (ensure-child-order state visible)
    (when mark-dirty?
      (mark-host-measure-dirty state))))

(fn effective-max-width [state self constraints]
  (local layout-width (if (> self.size.x 0) self.size.x 1000))
  (var max-width (value-or state.max-width layout-width))
  (when (finite-positive-number? self.size.x)
    (set max-width (math.min max-width self.size.x)))
  (local constraint-width (and constraints constraints.max constraints.max.x))
  (when (finite-nonnegative-number? constraint-width)
    (set max-width (math.min max-width constraint-width)))
  max-width)

(fn measure-children [state self constraints]
  (local max-width (effective-max-width state self constraints))
  (local child-constraints {:max (glm.vec3 max-width 1000 1000)})
  (set self.measure (glm.vec3 0))
  (each [idx child (ipairs state.children)]
    (child.layout:measure-constrained child-constraints)
    (set self.measure.x (math.max self.measure.x child.layout.measure.x))
    (set self.measure.y (+ self.measure.y child.layout.measure.y))
    (set self.measure.z (math.max self.measure.z child.layout.measure.z))
    (when (< idx (length state.children))
      (set self.measure.y (+ self.measure.y state.spacing)))))

(fn top-placement? [placement]
  (if (= placement :top-right)
      true
      (= placement :top-left)))

(fn right-placement? [placement]
  (if (= placement :top-right)
      true
      (= placement :bottom-right)))

(fn assert-supported-placement [placement]
  (when (not (or (= placement :top-right)
                 (= placement :top-left)
                 (= placement :bottom-right)
                 (= placement :bottom-left)))
    (error (.. "Unsupported snackbar placement: " (tostring placement)))))

(fn total-children-height [state]
  (var total 0)
  (each [idx child (ipairs state.children)]
    (set total (+ total child.layout.measure.y))
    (when (< idx (length state.children))
      (set total (+ total state.spacing))))
  total)

(fn child-x [state self child]
  (if (right-placement? state.placement)
      (+ self.position.x self.size.x (- child.layout.measure.x))
      self.position.x))

(fn initial-y [state self]
  (if (top-placement? state.placement)
      self.position.y
      (+ self.position.y self.size.y (- (total-children-height state)))))

(fn layout-children [state self]
  (assert-supported-placement state.placement)
  (var y (initial-y state self))
  (each [idx child (ipairs state.children)]
    (local child-layout child.layout)
    (set child-layout.size (glm.vec3 child-layout.measure.x child-layout.measure.y child-layout.measure.z))
    (set child-layout.position (glm.vec3 (child-x state self child) y self.position.z))
    (set child-layout.rotation self.rotation)
    (set child-layout.depth-offset-index (+ self.depth-offset-index idx))
    (set child-layout.clip-region self.clip-region)
    (child-layout:layouter)
    (set y (+ y child-layout.size.y state.spacing))))

(fn drop-host [state self]
  (when (not state.dropped?)
    (set state.dropped? true)
    (when state.disconnect
      (state.disconnect)
      (set state.disconnect nil))
    (while (> (length state.children) 0)
      (local child (table.remove state.children 1))
      (drop-rendered-child state child))
    (self.layout:drop))
  true)

(fn SnackbarHost [opts]
  (local options (if opts opts {}))
  (fn build [ctx]
    (local manager (assert options.manager "SnackbarHost requires :manager"))
    (local theme (SnackbarTheme.resolve ctx options.theme))
    (local state {:ctx ctx
                  :manager manager
                  :children []
                  :layout nil
                  :disconnect nil
                  :dropped? false
                  :placement (resolve-option options theme :placement)
                  :spacing (resolve-option options theme :spacing)
                  :max-width (resolve-option options theme :max-width)
                  :content-builder (if options.content-builder
                                       options.content-builder
                                       (SnackbarContent.default-builder {:theme theme}))})
    (assert-supported-placement state.placement)
    (set state.spacing (if (= state.spacing nil) 0.3 state.spacing))
    (fn host-measurer [self]
      (measure-children state self nil))
    (fn host-constrained-measurer [self constraints]
      (measure-children state self constraints))
    (fn host-layouter [self]
      (layout-children state self))
    (local layout (Layout {:name "snackbar-host"
                           :measurer host-measurer
                           :constrained-measurer host-constrained-measurer
                           :layouter host-layouter}))
    (set state.layout layout)
    (fn drop [self]
      (drop-host state self))
    (fn on-manager-change [event]
      (reconcile state event.visible true))
    (local host {:layout layout
                 :children state.children
                 :drop drop})
    (set state.disconnect
         (manager:subscribe on-manager-change))
    (reconcile state (manager:visible-entries) false)
    host))

SnackbarHost
