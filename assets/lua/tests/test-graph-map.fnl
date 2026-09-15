(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local glm (require :glm))
(local fs (require :fs))

(local tests [])

(fn register-test-loader [graph]
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    graph)

(fn graph-map-adds-and-looks-up-nodes []
    (local graph (Graph {:with-start false}))
    (register-test-loader graph)
    (local map (GraphMap.GraphMap {:graph graph :id "test-1" :name "Test 1"}))
    (local a (Graph.GraphNode {:key "test:a"}))
    (local b (Graph.GraphNode {:key "test:b"}))
    (map:add-node a {})
    (map:add-node b {})
    (assert (= (map:node-count) 2) "GraphMap should track node count")
    (assert (map:lookup "test:a") "GraphMap should lookup nodes by key")
    (assert (map:lookup "test:b") "GraphMap should lookup nodes by key")
    (assert (not (graph:lookup "test:a")) "GraphMap nodes should not leak into shared Graph")
    (assert (not (graph:lookup "test:b")) "GraphMap nodes should not leak into shared Graph")
    (map:drop)
    (graph:drop))

(fn graph-map-adds-edges []
    (local graph (Graph {:with-start false}))
    (register-test-loader graph)
    (local map (GraphMap.GraphMap {:graph graph :id "test-edges"}))
    (local a (Graph.GraphNode {:key "test:a"}))
    (local b (Graph.GraphNode {:key "test:b"}))
    (map:add-edge (Graph.GraphEdge {:source a :target b}))
    (assert (= (map:edge-count) 1) "GraphMap should track edge count")
    (assert (= (graph:edge-count) 0) "GraphMap edges should not leak into shared Graph")
    (map:drop)
    (graph:drop))

(fn graph-map-removes-nodes-and-edges []
    (local graph (Graph {:with-start false}))
    (register-test-loader graph)
    (local map (GraphMap.GraphMap {:graph graph :id "test-remove"}))
    (local a (Graph.GraphNode {:key "test:a"}))
    (local b (Graph.GraphNode {:key "test:b"}))
    (local c (Graph.GraphNode {:key "test:c"}))
    (map:add-node a {})
    (map:add-node b {})
    (map:add-node c {})
    (map:add-edge (Graph.GraphEdge {:source a :target b}))
    (map:add-edge (Graph.GraphEdge {:source b :target c}))
    (assert (= (map:edge-count) 2) "GraphMap should have 2 edges")
    (local removed (map:remove-nodes [b]))
    (assert (= removed 1) "GraphMap should report removed count")
    (assert (map:lookup "test:a") "Remaining node should still be in map")
    (assert (map:lookup "test:c") "Remaining node should still be in map")
    (assert (not (map:lookup "test:b")) "Removed node should not be in map")
    (assert (= (map:edge-count) 0) "Edges connected to removed node should be dropped")
    (map:drop)
    (graph:drop))

(fn graph-map-emits-signals []
    (local graph (Graph {:with-start false}))
    (register-test-loader graph)
    (local map (GraphMap.GraphMap {:graph graph :id "test-signals"}))
    (var node-adds 0)
    (var node-rems 0)
    (var edge-adds 0)
    (var edge-rems 0)
    (local na (map.node-added:connect (fn [_] (set node-adds (+ node-adds 1)))))
    (local nr (map.node-removed:connect (fn [_] (set node-rems (+ node-rems 1)))))
    (local ea (map.edge-added:connect (fn [_] (set edge-adds (+ edge-adds 1)))))
    (local er (map.edge-removed:connect (fn [_] (set edge-rems (+ edge-rems 1)))))
    (local a (Graph.GraphNode {:key "test:a"}))
    (local b (Graph.GraphNode {:key "test:b"}))
    (map:add-node a {})
    (map:add-edge (Graph.GraphEdge {:source a :target b}))
    (assert (= node-adds 2) "GraphMap should emit node-added for source and target")
    (assert (= edge-adds 1) "GraphMap should emit edge-added")
    (map:remove-nodes [a])
    (assert (= node-rems 1) "GraphMap should emit node-removed")
    (assert (= edge-rems 1) "GraphMap should emit edge-removed")
    (map.node-added:disconnect na true)
    (map.node-removed:disconnect nr true)
    (map.edge-added:disconnect ea true)
    (map.edge-removed:disconnect er true)
    (map:drop)
    (graph:drop))

(fn graph-map-mounts-nodes []
    (local graph (Graph {:with-start false}))
    (register-test-loader graph)
    (local map (GraphMap.GraphMap {:graph graph :id "test-mount"}))
    (local node (Graph.GraphNode {:key "test:mounted-node"}))
    (assert (= node.graph nil) "Node should start with nil graph")
    (map:add-node node {})
    (assert (= node.graph map) "GraphMap should mount node with node.graph == graph-map")
    (map:remove-nodes [node])
    (assert (= node.graph nil) "GraphMap should unmount node on remove")
    (map:drop)
    (graph:drop))

(fn graph-map-captures-state []
    (local graph (Graph {:with-start false}))
    (register-test-loader graph)
    (local map (GraphMap.GraphMap {:graph graph :id "test-capture"}))
    (local a (Graph.GraphNode {:key "test:a"}))
    (local b (Graph.GraphNode {:key "test:b"}))
    (map:add-node a {})
    (map:add-edge (Graph.GraphEdge {:source a :target b}))
    (local state (map:capture-state))
    (assert (= (length state.nodes) 2) "GraphMap capture-state should include both nodes")
    (assert (= (. state.nodes 1) "test:a"))
    (assert (= (. state.nodes 2) "test:b"))
    (assert (= (length state.edges) 1) "GraphMap capture-state should include one edge")
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :source)) "test:a"))
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :target)) "test:b"))
    (map:drop)
    (graph:drop))

(fn graph-map-restores-state []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-restore"}))
    (map:restore-state {:nodes ["test:A" "test:B"]
                        :edges [{:source "test:A" :target "test:B"}]})
    (assert (map:lookup "test:A") "GraphMap restore-state should load source node")
    (assert (map:lookup "test:B") "GraphMap restore-state should load target node")
    (assert (= (map:edge-count) 1) "GraphMap restore-state should recreate edges")
    (assert (not (graph:lookup "test:A")) "Restored nodes should not leak into shared Graph")
    (assert (not (graph:lookup "test:B")) "Restored nodes should not leak into shared Graph")
    (map:drop)
    (graph:drop))

(fn graph-map-removes-nodes-without-deleting-backing-objects []
    (local graph (Graph {:with-start false}))
    (register-test-loader graph)
    (local map (GraphMap.GraphMap {:graph graph :id "test-safe-remove"}))
    (local a (Graph.GraphNode {:key "a"}))
    (graph:add-node a {})
    (assert (graph:lookup "a") "Node should be in shared Graph")
    (map:add-node (Graph.GraphNode {:key "test:b"}))
    (map:remove-nodes [(map:lookup "test:b")])
    (assert (not (map:lookup "test:b")) "Node should be removed from map")
    (assert (graph:lookup "a") "Shared Graph node should still exist")
    (map:drop)
    (graph:drop))

(fn two-graph-maps-load-same-key-into-separate-adapters []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map-a (GraphMap.GraphMap {:graph graph :id "map-a" :name "Map A"}))
    (local map-b (GraphMap.GraphMap {:graph graph :id "map-b" :name "Map B"}))
    (local node-a (map-a:load-by-key "test:shared"))
    (local node-b (map-b:load-by-key "test:shared"))
    (assert (not (= node-a node-b))
            "Two graph maps should produce separate node adapter instances for the same key")
    (assert (map-a:lookup "test:shared") "Map A should contain the node")
    (assert (map-b:lookup "test:shared") "Map B should contain the node")
    (assert (= node-a.graph map-a) "Map A node should be mounted to map A")
    (assert (= node-b.graph map-b) "Map B node should be mounted to map B")
    (assert (not (graph:lookup "test:shared"))
            "Shared Graph should not contain nodes created via create-node-by-key")
    (map-a:drop)
    (map-b:drop)
    (graph:drop))

(fn removing-node-from-one-map-does-not-affect-another []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map-a (GraphMap.GraphMap {:graph graph :id "map-a" :name "Map A"}))
    (local map-b (GraphMap.GraphMap {:graph graph :id "map-b" :name "Map B"}))
    (map-a:load-by-key "test:item")
    (map-b:load-by-key "test:item")
    (local node-in-a (map-a:lookup "test:item"))
    (local node-in-b (map-b:lookup "test:item"))
    (assert node-in-a "Map A should have the node")
    (assert node-in-b "Map B should have the node")
    (map-a:remove-nodes [node-in-a])
    (assert (not (map-a:lookup "test:item")) "Node should be removed from map A")
    (assert (map-b:lookup "test:item") "Node should still be in map B")
    (map-a:drop)
    (map-b:drop)
    (graph:drop))

(fn graph-map-drop-unmounts-all-nodes []
    (local graph (Graph {:with-start false}))
    (register-test-loader graph)
    (local map (GraphMap.GraphMap {:graph graph :id "test-drop"}))
    (local a (Graph.GraphNode {:key "test:a"}))
    (local b (Graph.GraphNode {:key "test:b"}))
    (map:add-node a {})
    (map:add-node b {})
    (assert (= a.graph map) "Node should be mounted to map before drop")
    (map:drop)
    (assert (= a.graph nil) "Node should be unmounted after map drop")
    (assert (= b.graph nil) "Node should be unmounted after map drop")
    (graph:drop))

(fn graph-map-create-node-by-key-works []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local node (graph:create-node-by-key "test:from-create"))
    (assert node "create-node-by-key should create a node")
    (assert (= node.key "test:from-create") "create-node-by-key node should have correct key")
    (assert (not (graph:lookup "test:from-create"))
            "create-node-by-key should not insert node into shared Graph.nodes")
    (node:drop)
    (graph:drop))

(fn graph-map-create-node-by-key-returns-nil-for-unresolvable-key []
    (local graph (Graph {:with-start false}))
    (local node (graph:create-node-by-key "no-loader:item"))
    (assert (= node nil)
             "create-node-by-key should return nil for unresolvable key")
    (graph:drop))

(fn graph-map-rejects-non-loader-backed-node []
    (local graph (Graph {:with-start false}))
    (local map (GraphMap.GraphMap {:graph graph :id "test-strict-node"}))
    (local (ok err)
        (pcall (fn []
                 (map:add-node (Graph.GraphNode {:key "ephemeral"})))))
    (assert (not ok) "GraphMap should reject non-loader-backed nodes")
    (assert (string.find (tostring err) "not loader-backed" 1 true)
            "GraphMap rejection should explain loader-backed requirement")
    (map:drop)
    (graph:drop))

(fn shared-edge-removed-forwarding []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-edge-rm-fwd"}))
    (local a (map:load-by-key "test:A"))
    (local b (map:load-by-key "test:B"))
    (graph.edge-added:emit
        {:edge {:source {:key "test:A"}
                :target {:key "test:B"}}
         :opts {:from-link-entity "entity-der"}})
    (assert (= (map:edge-count) 1) "Derived edge should be in map before removal")
    (var removed-edge nil)
    (local handler (map.edge-removed:connect (fn [payload]
                     (set removed-edge (and payload payload.edge)))))
    (graph.edge-removed:emit {:edge {:source {:key "test:A"} :target {:key "test:B"}}})
    (assert removed-edge "Shared edge-removed should forward derived edge removal to map")
    (assert (= (and removed-edge.source removed-edge.source.key) "test:A")
            "Forwarded edge should have correct source key")
    (assert (= (and removed-edge.target removed-edge.target.key) "test:B")
            "Forwarded edge should have correct target key")
    (assert (= (map:edge-count) 0) "Derived edge should be removed from map")
    (map.edge-removed:disconnect handler true)
    (map:drop)
    (graph:drop))

(fn shared-node-replaced-creates-separate-adapter []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-repl-adapter"}))
    (local original-map (map:load-by-key "test:original"))
    (assert original-map "Map should contain the loaded original node")
    (assert (= original-map.graph map))
    (graph:load-by-key "test:original")
    (var replaced-payload nil)
    (local handler (map.node-replaced:connect (fn [payload]
                     (set replaced-payload payload))))
    (local replacement-shared (graph:create-node-by-key "test:original"))
    (graph:add-node replacement-shared)
    (assert replaced-payload "Map should forward node-replaced")
    (assert (= replaced-payload.old original-map)
            "Node-replaced old should be the map-local original")
    (local new-map-node (map:lookup "test:original"))
    (assert new-map-node "Replacement node should be in the map")
    (assert (not (= new-map-node original-map))
            "Replacement should be a separate adapter instance")
    (assert (not (= new-map-node replacement-shared))
            "Replacement should be map-local, not the shared replacement")
    (assert (= new-map-node.graph map)
            "Replacement should be mounted to the map")
    (map.node-replaced:disconnect handler true)
    (map:drop)
    (graph:drop))

(fn shared-edge-added-does-not-auto-load-endpoints []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-edge-no-auto"}))
    (map:load-by-key "test:A")
    (assert (map:lookup "test:A") "Endpoint A should be in map")
    (assert (not (map:lookup "test:B")) "Endpoint B should not be in map")
    (graph.edge-added:emit {:edge {:source {:key "test:A"} :target {:key "test:B"}}})
    (assert (not (map:lookup "test:B"))
            "Shared edge-added should not auto-load missing endpoint into map")
    (assert (= (map:edge-count) 0)
            "Edge should not be added when an endpoint is absent from the map")
    (map:drop)
    (graph:drop))

(fn morph-only-affects-maps-containing-source []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-morph-guard"}))
    (assert (not (map:lookup "test:old-key"))
            "Source key should not be in map initially")
    (var morph-emitted false)
    (local handler (map.node-morphed:connect (fn [_]
                     (set morph-emitted true))))
    (graph.node-morphed:emit {:source-key "test:old-key" :target-key "test:new-key"})
    (assert (not morph-emitted)
            "Morph should not emit for maps not containing the source key")
    (assert (not (map:lookup "test:new-key"))
            "Morph should not auto-add target to maps lacking source")
    (map.node-morphed:disconnect handler true)
    (map:drop)
    (graph:drop))

(fn morph-loads-target-when-source-is-in-map []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-morph-pos"}))
    (local source (map:load-by-key "test:source"))
    (assert source "Source should be in map")
    (assert (= (map:node-count) 1))
    (var morph-emitted false)
    (var morph-payload nil)
    (local handler (map.node-morphed:connect (fn [payload]
                     (set morph-emitted true)
                     (set morph-payload payload))))
    (graph.node-morphed:emit {:source-key "test:source" :target-key "test:target"})
    (assert morph-emitted "Morph should emit for maps containing the source key")
    (assert morph-payload "Morph payload should be forwarded")
    (assert (not (map:lookup "test:source"))
            "Source should be removed from map after morph")
    (assert (map:lookup "test:target")
            "Target should be loaded into map after morph")
    (assert (= (map:node-count) 1)
            "Map should have one node (target) after morph")
    (map.node-morphed:disconnect handler true)
    (map:drop)
    (graph:drop))

(fn shared-node-added-does-not-auto-sync-into-map []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-no-auto-sync"}))
    (graph:load-by-key "test:shared-only")
    (assert (graph:lookup "test:shared-only")
            "Node should be in shared graph")
    (assert (not (map:lookup "test:shared-only"))
            "Node should NOT auto-sync into map via shared node-added")
    (map:drop)
    (graph:drop))

(fn graph-map-refresh-adapters-by-scheme-rebuilds-visible-nodes []
    (local graph (Graph {:with-start false}))
    (var label-version "v1")
    (graph:register-key-loader "ext"
        (fn [key]
            (Graph.GraphNode {:key key :label label-version})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-refresh-ext"}))
    (local node-a (map:load-by-key "ext:a"))
    (local node-b (map:load-by-key "ext:b"))
    (map:add-edge (Graph.GraphEdge {:source node-a :target node-b}))
    (set map.selected_node_keys ["ext:a"])
    (set map.focused_node_key "ext:b")
    (var replaced-count 0)
    (local replaced-keys [])
    (local handler (map.node-replaced:connect
                       (fn [payload]
                           (set replaced-count (+ replaced-count 1))
                           (table.insert replaced-keys (and payload payload.new payload.new.key)))))
    (set label-version "v2")
    (local result (map:refresh-adapters-by-scheme "ext"))
    (local refreshed-a (map:lookup "ext:a"))
    (local refreshed-b (map:lookup "ext:b"))
    (assert (= result.scheme "ext") "Refresh result should include scheme")
    (assert (= (length result.refreshed) 2) "Refresh result should include refreshed keys")
    (assert (= (length result.failed) 0) "Refresh result should include no failures")
    (assert (= refreshed-a.label "v2") "Refreshed node A should use updated adapter")
    (assert (= refreshed-b.label "v2") "Refreshed node B should use updated adapter")
    (local edge (. map.edges 1))
    (assert (= edge.source refreshed-a) "Explicit edge source should point at replacement adapter")
    (assert (= edge.target refreshed-b) "Explicit edge target should point at replacement adapter")
    (assert (= (length map.selected_node_keys) 1) "Refresh should preserve selected key count")
    (assert (= (. map.selected_node_keys 1) "ext:a") "Refresh should preserve selected keys")
    (assert (= map.focused_node_key "ext:b") "Refresh should preserve focused key")
    (assert (= replaced-count 2) "Refresh should emit node-replaced for each refreshed node")
    (assert (= (. replaced-keys 1) "ext:a") "First replacement should be ext:a")
    (assert (= (. replaced-keys 2) "ext:b") "Second replacement should be ext:b")
    (map.node-replaced:disconnect handler true)
    (map:drop)
    (graph:drop))

(fn graph-map-refresh-adapters-by-scheme-fails-before-mutation []
    (local graph (Graph {:with-start false}))
    (var loadable? true)
    (graph:register-key-loader "ext"
        (fn [key]
            (if loadable?
                (Graph.GraphNode {:key key :label "v1"})
                nil)))
    (local map (GraphMap.GraphMap {:graph graph :id "test-refresh-fail"}))
    (local original (map:load-by-key "ext:a"))
    (set loadable? false)
    (local (ok err) (pcall #(map:refresh-adapters-by-scheme "ext")))
    (assert (not ok) "Refresh should fail when a visible node cannot be rebuilt")
    (assert (string.find (tostring err) "failed to refresh graph nodes for scheme ext" 1 true)
            "Refresh failure should name the failing scheme")
    (assert (= (map:lookup "ext:a") original)
            "Refresh failure should leave previous adapter visible")
    (assert (= original.label "v1")
            "Refresh failure should not mutate existing adapter")
    (map:drop)
    (graph:drop))

(fn graph-map-capture-preserves-unresolved-restored-state []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (if (= key "test:a")
                (Graph.GraphNode {:key key})
                nil)))
    (local map (GraphMap.GraphMap {:graph graph :id "test-unresolved"}))
    (map:restore-state {:nodes ["test:a" "test:missing"]
                        :edges [{:source "test:a"
                                 :target "test:missing"}]})
    (local state (map:capture-state))
    (assert (= (length state.nodes) 2)
            "GraphMap capture-state should preserve unresolved restored nodes")
    (assert (= (. state.nodes 1) "test:a"))
    (assert (= (. state.nodes 2) "test:missing")
            "GraphMap capture-state should include unresolved node key")
    (assert (= (length state.edges) 1)
            "GraphMap capture-state should preserve unresolved restored edges")
    (map:drop)
    (graph:drop))

(fn shared-edge-added-forwards-metadata []
    (local glm (require :glm))
    (local test-color (glm.vec4 0.45 0.42 0.3 1))
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-edge-meta"}))
    (map:load-by-key "test:A")
    (map:load-by-key "test:B")
    (var added-edge nil)
    (local handler (map.edge-added:connect (fn [payload]
                     (set added-edge (and payload payload.edge)))))
    (graph.edge-added:emit
        {:edge {:source {:key "test:A"}
                :target {:key "test:B"}
                :label "link-label"
                :color test-color}
         :opts {:from-link-entity "entity-1"}})
    (assert added-edge "Shared edge-added should forward to map")
    (assert (= (and added-edge.source added-edge.source.key) "test:A"))
    (assert (= (and added-edge.target added-edge.target.key) "test:B"))
    (assert (= added-edge.label "link-label")
            "Forwarded edge should preserve label")
    (assert (= added-edge.color test-color)
            "Forwarded edge should preserve color")
    (map.edge-added:disconnect handler true)
    (map:drop)
    (graph:drop))

(fn graph-map-capture-skips-derived-link-edges []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-derived-capture"}))
    (map:load-by-key "test:A")
    (map:load-by-key "test:B")
    (map:load-by-key "test:C")
    (local a (map:lookup "test:A"))
    (local b (map:lookup "test:B"))
    (local c (map:lookup "test:C"))
    (map:add-edge (Graph.GraphEdge {:source a :target b}))
    (graph.edge-added:emit
        {:edge {:source {:key "test:A"}
                :target {:key "test:C"}
                :label "derived-link"
                :color (glm.vec4 0.45 0.42 0.3 1)}
         :opts {:from-link-entity "entity-1"}})
    (assert (= (map:edge-count) 2) "Map should have 2 edges")
    (local state (map:capture-state))
    (assert (= (length state.nodes) 3) "Capture should include all nodes")
    (assert (= (length state.edges) 1)
            "Capture should skip derived link-entity edges")
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :source)) "test:A"))
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :target)) "test:B"))
    (map:drop)
    (graph:drop))

(fn graph-map-replacement-keeps-derived-opts []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-repl-derived"}))
    (map:load-by-key "test:A")
    (map:load-by-key "test:B")
    (local a (map:lookup "test:A"))
    (local b (map:lookup "test:B"))
    (map:add-edge (Graph.GraphEdge {:source a :target b :label "explicit"}))
    (assert (= (map:edge-count) 1) "Explicit edge should be in map")
    (graph.edge-added:emit
        {:edge {:source {:key "test:A"}
                :target {:key "test:B"}
                :label "derived-replace"}
         :opts {:from-link-entity "entity-repl"}})
    (assert (= (map:edge-count) 2)
            "Derived edge should coexist with explicit edge for same endpoints")
    (local state (map:capture-state))
    (assert (= (length state.edges) 1)
            "Explicit edge should still appear in capture while derived edge is skipped")
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :source)) "test:A"))
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :target)) "test:B"))
    (map:drop)
    (graph:drop))

(fn graph-map-replacement-clears-derived-opts []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-repl-explicit"}))
    (map:load-by-key "test:A")
    (map:load-by-key "test:B")
    (local a (map:lookup "test:A"))
    (local b (map:lookup "test:B"))
    (graph.edge-added:emit
        {:edge {:source {:key "test:A"}
                :target {:key "test:B"}
                :label "derived-first"}
         :opts {:from-link-entity "entity-first"}})
    (assert (= (map:edge-count) 1) "Derived edge should be in map")
    (map:add-edge (Graph.GraphEdge {:source a :target b :label "explicit-replace"}))
    (assert (= (map:edge-count) 2)
            "Explicit edge should coexist with existing derived edge")
    (local state (map:capture-state))
    (assert (= (length state.edges) 1)
            "Explicit replacement edge should appear in capture")
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :source)) "test:A"))
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :target)) "test:B"))
    (map:drop)
    (graph:drop))

(fn graph-map-replacement-emits-edge-added []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-repl-signal"}))
    (map:load-by-key "test:A")
    (map:load-by-key "test:B")
    (local a (map:lookup "test:A"))
    (local b (map:lookup "test:B"))
    (map:add-edge (Graph.GraphEdge {:source a :target b :label "explicit"}))
    (var replaced-edge nil)
    (local handler (map.edge-added:connect (fn [payload]
                     (set replaced-edge (and payload payload.edge)))))
    (graph.edge-added:emit
        {:edge {:source {:key "test:A"}
                :target {:key "test:B"}
                :label "replaced-by-derived"}
         :opts {:from-link-entity "entity-repl"}})
    (assert replaced-edge
            "Derived edge should emit edge-added when it coexists with explicit edge")
    (assert (= (map:edge-count) 2)
            "Derived edge should coexist with explicit edge for same endpoints")
    (local state (map:capture-state))
    (assert (= (length state.edges) 1)
            "Explicit edge should appear in capture while derived edge is skipped")
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :source)) "test:A"))
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :target)) "test:B"))
    (map.edge-added:disconnect handler true)
    (map:drop)
    (graph:drop))

(fn graph-map-allows-multiple-derived-link-edges-for-same-endpoints []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-link-edges"
                             (.. "multi-link-" (os.time) "-" (do
                                                                 (set temp-counter (+ temp-counter 1))
                                                                 temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local LinkEntityStore (require :entities/link))
                (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
                (link-store:create-entity {:id "one"
                                           :source-key "test:A"
                                           :target-key "test:B"
                                           :metadata {:name "one"}})
                (link-store:create-entity {:id "two"
                                           :source-key "test:A"
                                           :target-key "test:B"
                                           :metadata {:name "two"}})
                (local graph (Graph {:with-start false
                                     :entity-events? false
                                     :link-store link-store}))
                (register-test-loader graph)
                (local map (GraphMap.GraphMap {:graph graph :id "test-multi-derived"}))
                (map:load-by-key "test:A")
                (map:load-by-key "test:B")
                (assert (= (map:edge-count) 2)
                        "Two link entities between the same endpoints should create two visual edges")
                (local captured (map:capture-state))
                (assert (= (length captured.edges) 0)
                        "Derived link-entity edges should still be omitted from capture")
                (link-store:delete-entity "one")
                (assert (= (map:edge-count) 1)
                        "Deleting one link entity should leave the other visual edge")
                (link-store:delete-entity "two")
                (assert (= (map:edge-count) 0)
                        "Deleting both link entities should remove both visual edges")
                (map:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn graph-map-remove-nodes-preserves-list-entity-backing-store []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-list-test"
                             (.. "rm-list-" (os.time) "-" (do
                                                              (set temp-counter (+ temp-counter 1))
                                                              temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local StringEntityStore (require :entities/string))
                (local ListEntityStore (require :entities/list))
                (local IdentityStore (require :entities/identity))
                (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
                (local list-store (ListEntityStore.ListEntityStore {:base-dir (fs.join-path dir "list")}))
                (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path dir "identity")}))
                (local a (string-store:create-entity {:value "a"}))
                (local b (string-store:create-entity {:value "b"}))
                (local key-a (.. "string-entity:" a.id))
                (local key-b (.. "string-entity:" b.id))
                (local entity (list-store:create-entity {:name "test-list"
                                                         :items [key-a key-b]}))
                (local graph (Graph {:with-start false
                                     :identity-store identity-store}))
                (local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
                (local {:register-loader register-list-loader} (require :graph/nodes/list-entity))
                (register-string-loader graph {:store string-store})
                (register-list-loader graph {:store list-store :identity-store identity-store})
                (local map (GraphMap.GraphMap {:graph graph :id "test-rm-list"}))
                (map:load-by-key key-a)
                (map:load-by-key key-b)
                (local list-key (.. "list-entity:" entity.id))
                (local list-node (map:load-by-key list-key))
                (assert list-node "should load list node")
                (local pre-items (. (list-store:get-entity entity.id) :items))
                (assert (= (length (or pre-items [])) 2)
                        "list should have 2 items before remove")
                (assert (= (. pre-items 1) key-a) "items[1] should be key-a")
                (assert (= (. pre-items 2) key-b) "items[2] should be key-b")
                ;; Remove an item node while the list node stays mounted --
                ;; this must not mutate the backing store.
                (local node-a (map:lookup key-a))
                (assert node-a "should find item node in map")
                (map:remove-nodes [node-a])
                (local after-item-remove (. (list-store:get-entity entity.id) :items))
                (assert (= (length (or after-item-remove [])) 2)
                        "GraphMap remove-nodes of item node should not mutate list-entity backing store")
                (assert (= (. after-item-remove 1) key-a) "items[1] should still be key-a after item remove")
                (assert (= (. after-item-remove 2) key-b) "items[2] should still be key-b after item remove")
                ;; Container removal is also non-destructive.
                (map:remove-nodes [list-node])
                (local after-container-remove (. (list-store:get-entity entity.id) :items))
                (assert (= (length (or after-container-remove [])) 2)
                        "GraphMap remove-nodes of list node should not mutate backing store")
                (assert (= (. after-container-remove 1) key-a) "items[1] should still be key-a after container remove")
                (assert (= (. after-container-remove 2) key-b) "items[2] should still be key-b after container remove")
                (map:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn graph-map-remove-nodes-preserves-notebook-backing-store []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-notebook-test"
                             (.. "rm-nb-" (os.time) "-" (do
                                                              (set temp-counter (+ temp-counter 1))
                                                              temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local StringEntityStore (require :entities/string))
                (local NotebookStore (require :notebooks/store))
                (local IdentityStore (require :entities/identity))
                (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
                (local notebook-store (NotebookStore.NotebookStore {:base-dir (fs.join-path dir "notebooks")}))
                (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path dir "identity")}))
                (local a (string-store:create-entity {:value "a"}))
                (local b (string-store:create-entity {:value "b"}))
                (local key-a (.. "string-entity:" a.id))
                (local key-b (.. "string-entity:" b.id))
                (local notebook (notebook-store:create-notebook {:name "test-nb"
                                                                  :items [key-a key-b]}))
                (local graph (Graph {:with-start false
                                     :identity-store identity-store}))
                (local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
                (local {:register-loader register-notebook-loader} (require :graph/nodes/notebook))
                (register-string-loader graph {:store string-store})
                (register-notebook-loader graph {:store notebook-store
                                                  :string-store string-store
                                                  :identity-store identity-store})
                (local map (GraphMap.GraphMap {:graph graph :id "test-rm-nb"}))
                (map:load-by-key key-a)
                (map:load-by-key key-b)
                (local notebook-key (.. "notebook:" notebook.id))
                (local notebook-node (map:load-by-key notebook-key))
                (assert notebook-node "should load notebook node")
                (local pre-items (. (notebook-store:get-notebook notebook.id) :items))
                (assert (= (length (or pre-items [])) 2)
                        "notebook should have 2 items before remove")
                (assert (= (. pre-items 1) key-a) "items[1] should be key-a")
                (assert (= (. pre-items 2) key-b) "items[2] should be key-b")
                ;; Remove an item node while the notebook node stays mounted --
                ;; this must not mutate the backing store.
                (local node-a (map:lookup key-a))
                (assert node-a "should find item node in map")
                (map:remove-nodes [node-a])
                (local after-item-remove (. (notebook-store:get-notebook notebook.id) :items))
                (assert (= (length (or after-item-remove [])) 2)
                        "GraphMap remove-nodes of item node should not mutate notebook backing store")
                (assert (= (. after-item-remove 1) key-a) "items[1] should still be key-a after item remove")
                (assert (= (. after-item-remove 2) key-b) "items[2] should still be key-b after item remove")
                ;; Container removal is also non-destructive.
                (map:remove-nodes [notebook-node])
                (local after-container-remove (. (notebook-store:get-notebook notebook.id) :items))
                (assert (= (length (or after-container-remove [])) 2)
                        "GraphMap remove-nodes of notebook node should not mutate backing store")
                (assert (= (. after-container-remove 1) key-a) "items[1] should still be key-a after container remove")
                (assert (= (. after-container-remove 2) key-b) "items[2] should still be key-b after container remove")
                (map:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn graph-map-shared-delete-sync-removes-list-entity-item []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-shared-del"
                             (.. "sd-list-" (os.time) "-" (do
                                                               (set temp-counter (+ temp-counter 1))
                                                               temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local StringEntityStore (require :entities/string))
                (local ListEntityStore (require :entities/list))
                (local IdentityStore (require :entities/identity))
                (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
                (local list-store (ListEntityStore.ListEntityStore {:base-dir (fs.join-path dir "list")}))
                (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path dir "identity")}))
                (local a (string-store:create-entity {:value "a"}))
                (local b (string-store:create-entity {:value "b"}))
                (local key-a (.. "string-entity:" a.id))
                (local key-b (.. "string-entity:" b.id))
                (local entity (list-store:create-entity {:name "test-list"
                                                         :items [key-a key-b]}))
                (local graph (Graph {:with-start false
                                     :identity-store identity-store}))
                (local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
                (local {:register-loader register-list-loader} (require :graph/nodes/list-entity))
                (register-string-loader graph {:store string-store})
                (register-list-loader graph {:store list-store :identity-store identity-store})
                (local map (GraphMap.GraphMap {:graph graph :id "test-sd-list"}))
                ;; Load items into shared graph so remove-nodes works on the shared graph.
                (graph:load-by-key key-a)
                (graph:load-by-key key-b)
                ;; Load list and items into the map (separate adapter instances).
                (map:load-by-key key-a)
                (map:load-by-key key-b)
                (local list-key (.. "list-entity:" entity.id))
                (local list-node (map:load-by-key list-key))
                (assert list-node "should load list node in map")
                (local pre-items (. (list-store:get-entity entity.id) :items))
                (assert (= (length (or pre-items [])) 2)
                        "list should have 2 items before shared delete")
                (assert (= (. pre-items 1) key-a))
                (assert (= (. pre-items 2) key-b))
                ;; Remove key-a from the shared graph -- sync must propagate
                ;; to the map and be treated as a real deletion by the list node.
                (local shared-node-a (graph:lookup key-a))
                (assert shared-node-a "should find key-a in shared graph")
                (graph:remove-nodes [shared-node-a])
                (local after-items (. (list-store:get-entity entity.id) :items))
                (assert (= (length (or after-items [])) 1)
                        "GraphMap shared-delete sync should drop item from list-entity backing store")
                (assert (= (. after-items 1) key-b) "remaining item should be key-b")
                (map:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn graph-map-store-delete-removes-list-entity-item []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-store-del"
                             (.. "store-list-" (os.time) "-" (do
                                                                  (set temp-counter (+ temp-counter 1))
                                                                  temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local StringEntityStore (require :entities/string))
                (local ListEntityStore (require :entities/list))
                (local IdentityStore (require :entities/identity))
                (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
                (local list-store (ListEntityStore.ListEntityStore {:base-dir (fs.join-path dir "list")}))
                (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path dir "identity")}))
                (local a (string-store:create-entity {:value "a"}))
                (local b (string-store:create-entity {:value "b"}))
                (local key-a (.. "string-entity:" a.id))
                (local key-b (.. "string-entity:" b.id))
                (local entity (list-store:create-entity {:name "test-list"
                                                         :items [key-a key-b]}))
                (local graph (Graph {:with-start false
                                     :identity-store identity-store}))
                (local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
                (local {:register-loader register-list-loader} (require :graph/nodes/list-entity))
                (register-string-loader graph {:store string-store})
                (register-list-loader graph {:store list-store :identity-store identity-store})
                (local map (GraphMap.GraphMap {:graph graph :id "test-store-del-list"}))
                (map:load-by-key key-a)
                (map:load-by-key key-b)
                (map:load-by-key (.. "list-entity:" entity.id))
                (string-store:delete-entity a.id)
                (local after-items (. (list-store:get-entity entity.id) :items))
                (assert (= (length (or after-items [])) 1)
                        "Backing-store delete should drop item from list-entity backing store")
                (assert (= (. after-items 1) key-b)
                        "Remaining item should be key-b after backing-store delete")
                (map:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn graph-map-shared-delete-sync-removes-notebook-item []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-shared-del"
                             (.. "sd-nb-" (os.time) "-" (do
                                                              (set temp-counter (+ temp-counter 1))
                                                              temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local StringEntityStore (require :entities/string))
                (local NotebookStore (require :notebooks/store))
                (local IdentityStore (require :entities/identity))
                (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
                (local notebook-store (NotebookStore.NotebookStore {:base-dir (fs.join-path dir "notebooks")}))
                (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path dir "identity")}))
                (local a (string-store:create-entity {:value "a"}))
                (local b (string-store:create-entity {:value "b"}))
                (local key-a (.. "string-entity:" a.id))
                (local key-b (.. "string-entity:" b.id))
                (local notebook (notebook-store:create-notebook {:name "test-nb"
                                                                  :items [key-a key-b]}))
                (local graph (Graph {:with-start false
                                     :identity-store identity-store}))
                (local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
                (local {:register-loader register-notebook-loader} (require :graph/nodes/notebook))
                (register-string-loader graph {:store string-store})
                (register-notebook-loader graph {:store notebook-store
                                                  :string-store string-store
                                                  :identity-store identity-store})
                (local map (GraphMap.GraphMap {:graph graph :id "test-sd-nb"}))
                ;; Load items into shared graph so remove-nodes works on the shared graph.
                (graph:load-by-key key-a)
                (graph:load-by-key key-b)
                ;; Load notebook and items into the map (separate adapter instances).
                (map:load-by-key key-a)
                (map:load-by-key key-b)
                (local notebook-key (.. "notebook:" notebook.id))
                (local notebook-node (map:load-by-key notebook-key))
                (assert notebook-node "should load notebook node in map")
                (local pre-items (. (notebook-store:get-notebook notebook.id) :items))
                (assert (= (length (or pre-items [])) 2)
                        "notebook should have 2 items before shared delete")
                (assert (= (. pre-items 1) key-a))
                (assert (= (. pre-items 2) key-b))
                ;; Remove key-a from the shared graph -- sync must propagate
                ;; to the map and be treated as a real deletion by the notebook node.
                (local shared-node-a (graph:lookup key-a))
                (assert shared-node-a "should find key-a in shared graph")
                (graph:remove-nodes [shared-node-a])
                (local after-items (. (notebook-store:get-notebook notebook.id) :items))
                (assert (= (length (or after-items [])) 1)
                        "GraphMap shared-delete sync should drop item from notebook backing store")
                (assert (= (. after-items 1) key-b) "remaining item should be key-b")
                (map:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn graph-map-direct-link-store-events-refresh-derived-edges-with-shared-events []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-link-events"
                             (.. "shared-events-" (os.time) "-" (do
                                                                      (set temp-counter (+ temp-counter 1))
                                                                      temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local LinkEntityStore (require :entities/link))
                (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
                (link-store:create-entity {:id "persisted"
                                           :source-key "test:A"
                                           :target-key "test:B"
                                           :metadata {:name "original"}})
                (link-store:create-entity {:id "delete-only"
                                           :source-key "test:A"
                                           :target-key "test:C"})
                (local graph (Graph {:with-start false
                                     :link-store link-store}))
                (register-test-loader graph)
                (local map (GraphMap.GraphMap {:graph graph :id "test-direct-link-events"}))
                (map:load-by-key "test:A")
                (map:load-by-key "test:B")
                (map:load-by-key "test:C")
                (assert (= (map:edge-count) 2)
                        "Pre-existing persisted links should hydrate as derived map edges")
                (link-store:delete-entity "delete-only")
                (assert (= (map:edge-count) 1)
                        "Direct link delete should remove derived map edge even when shared graph had no link-edge-map entry")
                (link-store:update-entity "persisted" {:target-key "test:C"
                                                        :metadata {:name "updated"}})
                (assert (= (map:edge-count) 1)
                        "Link update should replace the stale derived map edge")
                (local edge (. map.edges 1))
                (assert (= (and edge edge.source edge.source.key) "test:A"))
                (assert (= (and edge edge.target edge.target.key) "test:C")
                        "Derived map edge should follow updated link target")
                (assert (= edge.label "updated")
                        "Derived map edge should refresh link metadata")
                (link-store:delete-entity "persisted")
                (assert (= (map:edge-count) 0)
                        "Direct link delete should remove updated derived map edge")
                (map:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn graph-map-direct-identity-events-refresh-derived-link-edges []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-identity-link-events"
                             (.. "identity-events-" (os.time) "-" (do
                                                                       (set temp-counter (+ temp-counter 1))
                                                                       temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local LinkEntityStore (require :entities/link))
                (local IdentityStore (require :entities/identity))
                (local link-store (LinkEntityStore.LinkEntityStore {:base-dir (fs.join-path dir "link")}))
                (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path dir "identity")}))
                (identity-store:create-entity {:id "alias" :target-key "test:A"})
                (link-store:create-entity {:id "identity-link"
                                           :source-key "identity:alias"
                                           :target-key "test:B"})
                (local graph (Graph {:with-start false
                                     :link-store link-store
                                     :identity-store identity-store}))
                (register-test-loader graph)
                (local map (GraphMap.GraphMap {:graph graph :id "test-identity-link-events"}))
                (map:load-by-key "test:A")
                (map:load-by-key "test:B")
                (map:load-by-key "test:C")
                (assert (= (map:edge-count) 1)
                        "Identity-resolved link should hydrate as a derived map edge")
                (identity-store:update-entity "alias" {:target-key "test:C"})
                (assert (= (map:edge-count) 1)
                        "Identity update should replace the derived map edge")
                (local edge (. map.edges 1))
                (assert (= (and edge edge.source edge.source.key) "test:C")
                        "Derived map edge should follow updated identity target")
                (assert (= (and edge edge.target edge.target.key) "test:B"))
                (identity-store:delete-entity "alias")
                (assert (= (map:edge-count) 0)
                        "Identity delete should remove derived link edges that no longer resolve into this map")
                (map:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(table.insert tests {:name "GraphMap adds and looks up nodes" :fn graph-map-adds-and-looks-up-nodes})
(table.insert tests {:name "GraphMap adds edges" :fn graph-map-adds-edges})
(table.insert tests {:name "GraphMap removes nodes and edges" :fn graph-map-removes-nodes-and-edges})
(table.insert tests {:name "GraphMap emits signals" :fn graph-map-emits-signals})
(table.insert tests {:name "GraphMap mounts nodes with node.graph == graph-map" :fn graph-map-mounts-nodes})
(table.insert tests {:name "GraphMap captures state" :fn graph-map-captures-state})
(table.insert tests {:name "GraphMap restores state" :fn graph-map-restores-state})
(table.insert tests {:name "GraphMap removes nodes without deleting backing objects" :fn graph-map-removes-nodes-without-deleting-backing-objects})
(table.insert tests {:name "Two GraphMaps load same key into separate adapters" :fn two-graph-maps-load-same-key-into-separate-adapters})
(table.insert tests {:name "Removing node from one map does not affect another" :fn removing-node-from-one-map-does-not-affect-another})
(table.insert tests {:name "GraphMap drop unmounts all nodes" :fn graph-map-drop-unmounts-all-nodes})
(table.insert tests {:name "Graph.create-node-by-key creates node without inserting" :fn graph-map-create-node-by-key-works})
(table.insert tests {:name "Graph.create-node-by-key returns nil for unresolvable key" :fn graph-map-create-node-by-key-returns-nil-for-unresolvable-key})
(table.insert tests {:name "GraphMap rejects non-loader-backed nodes" :fn graph-map-rejects-non-loader-backed-node})
(table.insert tests {:name "Shared edge-removed forwards correct payload to map" :fn shared-edge-removed-forwarding})
(table.insert tests {:name "Shared node-replaced creates separate map-local adapter" :fn shared-node-replaced-creates-separate-adapter})
(table.insert tests {:name "Shared edge-added does not auto-load missing endpoints" :fn shared-edge-added-does-not-auto-load-endpoints})
(table.insert tests {:name "Morph only affects maps containing the source key" :fn morph-only-affects-maps-containing-source})
(table.insert tests {:name "Morph loads target when source is in map" :fn morph-loads-target-when-source-is-in-map})
(table.insert tests {:name "Shared node-added does not auto-sync into map" :fn shared-node-added-does-not-auto-sync-into-map})
(table.insert tests {:name "GraphMap refresh-adapters-by-scheme rebuilds visible nodes"
                     :fn graph-map-refresh-adapters-by-scheme-rebuilds-visible-nodes})
(table.insert tests {:name "GraphMap refresh-adapters-by-scheme fails before mutation"
                     :fn graph-map-refresh-adapters-by-scheme-fails-before-mutation})
(table.insert tests {:name "GraphMap capture preserves unresolved restored state" :fn graph-map-capture-preserves-unresolved-restored-state})
(table.insert tests {:name "Shared edge-added forwards edge metadata" :fn shared-edge-added-forwards-metadata})
(table.insert tests {:name "GraphMap capture skips derived link-entity edges" :fn graph-map-capture-skips-derived-link-edges})
(table.insert tests {:name "GraphMap replacement keeps derived _opts on capture" :fn graph-map-replacement-keeps-derived-opts})
(table.insert tests {:name "GraphMap replacement clears derived _opts for explicit edge" :fn graph-map-replacement-clears-derived-opts})
(table.insert tests {:name "GraphMap replacement emits edge-added signal" :fn graph-map-replacement-emits-edge-added})
(table.insert tests {:name "GraphMap allows multiple derived link edges for same endpoints" :fn graph-map-allows-multiple-derived-link-edges-for-same-endpoints})
(table.insert tests {:name "GraphMap direct link store events refresh derived edges with shared events" :fn graph-map-direct-link-store-events-refresh-derived-edges-with-shared-events})
(table.insert tests {:name "GraphMap direct identity events refresh derived link edges" :fn graph-map-direct-identity-events-refresh-derived-link-edges})
(fn graph-map-active-restore-preserves-list-entity-backing-store []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-restore"
                             (.. "rs-list-" (os.time) "-" (do
                                                               (set temp-counter (+ temp-counter 1))
                                                               temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local StringEntityStore (require :entities/string))
                (local ListEntityStore (require :entities/list))
                (local IdentityStore (require :entities/identity))
                (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
                (local list-store (ListEntityStore.ListEntityStore {:base-dir (fs.join-path dir "list")}))
                (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path dir "identity")}))
                (local a (string-store:create-entity {:value "a"}))
                (local b (string-store:create-entity {:value "b"}))
                (local key-a (.. "string-entity:" a.id))
                (local key-b (.. "string-entity:" b.id))
                (local entity (list-store:create-entity {:name "test-list"
                                                         :items [key-a key-b]}))
                (local graph (Graph {:with-start false
                                     :identity-store identity-store}))
                (local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
                (local {:register-loader register-list-loader} (require :graph/nodes/list-entity))
                (register-string-loader graph {:store string-store})
                (register-list-loader graph {:store list-store :identity-store identity-store})
                (local map (GraphMap.GraphMap {:graph graph :id "test-rs-list"}))
                ;; Build active map state with list and items.
                (map:load-by-key key-a)
                (map:load-by-key key-b)
                (local list-key (.. "list-entity:" entity.id))
                (local list-node (map:load-by-key list-key))
                (assert list-node "should load list node in map")
                (local pre-items (. (list-store:get-entity entity.id) :items))
                (assert (= (length (or pre-items [])) 2)
                        "list should have 2 items before restore")
                (assert (= (. pre-items 1) key-a))
                (assert (= (. pre-items 2) key-b))
                ;; Restore with completely different nodes -- unmount/drop must not
                ;; mutate the backing store before node-removed fires.
                (local c (string-store:create-entity {:value "c"}))
                (local key-c (.. "string-entity:" c.id))
                (map:restore-state {:nodes [key-c]
                                    :edges []})
                (assert (map:lookup key-c)
                        "restore-state should load restored nodes")
                (assert (not (map:lookup key-a))
                        "restore-state should clear previous map nodes")
                (local after-items (. (list-store:get-entity entity.id) :items))
                (assert (= (length (or after-items [])) 2)
                        "GraphMap active restore-state should not mutate list-entity backing store")
                (assert (= (. after-items 1) key-a) "items[1] should still be key-a after restore")
                (assert (= (. after-items 2) key-b) "items[2] should still be key-b after restore")
                (map:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn graph-map-active-restore-preserves-notebook-backing-store []
    (var temp-counter 0)
    (local dir (fs.join-path "/tmp/space/tests" "graph-map-restore"
                             (.. "rs-nb-" (os.time) "-" (do
                                                              (set temp-counter (+ temp-counter 1))
                                                              temp-counter))))
    (when (fs.exists dir) (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result)
        (pcall
            (fn []
                (local StringEntityStore (require :entities/string))
                (local NotebookStore (require :notebooks/store))
                (local IdentityStore (require :entities/identity))
                (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
                (local notebook-store (NotebookStore.NotebookStore {:base-dir (fs.join-path dir "notebooks")}))
                (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path dir "identity")}))
                (local a (string-store:create-entity {:value "a"}))
                (local b (string-store:create-entity {:value "b"}))
                (local key-a (.. "string-entity:" a.id))
                (local key-b (.. "string-entity:" b.id))
                (local notebook (notebook-store:create-notebook {:name "test-nb"
                                                                  :items [key-a key-b]}))
                (local graph (Graph {:with-start false
                                     :identity-store identity-store}))
                (local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
                (local {:register-loader register-notebook-loader} (require :graph/nodes/notebook))
                (register-string-loader graph {:store string-store})
                (register-notebook-loader graph {:store notebook-store
                                                  :string-store string-store
                                                  :identity-store identity-store})
                (local map (GraphMap.GraphMap {:graph graph :id "test-rs-nb"}))
                ;; Build active map state with notebook and items.
                (map:load-by-key key-a)
                (map:load-by-key key-b)
                (local notebook-key (.. "notebook:" notebook.id))
                (local notebook-node (map:load-by-key notebook-key))
                (assert notebook-node "should load notebook node in map")
                (local pre-items (. (notebook-store:get-notebook notebook.id) :items))
                (assert (= (length (or pre-items [])) 2)
                        "notebook should have 2 items before restore")
                (assert (= (. pre-items 1) key-a))
                (assert (= (. pre-items 2) key-b))
                ;; Restore with completely different nodes -- unmount/drop must not
                ;; mutate the backing store before node-removed fires.
                (local c (string-store:create-entity {:value "c"}))
                (local key-c (.. "string-entity:" c.id))
                (map:restore-state {:nodes [key-c]
                                    :edges []})
                (assert (map:lookup key-c)
                        "restore-state should load restored nodes")
                (assert (not (map:lookup key-a))
                        "restore-state should clear previous map nodes")
                (local after-items (. (notebook-store:get-notebook notebook.id) :items))
                (assert (= (length (or after-items [])) 2)
                        "GraphMap active restore-state should not mutate notebook backing store")
                (assert (= (. after-items 1) key-a) "items[1] should still be key-a after restore")
                (assert (= (. after-items 2) key-b) "items[2] should still be key-b after restore")
                (map:drop)
                (graph:drop))))
    (fs.remove-all dir)
    (if ok result (error result)))

(fn graph-map-capture-includes-selection-state []
    (local graph (Graph {:with-start false}))
    (register-test-loader graph)
    (local map (GraphMap.GraphMap {:graph graph :id "test-sel-capture"}))
    (local a (Graph.GraphNode {:key "test:a"}))
    (local b (Graph.GraphNode {:key "test:b"}))
    (map:add-node a {})
    (map:add-node b {})
    (set map.selected_node_keys ["test:a" "test:b"])
    (set map.focused_node_key "test:a")
    (local state (map:capture-state))
    (assert (= (type state.selected_node_keys) :table)
            "GraphMap capture-state should include selected_node_keys")
    (assert (= (length state.selected_node_keys) 2)
            "GraphMap capture-state should preserve selected keys")
    (assert (= (. state.selected_node_keys 1) "test:a"))
    (assert (= (. state.selected_node_keys 2) "test:b"))
    (assert (= state.focused_node_key "test:a")
            "GraphMap capture-state should include focused_node_key")
    (map:drop)
    (graph:drop))

(fn graph-map-restore-includes-selection-state []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    (local map (GraphMap.GraphMap {:graph graph :id "test-sel-restore"}))
    (map:restore-state {:nodes ["test:a" "test:b"]
                         :edges []
                         :selected_node_keys ["test:a" "test:b"]
                         :focused_node_key "test:a"})
    (assert (map:lookup "test:a") "Map should have node test:a")
    (assert (map:lookup "test:b") "Map should have node test:b")
    (assert (= (length map.selected_node_keys) 2)
            "GraphMap restore-state should restore selected_node_keys")
    (assert (= (. map.selected_node_keys 1) "test:a"))
    (assert (= (. map.selected_node_keys 2) "test:b"))
    (assert (= map.focused_node_key "test:a")
            "GraphMap restore-state should restore focused_node_key")
    (map:drop)
    (graph:drop))

(fn graph-map-restore-prunes-stale-selected-keys []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
        (fn [key]
            (if (= key "test:a")
                (Graph.GraphNode {:key key})
                nil)))
    (local map (GraphMap.GraphMap {:graph graph :id "test-sel-prune"}))
    (map:restore-state {:nodes ["test:a"]
                         :edges []
                         :selected_node_keys ["test:a" "test:missing"]
                         :focused_node_key "test:missing"})
    (assert (= (length map.selected_node_keys) 1)
            "GraphMap restore-state should prune stale selected keys")
    (assert (= (. map.selected_node_keys 1) "test:a")
            "Only valid key should remain in selected_node_keys")
    (assert (= map.focused_node_key nil)
            "GraphMap restore-state should clear stale focused_node_key")
    (map:drop)
    (graph:drop))

(fn graph-map-remove-nodes-prunes-selection []
    (local graph (Graph {:with-start false}))
    (register-test-loader graph)
    (local map (GraphMap.GraphMap {:graph graph :id "test-rm-sel"}))
    (local a (Graph.GraphNode {:key "test:a"}))
    (local b (Graph.GraphNode {:key "test:b"}))
    (local c (Graph.GraphNode {:key "test:c"}))
    (map:add-node a {})
    (map:add-node b {})
    (map:add-node c {})
    (set map.selected_node_keys ["test:a" "test:b" "test:c"])
    (set map.focused_node_key "test:a")
    (map:remove-nodes [a])
    (assert (= (length map.selected_node_keys) 2)
            "GraphMap remove-nodes should prune removed node from selected_node_keys")
    (assert (= (. map.selected_node_keys 1) "test:b"))
    (assert (= (. map.selected_node_keys 2) "test:c"))
    (assert (= map.focused_node_key nil)
            "GraphMap remove-nodes should clear focused_node_key when focused node is removed")
    (map:drop)
    (graph:drop))

(table.insert tests {:name "GraphMap remove-nodes preserves list-entity backing store" :fn graph-map-remove-nodes-preserves-list-entity-backing-store})
(table.insert tests {:name "GraphMap remove-nodes preserves notebook backing store" :fn graph-map-remove-nodes-preserves-notebook-backing-store})
(table.insert tests {:name "GraphMap shared-delete sync removes list-entity item" :fn graph-map-shared-delete-sync-removes-list-entity-item})
(table.insert tests {:name "GraphMap backing-store delete removes list-entity item" :fn graph-map-store-delete-removes-list-entity-item})
(table.insert tests {:name "GraphMap shared-delete sync removes notebook item" :fn graph-map-shared-delete-sync-removes-notebook-item})
(table.insert tests {:name "GraphMap active restore preserves list-entity backing store" :fn graph-map-active-restore-preserves-list-entity-backing-store})
(table.insert tests {:name "GraphMap active restore preserves notebook backing store" :fn graph-map-active-restore-preserves-notebook-backing-store})
(table.insert tests {:name "GraphMap capture includes selection and focused_node_key" :fn graph-map-capture-includes-selection-state})
(table.insert tests {:name "GraphMap restore includes selection and focused_node_key" :fn graph-map-restore-includes-selection-state})
(table.insert tests {:name "GraphMap restore prunes stale selected keys" :fn graph-map-restore-prunes-stale-selected-keys})
(table.insert tests {:name "GraphMap remove-nodes prunes selection" :fn graph-map-remove-nodes-prunes-selection})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "graph-map" :tests tests})))

{:name "graph-map"
 :tests tests
 :main main}
