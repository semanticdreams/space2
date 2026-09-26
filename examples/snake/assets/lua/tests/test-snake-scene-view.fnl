(local Runner (require :tests/runner))
(local Snake (require :snake/game))
(local SceneView (require :snake/scene-view))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn make-fake-scene []
  (local state {:spawns [] :despawns [] :transforms [] :owned []})
  (local scene {})
  (set scene.spawn
       (fn [_self spec]
         (assert (= spec.kind :custom) "Snake scene cells should use embedded-compatible custom objects")
         (assert spec.object "Snake custom scene cells must include a concrete object")
         (assert spec.position "Snake scene cells must include a position")
         (assert spec.size "Snake scene cells must include a size")
         (local handle {:id spec.id :kind spec.kind :tags spec.tags :spec spec})
         (table.insert state.spawns spec)
         (table.insert state.owned handle)
         handle))
  (set scene.despawn
       (fn [_self handle]
         (table.insert state.despawns handle)
         (for [i (# state.owned) 1 -1]
           (when (= (. state.owned i) handle)
             (table.remove state.owned i)))
         true))
  (set scene.set-transform
       (fn [_self handle transform]
         (table.insert state.transforms {:handle handle :transform transform})
         transform))
  (set scene.list-owned
       (fn [_self]
         (local out [])
         (each [_ handle (ipairs state.owned)]
           (table.insert out handle))
         out))
  (values scene state))

(fn has-tag? [tags expected]
  (var found? false)
  (each [_ tag (ipairs (or tags []))]
    (when (= tag expected)
      (set found? true)))
  found?)

(fn find-spawn-with-tag [spawns tag]
  (var found nil)
  (each [_ spec (ipairs spawns)]
    (when (and (not found) (has-tag? spec.tags tag))
      (set found spec)))
  found)

(fn find-owned-id [owned expected-id]
  (var found nil)
  (each [_ handle (ipairs owned)]
    (when (and (not found) (= handle.id expected-id))
      (set found handle)))
  found)

(fn assert-owned-id [owned expected-id]
  (assert (find-owned-id owned expected-id)
          (.. "expected scene handle " expected-id)))

(fn assert-missing-owned-id [owned expected-id]
  (assert (not (find-owned-id owned expected-id))
          (.. "stale scene handle should be despawned: " expected-id)))

(fn count-owned-with-tag [owned tag]
  (var count 0)
  (each [_ handle (ipairs owned)]
    (when (has-tag? handle.tags tag)
      (set count (+ count 1))))
  count)

(fn assert-owned-role-counts [owned]
  (assert (= (# owned) 3) "owned visible cells should remain head body food")
  (assert (= (count-owned-with-tag owned :head) 1) "owned cells should include one head")
  (assert (= (count-owned-with-tag owned :body) 1) "owned cells should include one body segment")
  (assert (= (count-owned-with-tag owned :food) 1) "owned cells should include one food"))

(fn test-initial-sync-spawns-head-body-and-food []
  (local (scene state) (make-fake-scene))
  (local game (Snake.create {:width 8 :height 6
                             :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                             :initial-food {:x 6 :y 3}}))
  (local view (SceneView.create {:scene scene :game game}))
  (view:sync)
  (assert (= (# state.spawns) 3) "initial sync should spawn head, body, and food")
  (assert (find-spawn-with-tag state.spawns :head) "initial sync should tag a head")
  (assert (find-spawn-with-tag state.spawns :body) "initial sync should tag a body")
  (assert (find-spawn-with-tag state.spawns :food) "initial sync should tag food")
  (view:drop))

(add-test "initial sync spawns head body and food" test-initial-sync-spawns-head-body-and-food)

(fn test-sync-reuses-existing-cell-handles-and-despawns-obsolete-cells []
  (local (scene state) (make-fake-scene))
  (local game (Snake.create {:width 8 :height 6
                             :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                             :initial-food {:x 6 :y 3}}))
  (local view (SceneView.create {:scene scene :game game}))
  (view:sync)
  (local first-spawn-count (# state.spawns))
  (game:step)
  (view:sync)
  (assert (> (# state.spawns) first-spawn-count) "moving should spawn new visible cells")
  (assert (> (# state.despawns) 0) "moving should despawn obsolete cells")
  (assert (= (# state.owned) 3) "owned visible cells should remain head body food")
  (view:drop))

(fn test-drop-is-idempotent-and-despawns-owned-handles-once []
  (local (scene state) (make-fake-scene))
  (local game (Snake.create {:width 8 :height 6
                             :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                             :initial-food {:x 6 :y 3}}))
  (local view (SceneView.create {:scene scene :game game}))
  (view:sync)
  (view:drop)
  (view:drop)
  (assert (= (# state.despawns) 3) "drop should despawn each scene cell once")
  (assert (= (# state.owned) 0) "drop should leave no Snake-owned scene handles"))

(fn test-restart-sync-despawns-stale-handles-and-restores-start-cells []
  (local (scene state) (make-fake-scene))
  (local game (Snake.create {:width 8 :height 6
                             :initial-snake [{:x 3 :y 3} {:x 2 :y 3}]
                             :initial-food {:x 6 :y 3}}))
  (local view (SceneView.create {:scene scene :game game}))
  (view:sync)
  (game:step)
  (view:sync)
  (assert-owned-id state.owned "head-4-3")
  (assert-owned-id state.owned "body-2-3-3")
  (game:restart)
  (view:sync)
  (assert-owned-role-counts state.owned)
  (assert-owned-id state.owned "head-3-3")
  (assert-owned-id state.owned "body-2-2-3")
  (assert-owned-id state.owned "food-6-3")
  (assert-missing-owned-id state.owned "head-4-3")
  (assert-missing-owned-id state.owned "body-2-3-3")
  (view:drop))

(add-test "sync reuses and despawns cells" test-sync-reuses-existing-cell-handles-and-despawns-obsolete-cells)
(add-test "drop despawns owned handles once" test-drop-is-idempotent-and-despawns-owned-handles-once)
(add-test "restart sync despawns stale handles and restores start cells" test-restart-sync-despawns-stale-handles-and-restores-start-cells)

(fn main []
  (Runner.run-tests {:name "snake-scene-view" :tests tests}))

{:main main :tests tests}
