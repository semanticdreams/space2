(local Graph (require :graph/init))
(local fs (require :fs))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "graph-core"))

(fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "graph-core-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
    (local dir (make-temp-dir))
    (when (fs.exists dir)
        (fs.remove-all dir))
    (fs.create-dirs dir)
    (local (ok result) (pcall f dir))
    (fs.remove-all dir)
    (if ok
        result
        (error result)))

(fn make-ext-node-a [key]
    (Graph.GraphNode {:key key :label "a"}))

(fn make-ext-node-b [key]
    (Graph.GraphNode {:key key :label "b"}))

(fn graph-core-adds-nodes-and-edges []
    (local graph (Graph {:with-start false}))
    (local a (Graph.GraphNode {:key "a"}))
    (local b (Graph.GraphNode {:key "b"}))
    (graph:add-node a {})
    (graph:add-node b {})
    (graph:add-edge (Graph.GraphEdge {:source a :target b}))
    (assert (= (graph:node-count) 2) "Graph core should track node count")
    (assert (= (graph:edge-count) 1) "Graph core should track edge count")
    (assert (graph:lookup "a") "Graph core should lookup nodes by key")
    (graph:drop))

(fn graph-core-replaces-node-and-updates-edges []
    (local graph (Graph {:with-start false}))
    (local a (Graph.GraphNode {:key "a"}))
    (local b (Graph.GraphNode {:key "b"}))
    (graph:add-node a {})
    (graph:add-node b {})
    (graph:add-edge (Graph.GraphEdge {:source a :target b}))
    (var replaced nil)
    (local handler (graph.node-replaced:connect (fn [payload]
                                                    (set replaced payload))))
    (local a2 (Graph.GraphNode {:key "a"}))
    (graph:add-node a2 {})
    (assert replaced "Graph core should emit node-replaced")
    (assert (= replaced.old a) "Graph core should report replaced node")
    (assert (= replaced.new a2) "Graph core should report replacement node")
    (local edge (. graph.edges 1))
    (assert (= edge.source a2) "Graph core should update edge source to replacement node")
    (graph.node-replaced:disconnect handler true)
    (graph:drop))

(fn graph-core-removes-nodes-and-edges []
    (local graph (Graph {:with-start false}))
    (local a (Graph.GraphNode {:key "a"}))
    (local b (Graph.GraphNode {:key "b"}))
    (graph:add-node a {})
    (graph:add-node b {})
    (graph:add-edge (Graph.GraphEdge {:source a :target b}))
    (var removed nil)
    (var edge-removed 0)
    (local node-handler (graph.node-removed:connect (fn [payload]
                                                        (set removed payload))))
    (local edge-handler (graph.edge-removed:connect (fn [_payload]
                                                        (set edge-removed (+ edge-removed 1)))))
    (local count (graph:remove-nodes [b]))
    (assert (= count 1) "Graph core should report removed nodes")
    (assert removed "Graph core should emit node-removed payload")
    (assert (= (length removed.nodes) 1) "Graph core should include removed node list")
    (assert (rawget removed.removal-set b) "Graph core should include removal set")
    (assert (= edge-removed 1) "Graph core should emit edge-removed for connected edges")
    (assert (= (graph:edge-count) 0) "Graph core should remove edges when nodes are removed")
    (graph.node-removed:disconnect node-handler true)
    (graph.edge-removed:disconnect edge-handler true)
    (graph:drop))

(fn graph-core-emits-node-and-edge-added []
    (local graph (Graph {:with-start false}))
    (var node-added 0)
    (var edge-added 0)
    (local node-handler (graph.node-added:connect (fn [_payload]
                                                      (set node-added (+ node-added 1)))))
    (local edge-handler (graph.edge-added:connect (fn [_payload]
                                                      (set edge-added (+ edge-added 1)))))
    (local a (Graph.GraphNode {:key "a"}))
    (local b (Graph.GraphNode {:key "b"}))
    (graph:add-node a {})
    (graph:add-edge (Graph.GraphEdge {:source a :target b}))
    (assert (= node-added 2) "Graph core should emit node-added for source and target")
    (assert (= edge-added 1) "Graph core should emit edge-added")
    (graph.node-added:disconnect node-handler true)
    (graph.edge-added:disconnect edge-handler true)
    (graph:drop))

(fn graph-core-resolves-identity-key-to-target []
    (with-temp-dir
        (fn [dir]
            (local IdentityStore (require :entities/identity))
            (local store (IdentityStore.IdentityStore {:base-dir dir}))
            (local entity (store:create-entity {:id "id-a"
                                                :target-key "target-a"}))
            (local {:IdentityNode IdentityNode} (require :graph/nodes/identity))
            (local graph (Graph {:with-start false
                                 :identity-store store}))
            (local target (Graph.GraphNode {:key "target-a"}))
            (local identity (IdentityNode {:entity-id entity.id
                                           :store store}))
            (graph:add-node target {})
            (graph:add-node identity {})
            (local resolved (graph:resolve-key "identity:id-a"))
            (assert (= resolved "target-a")
                    "Graph core should resolve identity key to target key")
            (graph:drop))))

(fn graph-core-link-edges-resolve-identity-endpoints []
    (with-temp-dir
        (fn [dir]
            (local IdentityStore (require :entities/identity))
            (local LinkEntityStore (require :entities/link))
            (local identity-store (IdentityStore.IdentityStore {:base-dir dir}))
            (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
            (local identity (identity-store:create-entity {:id "id-link"
                                                           :target-key "a"}))
            (link-store:create-entity {:id "edge-1"
                                       :source-key (.. "identity:" identity.id)
                                       :target-key "b"})
            (local {:IdentityNode IdentityNode} (require :graph/nodes/identity))
            (local graph (Graph {:with-start false
                                 :link-store link-store
                                 :identity-store identity-store}))
            (local node-a (Graph.GraphNode {:key "a"}))
            (local node-b (Graph.GraphNode {:key "b"}))
            (local identity-node (IdentityNode {:entity-id identity.id
                                                :store identity-store}))
            (graph:add-node node-a {})
            (graph:add-node node-b {})
            (graph:add-node identity-node {})
            (assert (= (graph:edge-count) 1)
                    "Link edge should be created for identity-backed endpoint")
            (local edge (. graph.edges 1))
            (assert (= edge.source node-a)
                    "Link edge source should resolve through identity target")
            (assert (= edge.target node-b)
                    "Link edge target should remain direct endpoint")
            (graph:drop))))

(fn graph-core-create-identity-creates-node-and-resolves []
    (with-temp-dir
        (fn [dir]
            (local IdentityStore (require :entities/identity))
            (local identity-store (IdentityStore.IdentityStore {:base-dir dir}))
            (local graph (Graph {:with-start false
                                 :identity-store identity-store}))
            (local target (Graph.GraphNode {:key "target-create"}))
            (graph:add-node target {})
            (local identity-node (graph:create-identity "target-create"))
            (assert identity-node "create-identity should return a node")
            (assert (string.find identity-node.key "identity:" 1 true)
                    "create-identity should create identity key")
            (local resolved (graph:resolve-key identity-node.key))
            (assert (= resolved "target-create")
                    "create-identity node should resolve to target key")
            (graph:drop))))

(fn graph-core-ensure-identity-key-reuses-existing-identity []
    (with-temp-dir
        (fn [dir]
            (local IdentityStore (require :entities/identity))
            (local identity-store (IdentityStore.IdentityStore {:base-dir dir}))
            (local graph (Graph {:with-start false
                                 :identity-store identity-store}))
            (local key-1 (graph:ensure-identity-key "target-z"))
            (local key-2 (graph:ensure-identity-key "target-z"))
            (assert (= key-1 key-2)
                    "ensure-identity-key should reuse identity for same target")
            (local entities (identity-store:list-entities))
            (assert (= (length entities) 1)
                    "ensure-identity-key should create only one identity entity per target")
            (graph:drop))))

(fn graph-core-captures-state []
    (local graph (Graph {:with-start false}))
    (local a (Graph.GraphNode {:key "a"}))
    (local b (Graph.GraphNode {:key "b"}))
    (graph:add-node a {})
    (graph:add-edge (Graph.GraphEdge {:source a
                                      :target b}))
    (local state (graph:capture-state))
    (assert (= (length state.nodes) 2) "Graph capture-state should include both nodes")
    (assert (= (. state.nodes 1) "a"))
    (assert (= (. state.nodes 2) "b"))
    (assert (= (length state.edges) 1) "Graph capture-state should include one edge")
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :source)) "a"))
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :target)) "b"))
    (graph:drop))

(fn graph-core-restores-state []
    (local graph (Graph {:with-start false}))
    (local created {})
    (graph:register-key-loader "test"
      (fn [key]
        (set (. created key) true)
        (Graph.GraphNode {:key key})))
    (graph:restore-state {:nodes ["test:a" "test:b"]
                          :edges [{:source "test:a"
                                   :target "test:b"}]})
    (assert (graph:lookup "test:a") "Graph restore-state should load source node")
    (assert (graph:lookup "test:b") "Graph restore-state should load target node")
    (assert (= (graph:edge-count) 1) "Graph restore-state should recreate edges")
    (assert (. created "test:a"))
    (assert (. created "test:b"))
    (graph:drop))

(fn graph-core-restore-skips-unresolved-nodes []
    (local graph (Graph {:with-start false}))
    (graph:restore-state {:nodes ["unknown-scheme:item"]
                          :edges []})
    (assert (= (graph:node-count) 0)
            "Graph restore-state should skip unresolved nodes")
    (assert (= (graph:edge-count) 0)
            "Graph restore-state should not create edges for unresolved nodes")
    (graph:drop))

(fn graph-core-restore-skips-edges-with-unresolved-endpoints []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
      (fn [key]
        (Graph.GraphNode {:key key})))
    (graph:restore-state {:nodes ["test:a" "missing-scheme:b"]
                          :edges [{:source "test:a"
                                   :target "missing-scheme:b"}
                                  {:source "missing-scheme:b"
                                   :target "test:a"}]})
    (assert (graph:lookup "test:a")
            "Graph restore-state should still load resolvable nodes")
    (assert (= (graph:edge-count) 0)
            "Graph restore-state should skip edges with unresolved endpoints")
    (graph:drop))

(fn graph-core-capture-preserves-unresolved-restored-state []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "test"
      (fn [key]
        (if (= key "test:a")
            (Graph.GraphNode {:key key})
            nil)))
    (graph:restore-state {:nodes ["test:a" "test:missing"]
                          :edges [{:source "test:a"
                                   :target "test:missing"}]})
    (local state (graph:capture-state))
    (assert (= (length state.nodes) 2)
            "Graph capture-state should retain unresolved restored nodes")
    (assert (= (. state.nodes 1) "test:a"))
    (assert (= (. state.nodes 2) "test:missing"))
    (assert (= (length state.edges) 1)
            "Graph capture-state should retain unresolved restored edges")
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :source)) "test:a"))
    (assert (= (and (. state.edges 1) (. (. state.edges 1) :target)) "test:missing"))
    (graph:drop))

(fn graph-core-key-loader-handle-unregisters-owner-loader []
    (local graph (Graph {:with-start false}))
    (local handle
        (graph:register-key-loader "ext" make-ext-node-a {:owner-id "unit-a"}))
    (assert handle "register-key-loader should return a handle")
    (assert (= handle.scheme "ext") "Handle should include scheme")
    (assert (= handle.owner-id "unit-a") "Handle should include owner-id")
    (assert (= (graph:key-loader-owner "ext") "unit-a")
            "Graph should report key-loader owner")
    (assert (graph:has-key-loader-for-key "ext:item")
            "Registered loader should resolve matching keys")
    (assert (graph:unregister-key-loader handle)
            "Unregistering active handle should succeed")
    (assert (= (graph:key-loader-owner "ext") nil)
            "Unregistering handle should remove owner")
    (assert (not (graph:has-key-loader-for-key "ext:item"))
            "Unregistering handle should remove loader")
    (assert (graph:unregister-key-loader handle)
            "Unregistering the same inactive handle should be idempotent")
    (graph:drop))

(fn graph-core-key-loader-duplicate-active-loader-fails []
    (local graph (Graph {:with-start false}))
    (graph:register-key-loader "ext" make-ext-node-a {:owner-id "unit-a"})
    (local (ok err)
        (pcall #(graph:register-key-loader "ext" make-ext-node-b {:owner-id "unit-b"})))
    (assert (not ok) "Duplicate active loader registration should fail")
    (assert (string.find (tostring err) "duplicate scheme: ext" 1 true)
            "Duplicate active loader error should name the scheme")
    (graph:drop))

(fn graph-core-key-loader-stale-handle-cannot-remove-new-owner []
    (local graph (Graph {:with-start false}))
    (local handle-a
        (graph:register-key-loader "ext" make-ext-node-a {:owner-id "unit-a"}))
    (graph:unregister-key-loader handle-a)
    (graph:register-key-loader "ext" make-ext-node-b {:owner-id "unit-b"})
    (local (ok err) (pcall #(graph:unregister-key-loader handle-a)))
    (assert (not ok) "stale handle should not remove another owner registration")
    (assert (string.find (tostring err) "belongs to another registration" 1 true))
    (assert (= (graph:key-loader-owner "ext") "unit-b")
            "Stale unregister must not remove the newer owner")
    (graph:drop))

(table.insert tests {:name "Graph core adds nodes and edges" :fn graph-core-adds-nodes-and-edges})
(table.insert tests {:name "Graph core replaces nodes and updates edges" :fn graph-core-replaces-node-and-updates-edges})
(table.insert tests {:name "Graph core removes nodes and edges" :fn graph-core-removes-nodes-and-edges})
(table.insert tests {:name "Graph core emits node and edge added signals" :fn graph-core-emits-node-and-edge-added})
(table.insert tests {:name "Graph core resolves identity key to target" :fn graph-core-resolves-identity-key-to-target})
(table.insert tests {:name "Graph core link edges resolve identity endpoints" :fn graph-core-link-edges-resolve-identity-endpoints})
(table.insert tests {:name "Graph core create-identity creates node and resolves" :fn graph-core-create-identity-creates-node-and-resolves})
(table.insert tests {:name "Graph core ensure-identity-key reuses existing identity" :fn graph-core-ensure-identity-key-reuses-existing-identity})
(table.insert tests {:name "Graph core captures node and edge state" :fn graph-core-captures-state})
(table.insert tests {:name "Graph core restores node and edge state" :fn graph-core-restores-state})
(table.insert tests {:name "Graph core restore skips unresolved nodes"
                     :fn graph-core-restore-skips-unresolved-nodes})
(table.insert tests {:name "Graph core restore skips edges with unresolved endpoints"
                     :fn graph-core-restore-skips-edges-with-unresolved-endpoints})
(table.insert tests {:name "Graph core capture preserves unresolved restored state"
                      :fn graph-core-capture-preserves-unresolved-restored-state})
(table.insert tests {:name "Graph core key-loader handle unregisters owner loader"
                     :fn graph-core-key-loader-handle-unregisters-owner-loader})
(table.insert tests {:name "Graph core key-loader duplicate active loader fails"
                     :fn graph-core-key-loader-duplicate-active-loader-fails})
(table.insert tests {:name "Graph core key-loader stale handle cannot remove new owner"
                     :fn graph-core-key-loader-stale-handle-cannot-remove-new-owner})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-core"
                       :tests tests})))

{:name "graph-core"
 :tests tests
 :main main}
