(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphView (require :graph/view))
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

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-view-compact-projection" :tests tests})))

{:name "graph-view-compact-projection" :tests tests :main main}
