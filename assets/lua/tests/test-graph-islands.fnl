(local Graph (require :graph/init))
(local GraphMap (require :graph/map))

(local tests [])

(fn register-test-loader [graph]
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key})))
    graph)

(fn make-map [id]
    (assert id "make-map requires id")
    (local graph (Graph {:with-start false}))
    (register-test-loader graph)
    (local map (GraphMap.GraphMap {:graph graph :id id}))
    {:graph graph :map map})

(fn cleanup [fixture]
    (fixture.map:drop)
    (fixture.graph:drop))

(fn island-record [id members]
    {:id id
     :kind "ordered-list"
     :members members
     :state {:list-key "test:origin" :collapsed false}})

(fn graph-map-upserts-captures-and-restores-islands []
    (local fixture (make-map "island-capture"))
    (local map fixture.map)
    (local created (map:upsert-island (island-record "island-b" ["test:b" "test:c"])))
    (local allocated (map:create-island {:kind "freeform" :members ["test:a"]}))
    (assert (= created.id "island-b") "upsert-island should return created island")
    (assert (= allocated.id "island-1") "create-island should allocate stable id when omitted")
    (set created.state.collapsed true)
    (local stored-created (map:get-island "island-b"))
    (assert (= stored-created.state.collapsed false)
            "returned island should be cloned from stored state")
    (local updated (map:upsert-island {:id "island-b"
                                       :kind "ordered-list"
                                       :members ["test:c" "test:b"]
                                       :state {:list-key "test:origin" :collapsed true}}))
    (assert (= (. updated.members 1) "test:c") "upsert-island should update existing members")
    (local listed (map:list-islands))
    (assert (= (length listed) 2) "list-islands should include both records")
    (assert (= (. listed 1 :id) "island-1") "list-islands should sort by id")
    (assert (= (. listed 2 :id) "island-b") "list-islands should sort by id")
    (local captured (map:capture-state))
    (assert (= captured.next_island_id 2) "capture-state should persist next island id")
    (assert (= (length captured.islands) 2) "capture-state should persist island records")
    (cleanup fixture)
    (local restored-fixture (make-map "island-restore"))
    (local restored-map restored-fixture.map)
    (var added-count 0)
    (restored-map.island-added:connect (fn [_payload] (set added-count (+ added-count 1))))
    (restored-map:restore-state captured)
    (assert (= added-count 2) "restore-state should emit island-added for restored islands")
    (local restored-island (restored-map:get-island "island-b"))
    (assert (= restored-island.state.collapsed true)
            "restore-state should restore updated island state")
    (local restored-allocated (restored-map:create-island {:kind "freeform" :members ["test:z"]}))
    (assert (= restored-allocated.id "island-2")
            "restore-state should restore next island id")
    (cleanup restored-fixture))

(fn graph-map-rejects-invalid-island-records []
    (local fixture (make-map "island-invalid"))
    (local map fixture.map)
    (each [_ record (ipairs [{:id "" :kind "ordered-list" :members ["test:a"]}
                             {:id "island-1" :kind "" :members ["test:a"]}
                             {:id "island-1" :kind "ordered-list" :members []}
                             {:id "island-1" :kind "ordered-list" :members ["test:a" "test:a"]}
                             {:id "island-1" :kind "ordered-list" :members [""]}
                             {:id "island-1" :kind "ordered-list" :members ["test:a"] :state "bad"}])]
        (local (ok _err) (pcall (fn [] (map:create-island record))))
        (assert (not ok) "GraphMap should reject invalid island records"))
    (map:create-island (island-record "island-1" ["test:a"]))
    (local (ok err) (pcall (fn [] (map:create-island (island-record "island-1" ["test:b"])))))
    (assert (not ok) "create-island should reject duplicate ids")
    (assert (string.find (tostring err) "duplicate" 1 true)
            "duplicate id error should explain the conflict")
    (local (update-ok _update-err)
        (pcall (fn [] (map:update-island "island-1" {:kind "other"}))))
    (assert (not update-ok) "update-island should reject kind changes")
    (cleanup fixture))

(fn graph-map-removes-island-without-removing-member-nodes []
    (local fixture (make-map "island-remove-only"))
    (local map fixture.map)
    (map:load-by-key "test:a")
    (map:load-by-key "test:b")
    (map:create-island (island-record "island-1" ["test:a" "test:b"]))
    (local removed (map:remove-island "island-1"))
    (assert (= removed.id "island-1") "remove-island should return removed record")
    (assert (= (map:get-island "island-1") nil) "remove-island should remove island record")
    (assert (map:lookup "test:a") "remove-island should not remove member nodes")
    (assert (map:lookup "test:b") "remove-island should not remove member nodes")
    (cleanup fixture))

(fn graph-map-removes-origin-node-while-island-remains []
    (local fixture (make-map "island-origin-remove"))
    (local map fixture.map)
    (map:load-by-key "test:origin")
    (map:load-by-key "test:a")
    (map:load-by-key "test:b")
    (map:create-island (island-record "island-1" ["test:a" "test:b"]))
    (map:remove-nodes [(map:lookup "test:origin")])
    (local island (map:get-island "island-1"))
    (assert island "removing origin node should not remove island")
    (assert (= island.state.list-key "test:origin")
            "GraphMap should not interpret presenter-owned state while pruning")
    (assert (= (length island.members) 2) "origin removal should not prune member nodes")
    (cleanup fixture))

(fn graph-map-prunes-removed-member-nodes-from-islands []
    (local fixture (make-map "island-member-prune"))
    (local map fixture.map)
    (map:load-by-key "test:a")
    (map:load-by-key "test:b")
    (map:load-by-key "test:c")
    (map:create-island (island-record "island-1" ["test:a" "test:b"]))
    (map:create-island (island-record "island-2" ["test:c"]))
    (map:remove-nodes [(map:lookup "test:b") (map:lookup "test:c")])
    (local remaining (map:get-island "island-1"))
    (assert remaining "island with remaining members should stay")
    (assert (= (length remaining.members) 1) "removed member should be pruned")
    (assert (= (. remaining.members 1) "test:a") "remaining member order should be preserved")
    (assert (= (map:get-island "island-2") nil) "island with no members should be dropped")
    (local valid-keys {})
    (set (. valid-keys "test:a") true)
    (local pruned (map:prune-islands-for-node-keys valid-keys))
    (assert (= (length pruned) 0) "prune-islands-for-node-keys should report no changes when already valid")
    (cleanup fixture))

(fn graph-map-restore-emits-removed-for-replaced-islands []
    (local fixture (make-map "island-restore-removes"))
    (local map fixture.map)
    (map:create-island (island-record "island-old" ["test:a"]))
    (var removed-count 0)
    (var removed-id nil)
    (map.island-removed:connect
        (fn [payload]
            (set removed-count (+ removed-count 1))
            (set removed-id payload.island.id)))
    (map:restore-state {:nodes [] :edges [] :islands []})
    (assert (= removed-count 1) "restore-state should emit island-removed for cleared islands")
    (assert (= removed-id "island-old") "island-removed should identify cleared island")
    (assert (= (map:get-island "island-old") nil)
            "restore-state should remove islands that are absent from restored state")
    (cleanup fixture))

(table.insert tests {:name "GraphMap upserts captures and restores islands" :fn graph-map-upserts-captures-and-restores-islands})
(table.insert tests {:name "GraphMap rejects invalid island records" :fn graph-map-rejects-invalid-island-records})
(table.insert tests {:name "GraphMap removes island without removing member nodes" :fn graph-map-removes-island-without-removing-member-nodes})
(table.insert tests {:name "GraphMap removes origin node while island remains" :fn graph-map-removes-origin-node-while-island-remains})
(table.insert tests {:name "GraphMap prunes removed member nodes from islands" :fn graph-map-prunes-removed-member-nodes-from-islands})
(table.insert tests {:name "GraphMap restore emits removed for replaced islands" :fn graph-map-restore-emits-removed-for-replaced-islands})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "graph-islands" :tests tests})))

{:name "graph-islands"
 :tests tests
 :main main}
