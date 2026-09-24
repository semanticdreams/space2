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

(fn ordered-list-presenter-derives-origin-from-second-member-drop []
    (local host (make-host {:positions {"item:a" (glm.vec3 10 20 0)
                                        "item:b" (glm.vec3 10 -4 0)}}))
    (local island {:id "island-1"
                   :kind "ordered-list"
                   :members ["item:a" "item:b"]
                   :state {:list-key "list:1"
                           :interaction-policy "snap-back"
                           :spacing 24
                           :position [10 20 0]}})
    (local next-state (OrderedListPresenter.member-drag-end-state
                        island host {:member-key "item:b"
                                     :position (glm.vec3 50 60 0)}))
    (assert (= next-state.list-key "list:1") "list-key should be preserved")
    (assert (= next-state.interaction-policy "snap-back") "interaction policy should be preserved")
    (assert (= next-state.spacing 24) "spacing should be preserved")
    (assert (= (. next-state.position 1) 50) "new origin x should follow dropped member delta")
    (assert (= (. next-state.position 2) 84) "new origin y should keep second member at drop after spacing")
    (assert (= (. next-state.position 3) 0) "new origin z should follow dropped member delta"))

(fn ordered-list-presenter-upgrades-legacy-island-on-member-drop []
    (local host (make-host {:positions {"item:a" (glm.vec3 100 100 0)
                                        "item:b" (glm.vec3 100 76 0)}}))
    (local island {:id "island-1"
                   :kind "ordered-list"
                   :members ["item:a" "item:b"]
                   :state {:list-key "list:1" :spacing 24}})
    (local next-state (OrderedListPresenter.member-drag-end-state
                        island host {:member-key "item:b"
                                     :position (glm.vec3 200 176 0)}))
    (assert (= (. next-state.position 1) 200) "legacy island should receive explicit body x")
    (assert (= (. next-state.position 2) 200) "legacy island should receive explicit body y")
    (assert (= (. next-state.position 3) 0) "legacy island should receive explicit body z"))

(fn ordered-list-presenter-ignores-non-member-drop []
    (local host (make-host {:positions {"item:a" (glm.vec3 0 0 0)}}))
    (local island {:id "island-1" :kind "ordered-list" :members ["item:a"] :state {:position [0 0 0]}})
    (local next-state (OrderedListPresenter.member-drag-end-state
                        island host {:member-key "item:x"
                                     :position (glm.vec3 10 10 0)}))
    (assert (= next-state nil) "non-member drag should not update island state"))

(fn presenters-for-fixture [presenter]
    {:presenter-for-kind (fn [kind]
                           (if (= kind presenter.kind)
                               presenter
                               nil))})

(fn island-host-delegates-member-drag-end-state []
    (var called? false)
    (local presenter {:kind "custom"
                      :apply (fn [_island _host] {})
                      :member-drag-end-state
                      (fn [island _host request]
                          (set called? true)
                          {:position [request.position.x request.position.y request.position.z]
                           :source island.id})})
    (local host (IslandHost.GraphViewIslandHost
                  (make-host {:presenters (presenters-for-fixture presenter)
                              :positions {"item:a" (glm.vec3 0 0 0)}})))
    (local state (host:state-after-member-drag-end
                   {:id "island-1" :kind "custom" :members ["item:a"]}
                   {:member-key "item:a" :position (glm.vec3 9 8 7)}))
    (assert called? "host should call presenter hook")
    (assert (= state.source "island-1") "host should return presenter state"))

(fn island-host-returns-nil-when-presenter-has-no-member-drag-hook []
    (local presenter {:kind "custom" :apply (fn [_island _host] {})})
    (local host (IslandHost.GraphViewIslandHost
                  (make-host {:presenters (presenters-for-fixture presenter)
                              :positions {"item:a" (glm.vec3 0 0 0)}})))
    (local state (host:state-after-member-drag-end
                   {:id "island-1" :kind "custom" :members ["item:a"]}
                   {:member-key "item:a" :position (glm.vec3 1 2 3)}))
    (assert (= state nil) "presenters without hook should decline island movement"))

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

(fn island-host-positions-ordered-list-members-without-default-pins []
    (local backing-host (make-host {:positions {"item:a" (glm.vec3 1 2 3)}}))
    (local host (IslandHost.GraphViewIslandHost backing-host))
    (host:reconcile-island {:id "island-1"
                            :kind "ordered-list"
                            :members ["item:a" "item:b"]
                            :state {:spacing 5}})
    (assert (= (length backing-host.set-positions) 2)
            "reconcile should set positions for island members")
    (assert (= (length backing-host.pinned) 0)
            "ordered-list reconcile should not pin island members by default")
    (host:reconcile-island {:id "island-1"
                            :kind "ordered-list"
                            :members ["item:b"]
                            :state {:spacing 5}})
    (assert (= (length backing-host.pinned) 0)
            "ordered-list membership changes should not create default pin events")
    (host:drop-island "island-1")
    (assert (= (length backing-host.pinned) 0)
            "dropping an unpinned ordered-list island should not unpin members"))

(fn explicit-pin-presenter []
    {:kind "explicit-pin"
     :apply (fn [island host]
              (assert island.members "explicit-pin presenter requires members")
              (each [_ key (ipairs island.members)]
                  (host:set-member-pinned island.id key true)))})

(fn island-host-keeps-shared-members-pinned-until-last-island-drops []
    (local presenter (explicit-pin-presenter))
    (local backing-host (make-host {:presenters (presenters-for-fixture presenter)
                                    :positions {"shared" (glm.vec3 1 2 3)}}))
    (local host (IslandHost.GraphViewIslandHost backing-host))
    (host:reconcile-island {:id "island-1"
                            :kind "explicit-pin"
                            :members ["shared" "only:a"]
                            :state {:spacing 5}})
    (host:reconcile-island {:id "island-2"
                            :kind "explicit-pin"
                            :members ["shared" "only:b"]
                            :state {:spacing 5}})
    (host:reconcile-island {:id "island-1"
                            :kind "explicit-pin"
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
(table.insert tests {:name "OrderedListPresenter derives origin from second member drop"
                     :fn ordered-list-presenter-derives-origin-from-second-member-drop})
(table.insert tests {:name "OrderedListPresenter upgrades legacy island on member drop"
                     :fn ordered-list-presenter-upgrades-legacy-island-on-member-drop})
(table.insert tests {:name "OrderedListPresenter ignores non-member drop"
                     :fn ordered-list-presenter-ignores-non-member-drop})
(table.insert tests {:name "IslandHost delegates member drag end state"
                     :fn island-host-delegates-member-drag-end-state})
(table.insert tests {:name "IslandHost returns nil when presenter has no member drag hook"
                     :fn island-host-returns-nil-when-presenter-has-no-member-drag-hook})
(table.insert tests {:name "IslandHost errors on missing presenter kind"
                      :fn island-host-errors-on-missing-presenter-kind})
(table.insert tests {:name "IslandHost positions ordered-list members without default pins"
                     :fn island-host-positions-ordered-list-members-without-default-pins})
(table.insert tests {:name "IslandHost keeps shared members pinned until last island drops"
                     :fn island-host-keeps-shared-members-pinned-until-last-island-drops})

(local main
    (fn []
        (local runner (require :tests/runner))
        (runner.run-tests {:name "graph-island-presenters" :tests tests})))

{:name "graph-island-presenters"
 :tests tests
 :main main}
