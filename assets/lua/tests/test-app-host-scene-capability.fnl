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

(table.insert tests {:name "spawn transform list and drop"
                     :fn test-spawn_transform_list_and_drop})
(table.insert tests {:name "query volume filters by tags"
                     :fn test-query_volume_filters_by_tags})
(table.insert tests {:name "invalid handles and unsupported kinds fail loudly"
                     :fn test-invalid_handles_and_unsupported_kinds_fail_loudly})
(table.insert tests {:name "terrain queries delegate to backend"
                     :fn test-terrain_queries_delegate_to_backend})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "app-host-scene-capability"
                       :tests tests})))

{:name "app-host-scene-capability"
 :tests tests
 :main main}
