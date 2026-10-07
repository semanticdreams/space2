(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphView (require :graph/view))
(local BuildContext (require :build-context))
(local {: Layout : LayoutRoot} (require :layout))
(local {:FocusManager FocusManager} (require :focus))
(var fixture-counter 0)

(fn make-icons-stub []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}})
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
         {:type :font
          :codepoint (self:get name)
          :font self.font}))
  stub)

(fn make-ctx []
  (local focus-manager (FocusManager {:root-name "test-graph-preview-focus"}))
  (local focus-scope (focus-manager:create-scope {:name "graph-view-preview-focus"}))
  (local ctx (BuildContext {:layout-root (LayoutRoot {:log-dirt? false})
                            :clickables (assert app.clickables "test requires app.clickables")
                            :hoverables (assert app.hoverables "test requires app.hoverables")
                            :theme {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
                                            :label-color (glm.vec4 1 1 1 1)
                                            :label-target-pixels 13.0
                                            :label-min-scale 4.0
                                            :edge-color (glm.vec4 0.6 0.6 0.6 1)}
                                    :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}}
                            :focus-manager focus-manager
                            :focus-scope focus-scope}))
  (set ctx.icons (make-icons-stub))
  ctx)

(fn make-test-graph-map []
  (local graph (Graph {:with-start false}))
  (local original-has-key-loader graph.has-key-loader-for-key)
  (set graph.has-key-loader-for-key
       (fn [self key]
         (if (and original-has-key-loader (original-has-key-loader self key))
             true
             (if key true false))))
  (GraphMap.GraphMap {:graph graph :id "preview-focus"}))

(fn preview-widget [state node preview-ctx]
  (set state.built-node node)
  (local child (preview-ctx.focus:create-node {:name "preview-child"}))
  (local nested-scope (preview-ctx.focus:create-scope {:name "preview-nested-scope"}))
  (local nested-child (preview-ctx.focus:create-node {:name "preview-nested-child"
                                                     :parent nested-scope}))
  (set state.focus-child child)
  (set state.nested-scope nested-scope)
  (set state.nested-child nested-child)
  (local layout (Layout {:name "focus-child-preview"}))
  {:node node
   :layout layout
   :drop (fn [_self]
            (set state.dropped? true)
            (layout:drop)
            (child:drop))})

(fn focusables-contains? [manager node]
  (var found false)
  (each [_ focusable (ipairs manager.focusables)]
    (when (= focusable node)
      (set found true)))
  found)

(fn focus-child-preview [state]
  (fn [node _opts]
    (fn [preview-ctx]
      (preview-widget state node preview-ctx))))

(fn make-fixture []
  (set fixture-counter (+ fixture-counter 1))
  (local ctx (make-ctx))
  (local graph-map (make-test-graph-map))
  (local state {})
  (local node (Graph.GraphNode {:key "focus-preview-node"
                                :preview (focus-child-preview state)}))
  (local view (GraphView {:graph-map graph-map
                          :ctx ctx
                          :data-dir (.. "/tmp/space/tests/graph-view-preview-focus-" (os.time) "-" fixture-counter)}))
  (graph-map:add-node node {:position (glm.vec3 0 0 0)})
  (local point (. view.points node))
  (point:on-double-click {})
  {:ctx ctx :graph-map graph-map :view view :node node :state state :shell (. view.focus-nodes node)})

(fn drop-fixture [fixture]
  (when fixture
    (when fixture.view
      (fixture.view:drop))
    (when fixture.graph-map
      (fixture.graph-map:drop))))

(fn expanded-preview-children-attach-to-node-preview-scope []
  (local fixture (make-fixture))
  (local view fixture.view)
  (local shell fixture.shell)
  (local child fixture.state.focus-child)
  (local preview-scope shell.entry-scope)
  (assert preview-scope "Expanded graph node focus shell should expose a preview entry scope")
  (assert (= preview-scope.exit-node shell)
          "Preview entry scope should exit back to the graph node shell")
  (assert (= child.parent preview-scope)
          "Preview child focus nodes should attach to the node preview scope")
  (assert (= (. view.node-by-focus child) nil)
          "Preview child focus nodes must not map to graph nodes")
  (drop-fixture fixture))

(fn graph-node-commands-require-shell-focus-when-preview-child-focused []
  (local fixture (make-fixture))
  (local ctx fixture.ctx)
  (local view fixture.view)
  (local shell fixture.shell)
  (shell:request-focus)
  (assert (view:has-focused-node?)
          "Graph node commands should be available while the shell focus node is focused")
  (local child (ctx.focus.manager:focus-into {}))
  (assert (= child fixture.state.focus-child)
          "Focus into should move from graph shell to preview child")
  (assert (not (view:has-focused-node?))
          "Graph node commands should be unavailable while preview child is focused")
  (drop-fixture fixture))

(fn collapse-clears-preview-focus-descendants []
  (local fixture (make-fixture))
  (local ctx fixture.ctx)
  (local shell fixture.shell)
  (local child fixture.state.nested-child)
  (local nested-scope fixture.state.nested-scope)
  (shell:request-focus)
  (child:request-focus)
  (assert (= (ctx.focus.manager:get-focused-node) child)
          "Fixture should focus nested preview child before collapse")
  (local card (. fixture.view.points fixture.node))
  (local collapse-button (. card.header-bar.children 3 :element))
  (collapse-button:on-click {})
  (assert fixture.state.dropped?
          "Collapsing expanded preview should drop the preview widget")
  (assert (= child.parent nil)
          "Collapsing expanded preview should detach stale nested preview focus children")
  (assert (= nested-scope.parent nil)
          "Collapsing expanded preview should detach stale nested preview scopes")
  (assert (not (focusables-contains? ctx.focus.manager child))
          "Collapsing expanded preview should unregister stale nested preview focus children")
  (assert (not (= (ctx.focus.manager:get-focused-node) child))
          "Stale nested preview child focus should not remain current after collapse")
  (assert (= shell.entry-scope.exit-node shell)
          "Collapsing preview should leave shell entry scope linked for future expansions")
  (drop-fixture fixture))

(local tests [{:name "GraphView expanded preview children attach to node preview scope"
               :fn expanded-preview-children-attach-to-node-preview-scope}
              {:name "GraphView graph node commands require shell focus when preview child focused"
               :fn graph-node-commands-require-shell-focus-when-preview-child-focused}
              {:name "GraphView collapse clears preview focus descendants"
               :fn collapse-clears-preview-focus-descendants}])

(fn append-tests [target]
  (each [_ entry (ipairs tests)]
    (table.insert target entry))
  target)

{:tests tests
 :append-tests append-tests}
