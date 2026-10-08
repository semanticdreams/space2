(local glm (require :glm))
(local fs (require :fs))
(local Main (require :main))
(local Activities (require :activities))
(local Graph (require :graph/init))
(local GraphMapManager (require :graph/map-manager))
(local Scene (require :scene))
(local Canvas (require :canvas))
(local Camera (require :camera))
(local ObjectSelector (require :object-selector))
(local GraphActivityUnit (require :graph-activity-unit))
(local {: FocusManager} (require :focus))

(local tests [])

(local CTRL-MOD 64)
(local KEY_A (string.byte "a"))

(fn restore-app-fields! [snapshot]
  (each [_ key (ipairs snapshot.keys)]
    (set (. app key) (. snapshot.values key)))
  true)

(fn snapshot-app-fields [keys]
  (local snapshot {:keys keys
                   :values {}})
  (each [_ key (ipairs keys)]
    (set (. snapshot.values key) (. app key)))
  snapshot)

(fn make-font-stub []
  (local glyph {:advance 1})
  {:metadata {:metrics {:ascender 1 :descender -0.25 :lineHeight 1.25}
              :atlas {:width 1 :height 1}}
   :glyph-map {65533 glyph}})

(fn test-theme []
  {:font (make-font-stub)
   :graph {:background (glm.vec4 0.18 0.19 0.21 1)
           :selection-border-color (glm.vec4 1 0.6 0.2 1)
           :label-color (glm.vec4 1 1 1 1)
           :label-target-pixels 13.0
           :label-min-scale 4.0
           :edge-color (glm.vec4 0.6 0.6 0.6 1)}
   :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}})

(fn selector-context [canvas]
  (if (and canvas.active-activity-slot canvas.active-activity-slot.ctx)
      canvas.active-activity-slot.ctx
      canvas.build-context))

(fn make-selector-ctx-provider [canvas]
  (fn []
    (selector-context canvas)))

(fn no-active-input [] nil)

(fn text-active-input [] {:id "text-input"})

(fn make-activity-runtime [data-dir]
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "graph-activity-input-test"}))
  (local canvas (Canvas {:camera camera
                         :focus-manager focus-manager}))
  (local scene (Scene {:camera camera}))
  (local graph (Graph {:with-start false}))
  (local original-has-key-loader graph.has-key-loader-for-key)
  (set graph.has-key-loader-for-key
       (fn [self key]
         (if (and original-has-key-loader (original-has-key-loader self key))
             true
             (if key true false))))
  (local graph-map-manager (GraphMapManager.GraphMapManager {:graph graph}))
  (local graph-map (graph-map-manager:get-active-map))
  (local object-selector (ObjectSelector {:ctx-provider (make-selector-ctx-provider canvas)
                                          :enabled? true}))
  {:camera camera
   :focus-manager focus-manager
   :canvas canvas
   :scene scene
   :graph graph
   :graph-map graph-map
   :graph-map-manager graph-map-manager
   :object-selector object-selector
   :runtime {:canvas canvas
             :scene scene
             :graph graph
             :graph-map graph-map
             :graph-map-manager graph-map-manager
             :object-selector object-selector
             :movables app.movables
             :activity-cameras {:canvas {} :scene {}}
             :activity-controls {:canvas {} :scene {}}
             :world-dir data-dir}})

(fn drop-activity-runtime! [fixture]
  (pcall GraphActivityUnit.unload-graph-activity!)
  (when (and fixture.runtime fixture.runtime.graph-view)
    (fixture.runtime.graph-view:drop)
    (set fixture.runtime.graph-view nil))
  (fixture.object-selector:drop)
  (fixture.graph-map-manager:drop)
  (fixture.graph:drop)
  (fixture.scene:drop)
  (fixture.canvas:drop)
  (fixture.focus-manager:drop)
  (fixture.camera:drop))

(fn selection-contains? [nodes node]
  (var found? false)
  (each [_ selected (ipairs nodes)]
    (when (= selected node)
      (set found? true)))
  found?)

(fn assert-graph-activity-ctrl-a-behavior [fixture]
  (GraphActivityUnit.load-graph-activity!)
  (Activities.activate-activity "graph")
  (set app.canvas-interactive? true)
  (local handler (assert (and app.activity-input-handlers
                              app.activity-input-handlers.key-down)
                         "Graph activity should install a key-down input handler"))
  (local ctx {:active-input no-active-input})
  (assert (= (handler ctx {:key KEY_A :mod CTRL-MOD}) false)
          "Ctrl+A on an empty graph should no-op")
  (local a (Graph.GraphNode {:key "a"}))
  (local b (Graph.GraphNode {:key "b"}))
  (fixture.graph-map:add-node a {:position (glm.vec3 0 0 0)})
  (fixture.graph-map:add-node b {:position (glm.vec3 10 0 0)})
  (assert (= (handler ctx {:key KEY_A :mod 0}) false)
          "Plain A should not run graph select-all")
  (assert (= (handler ctx {:key KEY_A :mod CTRL-MOD}) true)
          "Ctrl+A should select visible graph nodes")
  (assert (= (length app.graph-view.selected-nodes) 2)
          "Ctrl+A should select both materialized graph nodes")
  (assert (selection-contains? app.graph-view.selected-nodes a)
          "Ctrl+A selection should include node a")
  (assert (selection-contains? app.graph-view.selected-nodes b)
          "Ctrl+A selection should include node b")
  (assert (= (length fixture.graph-map.selected_node_keys) 2)
          "Ctrl+A should sync GraphMap selected keys")
  (assert (not (fixture.graph-map:lookup "lazy-only"))
          "Ctrl+A should not materialize lazy-loadable nodes")
  (app.graph-view:clear-selection)
  (local active-input-ctx {:active-input text-active-input})
  (assert (= (handler active-input-ctx {:key KEY_A :mod CTRL-MOD}) false)
          "Ctrl+A should not run while a text input owns focus")
  (assert (= (length app.graph-view.selected-nodes) 0)
          "Active-input Ctrl+A should leave graph selection unchanged")
  true)

(fn graph-activity-ctrl-a-selects-materialized-nodes []
  (local app-keys [:active-world-runtime
                   :canvas
                   :graph-map
                   :graph-map-manager
                   :graph-view
                   :activity-input-handlers
                   :activity-registry
                   :activities-changed
                   :active-activity-id
                   :active-interaction-surface
                   :preferred-interaction-surface
                   :active-pointer-controls
                   :scene-interactive?
                   :canvas-interactive?
                   :canvas-surface-interactive?
                   :canvas-visible?
                   :canvas-controls
                   :first-person-controls
                   :viewport
                   :themes])
  (local app-snapshot (snapshot-app-fields app-keys))
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (set app.active-activity-id nil)
  (set app.themes {:get-active-theme test-theme})
  (local data-dir "/tmp/space/tests/graph-activity-input")
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (fs.create-dirs data-dir)
  (local AppProjection (require :app-projection))
  (when (not app.create-default-projection)
    (set app.create-default-projection AppProjection.create-default-projection))
  (local fixture (make-activity-runtime data-dir))
  (set app.active-world-runtime fixture.runtime)
  (set app.canvas fixture.canvas)
  (set app.graph-map fixture.graph-map)
  (set app.graph-map-manager fixture.graph-map-manager)
  (local (ok result) (pcall assert-graph-activity-ctrl-a-behavior fixture))
  (drop-activity-runtime! fixture)
  (restore-app-fields! app-snapshot)
  (when (fs.exists data-dir)
    (fs.remove-all data-dir))
  (if ok result (error result)))

(table.insert tests {:name "Graph activity Ctrl+A selects materialized graph nodes"
                     :fn graph-activity-ctrl-a-selects-materialized-nodes})

(fn main []
  (table.insert tests 1 {:name "Graph activity input suppresses selection info logs"
                         :fn (fn []
                               (assert ((. (require :logging) :set-level) "warn")
                                       "graph activity input test requires logging level control"))})
  ((. (require :tests/runner) :run-tests) {:name "graph-activity-input" :tests tests}))

{:name "graph-activity-input" :tests tests :main main}
