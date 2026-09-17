(local fs (require :fs))
(local Graph (require :graph/core))
(local GraphMap (require :graph/map))
(local GraphView (require :graph/view/init))
(local LinkEntityStore (require :entities/link))
(local BuildContext (require :build-context))
(local glm (require :glm))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "link-entity-crash"))

(fn allow-test-keys! [graph]
  (local original-has-key-loader graph.has-key-loader-for-key)
  (set graph.has-key-loader-for-key
       (fn [self key]
         (if (and original-has-key-loader (original-has-key-loader self key))
             true
             (if key true false))))
  graph)

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "crash-" (os.time) "-" temp-counter)))

(fn with-temp-env [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
  (local graph (allow-test-keys! (Graph {:with-start false :link-store store})))
  (local graph-map (GraphMap.GraphMap {:graph graph :id "link-entity-crash"}))
  ;; Use a real build context so vector buffers and handles are real usertypes.
  ;; We keep focus/clickables lightweight because the crash repro is about edge creation.
  (local clickables {:register (fn []) :register-double-click (fn [])
                     :unregister (fn []) :unregister-double-click (fn [])})
  (local focus-manager {:create-scope (fn [_self _opts] {})
                        :attach (fn [_self] nil)
                        :create-node (fn [_self _opts] {})
                        :focus-focus {:connect (fn [_sig _cb] nil)}
                        :focus-blur {:connect (fn [_sig _cb] nil)}
                        :get-focused-node (fn [_self] nil)
                        :arm-auto-focus (fn [_self _opts] nil)
                        :clear-auto-focus (fn [_self] nil)})
  (local focus {:manager focus-manager
                :create-scope (fn [_self _opts] {:attach-bounds (fn [_scope _spec] nil)
                                                :drop (fn [_scope] nil)})
                :create-node (fn [_self _opts] {:request-focus (fn [_node] nil)
                                               :drop (fn [_node] nil)})
                :attach-bounds (fn [_self _node _spec] nil)})
  (local theme {:graph {:selection-border-color (glm.vec4 1 0 0 1)
                        :label-color (glm.vec4 1 1 1 1)
                        :edge-color (glm.vec4 0.5 0.5 0.5 1)}
                :input {:focus-outline (glm.vec4 0 1 0 1)}})
  (local ctx (BuildContext {:clickables clickables
                            :theme theme}))
  (set ctx.width 100)
  (set ctx.height 100)
  (set ctx.units-per-pixel 1)
  (set ctx.focus focus)
  (local view (GraphView {:graph-map graph-map :ctx ctx :data-dir dir}))
  
  (local (ok result) (pcall f store graph-map view))
  (view:drop)
  (graph-map:drop)
  (graph:drop)
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(local tests [])

(fn test-graph-view-crash-reproduction []
  (with-temp-env
    (fn [store graph view]
      ;; 1. Create a link entity connecting "A" and "B"
      (store:create-entity {:source-key "A" :target-key "B"})
      
      ;; 2. Add node "A" to the graph
      (local node-a (Graph.GraphNode {:key "A" :label "A"}))
      (graph:add-node node-a)
      
      ;; 3. Add node "B" to the graph - this triggers link edge creation synchronously
      ;; The robust view should handle this without crashing / throwing error
      (local node-b (Graph.GraphNode {:key "B" :label "B"}))
      (graph:add-node node-b)
      
      ;; Verify edge exists in the MODEL immediately because we reverted the deferral
      (assert (= (graph:edge-count) 1) "Edge should be created immediately")
      
      ;; Verify the view has processed checking pending edges
      ;; Force a view update cycle to trigger pending edge processing (though our implementation does it on node-added)
      (view:update 0.016)
      
      ;; We don't have easy introspection into view internals here without mocking, 
      ;; but if it didn't crash, that's the primary success criteria.
  )))

(table.insert tests {:name "test-graph-view-crash-reproduction"
                     :fn test-graph-view-crash-reproduction})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "link-entity-crash" :tests tests})))

{:name "link-entity-crash"
 :tests tests
 :main main}
