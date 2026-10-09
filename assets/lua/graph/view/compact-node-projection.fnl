(local glm (require :glm))
(local GraphNodePresentation (require :graph/view/presentation))

(fn visible-size [point]
    (assert point "CompactNodeProjection visible-size requires point")
    (var size (assert point.size "CompactNodeProjection visible-size requires base size"))
    (when point.layers
        (each [_ layer (ipairs point.layers)]
            (when (and layer layer.size (> layer.size size))
                (set size layer.size))))
    size)

(fn bounds-for-presentation [presentation]
    (when presentation
        (if presentation._card-size
            (do
                (local position (if (and presentation.layout presentation.layout.position)
                                    presentation.layout.position
                                    (assert presentation.position
                                            "CompactNodeProjection card bounds require position")))
                (local size (if (and presentation.layout presentation.layout.size)
                                presentation.layout.size
                                (assert presentation._card-size
                                        "CompactNodeProjection card bounds require size")))
                {:position (glm.vec3 position.x position.y position.z)
                 :size size})
            (do
                (local position (assert presentation.position
                                        "CompactNodeProjection point bounds require position"))
                (local size (or presentation.size 0))
                (local half (* size 0.5))
                {:position (glm.vec3 (- position.x half)
                                     (- position.y half)
                                     (- position.z half))
                 :size (glm.vec3 size size size)}))))

(fn event-options [record reason event]
    {:reason reason
     :event event
     :owner record.owner})

(fn request-record-focus! [record reason event]
    (when record.focus-node
        (record.focus-node:request-focus (event-options record reason event)))
    (when record.on-focus
        (record.on-focus record.node (event-options record reason event))))

(fn point-click [point event]
    (local record (assert point._compact_projection_record
                          "CompactNodeProjection click requires record"))
    (request-record-focus! record :pointer event))

(fn point-right-click [point event]
    (local record (assert point._compact_projection_record
                          "CompactNodeProjection right-click requires record"))
    (request-record-focus! record :pointer-menu event)
    (when record.on-right-click
        (record.on-right-click record.node event (event-options record :pointer-menu event))))

(fn point-double-click [point event]
    (local record (assert point._compact_projection_record
                          "CompactNodeProjection double-click requires record"))
    (when record.on-activate
        (record.on-activate record.node (event-options record :activate event))))

(fn point-activate [point activate-opts]
    (local record (assert point._compact_projection_record
                          "CompactNodeProjection activate requires record"))
    (when record.on-activate
        (record.on-activate record.node activate-opts))
    true)

(fn focus-node-bounds [focus-node]
    (bounds-for-presentation (assert focus-node.presentation
                                     "CompactNodeProjection focus bounds require presentation")))

(fn refresh! [record opts]
    (assert record "CompactNodeProjection refresh! requires record")
    (local options (or opts {}))
    (local point (assert record.point "CompactNodeProjection refresh! requires point"))
    (local base-size (or point.size 0))
    (local selected? (not (not options.selected?)))
    (local focused? (not (not options.focused?)))
    (local selection-border-width (or record.selection-border-width 0))
    (local focus-border-width (or record.focus-border-width 0))
    (local selection-size (if selected?
                              (+ base-size selection-border-width)
                              0))
    (local focus-size (if focused?
                          (+ base-size
                             (if selected? selection-border-width 0)
                             focus-border-width)
                          0))
    (point:set-layer-size record.focus-layer-index focus-size)
    (point:set-layer-size record.selection-layer-index selection-size)
    record)

(fn drop! [record]
    (when (and record (not record.dropped?))
        (set record.dropped? true)
        (local point record.point)
        (local clickables (assert record.clickables
                                  "CompactNodeProjection drop! requires clickables"))
        (when point
            (when (and record.left? clickables clickables.unregister)
                (clickables:unregister point))
            (when (and record.right? clickables clickables.unregister-right-click)
                (clickables:unregister-right-click point))
            (when (and record.double? clickables clickables.unregister-double-click)
                (clickables:unregister-double-click point))
            (set point.on-click nil)
            (set point.on-right-click nil)
            (set point.on-double-click nil)
            (set point.activate nil)
            (set point._compact_projection_record nil))
        (when (and record.selector record.selectable)
            (record.selector:remove-selectables [record.selectable]))
        (when record.focus-node
            (record.focus-node:drop))
        (when (and point point.drop)
            (point:drop)))
    nil)

(fn attach! [opts]
    (local options (assert opts "CompactNodeProjection attach! requires opts"))
    (local points (assert options.points "CompactNodeProjection attach! requires :points"))
    (local node (assert options.node "CompactNodeProjection attach! requires :node"))
    (local position (assert options.position "CompactNodeProjection attach! requires :position"))
    (local layers (assert options.layers "CompactNodeProjection attach! requires :layers"))
    (local clickables (assert options.clickables "CompactNodeProjection attach! requires :clickables"))
    (local key (assert node.key "CompactNodeProjection node requires key"))
    (assert clickables.register "CompactNodeProjection requires clickables.register")
    (local point
          (GraphNodePresentation.compact-point
              {:points points
               :position position
               :pointer-target options.pointer-target
               :depth-offset-step options.depth-offset-step
               :base-depth-offset-index options.base-depth-offset-index
               :base-layer-index options.base-layer-index
               :layers layers}))
    (assert point (.. "CompactNodeProjection failed to create point for " (tostring key)))
    (set point.key key)
    (set point.node node)
    (local record {:node node
                   :key key
                   :point point
                   :presentation point
                   :selectable point
                   :focus-node nil
                   :clickables clickables
                   :selector options.selector
                   :focus-layer-index (or options.focus-layer-index 1)
                   :selection-layer-index (or options.selection-layer-index 2)
                   :focus-border-width (or options.focus-border-width 0)
                   :selection-border-width (or options.selection-border-width 0)
                   :owner options.owner
                   :on-focus options.on-focus
                   :on-right-click options.on-right-click
                   :on-activate options.on-activate})
    (set point._compact_projection_record record)
    (set point.on-click point-click)
    (set point.on-right-click point-right-click)
    (set point.on-double-click point-double-click)
    (set point.activate point-activate)
    (clickables:register point)
    (set record.left? true)
    (when clickables.register-right-click
        (clickables:register-right-click point)
        (set record.right? true))
    (when clickables.register-double-click
        (clickables:register-double-click point)
        (set record.double? true))
    (when options.selector
        (options.selector:add-selectables [point]))
    (when (and options.focus options.focus.create-node)
        (local focus-node (options.focus:create-node {:name (.. "graph-node-" (tostring key))
                                                      :parent options.focus-parent}))
        (when options.focus.attach-bounds
            (options.focus:attach-bounds focus-node
                                         {:get-bounds focus-node-bounds}))
        (set focus-node.presentation point)
        (set focus-node.activate point.activate)
        (set record.focus-node focus-node))
    (set record.refresh! (fn [self refresh-opts] (refresh! self refresh-opts)))
    (set record.drop! (fn [self] (drop! self)))
    (refresh! record {:selected? options.selected? :focused? options.focused?})
    record)

{:attach! attach!
 :refresh! refresh!
 :drop! drop!
 :bounds-for-presentation bounds-for-presentation
 :visible-size visible-size}
