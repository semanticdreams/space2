(local tests [])
(local SceneCapability (require :app-host.scene-capability))

(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false))
  (assert (string.find (tostring err) expected 1 true)))

(fn test-spawn_transform_list_and_drop []
  (local scene (SceneCapability.create {}))
  (local handle (scene:spawn {:kind :custom
                              :id :snake-head
                              :tags [:snake :head]
                              :position [1 2 3]
                              :size [1 1 1]}))
  (assert (= handle.id :snake-head))
  (assert (= handle.kind :custom))
  (assert (= (# (scene:list-owned)) 1))
  (scene:set-transform handle {:position [4 5 6]
                               :rotation nil
                               :size [2 2 2]})
  (local transform (scene:get-transform handle))
  (assert (= (. transform.position 1) 4))
  (scene:drop)
  (assert (= (# (scene:list-owned)) 0)))

(fn test-query_volume_filters_by_tags []
  (local scene (SceneCapability.create {}))
  (scene:spawn {:kind :custom
                :id :wall
                :tags [:solid :wall]
                :position [0 0 0]
                :size [1 1 1]})
  (scene:spawn {:kind :custom
                :id :food
                :tags [:pickup :food]
                :position [5 0 0]
                :size [1 1 1]})
  (local hits (scene:query-volume {:center [0 0 0]
                                   :size [2 2 2]}
                                  {:tags [:solid]}))
  (assert (= (# hits) 1))
  (local hit (. hits 1))
  (assert (= hit.id :wall)))

(fn test-invalid_handles_and_unsupported_kinds_fail_loudly []
  (local scene (SceneCapability.create {}))
  (assert-error-contains #(scene:spawn {:kind :unknown}) "unsupported spawn kind")
  (assert-error-contains #(scene:get-transform {:id :missing}) "invalid scene handle"))

(fn test-terrain_queries_delegate_to_backend []
  (local backend {:height-at (fn [_self point _opts]
                               (+ (. point 1) (. point 3)))
                  :raycast-terrain (fn [_self ray _opts]
                                     {:hit? true
                                      :ray ray})})
  (local scene (SceneCapability.create {:backend backend}))
  (assert (= (scene:height-at [2 0 3]) 5))
  (local hit (scene:raycast-terrain {:origin [0 1 0]
                                     :direction [0 -1 0]}))
  (assert (= hit.hit? true)))

(fn test-drop_failure_keeps_cleanup_recoverable []
  (var fail-second? true)
  (local despawned [])
  (local backend {:despawn (fn [_self handle]
                             (table.insert despawned handle.id)
                             (when (and fail-second? (= handle.id :second))
                               (error "transient despawn failure")))})
  (local scene (SceneCapability.create {:backend backend}))
  (scene:spawn {:kind :custom :id :first})
  (scene:spawn {:kind :custom :id :second})

  (assert-error-contains #(scene:drop) "transient despawn failure")
  (local remaining (scene:list-owned))
  (assert (= (# remaining) 1))
  (assert (= (. (. remaining 1) :id) :second))

  (set fail-second? false)
  (scene:drop)
  (assert (= (# (scene:list-owned)) 0))
  (assert (= (# despawned) 3))
  (assert (= (. despawned 1) :first))
  (assert (= (. despawned 2) :second))
  (assert (= (. despawned 3) :second)))

(table.insert tests {:name "spawn transform list and drop"
                     :fn test-spawn_transform_list_and_drop})
(table.insert tests {:name "query volume filters by tags"
                     :fn test-query_volume_filters_by_tags})
(table.insert tests {:name "invalid handles and unsupported kinds fail loudly"
                     :fn test-invalid_handles_and_unsupported_kinds_fail_loudly})
(table.insert tests {:name "terrain queries delegate to backend"
                      :fn test-terrain_queries_delegate_to_backend})
(table.insert tests {:name "drop failure keeps cleanup recoverable"
                     :fn test-drop_failure_keeps_cleanup_recoverable})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "app-host-scene-capability"
                       :tests tests})))

{:name "app-host-scene-capability"
 :tests tests
 :main main}
