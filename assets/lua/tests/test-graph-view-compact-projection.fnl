(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphView (require :graph/view))
(local CompactNodeProjection (require :graph/view/compact-node-projection))
(local BuildContext (require :build-context))
(local {:FocusManager FocusManager} (require :focus))
(local {: Layout : LayoutRoot} (require :layout))
(local LinkEntityStore (require :entities/link))
(local Signal (require :signal))

(local tests [])

(fn make-icons-stub []
    (local glyph {:advance 1})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {4242 glyph}})
    {:font font
     :get (fn [_self _name] 4242)
     :resolve (fn [self name]
                {:type :font
                 :codepoint (self:get name)
                 :font self.font})})

(fn make-ctx []
    (local focus-manager (FocusManager {:root-name "compact-projection-test"}))
    (local focus-scope (focus-manager:create-scope {:name "compact-projection-view"}))
    (local theme {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
                          :label-color (glm.vec4 1 1 1 1)
                          :label-target-pixels 13.0
                          :label-min-scale 4.0
                          :edge-color (glm.vec4 0.6 0.6 0.6 1)}
                  :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}})
    (local ctx (BuildContext {:layout-root (LayoutRoot {:log-dirt? false})
                              :clickables (assert app.clickables "compact projection test requires app.clickables")
                              :hoverables (assert app.hoverables "compact projection test requires app.hoverables")
                              :theme theme
                              :focus-manager focus-manager
                              :focus-scope focus-scope}))
    (set ctx.icons (make-icons-stub))
    ctx)

(fn preview-builder [_node _opts]
    (fn [_ctx]
        (local layout (Layout {:name "compact-projection-preview"}))
        {:layout layout
         :drop (fn [_self]
                 (layout:drop))}))

(fn compact-link-entities-for-key [_self key]
    (if (= (tostring key) "a")
        [{:source-key "a" :target-key "b"}]
        (= (tostring key) "b")
        [{:source-key "a" :target-key "b"}
         {:source-key "b" :target-key "c"}]
        []))

(fn compact-link-store []
    {:find-entities-for-key compact-link-entities-for-key
     :link-entity-created (Signal)
     :link-entity-updated (Signal)
     :link-entity-deleted (Signal)})

(fn graph-has-loader? [_self key]
    (if key true false))

(fn make-point-stub []
    (local point {:size 8
                  :layers [{:size 0} {:size 0} {:size 8}]
                  :drop-count 0})
    (set point.set-layer-size
         (fn [self idx size]
             (set (. self.layers idx :size) size)
             self))
    (set point.intersect (fn [_self _ray] nil))
    (set point.drop (fn [self]
                      (set self.drop-count (+ self.drop-count 1))))
    point)

(fn make-clickables-stub []
    (local registry {:registered []
                     :unregistered []
                     :right-registered []
                     :right-unregistered []
                     :double-registered []
                     :double-unregistered []})
    (set registry.register (fn [self point]
                             (table.insert self.registered point)))
    (set registry.unregister (fn [self point]
                               (table.insert self.unregistered point)))
    (set registry.register-right-click (fn [self point]
                                         (table.insert self.right-registered point)))
    (set registry.unregister-right-click (fn [self point]
                                           (table.insert self.right-unregistered point)))
    (set registry.register-double-click (fn [self point]
                                          (table.insert self.double-registered point)))
    (set registry.unregister-double-click (fn [self point]
                                            (table.insert self.double-unregistered point)))
    registry)

(fn raw-point-set-position [self position]
    (set self.position position))

(fn raw-point-set-position-values [self x y z]
    (set self.position (glm.vec3 x y z)))

(fn raw-point-set-color [self color]
    (set self.color color))

(fn raw-point-set-size [self size]
    (set self.size size))

(fn raw-point-set-depth-offset-index [self depth-offset-index]
    (set self.depth-offset-index depth-offset-index))

(fn raw-point-intersect [_self _ray]
    nil)

(fn make-raw-point-stub [opts raw-drops]
    {:position opts.position
     :color opts.color
     :size opts.size
     :depth-offset-index opts.depth-offset-index
     :set-position raw-point-set-position
     :set-position-values raw-point-set-position-values
     :set-color raw-point-set-color
     :set-size raw-point-set-size
     :set-depth-offset-index raw-point-set-depth-offset-index
     :intersect raw-point-intersect
     :drop (fn [_self]
             (set raw-drops.count (+ raw-drops.count 1)))})

(fn make-selector-stub []
    (local selector {:added [] :removed []})
    (set selector.add-selectables (fn [self selectables]
                                    (table.insert self.added selectables)))
    (set selector.remove-selectables (fn [self selectables]
                                       (table.insert self.removed selectables)))
    selector)

(fn focus-node-request-focus [focus-node request-opts]
    (table.insert focus-node.focus-requests request-opts))

(fn focus-node-drop [focus-node]
    (set focus-node.drop-count (+ focus-node.drop-count 1)))

(fn make-focus-stub []
    (local focus {:created []})
    (set focus.create-node
         (fn [self opts]
             (local node {:name opts.name
                          :parent opts.parent
                          :focus-requests []
                          :drop-count 0})
             (set node.request-focus focus-node-request-focus)
             (set node.drop focus-node-drop)
             (table.insert self.created node)
             node))
    (set focus.attach-bounds (fn [_self _node _opts] nil))
    focus)

(fn projection-node []
    {:key "compact-node" :size 8 :color (glm.vec4 1 1 1 1)})

(fn make-projection-callbacks [focus-calls right-click-calls activate-calls]
    {:on-focus (fn [focused-node opts]
                 (table.insert focus-calls {:node focused-node :opts opts}))
     :on-right-click (fn [right-click-node event opts]
                       (table.insert right-click-calls {:node right-click-node
                                                       :event event
                                                       :opts opts}))
     :on-activate (fn [activated-node opts]
                    (table.insert activate-calls {:node activated-node :opts opts}))})

(fn CompactNodeProjection-binds-interactions-to-supplied-point []
    (local point (make-point-stub))
    (local clickables (make-clickables-stub))
    (local owner {:name "projection-owner"})
    (local node (projection-node))
    (local focus-calls [])
    (local right-click-calls [])
    (local activate-calls [])
    (local callbacks (make-projection-callbacks focus-calls right-click-calls activate-calls))
    (local record
           (CompactNodeProjection.attach!
               {:point point
                :node node
                :clickables clickables
                :owner owner
                :on-focus callbacks.on-focus
                :on-right-click callbacks.on-right-click
                :on-activate callbacks.on-activate}))
    (assert (= record.point point) "Projection should use supplied point")
    (assert (= record.owns-point? false) "Projection should not own supplied point")
    (assert (= (type point.on-click) :function) "Supplied point should receive click handler")
    (assert (= (type point.on-right-click) :function) "Supplied point should receive right-click handler")
    (assert (= (type point.on-double-click) :function) "Supplied point should receive double-click handler")
    (assert (= (type point.activate) :function) "Supplied point should receive activate handler")
    (local click-event {:kind :click})
    (point:on-click click-event)
    (assert (= (. focus-calls 1 :node) node) "Click should focus supplied point node")
    (assert (= (. focus-calls 1 :opts :owner) owner) "Focus callback should include owner")
    (assert (= (. focus-calls 1 :opts :reason) :pointer) "Click focus reason should be pointer")
    (local right-event {:kind :right})
    (point:on-right-click right-event)
    (assert (= (. right-click-calls 1 :node) node) "Right-click should callback with node")
    (assert (= (. right-click-calls 1 :event) right-event) "Right-click should pass event")
    (assert (= (. right-click-calls 1 :opts :owner) owner) "Right-click callback should include owner")
    (local double-event {:kind :double})
    (point:on-double-click double-event)
    (assert (= (. activate-calls 1 :node) node) "Double-click should activate node")
    (assert (= (. activate-calls 1 :opts :owner) owner) "Double-click activation should include owner")
    (local activation-event {:kind :keyboard})
    (point:activate {:event activation-event})
    (assert (= (. activate-calls 2 :node) node) "Explicit activation should activate node")
    (assert (= (. activate-calls 2 :opts :event) activation-event) "Explicit activation should pass event")
    (record:drop!))

(fn CompactNodeProjection-does-not-drop-supplied-point-by-default []
    (local point (make-point-stub))
    (local clickables (make-clickables-stub))
    (local selector (make-selector-stub))
    (local focus (make-focus-stub))
    (local record
           (CompactNodeProjection.attach!
               {:point point
                :node (projection-node)
                :clickables clickables
                :selector selector
                :focus focus}))
    (record:drop!)
    (assert (= (length clickables.unregistered) 1) "Drop should unregister click handler")
    (assert (= (length clickables.right-unregistered) 1) "Drop should unregister right-click handler")
    (assert (= (length clickables.double-unregistered) 1) "Drop should unregister double-click handler")
    (assert (= (length selector.removed) 1) "Drop should remove selectable")
    (assert (= (. focus.created 1 :drop-count) 1) "Drop should drop default focus node")
    (assert (= point.drop-count 0) "Drop should not drop supplied point by default"))

(fn CompactNodeProjection-still-drops-internally-created-point-by-default []
    (local raw-drops {:count 0})
    (local points {})
    (set points.create-point
         (fn [_self opts]
             (make-raw-point-stub opts raw-drops)))
    (local record
           (CompactNodeProjection.attach!
               {:points points
                :position (glm.vec3 0 0 0)
                :layers [{:size 0 :color (glm.vec4 1 1 1 1)}
                         {:size 0 :color (glm.vec4 1 1 1 1)}
                         {:size 8 :color (glm.vec4 1 1 1 1)}]
                :node (projection-node)
                :clickables (make-clickables-stub)}))
    (assert (= record.owns-point? true) "Projection should own internally-created point")
    (record:drop!)
    (assert (= raw-drops.count 3) "Drop should drop all internally-created point layers"))

(fn run-alt-activation-fixture [loaded]
    (local ctx (make-ctx))
    (local graph (Graph {:with-start false}))
    (set graph.has-key-loader-for-key graph-has-loader?)
    (local graph-map (GraphMap.GraphMap {:graph graph :id "compact-projection-alt"}))
    (set graph-map.load-by-key
         (fn [self key]
             (table.insert loaded (tostring key))
             (self:lookup key)))
    (local a (Graph.GraphNode {:key "a" :preview preview-builder}))
    (local b (Graph.GraphNode {:key "b"}))
    (local c (Graph.GraphNode {:key "c"}))
    (graph-map:add-node a {:position (glm.vec3 0 0 0)})
    (graph-map:add-node b {:position (glm.vec3 10 0 0)})
    (graph-map:add-node c {:position (glm.vec3 20 0 0)})
    (local view (GraphView {:graph-map graph-map :ctx ctx}))
    (local point (. view.points a))
    (point:on-double-click {})
    (local card (. view.points a))
    (assert card._card-size "Fixture should expand before collapse")
    (local collapse-button (. card.header-bar.children 3 :element))
    (collapse-button:on-click {})
    (assert (not (. view.points a :_card-size)) "Fixture should collapse back to compact")
    (local focus-node (. view.focus-nodes a))
    (focus-node:request-focus)
    (focus-node:activate {:event {:mod 256 :payload {:timestamp 100}}})
    (focus-node:activate {:event {:mod 256 :payload {:timestamp 200}}})
    (assert (= (. loaded 1) "b") "First Alt activation should expand from focused node")
    (assert (= (. loaded 2) "a") "Second Alt activation should continue from previous frontier")
    (assert (= (. loaded 3) "c") "Second Alt activation should include linked frontier neighbor")
    (assert (= (length loaded) 3) "Repeated Alt activation should not restart from the original node")
    (view:drop)
    (graph-map:drop)
    (graph:drop))

(fn graph-view-collapse-preserves-alt-focus-activation-frontier []
    (local original-get-default LinkEntityStore.get-default)
    (local loaded [])
    (set LinkEntityStore.get-default compact-link-store)
    (local (ok err) (pcall run-alt-activation-fixture loaded))
    (set LinkEntityStore.get-default original-get-default)
    (when (not ok)
        (error err)))

(table.insert tests {:name "GraphView collapsed compact focus preserves Alt activation frontier"
                      :fn graph-view-collapse-preserves-alt-focus-activation-frontier})
(table.insert tests {:name "CompactNodeProjection binds interactions to supplied point"
                     :fn CompactNodeProjection-binds-interactions-to-supplied-point})
(table.insert tests {:name "CompactNodeProjection does not drop supplied point by default"
                     :fn CompactNodeProjection-does-not-drop-supplied-point-by-default})
(table.insert tests {:name "CompactNodeProjection still drops internally-created point by default"
                     :fn CompactNodeProjection-still-drops-internally-created-point-by-default})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-view-compact-projection" :tests tests})))

{:name "graph-view-compact-projection" :tests tests :main main}
