(local glm (require :glm))
(local fs (require :fs))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local GraphView (require :graph/view/init))
(local BuildContext (require :build-context))
(local JsonUtils (require :json-utils))
(local StringEntityStore (require :entities/string))
(local ListEntityStore (require :entities/list))
(local IdentityStore (require :entities/identity))
(local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
(local {:register-loader register-list-loader} (require :graph/nodes/list-entity))
(local {:FocusManager FocusManager} (require :focus))
(local {:Layout Layout :LayoutRoot LayoutRoot} (require :layout))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "graph-view-islands"))

(fn assert-close [actual expected message]
    (assert (< (math.abs (- actual expected)) 1e-5)
            (or message (string.format "expected %s to equal %s" actual expected))))

(fn assert-vec3 [actual expected message]
    (assert actual (or message "expected vec3, got nil"))
    (assert-close actual.x expected.x (.. (or message "vec3") " x"))
    (assert-close actual.y expected.y (.. (or message "vec3") " y"))
    (assert-close actual.z expected.z (.. (or message "vec3") " z")))

(fn make-temp-dir []
    (set temp-counter (+ temp-counter 1))
    (fs.join-path temp-root (.. "case-" (os.time) "-" temp-counter)))

(fn make-icons-stub []
    (local glyph {:advance 1})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {65533 glyph 4242 glyph}})
    (local stub {:font font
                 :codepoints {:open_in_new 4242
                               :content_copy 4242
                               :open_in_full 4242
                               :close_fullscreen 4242
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
    (local focus-manager (FocusManager {:root-name "test-graph-view-islands"}))
    (local focus-scope (focus-manager:create-scope {:name "graph-view-islands"}))
    (local layout-root (LayoutRoot {:log-dirt? false}))
    (local ctx
        (BuildContext {:layout-root layout-root
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

(fn island-preview-measurer [self]
    (set self.measure (glm.vec3 40 24 0)))

(fn island-preview-constrained-measurer [self _constraints]
    (set self.measure (glm.vec3 40 24 0)))

(fn island-preview-layouter [_self]
    nil)

(fn build-island-preview [_ctx]
    (local widget {})
    (local layout (Layout {:name "graph-view-island-preview"
                          :measurer island-preview-measurer
                          :constrained-measurer island-preview-constrained-measurer
                          :layouter island-preview-layouter}))
    (set widget.layout layout)
    (set widget.drop (fn [_self] (layout:drop)))
    widget)

(fn make-preview []
    (fn preview-factory [_node _opts]
        build-island-preview))

(fn register-test-loader [graph]
    (graph:register-key-loader "test"
        (fn [key]
            (Graph.GraphNode {:key key
                              :label key
                              :size 10
                              :color (glm.vec4 0.4 0.6 1 1)
                              :preview (make-preview)})))
    graph)

(fn make-movables-stub []
    (local entries [])
    (local by-node {})
    {:entries entries
     :by-node by-node
     :register (fn [_self _point entry]
                 (table.insert entries entry)
                 (set (. by-node entry.key) entry))
     :unregister (fn [_self node]
                   (set (. by-node node) nil))})

(fn option-value [options key default]
    (if (not (= (. options key) nil))
        (. options key)
        default))

(fn island-record [opts]
    (local options (if opts opts {}))
    {:id (option-value options :id "island-1")
     :kind (option-value options :kind "ordered-list")
     :members (option-value options :members ["test:a" "test:b"])
     :state (option-value options :state {:position (glm.vec3 100 200 0)
                                          :spacing 12})})

(fn check-applies-ordered-list-island-positions [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (assert view.island-host "GraphView should expose island-host")
    (assert-vec3 (view:get-position (map:lookup "test:a")) (glm.vec3 50 75 2)
                 "first member should use island origin")
    (assert-vec3 (view:get-position (map:lookup "test:b")) (glm.vec3 50 55 2)
                 "second member should be vertically offset")
    (assert (. view.pinned (map:lookup "test:a")) "first member should be pinned by island")
    (assert (. view.pinned (map:lookup "test:b")) "second member should be pinned by island"))

(fn check-updates-island-layout-when-island-changes [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (map:update-island "island-1" {:state {:position (glm.vec3 30 60 1)
                                           :spacing 5}})
    (assert-vec3 (view:get-position (map:lookup "test:a")) (glm.vec3 30 60 1)
                 "updated origin should move first member")
    (assert-vec3 (view:get-position (map:lookup "test:b")) (glm.vec3 30 55 1)
                 "updated spacing should move second member"))

(fn label-position-for-node [view node]
    (local span (. view.labels.labels node))
    (assert span "expected label span for node")
    (assert span.layout "expected label span layout")
    span.layout.position)

(fn check-refreshes-labels-after-island-update [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (view:update 0.016)
    (local before-label (label-position-for-node view node-a))
    (local before-node (view:get-position node-a))
    (map:update-island "island-1" {:state {:position (glm.vec3 80 90 0)
                                           :spacing 10}})
    (local after-label (label-position-for-node view node-a))
    (local after-node (view:get-position node-a))
    (local node-delta (- after-node before-node))
    (local expected-label (+ before-label node-delta))
    (assert-vec3 after-label expected-label
                 "label should move with node after island update reconciliation"))

(fn no-op-fixture [_fixture]
    nil)

(fn check-unpins-members-after-island-removal [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (local node-b (map:lookup "test:b"))
    (assert (. view.pinned node-a) "fixture should start with first member pinned")
    (assert (. view.pinned node-b) "fixture should start with second member pinned")
    (map:remove-island "island-1")
    (assert (not (. view.pinned node-a)) "first member should unpin after island removal")
    (assert (not (. view.pinned node-b)) "second member should unpin after island removal"))

(fn check-preserves-expanded-member-pin-after-island-removal [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (local point-a (. view.points node-a))
    (assert point-a "fixture should have first member point")
    (assert point-a.on-double-click "fixture point should expose double-click expansion")
    (point-a:on-double-click {})
    (assert (. (. view.points node-a) :_card-size) "member should expand into a card")
    (assert (. view.pinned node-a) "expanded member should be pinned before island removal")
    (map:remove-island "island-1")
    (assert (. view.pinned node-a) "expanded member should remain pinned after island removal"))

(fn check-unpins-expanded-member-after-island-removal-and-collapse [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (local point-a (. view.points node-a))
    (assert point-a "fixture should have first member point")
    (point-a:on-double-click {})
    (local card (. view.points node-a))
    (assert card._card-size "member should expand into a card")
    (map:remove-island "island-1")
    (assert (. view.pinned node-a) "expanded member should stay pinned until collapse")
    (local collapse-button (. card.header-bar.children 4 :element))
    (assert collapse-button "expanded card should expose collapse button")
    (collapse-button:on-click {})
    (assert (not (. view.pinned node-a))
            "member should unpin after island removal and expanded-card collapse"))

(fn check-clears-expanded-pin-reason-before-later-island-removal [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (local point-a (. view.points node-a))
    (assert point-a "fixture should have first member point")
    (point-a:on-double-click {})
    (local card (. view.points node-a))
    (assert card._card-size "member should expand into a card")
    (map:create-island (island-record {:id "island-1" :members ["test:a"]}))
    (map:remove-island "island-1")
    (assert (. view.pinned node-a) "expanded member should remain pinned after first island removal")
    (local collapse-button (. card.header-bar.children 4 :element))
    (assert collapse-button "expanded card should expose collapse button")
    (collapse-button:on-click {})
    (assert (not (. view.pinned node-a))
            "collapsed member should release the expanded-card pin")
    (map:create-island (island-record {:id "island-2" :members ["test:a"]}))
    (assert (. view.pinned node-a) "second island should pin member while present")
    (map:remove-island "island-2")
    (assert (not (. view.pinned node-a))
            "second island removal should not restore stale expanded-card pin ownership"))

(fn check-removes-island-member-node-without-pin-cleanup-error [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local node-a (map:lookup "test:a"))
    (assert (. view.pinned node-a) "fixture should start with removed member pinned")
    (local (ok err) (pcall (fn [] (map:remove-nodes [node-a]))))
    (assert ok (.. "removing island member should not fail: " (tostring err)))
    (assert (not (map:lookup "test:a")) "removed node should leave graph map")
    (assert (not (. view.pinned node-a)) "removed member should not remain pinned in view"))

(fn check-snaps-island-member-back-after-drag-end [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local node-a (map:lookup "test:a"))
    (local entry (. movables.by-node node-a))
    (assert entry "movable entry should be registered for island member")
    (entry.target:set-position (glm.vec3 400 500 0))
    (assert-vec3 (view:get-position node-a) (glm.vec3 400 500 0)
                 "drag should move member before drag end")
    (entry.on-drag-end entry)
    (assert-vec3 (view:get-position node-a) (glm.vec3 5 6 0)
                 "drag end should reconcile island and snap member back"))

(fn check-list-created-island-preserves-body-position-after-unrelated-drag-end [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local unrelated-node (map:lookup fixture.unrelated-key))
    (local list-entry (. movables.by-node list-node))
    (local item-entry (. movables.by-node item-node))
    (local unrelated-entry (. movables.by-node unrelated-node))
    (assert list-entry "list node should be movable")
    (assert item-entry "list item should be movable")
    (assert unrelated-entry "unrelated node should be movable")
    (list-entry.target:set-position (glm.vec3 24 0 0))
    (assert-vec3 (view:get-position list-node) (glm.vec3 24 0 0)
                 "fixture should place list node at non-origin position")
    (assert (. map.presentation-points list-node.key) "graph map should expose GraphView presentation point")
    (list-node:expand-items-as-island)
    (local island (map:get-island "ordered-list:list"))
    (assert (= (. island.state.position 1) 48)
            (.. "island body x should initialize near list node, got " (. island.state.position 1)))
    (list-entry.target:set-position (glm.vec3 500 0 0))
    (assert-vec3 (view:get-position list-node) (glm.vec3 500 0 0)
                 "source list node should be allowed to move after island creation")
    (item-entry.target:set-position (glm.vec3 300 400 0))
    (unrelated-entry.on-drag-end unrelated-entry)
    (local reconciled-position (view:get-position item-node))
    (assert-vec3 reconciled-position (glm.vec3 48 0 0)
                 "unrelated drag-end reconciliation should use stored island body position")
    (local list-position (view:get-position list-node))
    (assert (not (and (= reconciled-position.x (+ list-position.x 24))
                      (= reconciled-position.y list-position.y)
                      (= reconciled-position.z list-position.z)))
            "first list island member should not be recomputed from current list node position"))

(fn check-restored-old-format-list-island-uses-member-fallback-after-drag-end [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local unrelated-node (map:lookup fixture.unrelated-key))
    (local unrelated-entry (. movables.by-node unrelated-node))
    (assert unrelated-entry "unrelated node should be movable")
    (assert-vec3 (view:get-position list-node) (glm.vec3 24 0 0)
                 "restored fixture should materialize list node at non-origin position")
    (assert (map:get-island "ordered-list:list")
            "restored fixture should have old-format ordered-list island")
    (unrelated-entry.on-drag-end unrelated-entry)
    (local list-position (view:get-position list-node))
    (local item-position (view:get-position item-node))
    (assert-vec3 item-position (glm.vec3 300 400 0)
                 "old-format island without body position should fall back to member position")
    (assert (not (and (= item-position.x list-position.x)
                      (= item-position.y list-position.y)
                      (= item-position.z list-position.z)))
            "restored old-format island first member should not overlap list node after unrelated drag-end"))

(fn check-alt-dragging-second-island-member-moves-whole-island-on-drag-end [fixture]
    (local map fixture.map)
    (local view fixture.view)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local item-node (map:lookup fixture.item-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local list-entry (. movables.by-node list-node))
    (local second-entry (. movables.by-node second-node))
    (list-entry.target:set-position (glm.vec3 24 0 0))
    (list-node:expand-items-as-island)
    (second-entry.on-drag-start second-entry {} {:mod 256})
    (second-entry.target:set-position (glm.vec3 200 300 0))
    (assert-vec3 (view:get-position item-node) (glm.vec3 48 0 0)
                 "other members should not live-move during alt drag")
    (second-entry.on-drag-end second-entry {})
    (local island (map:get-island "ordered-list:list"))
    (assert (= (. island.state.position 1) 200) "island body x should update from second member drop")
    (assert (= (. island.state.position 2) 324) "island body y should keep second member at drop")
    (assert-vec3 (view:get-position item-node) (glm.vec3 200 324 0)
                 "first member should move to new island body")
    (assert-vec3 (view:get-position second-node) (glm.vec3 200 300 0)
                 "dragged second member should stay at dropped position after reconcile"))

(fn check-alt-drag-end-clears-state-before-visible-update-failure [fixture]
    (local map fixture.map)
    (local movables fixture.movables)
    (local list-node (map:lookup fixture.list-key))
    (local second-node (map:lookup fixture.second-item-key))
    (local list-entry (. movables.by-node list-node))
    (local second-entry (. movables.by-node second-node))
    (list-entry.target:set-position (glm.vec3 24 0 0))
    (list-node:expand-items-as-island)
    (set map.update-island false)
    (second-entry.on-drag-start second-entry {} {:mod 256})
    (second-entry.target:set-position (glm.vec3 200 300 0))
    (local (failed? err) (pcall (fn [] (second-entry.on-drag-end second-entry {}))))
    (assert (not failed?) "alt drag end should still fail visibly when update-island is missing")
    (assert (string.find (tostring err) "GraphView island member alt-drag requires GraphMap.update-island" 1 true)
            "failure should explain missing update-island")
    (local (cleared? second-err) (pcall (fn [] (second-entry.on-drag-end second-entry {}))))
    (assert cleared? (.. "drag state should clear before visible update failure: " (tostring second-err))))

(fn with-fixture [opts f]
    (local options (or opts {}))
    (local dir (make-temp-dir))
    (when (fs.exists dir)
        (fs.remove-all dir))
    (fs.create-dirs dir)
    (local graph (register-test-loader (Graph {:with-start false})))
    (local map (GraphMap.GraphMap {:graph graph :id (or options.map-id "islands")}))
    (each [_ key (ipairs (or options.keys ["test:a" "test:b" "test:c"]))]
        (map:load-by-key key))
    (when options.island
        (map:create-island options.island))
    (local ctx (make-ctx))
    (local movables (make-movables-stub))
    (var view nil)
    (local (ok result)
        (pcall
            (fn []
                (set view (GraphView {:graph-map map
                                      :ctx ctx
                                      :data-dir dir
                                      :movables movables}))
                (f {:graph graph :map map :view view :movables movables :dir dir}))))
    (when view
        (view:drop))
    (map:drop)
    (graph:drop)
    (fs.remove-all dir)
    (if ok
        result
        (error result)))

(fn with-list-fixture [maybe-opts maybe-f]
    (local options (if (= (type maybe-opts) :function) {} (or maybe-opts {})))
    (local f (if (= (type maybe-opts) :function) maybe-opts maybe-f))
    (assert (= (type f) :function) "with-list-fixture requires callback")
    (local dir (make-temp-dir))
    (when (fs.exists dir)
        (fs.remove-all dir))
    (fs.create-dirs dir)
    (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
    (local list-store (ListEntityStore.ListEntityStore {:base-dir (fs.join-path dir "list")}))
    (local identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path dir "identity")}))
    (local graph (Graph {:with-start false :identity-store identity-store}))
    (register-string-loader graph {:store string-store})
    (register-list-loader graph {:store list-store :identity-store identity-store})
    (local map (GraphMap.GraphMap {:graph graph :id "graph-view-list-islands"}))
    (local item (string-store:create-entity {:id "item-a" :value "A"}))
    (local item-b (string-store:create-entity {:id "item-b" :value "B"}))
    (local unrelated (string-store:create-entity {:id "unrelated" :value "Unrelated"}))
    (local list (list-store:create-entity {:id "list"
                                           :name "List"
                                           :items [(.. "string-entity:" item.id)
                                                   (.. "string-entity:" item-b.id)]}))
    (local list-key (.. "list-entity:" list.id))
    (local item-key (.. "string-entity:" item.id))
    (local second-item-key (.. "string-entity:" item-b.id))
    (local unrelated-key (.. "string-entity:" unrelated.id))
    (map:load-by-key list-key)
    (map:load-by-key item-key)
    (map:load-by-key second-item-key)
    (map:load-by-key unrelated-key)
    (when options.restore-state
        (map:restore-state options.restore-state))
    (when options.persisted-positions
        (local graph-dir (fs.join-path (fs.join-path (fs.join-path dir "graph") "maps") "graph-view-list-islands"))
        (fs.create-dirs graph-dir)
        (JsonUtils.write-json! (fs.join-path graph-dir "metadata.json")
                               {:positions options.persisted-positions}))
    (local ctx (make-ctx))
    (local movables (make-movables-stub))
    (var view nil)
    (local (ok result)
        (pcall
            (fn []
                (set view (GraphView {:graph-map map
                                      :ctx ctx
                                      :data-dir dir
                                      :movables movables}))
                (f {:graph graph
                    :map map
                    :view view
                    :movables movables
                     :dir dir
                     :list-key list-key
                     :item-key item-key
                     :second-item-key second-item-key
                     :unrelated-key unrelated-key}))))
    (when view
        (view:drop))
    (map:drop)
    (graph:drop)
    (fs.remove-all dir)
    (if ok
        result
        (error result)))

(fn graph-view-applies-ordered-list-island-positions []
    (with-fixture {:island (island-record {:state {:position (glm.vec3 50 75 2)
                                                   :spacing 20}})}
        check-applies-ordered-list-island-positions))

(fn graph-view-updates-island-layout-when-island-changes []
    (with-fixture {:island (island-record {:state {:position (glm.vec3 10 20 0)
                                                   :spacing 10}})}
        check-updates-island-layout-when-island-changes))

(fn graph-view-refreshes-labels-after-island-update []
    (with-fixture {:island (island-record {:state {:position (glm.vec3 10 20 0)
                                                   :spacing 10}})}
        check-refreshes-labels-after-island-update))

(fn graph-view-fails-visibly-for-missing-island-presenter []
    (local (ok err)
        (pcall
            (fn []
                (with-fixture {:island (island-record {:kind "missing-kind"
                                                       :members ["test:a"]})}
                    no-op-fixture))))
    (assert (not ok) "GraphView should fail when no island presenter exists")
    (assert (string.find (tostring err) "missing graph island presenter kind: missing-kind" 1 true)
            "missing presenter error should include island kind"))

(fn graph-view-unpins-members-after-island-removal []
    (with-fixture {:island (island-record {})}
        check-unpins-members-after-island-removal))

(fn graph-view-preserves-expanded-member-pin-after-island-removal []
    (with-fixture {:island (island-record {})}
        check-preserves-expanded-member-pin-after-island-removal))

(fn graph-view-unpins-expanded-member-after-island-removal-and-collapse []
    (with-fixture {:island (island-record {})}
        check-unpins-expanded-member-after-island-removal-and-collapse))

(fn graph-view-clears-expanded-pin-reason-before-later-island-removal []
    (with-fixture {}
        check-clears-expanded-pin-reason-before-later-island-removal))

(fn graph-view-removes-island-member-node-without-pin-cleanup-error []
    (with-fixture {:island (island-record {})}
        check-removes-island-member-node-without-pin-cleanup-error))

(fn graph-view-snaps-island-member-back-after-drag-end []
    (with-fixture {:island (island-record {:state {:position (glm.vec3 5 6 0)
                                                   :spacing 7}})}
        check-snaps-island-member-back-after-drag-end))

(fn graph-view-list-created-island-preserves-body-position-after-unrelated-drag-end []
    (with-list-fixture
        check-list-created-island-preserves-body-position-after-unrelated-drag-end))

(fn graph-view-restored-old-format-list-island-uses-member-fallback-after-drag-end []
    (with-list-fixture
        {:restore-state {:nodes ["list-entity:list" "string-entity:item-a" "string-entity:unrelated"]
                         :edges []
                         :islands [{:id "ordered-list:list"
                                    :kind "ordered-list"
                                    :members ["string-entity:item-a"]
                                    :state {:list-key "list-entity:list"
                                            :spacing 24}}]}
         :persisted-positions {"list-entity:list" [24 0 0]
                                "string-entity:item-a" [300 400 0]
                                 "string-entity:unrelated" [-100 -100 0]}}
        check-restored-old-format-list-island-uses-member-fallback-after-drag-end))

(fn graph-view-alt-dragging-second-island-member-moves-whole-island-on-drag-end []
    (with-list-fixture
        check-alt-dragging-second-island-member-moves-whole-island-on-drag-end))

(fn graph-view-alt-drag-end-clears-state-before-visible-update-failure []
    (with-list-fixture
        check-alt-drag-end-clears-state-before-visible-update-failure))

(table.insert tests {:name "GraphView applies ordered-list island positions"
                     :fn graph-view-applies-ordered-list-island-positions})
(table.insert tests {:name "GraphView updates island layout when island changes"
                     :fn graph-view-updates-island-layout-when-island-changes})
(table.insert tests {:name "GraphView refreshes labels after island update"
                     :fn graph-view-refreshes-labels-after-island-update})
(table.insert tests {:name "GraphView fails visibly for missing island presenter"
                     :fn graph-view-fails-visibly-for-missing-island-presenter})
(table.insert tests {:name "GraphView unpins members after island removal"
                     :fn graph-view-unpins-members-after-island-removal})
(table.insert tests {:name "GraphView preserves expanded member pin after island removal"
                     :fn graph-view-preserves-expanded-member-pin-after-island-removal})
(table.insert tests {:name "GraphView unpins expanded member after island removal and collapse"
                     :fn graph-view-unpins-expanded-member-after-island-removal-and-collapse})
(table.insert tests {:name "GraphView clears expanded pin reason before later island removal"
                     :fn graph-view-clears-expanded-pin-reason-before-later-island-removal})
(table.insert tests {:name "GraphView removes island member node without pin cleanup error"
                     :fn graph-view-removes-island-member-node-without-pin-cleanup-error})
(table.insert tests {:name "GraphView snaps island member back after drag end"
                     :fn graph-view-snaps-island-member-back-after-drag-end})
(table.insert tests {:name "GraphView list-created island preserves body position after unrelated drag end"
                     :fn graph-view-list-created-island-preserves-body-position-after-unrelated-drag-end})
(table.insert tests {:name "GraphView restored old-format list island uses member fallback after unrelated drag end"
                     :fn graph-view-restored-old-format-list-island-uses-member-fallback-after-drag-end})
(table.insert tests {:name "GraphView alt-dragging second island member moves whole island on drag end"
                     :fn graph-view-alt-dragging-second-island-member-moves-whole-island-on-drag-end})
(table.insert tests {:name "GraphView alt drag end clears state before visible update failure"
                     :fn graph-view-alt-drag-end-clears-state-before-visible-update-failure})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "graph-view-islands" :tests tests})))

{:name "graph-view-islands"
 :tests tests
 :main main}
