(local glm (require :glm))
(local IslandHost (require :graph/view/island-host))
(local Presenters (require :graph/view/island-presenters))
(local OrderedListPresenter (require :graph/view/island-presenters/ordered-list))

(local tests [])

(fn assert-close [actual expected message]
    (assert (< (math.abs (- actual expected)) 1e-6)
            (or message
                (string.format "Expected %s to equal %s" actual expected))))

(fn assert-vec3 [actual expected message]
    (assert actual (or message "expected vec3, got nil"))
    (assert-close actual.x expected.x (.. (or message "vec3") " x"))
    (assert-close actual.y expected.y (.. (or message "vec3") " y"))
    (assert-close actual.z expected.z (.. (or message "vec3") " z")))

(fn count-pin-events [events key pinned?]
    (var count 0)
    (each [_ event (ipairs events)]
        (when (and (= event.key key) (= event.pinned? pinned?))
            (set count (+ count 1))))
    count)

(fn make-host [opts]
    (local options (if opts opts {}))
    (local positions (if options.positions options.positions {}))
    (local set-positions [])
    (local pinned [])
    (fn host-node-for-key [_self key]
        {:key key})
    (fn host-position-for-key [_self key]
        (. positions key))
    (fn host-set-node-position [_self key position]
        (table.insert set-positions {:key key :position position}))
    (fn host-set-node-pinned [_self key pinned?]
        (table.insert pinned {:key key :pinned? pinned?}))
    (local host
        {:presenters (if options.presenters options.presenters Presenters)
         :node-for-key host-node-for-key
         :position-for-key host-position-for-key
         :set-node-position host-set-node-position
         :set-node-pinned host-set-node-pinned})
    (set host.set-positions set-positions)
    (set host.pinned pinned)
    host)

(fn ordered-list-presenter-uses-member-position-for-legacy-island-without-body-position []
    (local host (make-host {:positions {"list:1" (glm.vec3 100 200 3)
                                        "item:a" (glm.vec3 10 20 30)}}))
    (local island {:id "island-1"
                   :kind "ordered-list"
                   :members ["item:a" "item:b" "item:c"]
                   :state {:list-key "list:1" :spacing 10}})
    (local layout (OrderedListPresenter.layout-island island host))
    (assert-vec3 (. layout "item:a") (glm.vec3 10 20 30)
                 "legacy island without body position should fall back to first member position")
    (assert-vec3 (. layout "item:b") (glm.vec3 10 10 30)
                 "second member should offset from member fallback by spacing")
    (assert-vec3 (. layout "item:c") (glm.vec3 10 0 30)
                 "third member should offset from member fallback deterministically"))

(fn ordered-list-presenter-uses-default-origin-without-body-or-member-position []
    (local host (make-host {:positions {"list:1" (glm.vec3 100 200 3)}}))
    (local island {:id "island-1"
                   :kind "ordered-list"
                   :members ["item:a" "item:b"]
                   :state {:list-key "list:1"}})
    (local layout (OrderedListPresenter.layout-island island host))
    (assert-vec3 (. layout "item:a") (glm.vec3 0 0 0)
                 "legacy island without body or member position should use default origin")
    (assert-vec3 (. layout "item:b") (glm.vec3 0 -24 0)
                 "default spacing should apply from default origin"))

(fn ordered-list-presenter-uses-state-position-before-member-fallback []
    (local host (make-host {:positions {"list:1" (glm.vec3 100 200 3)
                                        "item:a" (glm.vec3 10 20 30)}}))
    (local island {:id "island-1"
                   :kind "ordered-list"
                   :members ["item:a" "item:b"]
                   :state {:list-key "list:1"
                           :position (glm.vec3 7 8 9)}})
    (local layout (OrderedListPresenter.layout-island island host))
    (assert-vec3 (. layout "item:a") (glm.vec3 7 8 9)
                 "explicit island state position should be preferred")
    (assert-vec3 (. layout "item:b") (glm.vec3 7 -16 9)
                  "default spacing should be applied from explicit state position"))

(fn ordered-list-presenter-uses-restored-array-state-position []
    (local host (make-host {:positions {"list:1" (glm.vec3 100 200 3)
                                        "item:a" (glm.vec3 10 20 30)}}))
    (local island {:id "island-1"
                   :kind "ordered-list"
                   :members ["item:a" "item:b"]
                   :state {:list-key "list:1"
                           :position [7 8 9]}})
    (local layout (OrderedListPresenter.layout-island island host))
    (assert-vec3 (. layout "item:a") (glm.vec3 7 8 9)
                 "restored array state position should be preferred")
    (assert-vec3 (. layout "item:b") (glm.vec3 7 -16 9)
                 "default spacing should apply from restored array state position"))

(fn island-host-errors-on-missing-presenter-kind []
    (fn no-presenter-for-kind [_kind]
        nil)
    (local host (IslandHost.GraphViewIslandHost (make-host {:presenters {:presenter-for-kind no-presenter-for-kind}})))
    (fn reconcile-missing-kind []
        (host:reconcile-island {:id "island-1"
                                :kind "missing-kind"
                                :members ["item:a"]
                                :state {}}))
    (local (ok err) (pcall reconcile-missing-kind))
    (assert (not ok) "missing presenter kind should fail visibly")
    (assert (string.find (tostring err) "missing graph island presenter kind: missing-kind" 1 true)
            "missing presenter error should include island kind"))

(fn island-host-pins-and-unpins-island-members-through-host-callbacks []
    (local backing-host (make-host {:positions {"item:a" (glm.vec3 1 2 3)}}))
    (local host (IslandHost.GraphViewIslandHost backing-host))
    (host:reconcile-island {:id "island-1"
                            :kind "ordered-list"
                            :members ["item:a" "item:b"]
                            :state {:spacing 5}})
    (assert (= (length backing-host.set-positions) 2)
            "reconcile should set positions for island members")
    (assert (= (length backing-host.pinned) 2)
            "reconcile should pin island members")
    (assert (= (. backing-host.pinned 1 :key) "item:a") "first pin should be first member")
    (assert (= (. backing-host.pinned 1 :pinned?) true) "pin callback should set true")
    (host:reconcile-island {:id "island-1"
                            :kind "ordered-list"
                            :members ["item:b"]
                            :state {:spacing 5}})
    (assert (= (length backing-host.pinned) 4)
            "second reconcile should unpin removed member and keep remaining pinned")
    (assert (= (. backing-host.pinned 3 :key) "item:a") "removed member should be unpinned")
    (assert (= (. backing-host.pinned 3 :pinned?) false) "removed member should be unpinned with false")
    (assert (= (. backing-host.pinned 4 :key) "item:b") "remaining member should be re-pinned")
    (assert (= (. backing-host.pinned 4 :pinned?) true) "remaining member should stay pinned")
    (host:drop-island "island-1")
    (assert (= (. backing-host.pinned 5 :key) "item:b") "drop-island should unpin tracked member")
    (assert (= (. backing-host.pinned 5 :pinned?) false) "drop-island should unpin with false"))

(fn island-host-keeps-shared-members-pinned-until-last-island-drops []
    (local backing-host (make-host {:positions {"shared" (glm.vec3 1 2 3)}}))
    (local host (IslandHost.GraphViewIslandHost backing-host))
    (host:reconcile-island {:id "island-1"
                            :kind "ordered-list"
                            :members ["shared" "only:a"]
                            :state {:spacing 5}})
    (host:reconcile-island {:id "island-2"
                            :kind "ordered-list"
                            :members ["shared" "only:b"]
                            :state {:spacing 5}})
    (host:reconcile-island {:id "island-1"
                            :kind "ordered-list"
                            :members ["only:a"]
                            :state {:spacing 5}})
    (assert (= (count-pin-events backing-host.pinned "shared" false) 0)
            "removing a shared member from one island should not unpin while another island owns it")
    (host:drop-island "island-2")
    (assert (= (count-pin-events backing-host.pinned "shared" false) 1)
            "dropping the last island owner should unpin the shared member"))

(table.insert tests {:name "OrderedListPresenter uses member position for legacy island without body position"
                     :fn ordered-list-presenter-uses-member-position-for-legacy-island-without-body-position})
(table.insert tests {:name "OrderedListPresenter uses default origin without body or member position"
                     :fn ordered-list-presenter-uses-default-origin-without-body-or-member-position})
(table.insert tests {:name "OrderedListPresenter uses state position before member fallback"
                     :fn ordered-list-presenter-uses-state-position-before-member-fallback})
(table.insert tests {:name "OrderedListPresenter uses restored array state position"
                     :fn ordered-list-presenter-uses-restored-array-state-position})
(table.insert tests {:name "IslandHost errors on missing presenter kind"
                     :fn island-host-errors-on-missing-presenter-kind})
(table.insert tests {:name "IslandHost pins and unpins island members through host callbacks"
                     :fn island-host-pins-and-unpins-island-members-through-host-callbacks})
(table.insert tests {:name "IslandHost keeps shared members pinned until last island drops"
                     :fn island-host-keeps-shared-members-pinned-until-last-island-drops})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "graph-island-presenters" :tests tests})))

{:name "graph-island-presenters"
 :tests tests
 :main main}
