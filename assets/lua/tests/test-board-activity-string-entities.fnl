(local tests [])
(local glm (require :glm))
(local runner (require :tests/runner))
(local Canvas (require :canvas))
(local Camera (require :camera))
(local {: FocusManager} (require :focus))
(local Activities (require :activities))
(local BoardActivityUnit (require :board-activity-unit))
(local StringEntityStore (require :entities/string))

(fn make-test-font []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :bottom 0 :top 1}
                :atlasBounds {:left 0 :right 1 :bottom 0 :top 1}})
  {:metadata {:metrics {:ascender 1 :descender 0 :lineHeight 1}
              :atlas {:width 1 :height 1}}
   :glyph-map {32 glyph 65 glyph 66 glyph 65533 glyph}})

(fn make-scene-stub []
  {:ensure-activity-slot (fn [_self _activity-id] {})
   :activate-activity-slot (fn [self activity-id]
                             (local slot (self:ensure-activity-slot activity-id))
                             (set self.active-activity-slot slot)
                             slot)
   :deactivate-activity-slot (fn [self _activity-id]
                               (set self.active-activity-slot nil)
                               nil)
   :capture-activity-slot-state (fn [_self _activity-id] {})
   :restore-activity-slot-state (fn [_self _activity-id _state] true)})

(fn make-canvas-fixture []
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "board-string-entity-test"}))
  (local canvas (Canvas {:camera camera :focus-manager focus-manager}))
  {:canvas canvas
   :drop (fn [_self]
           (canvas:drop)
           (focus-manager:drop)
           (camera:drop))})

(fn with-board-runtime [body board-state]
  (local previous-canvas app.canvas)
  (local previous-active-world-runtime app.active-world-runtime)
  (local previous-active-interaction-surface app.active-interaction-surface)
  (local previous-active-activity-id app.active-activity-id)
  (local previous-activity-registry app.activity-registry)
  (local previous-activities-changed app.activities-changed)
  (local previous-board app.board)
  (local previous-board-view app.board-view)
  (local previous-text-style app.text-style)
  (local previous-themes app.themes)
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (local fixture (make-canvas-fixture))
  (set app.canvas fixture.canvas)
  (set app.text-style {:font (make-test-font)
                       :scale 1.0
                       :color (glm.vec4 1 1 1 1)})
  (set app.themes {:get-active-theme (fn [] {:font app.text-style.font
                                             :text {:scale 1.0
                                                    :foreground (glm.vec4 1 1 1 1)}})})
  (set app.active-interaction-surface :canvas)
  (set app.active-world-runtime {:canvas fixture.canvas
                                 :activity-cameras {:canvas {} :scene {}}
                                 :activity-controls {:canvas {} :scene {}}
                                 :scene (make-scene-stub)
                                 :board-state board-state})
  (local (ok err)
    (pcall
      (fn []
        (BoardActivityUnit.load-board-activity!)
        (Activities.activate-activity "board")
        (body))))
  (pcall BoardActivityUnit.unload-board-activity!)
  (fixture:drop)
  (set app.canvas previous-canvas)
  (set app.active-world-runtime previous-active-world-runtime)
  (set app.active-interaction-surface previous-active-interaction-surface)
  (set app.active-activity-id previous-active-activity-id)
  (set app.activity-registry previous-activity-registry)
  (set app.activities-changed previous-activities-changed)
  (set app.board previous-board)
  (set app.board-view previous-board-view)
  (set app.text-style previous-text-style)
  (set app.themes previous-themes)
  (if ok true (error err)))

(local valid-entity-id "board-prune-valid-string-entity")
(local missing-entity-id "board-prune-missing-string-entity")

(fn stale-string-entity-state []
  {:items [{:id "valid-string"
            :type "string-entity"
            :subject-key (.. "string-entity:" valid-entity-id)
            :position [0 0 0]
            :rotation [1 0 0 0]
            :size [32 16 0]}
           {:id "missing-string"
            :type "string-entity"
            :subject-key (.. "string-entity:" missing-entity-id)
            :position [40 0 0]
            :rotation [1 0 0 0]
            :size [32 16 0]}]
   :connectors [{:id "stale-connector"
                 :source-item-id "valid-string"
                 :target-item-id "missing-string"}]})

(fn cleanup-string-entities [store]
  (pcall (fn [] (store:retire-entity! valid-entity-id)))
  (pcall (fn [] (store:retire-entity! missing-entity-id))))

(fn with-valid-string-entity [body]
  (local store (StringEntityStore.get-default))
  (cleanup-string-entities store)
  (store:create-entity {:id valid-entity-id :value "valid"})
  (local (ok err) (pcall body))
  (cleanup-string-entities store)
  (if ok true (error err)))

(fn assert-stale-item-pruned []
  (assert app.board "Board activity should activate")
  (assert (. app.board.items "valid-string")
          "Valid string entity item should remain restored")
  (assert (not (. app.board.items "missing-string"))
          "Stale string entity item should be pruned")
  (assert (= (length app.board.connectors-in-order) 0)
          "Connector referencing stale item should be pruned"))

(fn activation-restore-runtime []
  (with-board-runtime assert-stale-item-pruned (stale-string-entity-state)))

(fn active-restore-body []
  (Activities.restore-active-activity {:active? true
                                       :board-state (stale-string-entity-state)})
  (assert-stale-item-pruned))

(fn active-restore-runtime []
  (with-board-runtime active-restore-body {:items [] :connectors []}))

(fn activation-restore-prunes-stale-string-entity-item []
  (with-valid-string-entity activation-restore-runtime))

(fn active-restore-prunes-stale-string-entity-item []
  (with-valid-string-entity active-restore-runtime))

(table.insert tests {:name "Board activity activation restore prunes stale string entity item"
                     :fn activation-restore-prunes-stale-string-entity-item})
(table.insert tests {:name "Board activity active restore prunes stale string entity item"
                     :fn active-restore-prunes-stale-string-entity-item})

(fn main []
  (runner.run-tests {:name "board-activity-string-entities"
                     :tests tests}))

{:name "board-activity-string-entities"
 :tests tests
 :main main}
