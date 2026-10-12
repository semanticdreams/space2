(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local Edge (require :graph/edge))
(local GraphView (require :graph/view))
(local OutlineRowWidget (require :graph/view/outline-row-widget))
(local {: Layout : LayoutRoot} (require :layout))

(local tests [])

(fn approx [actual expected]
  (< (math.abs (- actual expected)) 0.0001))

(fn make-test-font []
  (local glyph {:advance 8
                :planeBounds {:left 0 :bottom 0 :right 8 :top 10}
                :atlasBounds {:left 0 :bottom 0 :right 8 :top 10}})
  (local font {:glyph-map {}
               :metadata {:metrics {:lineHeight 12 :ascender 10 :descender -2}
                          :atlas {:distanceRange 4}}})
  (for [codepoint 32 126]
    (set (. font.glyph-map codepoint) glyph))
  (set (. font.glyph-map 65533) glyph)
  font)

(fn make-icons-stub []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {65533 glyph 4242 glyph}})
  (local stub {:font font
               :codepoints {:close_fullscreen 4242
                            :open_in_new 4242
                            :more_vert 4242}})
  (set stub.get
       (fn [self name]
         (local value (. self.codepoints name))
         (assert value (.. "Missing icon " name))
         value))
  (set stub.resolve
       (fn [self name]
         {:type :font :codepoint (self:get name) :font self.font}))
  stub)

(fn make-drop-handle []
  {:drop (fn [_self] nil)})

(fn make-hoverables-stub []
  {:register (fn [_self _obj] nil)
   :unregister (fn [_self _obj] nil)})

(fn make-text-batcher-stub [events]
  {:upsert-text (fn [_self _key payload]
                  (table.insert events {:kind :text-upsert :text payload.codepoints}))
   :update-text-transform (fn [_self _key _payload]
                            (table.insert events {:kind :text-transform}))
   :remove-text (fn [_self _key]
                  (table.insert events {:kind :text-remove}))})

(fn make-quad-batcher-stub [events]
  {:upsert-quad (fn [_self _key payload]
                  (table.insert events {:kind :quad-upsert :color payload.color}))
   :remove-quad (fn [_self _key]
                  (table.insert events {:kind :quad-remove}))})

(fn point-set-position [self position]
  (set self.position position))

(fn point-set-position-values [self x y z]
  (set self.position (glm.vec3 x y z)))

(fn point-set-color [self color]
  (set self.color color))

(fn point-set-size [self size]
  (set self.size size))

(fn point-set-depth-offset-index [self depth-offset-index]
  (set self.depth-offset-index depth-offset-index))

(fn point-intersect [self ray]
  (local direction (assert (and ray ray.direction) "point intersect requires ray.direction"))
  (local origin (assert ray.origin "point intersect requires ray.origin"))
  (if (= direction.z 0)
      (values false nil nil)
      (do
        (local distance (/ (- self.position.z origin.z) direction.z))
        (if (< distance 0)
            (values false nil nil)
            (do
              (local point (+ origin (* direction distance)))
              (local half (/ (or self.size 0) 2.0))
              (if (and (<= (math.abs (- point.x self.position.x)) half)
                       (<= (math.abs (- point.y self.position.y)) half))
                  (values true point distance)
                  (values false nil nil)))))))

(fn point-drop [self]
  (when (and self.fail-on-double-drop? self.dropped?)
    (error "test point dropped twice"))
  (set self.dropped? true))

(fn make-points-stub [events]
  (local created [])
  {:created created
   :create-point (fn [_self opts]
                   (local point {:position opts.position
                                 :color opts.color
                                 :size opts.size
                                 :depth-offset-index opts.depth-offset-index
                                 :set-position point-set-position
                                 :set-position-values point-set-position-values
                                 :set-color point-set-color
                                 :set-size point-set-size
                                 :set-depth-offset-index point-set-depth-offset-index
                                 :intersect point-intersect
                                 :drop point-drop})
                   (table.insert created point)
                   (table.insert events {:kind :point-create
                                         :position opts.position
                                         :color opts.color
                                         :size opts.size
                                         :depth-offset-index opts.depth-offset-index})
                   point)})

(fn register-clickable-stub [_self _target]
  (make-drop-handle))

(fn unregister-clickable-stub [_self _target]
  nil)

(fn create-focus-scope-stub [_self _opts]
  (make-drop-handle))

(fn add-render-stub [_self _opts]
  (make-drop-handle))

(fn text-batcher-from-ctx [self]
  self.text-batcher)

(fn quad-batcher-from-ctx [self]
  self.quad-batcher)

(fn make-clickables-stub []
  {:register register-clickable-stub
   :unregister unregister-clickable-stub
   :register-right-click register-clickable-stub
   :unregister-right-click unregister-clickable-stub
   :register-double-click register-clickable-stub
   :unregister-double-click unregister-clickable-stub})

(fn make-render-ctx []
  (local render-events [])
  (local text-batcher (make-text-batcher-stub render-events))
  (local quad-batcher (make-quad-batcher-stub render-events))
  {:triangle-vector {:add add-render-stub}
   :points (make-points-stub render-events)
   :clickables (make-clickables-stub)
   :focus {:create-scope create-focus-scope-stub}
   :layout-root (LayoutRoot {:log-dirt? false})
   :icons (make-icons-stub)
   :hoverables (make-hoverables-stub)
   :theme {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)}
           :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}
           :font (make-test-font)
           :text {:foreground (glm.vec4 0.8 0.8 0.8 1) :scale 1.0}}
   :render-events render-events
   :text-batcher text-batcher
   :quad-batcher quad-batcher
   :get-text-ssbo-batcher text-batcher-from-ctx
   :get-rectangle-quad-batcher quad-batcher-from-ctx})

(fn preview-measurer [self]
  (set self.measure (glm.vec3 24 12 0)))

(fn preview-layouter [_self]
  nil)

(fn preview-drop [widget]
  (set widget.state.dropped? true)
  (widget.layout:drop))

(fn build-preview-widget [node state]
  (set state.built-node node)
  (local layout (Layout {:name "outline-row-preview"
                         :measurer preview-measurer
                         :layouter preview-layouter}))
  {:layout layout
   :state state
   :drop preview-drop})

(fn preview-builder [node state]
  (fn [_ctx]
    (build-preview-widget node state)))

(fn preview-for-node [node _opts]
  (preview-builder node {}))

(fn tracked-preview [_state]
  preview-for-node)

(fn test-key-loader [key]
  (Graph.GraphNode {:key key
                    :label key
                    :size 8
                    :color (glm.vec4 0.25 0.5 0.75 1)
                    :preview (tracked-preview {})}))

(fn register-test-loader [graph]
  (graph:register-key-loader "test" test-key-loader)
  graph)

(fn make-map []
  (local graph (register-test-loader (Graph {:with-start false})))
  (local graph-map (GraphMap.GraphMap {:graph graph :id "outline-row-test" :name "Outline Row Test"}))
  {:graph graph :graph-map graph-map})

(fn add-edge! [graph-map source-key target-key]
  (local source (if (graph-map:lookup source-key)
                    (graph-map:lookup source-key)
                    (graph-map:load-by-key source-key)))
  (local target (if (graph-map:lookup target-key)
                    (graph-map:lookup target-key)
                    (graph-map:load-by-key target-key)))
  (assert source (.. "missing source " source-key))
  (assert target (.. "missing target " target-key))
  (graph-map:add-edge (Edge.GraphEdge {:source source :target target})))

(fn outline-row-false? [_row _owner]
  false)

(fn make-outline-row-node [key]
  (Graph.GraphNode {:key key
                    :label key
                    :size 8
                    :color (glm.vec4 0.25 0.5 0.75 1)
                    :preview (tracked-preview {})}))

(fn make-outline-row [key]
  {:key key
   :node (make-outline-row-node key)
   :depth 1
   :index 1
   :expanded? false
   :has-children? false})

(fn outline-row-add-selectables [events self selectables]
  (each [_ selectable (ipairs selectables)]
    (table.insert self.selectables selectable)
    (table.insert events {:kind :selector-add :selectable selectable})))

(fn outline-row-remove-selectables [events self selectables]
  (each [_ selectable (ipairs selectables)]
    (table.insert events {:kind :selector-remove :selectable selectable})
    (for [idx (length self.selectables) 1 -1]
      (when (= (. self.selectables idx) selectable)
        (table.remove self.selectables idx)))))

(fn outline-row-replace-selectable [events self previous next]
  (table.insert events {:kind :selector-replace :previous previous :next next})
  (for [idx 1 (length self.selectables)]
    (when (= (. self.selectables idx) previous)
      (set (. self.selectables idx) next))))

(fn make-outline-row-selector-stub [events]
  {:selectables []
   :selected []
   :add-selectables (fn [self selectables]
                      (outline-row-add-selectables events self selectables))
   :remove-selectables (fn [self selectables]
                         (outline-row-remove-selectables events self selectables))
   :replace-selectable (fn [self previous next]
                         (outline-row-replace-selectable events self previous next))})

(fn outline-row-focus-request [events self request]
  (set self.last-request request)
  (table.insert events {:kind :focus-request :request request}))

(fn outline-row-focus-drop [events self]
  (assert (not self.dropped?) "test focus node dropped twice")
  (set self.dropped? true)
  (table.insert events {:kind :focus-drop}))

(fn outline-row-create-focus-node [events opts]
  (local focus-node {:name opts.name :dropped? false})
  (set focus-node.request-focus
       (fn [self request]
         (outline-row-focus-request events self request)))
  (set focus-node.drop
       (fn [self]
         (outline-row-focus-drop events self)))
  focus-node)

(fn make-outline-row-focus-stub [events]
  {:create-node (fn [_self opts]
                  (outline-row-create-focus-node events opts))
   :attach-bounds (fn [_self node opts]
                    (set node.get-bounds opts.get-bounds))})

(fn value-or [value fallback]
  (if (= value nil) fallback value))

(local row-state {:selected? false :focused? false})

(fn row-state-selected? [_row _owner]
  row-state.selected?)

(fn row-state-focused? [_row _owner]
  row-state.focused?)

(fn make-outline-row-widget [overrides]
  (local opts (value-or overrides {}))
  (local ctx (value-or opts.ctx (make-render-ctx)))
  (local events (value-or opts.events []))
  (local row (value-or opts.row (make-outline-row "test:row")))
  (local selector (value-or opts.selector (make-outline-row-selector-stub events)))
  (local focus (value-or opts.focus (make-outline-row-focus-stub events)))
  (local widget ((OutlineRowWidget {:ctx ctx
                                    :row row
                                    :clickables (value-or opts.clickables ctx.clickables)
                                    :selector selector
                                    :focus focus
                                    :pointer-target (value-or opts.pointer-target {})
                                    :depth-indent 18
                                    :left-padding 12
                                    :label-gap 1
                                    :vertical-padding 1
                                    :expanded-gap 3
                                    :label-scale opts.label-scale
                                    :selected? (value-or opts.selected? outline-row-false?)
                                    :focused? (value-or opts.focused? outline-row-false?)
                                    :on-focus opts.on-focus
                                    :on-right-click opts.on-right-click
                                    :on-activate opts.on-activate
                                    :on-collapse opts.on-collapse
                                    :on-open opts.on-open
                                    :on-menu opts.on-menu}) ctx))
  {:widget widget :ctx ctx :events events :row row :selector selector :focus focus})

(fn layout-widget! [widget]
  (widget.layout:measurer)
  (set widget.layout.position (glm.vec3 0 (- widget.layout.measure.y) 0))
  (set widget.layout.size (glm.vec3 widget.layout.measure.x widget.layout.measure.y 0))
  (widget.layout:layouter)
  widget)

(fn outline-row-marker-measurement-is-stable-across-focus-and-selection []
  (set row-state.selected? false)
  (set row-state.focused? false)
  (local {:widget widget} (make-outline-row-widget {:label-scale 0.5
                                                    :selected? row-state-selected?
                                                    :focused? row-state-focused?}))
  (layout-widget! widget)
  (local initial-height widget.layout.measure.y)
  (local initial-label-x widget.label.layout.position.x)
  (local initial-label-y widget.label.layout.position.y)
  (local initial-point-y widget.point.position.y)
  (set row-state.selected? true)
  (set row-state.focused? true)
  (widget:refresh)
  (layout-widget! widget)
  (assert (approx widget.layout.measure.y initial-height)
          "outline row height should not change when selection/focus rings appear")
  (assert (approx widget.label.layout.position.x initial-label-x)
           "outline label x should not move when selection/focus rings appear")
  (assert (approx widget.label.layout.position.y initial-label-y)
          "outline label y should not move when selection/focus rings appear")
  (assert (approx widget.point.position.y initial-point-y)
          "outline point y should not move when selection/focus rings appear")
  (assert (> (. widget.point.layers 1 :size) 0)
          "focus layer should become visible")
  (assert (> (. widget.point.layers 2 :size) 0)
          "selection layer should become visible")
  (widget:drop))

(fn outline-row-centers-short-label-within-marker-lane []
  (local {:widget widget} (make-outline-row-widget {:label-scale 0.5}))
  (layout-widget! widget)
  (assert widget.marker-box "outline row should expose marker-box")
  (widget.marker-box.layout:measurer)
  (widget.label.layout:measurer)
  (local marker-center-y (+ widget.marker-box.layout.position.y
                            (/ widget.marker-box.layout.size.y 2.0)))
  (local label-center-y (+ widget.label.layout.position.y
                           (/ widget.label.layout.measure.y 2.0)))
  (assert (approx label-center-y marker-center-y)
          "short outline label should be vertically centered in the marker lane")
  (widget:drop))

(fn outline-row-tall-label-remains-top-aligned []
  (local {:widget widget} (make-outline-row-widget {:label-scale 2.0}))
  (layout-widget! widget)
  (assert widget.marker-box "outline row should expose marker-box")
  (widget.marker-box.layout:measurer)
  (widget.label.layout:measurer)
  (local summary-top (+ widget.layout.position.y widget.layout.size.y))
  (local expected-top (- summary-top 1))
  (assert (approx (+ widget.marker-box.layout.position.y widget.marker-box.layout.size.y) expected-top)
          "marker box top should match summary content top")
  (assert (approx (+ widget.label.layout.position.y widget.label.layout.measure.y) expected-top)
          "tall label top should match summary content top")
  (assert (approx widget.layout.measure.y (+ widget.label.layout.measure.y 2))
          "tall label should grow row height instead of being clipped by marker lane")
  (assert (approx widget.point.position.y (+ widget.marker-box.layout.position.y (/ widget.marker-box.layout.size.y 2.0)))
          "point center should come from marker box center, not full label height")
  (widget:drop))

(fn view-record-for-key [view key]
  (var found nil)
  (each [_ record (ipairs (or view.row-handles [])) &until found]
    (when (and record record.row (= record.row.key key))
      (set found record)))
  (assert found (.. "missing outline record for " key)))

(fn outline-focus-and-selection-do-not-move-descendant-row-points []
  (local {:graph graph :graph-map graph-map} (make-map))
  (add-edge! graph-map "test:root" "test:child")
  (graph-map:set-view-mode! "outline")
  (graph-map:set-outline-root-keys! ["test:root"])
  (local view (GraphView {:graph-map graph-map
                          :ctx (make-render-ctx)
                          :outline-text-scale 0.5}))
  (local child-record (view-record-for-key view "test:child"))
  (local initial-y child-record.point.position.y)
  (view:reveal-node "test:root" {:select? true :focus? true})
  (local next-child-record (view-record-for-key view "test:child"))
  (assert (approx next-child-record.point.position.y initial-y)
          "selection/focus rings on an ancestor should not move descendant row points")
  (view:drop)
  (graph-map:drop)
  (graph:drop))

(fn count-events [events kind]
  (accumulate [count 0 _ event (ipairs events)]
    (if (= event.kind kind) (+ count 1) count)))

(fn outline-row-keeps-marker-box-point-across-expand-and-collapse []
  (local events [])
  (local {:widget widget :selector selector} (make-outline-row-widget {:events events}))
  (assert widget.marker-box "outline row should expose marker-box")
  (local initial-point widget.point)
  (local marker-point widget.marker-box.point)
  (assert (= initial-point marker-point)
          "widget point should be the marker box point")
  (widget:expand!)
  (assert (= widget.marker-box.point marker-point)
          "expand should keep marker box point alive")
  (widget:collapse!)
  (assert (= widget.marker-box.point marker-point)
          "collapse should reuse marker box point")
  (assert (= widget.point marker-point)
          "compact projection should reattach to marker box point")
  (assert (= (type widget.point.on-click) :function)
          "compact click handler should be restored after collapse")
  (assert (= (. selector.selectables 1) widget.selectable)
          "selector should own current compact selectable after collapse")
  (assert (= widget.focus-node.presentation widget.point)
          "focus node should target compact point after collapse")
  (assert (= (count-events events :focus-drop) 0)
          "expand/collapse should not drop shared focus node")
  (widget:drop))

(fn outline-expanded-row-refreshes-marker-focus-and-selection []
  (set row-state.selected? false)
  (set row-state.focused? false)
  (local {:widget widget} (make-outline-row-widget {:selected? row-state-selected?
                                                    :focused? row-state-focused?}))
  (local marker-point widget.marker-box.point)
  (widget:expand!)
  (assert (= widget.marker-box.point marker-point)
          "expanded row should keep marker point visible")
  (assert (= (. marker-point.layers 1 :size) 0)
          "expanded marker focus layer should start hidden")
  (assert (= (. marker-point.layers 2 :size) 0)
          "expanded marker selection layer should start hidden")
  (set row-state.selected? true)
  (set row-state.focused? true)
  (widget:refresh)
  (assert (> (. marker-point.layers 1 :size) 0)
          "expanded marker focus layer should refresh while compact projection is detached")
  (assert (> (. marker-point.layers 2 :size) 0)
          "expanded marker selection layer should refresh while compact projection is detached")
  (widget:drop))

(table.insert tests {:name "outline row marker measurement is stable across focus and selection"
                     :fn outline-row-marker-measurement-is-stable-across-focus-and-selection})
(table.insert tests {:name "outline row centers short label within marker lane"
                     :fn outline-row-centers-short-label-within-marker-lane})
(table.insert tests {:name "outline row tall label remains top aligned"
                     :fn outline-row-tall-label-remains-top-aligned})
(table.insert tests {:name "outline focus and selection do not move descendant row points"
                     :fn outline-focus-and-selection-do-not-move-descendant-row-points})
(table.insert tests {:name "outline row keeps marker box point across expand and collapse"
                     :fn outline-row-keeps-marker-box-point-across-expand-and-collapse})
(table.insert tests {:name "outline expanded row refreshes marker focus and selection"
                     :fn outline-expanded-row-refreshes-marker-focus-and-selection})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-outline-row-widget"
                       :tests tests})))

{:name "graph-outline-row-widget"
 :tests tests
 :main main}
