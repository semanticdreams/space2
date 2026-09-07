(local Graph (require :graph/init))
(local GraphMapModule (require :graph/map))
(local KindBadge (require :graph/kind-badge))
(local glm (require :glm))

(local GraphMap GraphMapModule.GraphMap)
(local tests [])

(fn approx [a b]
  (< (math.abs (- a b)) 1e-5))

(fn color= [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)
       (approx a.w b.w)))

(fn normalize-derives-uppercase-scheme []
  (local badge (KindBadge.normalize {:key "fs:/tmp/a.txt"
                                     :color (glm.vec4 0.3 0.6 1 1)}))
  (assert badge "scheme-bearing keys should derive a default badge")
  (assert (= badge.text "FS"))
  (assert (color= badge.background-color (glm.vec4 0.3 0.6 1 1))))

(fn normalize-no-scheme-is-nil []
  (assert (= (KindBadge.normalize {:key "start"}) nil)
          "keys without ':' should not derive badges"))

(fn normalize-explicit-false-opts-out []
  (assert (= (KindBadge.normalize {:key "fs:/tmp/a.txt" :value false}) false)
          "explicit false should suppress derived badges"))

(fn normalize-explicit-text-trims-without-changing-case []
  (local badge (KindBadge.normalize {:key "fs:/tmp/a.txt"
                                     :value {:text " File "
                                             :foreground-color (glm.vec4 1 1 0 1)}}))
  (assert (= badge.text "File"))
  (assert (color= badge.foreground-color (glm.vec4 1 1 0 1))))

(fn malformed-explicit-badge-fails-loudly []
  (each [_ value (ipairs [true {} {:text ""} {:text "  "}])]
    (local (ok err)
      (pcall (fn [] (KindBadge.normalize {:key "fs:/tmp/a.txt" :value value}))))
    (assert (not ok) "malformed explicit badge should fail")
    (assert (string.find (tostring err) "kind-badge" 1 true)
            (.. "expected clear kind-badge error, got " (tostring err)))))

(fn malformed-explicit-colors-fail-loudly []
  (each [_ field (ipairs [:background-color :foreground-color])]
    (each [_ color-value (ipairs [false true "red" 12 (glm.vec3 1 0 0) (glm.quat 1 0 0 0)])]
      (local metadata {:text "FS"})
      (tset metadata field color-value)
      (local (ok err)
        (pcall (fn [] (KindBadge.normalize {:key "fs:/tmp/a.txt" :value metadata}))))
      (assert (not ok) (.. "malformed explicit " field " should fail"))
      (assert (string.find (tostring err) (.. "kind-badge." field) 1 true)
              (.. "expected clear kind-badge color error, got " (tostring err))))))

(fn graph-node-stores-normalized-derived-kind-badge []
  (local node (Graph.GraphNode {:key "fs:/tmp/a.txt"
                                :label "a.txt"
                                :color (glm.vec4 0.25 0.5 0.75 1)}))
  (assert node.kind-badge "GraphNode should store normalized badge metadata")
  (assert (= node.kind-badge.text "FS")))

(fn graph-node-preserves-explicit-kind-badge-opt-out []
  (local node (Graph.GraphNode {:key "fs:/tmp/a.txt" :kind-badge false}))
  (assert (= node.kind-badge false)
          "GraphNode should preserve explicit false opt-out"))

(fn graph-map-capture-excludes-kind-badge-metadata []
  (local graph (Graph {:with-start false}))
  (graph:register-key-loader "test"
    (fn [key]
      (Graph.GraphNode {:key key :kind-badge {:text "Test"}})))
  (local graph-map (GraphMap {:graph graph :id "badge-topology"}))
  (local a (graph-map:load-by-key "test:a"))
  (local b (graph-map:load-by-key "test:b"))
  (graph-map:add-edge (Graph.GraphEdge {:source a :target b}))
  (local state (graph-map:capture-state))
  (assert (= state.kind-badge nil) "capture-state must not add top-level badge metadata")
  (assert (= (length state.nodes) 2) "capture-state should preserve node keys")
  (assert (= (. state.nodes 1) "test:a"))
  (assert (= (. state.nodes 2) "test:b"))
  (assert (= (length state.edges) 1) "capture-state should preserve edges")
  (assert (= (. state.edges 1 :kind-badge) nil) "captured edges must not include badges")
  (graph-map:drop)
  (graph:drop))

(fn stub-point-set-position [self position]
  (set self.position position))

(fn stub-point-set-position-values [self x y z]
  (set self.position (glm.vec3 x y z)))

(fn stub-point-set-color [self color]
  (set self.color color))

(fn stub-point-set-size [self size]
  (set self.size size))

(fn stub-point-set-depth-offset-index [self depth]
  (set self.depth-offset-index depth))

(fn stub-point-intersect [_self _ray]
  nil)

(fn stub-point-drop [_self]
  nil)

(fn create-stub-point [created opts]
  (local point {:opts opts
                :position opts.position
                :color opts.color
                :size opts.size
                :depth-offset-index opts.depth-offset-index
                :set-position stub-point-set-position
                :set-position-values stub-point-set-position-values
                :set-color stub-point-set-color
                :set-size stub-point-set-size
                :set-depth-offset-index stub-point-set-depth-offset-index
                :intersect stub-point-intersect
                :drop stub-point-drop})
  (table.insert created point)
  point)

(fn make-points-stub []
  (local created [])
  {:created created
   :create-point (fn [_self opts]
                   (create-stub-point created opts))})

(fn compact-point-ignores-kind-badge-metadata []
  (local GraphNodePresentation (require :graph/view/presentation))
  (local points (make-points-stub))
  (local node (Graph.GraphNode {:key "fs:/tmp/badged.txt"
                                :label "badged.txt"
                                :color (glm.vec4 0.1 0.2 0.3 1)
                                :size 11.0}))
  (local point
    (GraphNodePresentation.compact-point
      {:points points
       :position (glm.vec3 1 2 3)
       :depth-offset-step 1
       :base-depth-offset-index 2
       :base-layer-index 3
       :kind-badge node.kind-badge
       :layers [{:size 0 :color (glm.vec4 0.7 0.8 0.9 1)}
                {:size 0 :color (glm.vec4 0.4 0.5 0.6 1)}
                {:size node.size :color node.color}]}))
  (assert (= (length point.layers) 3) "compact point should keep three layers")
  (assert (= point.header-bar nil) "compact point should not gain titlebar UI")
  (assert (= point.kind-badge nil) "compact point should not copy badge metadata")
  (when point.drop (point:drop)))

(fn titlebar-builder-returns-nil-for-missing-or-opted-out-badges []
  (local ViewKindBadge (require :graph/view/kind-badge))
  (assert (= (ViewKindBadge.titlebar-builder nil) nil))
  (assert (= (ViewKindBadge.titlebar-builder false) nil)))

(fn make-icons-stub []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}
               :advance 1})
  (local stub {:font font
               :codepoints {:close_fullscreen 4242
                            :open_in_new 4242
                            :more_vert 4242
                            :table 4242
                            :code 4242
                            :close 4242}})
  (set stub.get
       (fn [self name]
         (local value (. self.codepoints name))
         (assert value (.. "Missing icon " name))
         value))
  (set stub.resolve
       (fn [self name]
         (local code (self:get name))
         {:type :font :codepoint code :font self.font}))
  stub)

(fn stub-register [_self _obj]
  nil)

(fn make-clickables-stub []
  {:register stub-register
   :unregister stub-register
   :register-right-click stub-register
   :unregister-right-click stub-register
   :register-double-click stub-register
   :unregister-double-click stub-register})

(fn make-hoverables-stub []
  {:register stub-register
   :unregister stub-register})

(fn make-ui-ctx []
  (local BuildContext (require :build-context))
  (local {: LayoutRoot} (require :layout))
  (local ctx (BuildContext {:layout-root (LayoutRoot {:log-dirt? false})
                            :clickables (make-clickables-stub)
                            :hoverables (make-hoverables-stub)}))
  (set ctx.icons (make-icons-stub))
  ctx)

(fn make-simple-widget [name]
  (local {: Layout} (require :layout))
  (fn simple-measurer [self]
    (set self.measure (glm.vec3 4 2 0)))
  (fn simple-layouter [_self]
    nil)
  (local layout
    (Layout {:name name
             :measurer simple-measurer
             :layouter simple-layouter}))
  (fn drop [_self]
    (layout:drop))
  {:layout layout :drop drop})

(fn dialog-title-prefix-builder [ctx]
  (local Text (require :text))
  (local text ((Text {:text "FS"}) ctx))
  (set text.text "FS")
  text)

(fn dialog-body-builder [_ctx]
  (make-simple-widget "body"))

(fn test-node-view-builder [_ctx _opts]
  (make-simple-widget "node-view"))

(fn test-node-view [_node]
  test-node-view-builder)

(fn dialog-title-prefix-renders-before-title []
  (local Dialog (require :dialog))
  (local dialog
    ((Dialog {:title "Node"
              :title-prefix dialog-title-prefix-builder
              :child dialog-body-builder})
     (make-ui-ctx)))
  (local titlebar-card (. dialog.children 1 :element))
  (local title-flex (. titlebar-card.children 2))
  (assert (= (. title-flex.children 1 :element :text) "FS")
          "title prefix should be before title")
  (dialog:drop))

(fn node-view-dialog-renders-kind-badge-before-title []
  (local Builder (require :graph/view/node-view-dialog-builder))
  (local node (Graph.GraphNode {:key "fs:/tmp/a.txt"
                                :label "a.txt"
                                :view test-node-view}))
  (local builder (Builder.make-dialog-builder node (node.view node) {}))
  (local dialog (builder (make-ui-ctx) {}))
  (assert dialog.title-kind-badge "node-view dialog should expose the title badge")
  (assert (= dialog.title-kind-badge-text "FS"))
  (dialog:drop))

(fn noop []
  nil)

(fn noop-event [_event]
  nil)

(fn tracked-preview []
  (fn [_node _opts]
    (fn [_ctx]
      (make-simple-widget "graph-kind-badge-preview"))))

(fn build-test-card [GraphNodePresentation node]
  (set node.preview (tracked-preview))
  ((GraphNodePresentation.card-builder
     {:node node
      :position (glm.vec3 0 0 0)
      :default-size (glm.vec3 32 18 0)
      :on-collapse noop
      :on-open noop-event
      :on-menu noop-event})
   (make-ui-ctx)))

(fn expanded-card-renders-kind-badge-before-title []
  (local GraphNodePresentation (require :graph/view/presentation))
  (local node (Graph.GraphNode {:key "fs:/tmp/a.txt" :label "a.txt"}))
  (local card (build-test-card GraphNodePresentation node))
  (assert card.header-kind-badge "badged card should expose header-kind-badge")
  (assert (= (. card.header-bar.children 1 :element) card.header-kind-badge)
          "badge should be first header child")
  (assert (= (. card.header-bar.children 2 :element) card.header-title)
          "title should immediately follow badge")
  (assert (= card.header-title-text "a.txt"))
  (card:drop))

(fn expanded-card-without-badge-keeps-existing-titlebar-structure []
  (local GraphNodePresentation (require :graph/view/presentation))
  (local node (Graph.GraphNode {:key "start" :label "Start"}))
  (local card (build-test-card GraphNodePresentation node))
  (assert (= node.kind-badge nil))
  (assert (= card.header-kind-badge nil))
  (assert (= (. card.header-bar.children 1 :element) card.header-title)
          "title should remain first header child without badge")
  (card:drop))

(table.insert tests {:name "KindBadge derives uppercase scheme text"
                     :fn normalize-derives-uppercase-scheme})
(table.insert tests {:name "KindBadge omits badge for keys without scheme"
                     :fn normalize-no-scheme-is-nil})
(table.insert tests {:name "KindBadge explicit false opts out"
                     :fn normalize-explicit-false-opts-out})
(table.insert tests {:name "KindBadge explicit text trims without changing case"
                     :fn normalize-explicit-text-trims-without-changing-case})
(table.insert tests {:name "KindBadge malformed explicit metadata fails loudly"
                     :fn malformed-explicit-badge-fails-loudly})
(table.insert tests {:name "KindBadge malformed explicit colors fail loudly"
                     :fn malformed-explicit-colors-fail-loudly})
(table.insert tests {:name "GraphNode stores normalized derived kind-badge metadata"
                     :fn graph-node-stores-normalized-derived-kind-badge})
(table.insert tests {:name "GraphNode preserves explicit kind-badge opt-out"
                     :fn graph-node-preserves-explicit-kind-badge-opt-out})
(table.insert tests {:name "GraphMap capture excludes kind-badge metadata"
                     :fn graph-map-capture-excludes-kind-badge-metadata})
(table.insert tests {:name "Compact point ignores kind-badge metadata"
                      :fn compact-point-ignores-kind-badge-metadata})
(table.insert tests {:name "Graph view kind badge builder omits missing badges"
                     :fn titlebar-builder-returns-nil-for-missing-or-opted-out-badges})
(table.insert tests {:name "Expanded card renders kind badge before title"
                     :fn expanded-card-renders-kind-badge-before-title})
(table.insert tests {:name "Expanded card without badge keeps existing titlebar structure"
                      :fn expanded-card-without-badge-keeps-existing-titlebar-structure})
(table.insert tests {:name "Dialog title prefix renders before title"
                     :fn dialog-title-prefix-renders-before-title})
(table.insert tests {:name "Node view dialog renders kind badge before title"
                     :fn node-view-dialog-renders-kind-badge-before-title})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "graph-kind-badge" :tests tests}))

{:name "graph-kind-badge" :tests tests :main main}
