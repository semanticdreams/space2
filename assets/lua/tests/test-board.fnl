(local glm (require :glm))
(local {: Layout : LayoutRoot} (require :layout))
(local BuildContext (require :build-context))
(local Signal (require :signal))
(local tempfile (require :tempfile))
(local runner (require :tests/runner))
(local {:Board Board} (require :board/core))
(local BoardRegistry (require :board/registry))
(local BoardView (require :board/view))
(local LinkEntityStore (require :entities/link))
(local StringEntityStore (require :entities/string))
(local StringEntityBoardWidget (require :board/string-entity-widget))
(local Activities (require :activities))
(local BoardActivityUnit (require :board-activity-unit))
(local BuiltinStringEntity (require :board/builtin-string-entity))
(local Canvas (require :canvas))
(local Camera (require :camera))
(local {: FocusManager} (require :focus))
(local H (require :tests/test-reference-lifecycle-helpers))
;; Minimal Scene stub providing the activity-slot lifecycle needed by
;; board-activity-unit (ensure, activate, deactivate, capture, restore).
;; This avoids requiring a full Scene with BuildContext, layout roots,
;; and focus-manager dependencies.
(local make-scene-stub
  (fn []
    (local slots {})
    (local stub
      {:activity-slots slots
       :active-activity-slot nil
       :active-activity-slot-id nil})
    (fn make-slot [activity-id]
      {:activity-id activity-id
       :surface :scene
       :entity nil
       :scene-children nil
       :scene-terrains nil
       :queued-cube-panels []
       :panel-restorers {}
       :demo-browser nil
       :physics-body-count 0
       :scene-state nil
       :visible? false
       :interactive? false
       :activate (fn [self] (set self.visible? true) (set self.interactive? true) self)
       :deactivate (fn [self] (set self.visible? false) (set self.interactive? false) self)
       :drop (fn [self] (self:deactivate) (set self.entity nil) true)})
    (set stub.ensure-activity-slot
         (fn [_self activity-id]
           (assert (= (type activity-id) :string) "Scene.ensure-activity-slot requires string activity id")
           (local existing (. slots activity-id))
           (if existing
               existing
               (let [slot (make-slot activity-id)]
                 (set (. slots activity-id) slot)
                 slot))))
    (set stub.activate-activity-slot
         (fn [self activity-id]
           (local slot (self:ensure-activity-slot activity-id))
           (when (and self.active-activity-slot
                      (not= self.active-activity-slot slot))
             (self.active-activity-slot:deactivate)
             (set self.active-activity-slot nil)
             (set self.active-activity-slot-id nil))
           (slot:activate)
           (set self.active-activity-slot-id activity-id)
           (set self.active-activity-slot slot)
           slot))
    (set stub.deactivate-activity-slot
         (fn [self activity-id]
           (local slot (. slots activity-id))
           (when slot
             (slot:deactivate)
             (when (= self.active-activity-slot slot)
               (set self.active-activity-slot nil)
               (set self.active-activity-slot-id nil)))
           slot))
    (set stub.capture-activity-slot-state
         (fn [_self _activity-id]
           {:panels []
            :terrains []
            :lights nil
            :skybox nil
            :background nil}))
    (set stub.restore-activity-slot-state
         (fn [_self _activity-id _state]
           true))
    stub))

(local tests [])

(fn dummy-widget [_item]
  (fn [_ctx]
    (local layout (Layout {:name "board-test-item"
                           :measurer (fn [self]
                                       (set self.measure (glm.vec3 8 4 0)))
                           :layouter (fn [_self] nil)}))
    {:layout layout
     :drop (fn [_self] nil)}))

(fn with-temp-dir [f]
  (local handle (tempfile.TemporaryDirectory {:prefix "board-test-"}))
  (local (ok result) (pcall f handle.path))
  (handle:drop)
  (if ok result (error result)))

(fn make-activity-canvas [opts]
  (local options (or opts {}))
  (local camera (Camera {:position (glm.vec3 0 0 100)}))
  (local focus-manager (FocusManager {:root-name "board-activity-test"}))
  (local canvas (Canvas {:camera camera
                         :focus-manager focus-manager}))
  (when options.screen-pos-ray
    (set canvas.screen-pos-ray options.screen-pos-ray))
  {:canvas canvas
   :ctx canvas.build-context
   :root canvas.layout-root
   :drop (fn [_self]
           (canvas:drop)
           (focus-manager:drop)
           (camera:drop))})

(fn board-view-connects-items-with-semantic-link []
  (with-temp-dir
    (fn [dir]
      (local owner {})
      (BoardRegistry.unregister-item-type "test-item" owner)
      (BoardRegistry.register-item-type {:id "test-item"
                                         :label "Test"
                                         :builder dummy-widget}
                                        owner)
      (local root (LayoutRoot))
      (local ctx (BuildContext {:layout-root root}))
      (local canvas {:layout-root root
                     :build-context ctx})
      (local board (Board {}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (local view (BoardView {:board board
                              :canvas canvas
                              :ctx ctx
                              :link-store link-store}))
      (local source (view:add-item {:type "test-item"
                                    :subject-key "string-entity:source"
                                    :position (glm.vec3 1 2 0)
                                    :size (glm.vec3 8 4 0)}))
      (local target (view:add-item {:type "test-item"
                                    :subject-key "string-entity:target"
                                    :position (glm.vec3 20 30 0)
                                    :size (glm.vec3 8 4 0)}))
      (local retarget (view:add-item {:type "test-item"
                                      :subject-key "string-entity:retarget"
                                      :position (glm.vec3 40 50 0)
                                      :size (glm.vec3 8 4 0)}))
      (local connector (view:connect-items source target))
      (assert connector "BoardView.connect-items should return a connector")
      (assert (= (length board.connectors-in-order) 1)
              "Board should record connector")
      (local link (link-store:get-entity connector.semantic-link-id))
      (assert link "Board connector should reference persisted link entity")
      (H.assert-reference link-store.identity-store link.source-key
                          "string-entity:source")
      (H.assert-reference link-store.identity-store link.target-key
                          "string-entity:target")
      (assert (. view.connector-records connector.id)
              "BoardView should render connector record")
      (link-store:update-entity connector.semantic-link-id
                                {:target-key "string-entity:retarget"})
      (assert (= connector.target-item-id retarget.id)
              "Board connector should follow semantic link retargets")
      (assert (. view.connector-records connector.id)
              "BoardView should retain connector render record after retarget")
      (link-store:retire-entity! connector.semantic-link-id)
      (assert (= (length board.connectors-in-order) 0)
              "Board should remove connector when semantic link is deleted")
      (assert (not (. view.connector-records connector.id))
              "BoardView should remove connector render record after link deletion")
      (board:update-item-transform source.id {:position (glm.vec3 5 6 0)})
      (local state (view:capture-state))
      (assert (= (length state.items) 3) "Board state should capture items")
      (assert (= (length state.connectors) 0) "Board state should omit deleted connectors")
      (view:drop)
      (BoardRegistry.unregister-owner owner)
      true)))

(table.insert tests {:name "BoardView connects items with semantic link"
                     :fn board-view-connects-items-with-semantic-link})

(fn board-view-hydrates-existing-items-with-view-context []
  (local owner {})
  (var saw-view? false)
  (BoardRegistry.register-item-type {:id "hydrate-item"
                                     :label "Hydrate"
                                     :builder (fn [_item view]
                                                (set saw-view? (not (= view nil)))
                                                (dummy-widget _item))}
                                    owner)
  (local board (Board {:state {:items [{:id "existing"
                                        :type "hydrate-item"
                                        :position [0 0 0]
                                        :rotation [1 0 0 0]
                                        :size [4 4 0]}]}}))
  (local root (LayoutRoot))
  (local ctx (BuildContext {:layout-root root}))
  (local view (BoardView {:board board
                          :canvas {:layout-root root :build-context ctx}
                          :ctx ctx}))
  (assert saw-view? "BoardView should pass self to builders during initial hydration")
  (view:drop)
  (BoardRegistry.unregister-owner owner)
  true)

(fn board-rejects-invalid-transforms []
  (local board (Board {}))
  (local (bad-add-ok _bad-add-err)
    (pcall (fn []
             (board:add-item {:type "anything"
                              :position [math.huge 0 0]}))))
  (assert (not bad-add-ok) "Board should reject invalid persisted positions")
  (local item (board:add-item {:type "anything"}))
  (local (bad-update-ok _bad-update-err)
    (pcall (fn []
             (board:update-item-transform item.id {:position (glm.vec3 math.huge 0 0)}))))
  (assert (not bad-update-ok) "Board should reject invalid runtime positions")
  true)

(fn board-update-transform-is-atomic []
  (local board (Board {}))
  (local item (board:add-item {:type "anything"
                               :position (glm.vec3 1 2 0)
                               :size (glm.vec3 4 5 0)}))
  (local (bad-size-ok _bad-size-err)
    (pcall
      (fn []
        (board:update-item-transform item.id {:position (glm.vec3 9 10 0)
                                              :size (glm.vec3 math.huge 1 0)}))))
  (assert (not bad-size-ok)
          "Board.update-item-transform should fail on invalid size")
  (assert (= item.position.x 1)
          "Board.update-item-transform should not keep earlier field changes after validation failure")
  (local handler
    (board.item-updated:connect
      (fn [_item]
        (error "view update failed"))))
  (local (listener-ok _listener-err)
    (pcall
      (fn []
        (board:update-item-transform item.id {:position (glm.vec3 11 12 0)}))))
  (board.item-updated:disconnect handler true)
  (assert (not listener-ok)
          "Board.update-item-transform should fail when item-updated handlers fail")
  (assert (= item.position.x 1)
          "Board.update-item-transform should roll back after item-updated handler failure")
  true)

(fn board-auto-ids-skip-restored-sparse-ids []
  (local board
    (Board {:state {:items [{:id "item-1" :type "anything"}
                            {:id "item-3" :type "anything"}]
                    :connectors [{:id "connector-2"
                                  :source-item-id "item-1"
                                  :target-item-id "item-3"}]}}))
  (local item (board:add-item {:type "anything"}))
  (assert (= item.id "item-4")
          "Board should advance auto item ids beyond restored sparse ids")
  (local connector (board:add-connector {:source-item-id "item-1"
                                         :target-item-id item.id}))
  (assert (= connector.id "connector-3")
          "Board should advance auto connector ids beyond restored sparse ids")
  true)

(fn board-restore-resets-auto-id-sequences []
  (local board (Board {:state {:items [{:id "item-50" :type "anything"}]}}))
  (board:restore-state {:items [] :connectors []})
  (local item (board:add-item {:type "anything"}))
  (assert (= item.id "item-1")
          "Board.restore-state should reset auto item ids to the restored state")
  true)

(fn string-entity-widget-requires-existing-entity []
  (with-temp-dir
    (fn [dir]
      (local store (StringEntityStore.StringEntityStore {:base-dir dir}))
      (local widget
        (StringEntityBoardWidget {:item {:id "item-1"}
                                  :store store
                                  :entity-id "missing"}))
      (local (ok err)
        (pcall (fn [] (widget {}))))
      (assert (not ok)
              "StringEntityBoardWidget should fail when its entity is missing")
      (assert (and err (string.find err "missing entity"))
              "StringEntityBoardWidget should report missing entity clearly")
      true)))

(fn string-entity-create-rolls-back-on-board-failure []
  (with-temp-dir
    (fn [dir]
      (local board (Board {}))
      (local default-store (StringEntityStore.get-default))
      (local previous-count (length (default-store:list-entities)))
      (local (ok _err)
        (pcall
          (fn []
            (BuiltinStringEntity.create-string-entity
              board
              {:position [math.huge 0 0]}))))
      (assert (not ok)
              "String entity board create should fail on invalid board transform")
      (assert (= (length (default-store:list-entities)) previous-count)
              "String entity board create should delete the new entity when board:add-item fails")
      true)))

(fn string-entity-create-rolls-back-after-item-added-failure []
  (with-temp-dir
    (fn [dir]
      (local board (Board {}))
      (local default-store (StringEntityStore.get-default))
      (local previous-count (length (default-store:list-entities)))
      (local handler
        (board.item-added:connect
          (fn [_item]
            (error "render failed"))))
      (local (ok _err)
        (pcall
          (fn []
            (BuiltinStringEntity.create-string-entity board {}))))
      (board.item-added:disconnect handler true)
      (assert (not ok)
              "String entity board create should fail when item-added handlers fail")
      (assert (= (length board.items-in-order) 0)
              "String entity board create should remove the inserted board item after item-added failure")
      (assert (= (length (default-store:list-entities)) previous-count)
              "String entity board create should delete the new entity after item-added failure")
      true)))

(fn board-view-add-item-cleans-up-partial-attachment-on-view-failure []
  (local previous-movables app.movables)
  (local owner {})
  (var drop-count 0)
  (var unregister-count 0)
  (BoardRegistry.unregister-item-type "partial-item" owner)
  (BoardRegistry.register-item-type
    {:id "partial-item"
     :label "Partial"
     :builder (fn [_item]
                (fn [_ctx]
                  (local layout (Layout {:name "partial-board-item"
                                         :measurer (fn [self]
                                                     (set self.measure (glm.vec3 8 4 0)))
                                         :layouter (fn [_self] nil)}))
                  {:layout layout
                   :drop (fn [_self]
                           (set drop-count (+ drop-count 1)))}))}
    owner)
  (set app.movables {:register (fn [_self _element _opts]
                                 (error "movable registration failed"))
                     :unregister (fn [_self _element]
                                   (set unregister-count (+ unregister-count 1)))})
  (local (ok result)
    (pcall
      (fn []
        (local root (LayoutRoot))
        (local ctx (BuildContext {:layout-root root}))
        (local board (Board {}))
        (local view (BoardView {:board board
                                :canvas {:layout-root root :build-context ctx}
                                :ctx ctx}))
        (local (add-ok _add-err)
          (pcall (fn []
                   (view:add-item {:type "partial-item"}))))
        (assert (not add-ok)
                "BoardView add-item should fail when view-side registration fails")
        (assert (= (length board.items-in-order) 0)
                "Board model should roll back item insertion after view failure")
        (assert (= (length view.layer.children) 0)
                "BoardView should detach partially attached item views after failure")
        (assert (= drop-count 1)
                "BoardView should drop the partially attached item view exactly once")
        (assert (= unregister-count 1)
                "BoardView should unregister partial movables during cleanup")
        (view:drop)
        true)))
  (set app.movables previous-movables)
  (BoardRegistry.unregister-owner owner)
  (if ok result (error result)))

(fn board-view-connect-rolls-back-new-link-on-board-failure []
  (with-temp-dir
    (fn [dir]
      (local root (LayoutRoot))
      (local ctx (BuildContext {:layout-root root}))
      (local owner {})
      (BoardRegistry.register-item-type {:id "anything"
                                         :label "Test"
                                         :builder dummy-widget}
                                        owner)
      (local board (Board {}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (local source (board:add-item {:type "anything" :subject-key "string-entity:source"}))
      (local target (board:add-item {:type "anything" :subject-key "string-entity:target"}))
      (local view (BoardView {:board board
                              :canvas {:layout-root root :build-context ctx}
                              :ctx ctx
                              :link-store link-store}))
      ;; Make board:add-connector fail so the link-creation rollback path is exercised
      (local failing-handler
        (board.connector-added:connect
          (fn [_connector]
            (error "connector render failed"))))
      (local (ok _err)
        (pcall
          (fn []
            (view:connect-items source target))))
      (board.connector-added:disconnect failing-handler)
      (assert (not ok)
              "BoardView.connect-items should fail when board:add-connector fails")
      (assert (= (length (link-store:list-entities)) 0)
              "BoardView.connect-items should delete a newly-created semantic link when board:add-connector fails")
      (view:drop)
      (BoardRegistry.unregister-owner owner)
      true)))

(fn board-add-connector-rolls-back-after-listener-failure []
  (local board (Board {}))
  (local source (board:add-item {:type "anything"}))
  (local target (board:add-item {:type "anything"}))
  (local handler
    (board.connector-added:connect
      (fn [_connector]
        (error "connector render failed"))))
  (local (ok _err)
    (pcall
      (fn []
        (board:add-connector {:source-item-id source.id
                              :target-item-id target.id}))))
  (board.connector-added:disconnect handler true)
  (assert (not ok)
          "Board.add-connector should fail when connector-added handlers fail")
  (assert (= (length board.connectors-in-order) 0)
          "Board.add-connector should roll back inserted connector after listener failure")
  (local connector (board:add-connector {:source-item-id source.id
                                         :target-item-id target.id
                                         :kind "visual"}))
  (assert (= connector.id "connector-1")
          "Board.add-connector should restore id sequence after listener failure")
  true)

(fn board-add-item-rolls-back-side-effects-after-later-listener-failure []
  (local board (Board {}))
  (local owner {})
  (BoardRegistry.unregister-item-type "late-fail-item" owner)
  (BoardRegistry.register-item-type {:id "late-fail-item"
                                     :label "LateFail"
                                     :builder dummy-widget}
                                    owner)
  (var viewed-added-ids [])
  (var viewed-removed-ids [])
  (local view (BoardView {:board board
                          :canvas {:layout-root (LayoutRoot)
                                   :build-context (BuildContext {:layout-root (LayoutRoot)})}
                          :ctx (BuildContext {:layout-root (LayoutRoot)})}))
  (board.item-added:connect
    (fn [item]
      (table.insert viewed-added-ids item.id)))
  (board.item-removed:connect
    (fn [item]
      (table.insert viewed-removed-ids item.id)))
  (local failing-handler
    (board.item-added:connect
      (fn [_item]
        (error "later listener failed"))))
  (local (ok _err)
    (pcall
      (fn []
        (board:add-item {:type "late-fail-item"}))))
  (board.item-added:disconnect failing-handler true)
  (assert (not ok)
          "Board.add-item should fail when later listener fails")
  (assert (= (length board.items-in-order) 0)
          "Board should roll back model after later listener failure")
  (assert (= (length viewed-added-ids) 1)
          "Board should have emitted item-added before later listener failure")
  (assert (= (length viewed-removed-ids) 1)
          "Board should emit item-removed to clean up side effects after rollback")
  (assert (= (. viewed-removed-ids 1) (. viewed-added-ids 1))
          "Board should emit item-removed for the rolled-back item")
  (view:drop)
  (BoardRegistry.unregister-owner owner)
  true)

(fn board-update-transform-rolls-back-after-later-listener-failure []
  (local board (Board {}))
  (local item (board:add-item {:type "anything"
                               :position (glm.vec3 1 2 0)}))
  (var viewed-updates [])
  (var viewed-rollback-updates [])
  (var current-pos (. item.position))
  (local first-handler
    (board.item-updated:connect
      (fn [it]
        (table.insert viewed-updates {:x it.position.x :y it.position.y :z it.position.z})
        (set current-pos it.position))))
  (local failing-handler
    (board.item-updated:connect
      (fn [_it]
        (error "later transform listener failed"))))
  (local (ok _err)
    (pcall
      (fn []
        (board:update-item-transform item.id {:position (glm.vec3 50 60 0)}))))
  (board.item-updated:disconnect failing-handler true)
  (assert (not ok)
          "Board.update-item-transform should fail when later listener fails")
  (assert (= item.position.x 1)
          "Board should roll back position after later listener failure")
  (assert (>= (length viewed-updates) 2)
          "Board should emit item-updated for the first listener and again for rollback")
  (assert (= (. (. viewed-updates (length viewed-updates)) :x) 1)
          "Board should emit item-updated with rolled-back position")
  (board.item-updated:disconnect first-handler true)
  true)

(fn board-add-connector-rolls-back-side-effects-after-later-listener-failure []
  (local board (Board {}))
  (local source (board:add-item {:type "anything"}))
  (local target (board:add-item {:type "anything"}))
  (var viewed-added-ids [])
  (var viewed-removed-ids [])
  (board.connector-added:connect
    (fn [c]
      (table.insert viewed-added-ids c.id)))
  (board.connector-removed:connect
    (fn [c]
      (table.insert viewed-removed-ids c.id)))
  (local failing-handler
    (board.connector-added:connect
      (fn [_c]
        (error "later connector listener failed"))))
  (local (ok _err)
    (pcall
      (fn []
        (board:add-connector {:source-item-id source.id
                              :target-item-id target.id}))))
  (board.connector-added:disconnect failing-handler true)
  (assert (not ok)
          "Board.add-connector should fail when later listener fails")
  (assert (= (length board.connectors-in-order) 0)
          "Board should roll back connector after later listener failure")
  (assert (= (length viewed-added-ids) 1)
          "Board should have emitted connector-added before later listener failure")
  (assert (= (length viewed-removed-ids) 1)
          "Board should emit connector-removed to clean up after rollback")
  (assert (= (. viewed-removed-ids 1) (. viewed-added-ids 1))
          "Board should emit connector-removed for the rolled-back connector")
  true)

(fn board-remove-connector-rolls-back-after-listener-failure []
  (local board (Board {}))
  (local source (board:add-item {:type "anything"}))
  (local target (board:add-item {:type "anything"}))
  (local connector (board:add-connector {:source-item-id source.id
                                         :target-item-id target.id}))
  (var removed-called? false)
  (board.connector-removed:connect
    (fn [_c]
      (set removed-called? true)
      (error "connector-removed listener failed")))
  (local (ok _err)
    (pcall
      (fn []
        (board:remove-connector connector.id))))
  (assert (not ok)
          "Board.remove-connector should fail when connector-removed listener fails")
  (assert (. board.connectors connector.id)
          "Board should roll back connector removal after listener failure")
  (assert (= (length board.connectors-in-order) 1)
          "Board should not lose ordered connector after listener failure")
  true)

(fn board-remove-item-rolls-back-after-listener-failure []
  (local board (Board {}))
  (local item (board:add-item {:type "anything"}))
  (var removed-called? false)
  (board.item-removed:connect
    (fn [_item]
      (set removed-called? true)
      (error "item-removed listener failed")))
  (local (ok _err)
    (pcall
      (fn []
        (board:remove-item item.id))))
  (assert (not ok)
          "Board.remove-item should fail when item-removed listener fails")
  (assert (. board.items item.id)
          "Board should roll back item removal after listener failure")
  (assert (= (length board.items-in-order) 1)
          "Board should not lose ordered item after listener failure")
  true)

(fn board-remove-item-rolls-back-connectors-after-item-removed-listener-failure []
  (local board (Board {}))
  (local source (board:add-item {:type "anything"}))
  (local target (board:add-item {:type "anything"}))
  (local connector (board:add-connector {:source-item-id source.id
                                          :target-item-id target.id}))
  (var added-on-rollback-ids [])
  (board.connector-added:connect
    (fn [c]
      (table.insert added-on-rollback-ids c.id)))
  (board.item-removed:connect
    (fn [_item]
      (error "item-removed listener failed")))
  (local (ok _err)
    (pcall
      (fn []
        (board:remove-item source.id))))
  (assert (not ok)
          "Board.remove-item should fail when item-removed listener fails")
  (assert (. board.items source.id)
          "Board should roll back source item removal")
  (assert (. board.connectors connector.id)
          "Board should roll back dependent connector removal after item-removed listener failure")
  (assert (= (length added-on-rollback-ids) 1)
          "Board should emit connector-added for the rolled-back connector")
  (assert (= (. added-on-rollback-ids 1) connector.id)
          "Board should emit connector-added for the specific rolled-back connector")
  true)

(fn board-remove-item-rolls-back-connected-connectors-after-mid-removal-failure []
  (local board (Board {}))
  (local source (board:add-item {:type "anything"}))
  (local target1 (board:add-item {:type "anything"}))
  (local target2 (board:add-item {:type "anything"}))
  (local connector1 (board:add-connector {:source-item-id source.id
                                          :target-item-id target1.id}))
  (local connector2 (board:add-connector {:source-item-id source.id
                                          :target-item-id target2.id}))
  (var added-on-rollback-ids [])
  (board.connector-added:connect
    (fn [c]
      (table.insert added-on-rollback-ids c.id)))
  (board.connector-removed:connect
    (fn [c]
      (when (= c.id connector2.id)
        (error "connector2 removal listener failed"))))
  (local (ok _err)
    (pcall
      (fn []
        (board:remove-item source.id))))
  (assert (not ok)
          "Board.remove-item should fail when dependent connector removal fails")
  (assert (. board.items source.id)
          "Board should roll back source item after dependent connector removal failure")
  (assert (. board.connectors connector1.id)
          "Board should roll back first dependent connector after second one fails")
  (assert (. board.connectors connector2.id)
          "Board should roll back the failing connector")
  (assert (>= (length added-on-rollback-ids) 1)
          "Board should emit connector-added for rolled-back connectors")
  true)

(fn board-view-rejects-missing-semantic-link-on-hydration []
  (with-temp-dir
    (fn [dir]
      (local owner {})
      (BoardRegistry.unregister-item-type "test-item" owner)
      (BoardRegistry.register-item-type {:id "test-item"
                                          :label "Test"
                                          :builder dummy-widget}
                                         owner)
      (local root (LayoutRoot))
      (local ctx (BuildContext {:layout-root root}))
      (local board (Board {:state {:items [{:id "source"
                                             :type "test-item"
                                             :subject-key "string-entity:source"}
                                            {:id "target"
                                             :type "test-item"
                                             :subject-key "string-entity:target"}]
                                     :connectors [{:id "connector-1"
                                                   :source-item-id "source"
                                                   :target-item-id "target"
                                                   :kind "semantic-link"
                                                   :semantic-link-id "deleted-link"}]}}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (local (ok err)
        (pcall
          (fn []
            (BoardView {:board board
                        :canvas {:layout-root root :build-context ctx}
                        :ctx ctx
                        :link-store link-store}))))
      (BoardRegistry.unregister-owner owner)
      (assert (not ok)
              "BoardView should reject semantic connectors whose link entity is missing")
      (assert (and err (string.find err "missing link entity" 1 true))
              "BoardView should report missing semantic link entity")
      true)))

(fn board-view-hydration-failure-disconnects-handlers []
  (with-temp-dir
    (fn [dir]
      (local owner {})
      (local post-owner {})
      (var build-count 0)
      (BoardRegistry.unregister-item-type "test-item" owner)
      (BoardRegistry.register-item-type {:id "test-item"
                                          :label "Test"
                                          :builder (fn [item]
                                                     (fn [ctx]
                                                       (set build-count (+ build-count 1))
                                                       ((dummy-widget item) ctx)))}
                                         owner)
      (BoardRegistry.unregister-item-type "post-drop-item" post-owner)
      (BoardRegistry.register-item-type {:id "post-drop-item"
                                          :label "PostDrop"
                                          :builder dummy-widget}
                                         post-owner)
      (local root (LayoutRoot))
      (local ctx (BuildContext {:layout-root root}))
      (local board (Board {:state {:items [{:id "source"
                                             :type "test-item"
                                             :subject-key "string-entity:source"}
                                            {:id "target"
                                             :type "test-item"
                                             :subject-key "string-entity:target"}]
                                     :connectors [{:id "connector-1"
                                                   :source-item-id "source"
                                                   :target-item-id "target"
                                                   :kind "semantic-link"
                                                   :semantic-link-id "deleted-link"}]}}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (local (ok _err)
        (pcall
          (fn []
            (BoardView {:board board
                        :canvas {:layout-root root :build-context ctx}
                        :ctx ctx
                        :link-store link-store}))))
      (BoardRegistry.unregister-owner owner)
      (assert (not ok)
              "test setup should fail BoardView hydration")
      (assert (= build-count 2)
              "test setup should build existing items before connector hydration fails")
      (board:add-item {:type "post-drop-item"})
      (assert (= build-count 2)
              "BoardView should disconnect item handlers when initial hydration fails")
      (BoardRegistry.unregister-owner post-owner)
      true)))

(fn string-entity-create-returns-board-item []
  (local board (Board {}))
  (local default-store (StringEntityStore.get-default))
  (local item (BuiltinStringEntity.create-string-entity board {}))
  (assert item "String entity create should return the board item")
  (assert (= item.type BuiltinStringEntity.item-type)
          "String entity create should return the created string board item")
  (local identity-store ((. (require :entities/identity) :get-default) {:base-dir default-store.base-dir}))
  (local entity-id (BuiltinStringEntity.entity-id-from-subject (identity-store:resolve-key item.subject-key)))
  (when entity-id
    (default-store:retire-entity! entity-id))
  (board:remove-item item.id)
  true)

(fn board-view-transform-update-dirties-layer-layout []
  (local owner {})
  (BoardRegistry.unregister-item-type "test-item" owner)
  (BoardRegistry.register-item-type {:id "test-item"
                                     :label "Test"
                                     :builder dummy-widget}
                                    owner)
  (local root (LayoutRoot))
  (local ctx (BuildContext {:layout-root root}))
  (local board (Board {}))
  (local view (BoardView {:board board
                          :canvas {:layout-root root :build-context ctx}
                          :ctx ctx}))
  (local item (view:add-item {:type "test-item"}))
  (board:update-item-transform item.id {:position (glm.vec3 12 13 0)})
  (root:update)
  (local record (. view.item-records item.id))
  (assert (= record.element.layout.position.x 12)
          "BoardView should move item layout after external x transform updates")
  (assert (= record.element.layout.position.y 13)
          "BoardView should move item layout after external y transform updates")
  (view:drop)
  (BoardRegistry.unregister-owner owner)
  true)

(fn board-view-resizable-target-updates-board-transform []
  (local previous-movables app.movables)
  (local previous-resizables app.resizables)
  (local owner {})
  (local registered [])
  (var unregister-count 0)
  (BoardRegistry.unregister-item-type "resize-item" owner)
  (BoardRegistry.register-item-type {:id "resize-item"
                                     :label "Resize"
                                     :builder dummy-widget}
                                    owner)
  (set app.movables nil)
  (set app.resizables {:register (fn [_self element opts]
                                   (table.insert registered {:element element
                                                             :opts opts})
                                   opts)
                       :unregister (fn [_self _element]
                                     (set unregister-count (+ unregister-count 1)))})
  (local (ok result)
    (pcall
      (fn []
        (local root (LayoutRoot))
        (local ctx (BuildContext {:layout-root root}))
        (local pointer-target {:interaction-surface :canvas
                               :activity-slot {:interactive? true}})
        (set ctx.pointer-target pointer-target)
        (local canvas {:layout-root root
                       :build-context ctx})
        (local board (Board {}))
        (local view (BoardView {:board board
                                :canvas canvas
                                :ctx ctx}))
        (local item (view:add-item {:type "resize-item"
                                    :position (glm.vec3 1 2 0)
                                    :size (glm.vec3 8 4 0)}))
        (assert (= (length registered) 1)
                "BoardView should register board items with resizables")
        (local entry (. registered 1))
        (local target (assert entry.opts.target
                              "BoardView resizable registration requires a target"))
        (assert (= entry.opts.pointer-target pointer-target)
                "BoardView resizable registration should target the build context pointer target")
        (target:set-position (glm.vec3 9 10 0))
        (target:set-size (glm.vec3 20 12 0))
        (assert (= item.position.x 9)
                "BoardView resizable target should persist x position updates")
        (assert (= item.position.y 10)
                "BoardView resizable target should persist y position updates")
        (assert (= item.size.x 20)
                "BoardView resizable target should persist width updates")
        (assert (= item.size.y 12)
                "BoardView resizable target should persist height updates")
        (root:update)
        (local record (. view.item-records item.id))
        (assert (= record.element.layout.size.x 20)
                "BoardView should apply resized width to the item layout")
        (assert (= record.element.layout.size.y 12)
                "BoardView should apply resized height to the item layout")
        (var update-count 0)
        (local update-handler
          (board.item-updated:connect
            (fn [_updated]
              (set update-count (+ update-count 1)))))
        (target:set-transform {:position (glm.vec3 30 31 0)
                               :size (glm.vec3 40 41 0)})
        (assert (= update-count 1)
                "BoardView target transform should emit exactly one board update")
        (assert (= item.position.x 30)
                "BoardView target transform should persist combined x position")
        (assert (= item.size.x 40)
                "BoardView target transform should persist combined width")
        (board.item-updated:disconnect update-handler true)
        (view:drop)
        (assert (= unregister-count 1)
                "BoardView should unregister board item resizables on drop")
        true)))
  (set app.movables previous-movables)
  (set app.resizables previous-resizables)
  (BoardRegistry.unregister-owner owner)
  (if ok result (error result)))

(fn board-view-transform-target-rolls-back-after-board-failure []
  (local previous-movables app.movables)
  (local previous-resizables app.resizables)
  (local owner {})
  (local registered [])
  (BoardRegistry.unregister-item-type "rollback-item" owner)
  (BoardRegistry.register-item-type {:id "rollback-item"
                                     :label "Rollback"
                                     :builder dummy-widget}
                                    owner)
  (set app.movables nil)
  (set app.resizables {:register (fn [_self element opts]
                                   (table.insert registered {:element element
                                                             :opts opts})
                                   opts)
                       :unregister (fn [_self _element] nil)})
  (local (ok result)
    (pcall
      (fn []
        (local root (LayoutRoot))
        (local ctx (BuildContext {:layout-root root}))
        (local canvas {:layout-root root
                       :build-context ctx})
        (local board (Board {}))
        (local view (BoardView {:board board
                                :canvas canvas
                                :ctx ctx}))
        (local item (view:add-item {:type "rollback-item"
                                    :position (glm.vec3 1 2 0)
                                    :size (glm.vec3 8 4 0)}))
        (root:update)
        (local record (. view.item-records item.id))
        (local entry (. registered 1))
        (local target (assert entry.opts.target
                              "BoardView resizable registration requires a target"))
        (local handler
          (board.item-updated:connect
            (fn [updated]
              (when (or (= updated.position.x 99)
                        (= updated.size.x 99))
                (error "reject transform")))))
        (local (position-ok _position-err)
          (pcall (fn []
                   (target:set-position (glm.vec3 99 10 0)))))
        (assert (not position-ok)
                "BoardView target position update should fail when board transform fails")
        (assert (= item.position.x 1)
                "Board item x position should roll back after rejected target position")
        (assert (= target.position.x 1)
                "Board target x position should not pre-mutate before rejected board position")
        (assert (= record.metadata.world-position.x 1)
                "Board metadata x position should roll back after rejected target position")
        (local (size-ok _size-err)
          (pcall (fn []
                   (target:set-size (glm.vec3 99 12 0)))))
        (assert (not size-ok)
                "BoardView target size update should fail when board transform fails")
        (assert (= item.size.x 8)
                "Board item width should roll back after rejected target size")
        (assert (= target.size.x 8)
                "Board target width should not pre-mutate before rejected board size")
        (assert (= record.element.layout.size.x 8)
                "Board item layout width should roll back after rejected target size")
        (local (transform-ok _transform-err)
          (pcall (fn []
                   (target:set-transform {:position (glm.vec3 50 10 0)
                                          :size (glm.vec3 99 12 0)}))))
        (assert (not transform-ok)
                "BoardView target transform update should fail when combined board transform fails")
        (assert (= item.position.x 1)
                "Board item x position should roll back after rejected combined target transform")
        (assert (= item.size.x 8)
                "Board item width should roll back after rejected combined target transform")
        (assert (= target.position.x 1)
                "Board target x position should not pre-mutate before rejected combined transform")
        (assert (= target.size.x 8)
                "Board target width should not pre-mutate before rejected combined transform")
        (board.item-updated:disconnect handler true)
        (view:drop)
        true)))
  (set app.movables previous-movables)
  (set app.resizables previous-resizables)
  (BoardRegistry.unregister-owner owner)
  (if ok result (error result)))

(fn board-root-action-uses-root-event-position []
  (local previous-active-world-runtime app.active-world-runtime)
  (local previous-canvas app.canvas)
  (local previous-board app.board)
  (local previous-board-view app.board-view)
  (local previous-registry app.activity-registry)
  (local previous-activities-changed app.activities-changed)
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (var ray-event nil)
  (local fixture (make-activity-canvas
                   {:screen-pos-ray (fn [_self event]
                                      (set ray-event event)
                                      {:origin (glm.vec3 (or event.x 0) (or event.y 0) 30)
                                       :direction (glm.vec3 2 4 -10)})}))
  (local canvas fixture.canvas)
  (set app.active-world-runtime {:canvas canvas
                                 :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}} :scene (make-scene-stub)
                                 :board-state {:items [] :connectors []}})
  (set app.canvas canvas)
  (BoardActivityUnit.load-board-activity!)
  (Activities.activate-activity "board")
  (local actions (app.activity-root-actions {:event {:screen {:x 10 :y 20}}}))
  ((. (. actions 1) :fn) nil {:x 90 :y 100})
  (assert (= ray-event.x 10)
          "Board root action should extract pointer from context-menu event.screen")
  (assert (= ray-event.y 20)
          "Board root action should use event.screen coordinates for placement")
  (assert (not ray-event.screen)
          "Board root action should unwrap event.screen before passing to canvas screen-pos-ray")
  (local item (. app.board.items-in-order 1))
  (assert (= item.position.x 16)
          "Board root action should place items at the ray intersection with the z=0 plane")
  (assert (= item.position.y 32)
          "Board root action should use the ray direction when placing board items")
  (BoardActivityUnit.unload-board-activity!)
  (set app.active-world-runtime previous-active-world-runtime)
  (set app.canvas previous-canvas)
  (set app.board previous-board)
  (set app.board-view previous-board-view)
  (set app.activity-registry previous-registry)
  (set app.activities-changed previous-activities-changed)
  (fixture:drop)
  true)

(fn board-root-action-uses-explicit-event-ray []
  (local previous-active-world-runtime app.active-world-runtime)
  (local previous-canvas app.canvas)
  (local previous-board app.board)
  (local previous-board-view app.board-view)
  (local previous-registry app.activity-registry)
  (local previous-activities-changed app.activities-changed)
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (var screen-pos-ray-calls 0)
  (local fixture (make-activity-canvas
                   {:screen-pos-ray (fn [_self _event]
                                      (set screen-pos-ray-calls (+ screen-pos-ray-calls 1))
                                      (error "screen-pos-ray should not be called when event.ray is present"))}))
  (local canvas fixture.canvas)
  (set app.active-world-runtime {:canvas canvas
                                 :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}} :scene (make-scene-stub)
                                 :board-state {:items [] :connectors []}})
  (set app.canvas canvas)
  (BoardActivityUnit.load-board-activity!)
  (Activities.activate-activity "board")
  (local explicit-ray {:origin (glm.vec3 50 60 30)
                       :direction (glm.vec3 2 4 -10)})
  (local actions (app.activity-root-actions {:event {:ray explicit-ray
                                                         :screen {:x 10 :y 20}}}))
  ((. (. actions 1) :fn) nil {:x 90 :y 100})
  (assert (= screen-pos-ray-calls 0)
          "Board root action should prefer event.ray and skip canvas.screen-pos-ray")
  (local item (. app.board.items-in-order 1))
  (assert (= item.position.x 56)
          "Board root action should place item from event.ray origin and direction")
  (assert (= item.position.y 72)
          "Board root action should compute z=0 plane intersection from the explicit ray")
  (BoardActivityUnit.unload-board-activity!)
  (set app.active-world-runtime previous-active-world-runtime)
  (set app.canvas previous-canvas)
  (set app.board previous-board)
  (set app.board-view previous-board-view)
  (set app.activity-registry previous-registry)
  (set app.activities-changed previous-activities-changed)
  (fixture:drop)
  true)

(table.insert tests {:name "BoardView hydrates existing items with view context"
                     :fn board-view-hydrates-existing-items-with-view-context})
(table.insert tests {:name "Board rejects invalid transforms"
                     :fn board-rejects-invalid-transforms})
(table.insert tests {:name "Board update transform is atomic"
                     :fn board-update-transform-is-atomic})
(table.insert tests {:name "Board auto ids skip restored sparse ids"
                     :fn board-auto-ids-skip-restored-sparse-ids})
(table.insert tests {:name "Board restore resets auto id sequences"
                     :fn board-restore-resets-auto-id-sequences})
(table.insert tests {:name "String entity widget requires existing entity"
                     :fn string-entity-widget-requires-existing-entity})
(table.insert tests {:name "String entity create rolls back on board failure"
                     :fn string-entity-create-rolls-back-on-board-failure})
(table.insert tests {:name "String entity create rolls back after item-added failure"
                     :fn string-entity-create-rolls-back-after-item-added-failure})
(table.insert tests {:name "BoardView add-item cleans up partial attachment on view failure"
                     :fn board-view-add-item-cleans-up-partial-attachment-on-view-failure})
(table.insert tests {:name "BoardView connect rolls back new link on board failure"
                     :fn board-view-connect-rolls-back-new-link-on-board-failure})
(table.insert tests {:name "Board add connector rolls back after listener failure"
                     :fn board-add-connector-rolls-back-after-listener-failure})
(table.insert tests {:name "Board add-item rolls back side effects after later listener failure"
                     :fn board-add-item-rolls-back-side-effects-after-later-listener-failure})
(table.insert tests {:name "Board update transform rolls back after later listener failure"
                     :fn board-update-transform-rolls-back-after-later-listener-failure})
(table.insert tests {:name "Board add connector rolls back side effects after later listener failure"
                      :fn board-add-connector-rolls-back-side-effects-after-later-listener-failure})
(table.insert tests {:name "Board remove connector rolls back after listener failure"
                      :fn board-remove-connector-rolls-back-after-listener-failure})
(table.insert tests {:name "Board remove item rolls back after listener failure"
                      :fn board-remove-item-rolls-back-after-listener-failure})
(table.insert tests {:name "Board remove item rolls back connectors after item-removed listener failure"
                      :fn board-remove-item-rolls-back-connectors-after-item-removed-listener-failure})
(table.insert tests {:name "Board remove item rolls back connected connectors after mid-removal failure"
                      :fn board-remove-item-rolls-back-connected-connectors-after-mid-removal-failure})
(table.insert tests {:name "BoardView rejects missing semantic link on hydration"
                     :fn board-view-rejects-missing-semantic-link-on-hydration})
(table.insert tests {:name "BoardView hydration failure disconnects handlers"
                     :fn board-view-hydration-failure-disconnects-handlers})
(table.insert tests {:name "String entity create returns board item"
                     :fn string-entity-create-returns-board-item})
(table.insert tests {:name "BoardView transform update dirties layer layout"
                     :fn board-view-transform-update-dirties-layer-layout})
(table.insert tests {:name "BoardView resizable target updates board transform"
                     :fn board-view-resizable-target-updates-board-transform})
(table.insert tests {:name "BoardView transform target rolls back after board failure"
                     :fn board-view-transform-target-rolls-back-after-board-failure})
(table.insert tests {:name "Board root action uses root event position"
                     :fn board-root-action-uses-root-event-position})
(table.insert tests {:name "Board root action uses explicit event.ray"
                     :fn board-root-action-uses-explicit-event-ray})

(fn board-root-action-uses-ray-only-event []
  (local previous-active-world-runtime app.active-world-runtime)
  (local previous-canvas app.canvas)
  (local previous-board app.board)
  (local previous-board-view app.board-view)
  (local previous-registry app.activity-registry)
  (local previous-activities-changed app.activities-changed)
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (var screen-pos-ray-calls 0)
  (local fixture (make-activity-canvas
                   {:screen-pos-ray (fn [_self _event]
                                      (set screen-pos-ray-calls (+ screen-pos-ray-calls 1))
                                      (error "screen-pos-ray should not be called when event.ray is present"))}))
  (local canvas fixture.canvas)
  (set app.active-world-runtime {:canvas canvas
                                 :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}} :scene (make-scene-stub)
                                 :board-state {:items [] :connectors []}})
  (set app.canvas canvas)
  (BoardActivityUnit.load-board-activity!)
  (Activities.activate-activity "board")
  (local explicit-ray {:origin (glm.vec3 50 60 30)
                       :direction (glm.vec3 2 4 -10)})
  (local actions (app.activity-root-actions {:event {:ray explicit-ray}}))
  ((. (. actions 1) :fn) nil nil)
  (assert (= screen-pos-ray-calls 0)
          "Board root action should prefer event.ray without event.screen present")
  (local item (. app.board.items-in-order 1))
  (assert (= item.position.x 56)
          "Board root action should place item from event.ray when only :ray is present")
  (assert (= item.position.y 72)
          "Board root action should compute z=0 plane intersection from ray-only event")
  (BoardActivityUnit.unload-board-activity!)
  (set app.active-world-runtime previous-active-world-runtime)
  (set app.canvas previous-canvas)
  (set app.board previous-board)
  (set app.board-view previous-board-view)
  (set app.activity-registry previous-registry)
  (set app.activities-changed previous-activities-changed)
  (fixture:drop)
  true)

(table.insert tests {:name "Board root action uses ray-only event"
                     :fn board-root-action-uses-ray-only-event})

(fn board-placement-rejects-malformed-event []
  (local previous-active-world-runtime app.active-world-runtime)
  (local previous-canvas app.canvas)
  (local previous-board app.board)
  (local previous-board-view app.board-view)
  (local previous-registry app.activity-registry)
  (local previous-activities-changed app.activities-changed)
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (var screen-pos-ray-calls 0)
  (local fixture (make-activity-canvas
                   {:screen-pos-ray (fn [_self _event]
                                      (set screen-pos-ray-calls (+ screen-pos-ray-calls 1))
                                      {:origin (glm.vec3 0 0 0)
                                       :direction (glm.vec3 0 0 1)})}))
  (local canvas fixture.canvas)
  (set app.active-world-runtime {:canvas canvas
                                 :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}} :scene (make-scene-stub)
                                 :board-state {:items [] :connectors []}})
  (set app.canvas canvas)
  (BoardActivityUnit.load-board-activity!)
  (Activities.activate-activity "board")
  (local actions (app.activity-root-actions {:event {}}))
  (local (ok err) (pcall (fn []
                           ((. (. actions 1) :fn) nil nil))))
  (assert (not ok)
          "Board placement should reject malformed event without ray, screen, or x/y")
  (assert (and err (string.find err "requires event.ray" 1 true))
          "Board placement should explain what event shape is required")
  (assert (= screen-pos-ray-calls 0)
          "Board placement should not call canvas.screen-pos-ray with malformed event")
  (BoardActivityUnit.unload-board-activity!)
  (set app.active-world-runtime previous-active-world-runtime)
  (set app.canvas previous-canvas)
  (set app.board previous-board)
  (set app.board-view previous-board-view)
  (set app.activity-registry previous-registry)
  (set app.activities-changed previous-activities-changed)
  (fixture:drop)
  true)

(table.insert tests {:name "Board placement rejects malformed event"
                     :fn board-placement-rejects-malformed-event})

(fn board-activity-drops-view-on-restore-failure []
  (with-temp-dir
    (fn [dir]
      (local previous-active-world-runtime app.active-world-runtime)
      (local previous-active-world-entry app.active-world-entry)
      (local previous-canvas app.canvas)
      (local previous-board app.board)
      (local previous-board-view app.board-view)
      (local previous-registry app.activity-registry)
      (local previous-activities-changed app.activities-changed)
      (set app.activity-registry nil)
      (set app.activities-changed nil)
      (local fixture (make-activity-canvas))
      (local canvas fixture.canvas)
      (local runtime {:canvas canvas
                       :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}} :scene (make-scene-stub)
                       :board-state {:items [{:id "bad"
                                              :type "missing-board-item-type"}]
                                    :connectors []}})
      (set app.active-world-entry {:dir dir})
      (set app.active-world-runtime runtime)
      (set app.canvas canvas)
      (BoardActivityUnit.load-board-activity!)
      (local (ok _err)
        (pcall (fn []
                 (Activities.activate-activity "board"))))
      (assert (not ok)
              "Board activity activation should fail when restored item type is unknown")
      (assert (not app.board-view)
              "Board activity activation failure should clear app.board-view")
      (assert (not runtime.board-view)
              "Board activity activation failure should clear runtime.board-view")
      (BoardActivityUnit.unload-board-activity!)
      (set app.active-world-runtime previous-active-world-runtime)
      (set app.active-world-entry previous-active-world-entry)
      (set app.canvas previous-canvas)
      (set app.board previous-board)
      (set app.board-view previous-board-view)
      (set app.activity-registry previous-registry)
      (set app.activities-changed previous-activities-changed)
      (fixture:drop)
      true)))

(table.insert tests {:name "Board activity drops view on restore failure"
                     :fn board-activity-drops-view-on-restore-failure})

(fn board-activity-owns-board-view-lifecycle []
  (with-temp-dir
    (fn [dir]
      (local previous-active-world-runtime app.active-world-runtime)
      (local previous-active-world-entry app.active-world-entry)
      (local previous-canvas app.canvas)
      (local previous-board app.board)
      (local previous-board-view app.board-view)
      (local previous-registry app.activity-registry)
      (local previous-activities-changed app.activities-changed)
      (set app.activity-registry nil)
      (set app.activities-changed nil)
      (local fixture (make-activity-canvas))
      (local canvas fixture.canvas)
      (set app.active-world-entry {:dir dir})
      (set app.active-world-runtime {:canvas canvas
                                      :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}} :scene (make-scene-stub)
                                      :board-state {:items [] :connectors []}})
      (set app.canvas canvas)
      (BoardActivityUnit.load-board-activity!)
      (Activities.activate-activity "board")
      (local slot (canvas:activity-slot "board"))
      (assert slot "Board activity should create a board canvas slot")
      (assert (= canvas.active-activity-slot slot)
              "Board activity should activate its canvas slot")
      (assert (= slot.pointer-target.canvas-target-kind :board)
              "Board activity slot should expose board target kind")
      (assert app.board-view "Board activity activation should create app.board-view")
      (assert app.active-world-runtime.board-view
              "Board activity activation should bind runtime.board-view")
      (assert (= app.board-view.ctx slot.ctx)
              "Board view should be built with the board slot context")
      (assert (= app.board-view.ctx.pointer-target slot.pointer-target)
              "Board view context should route interactions through the board slot pointer target")
      (assert (= (canvas:get-triangle-vector) slot.ctx.triangle-vector)
              "Active board slot draw data should be exposed by the canvas")
      (Activities.deactivate-active-activity)
      (assert (not slot.visible?)
              "Board activity deactivation should hide the board slot")
      (assert (not app.board-view) "Board activity deactivation should clear app.board-view")
      (assert app.active-world-runtime.board-view
              "Board activity deactivation should retain runtime.board-view")
      (BoardActivityUnit.unload-board-activity!)
      (set app.active-world-runtime previous-active-world-runtime)
      (set app.active-world-entry previous-active-world-entry)
      (set app.canvas previous-canvas)
      (set app.board previous-board)
      (set app.board-view previous-board-view)
      (set app.activity-registry previous-registry)
      (set app.activities-changed previous-activities-changed)
      (fixture:drop)
      true)))

(table.insert tests {:name "Board activity owns board view lifecycle"
                     :fn board-activity-owns-board-view-lifecycle})

(fn board-activity-restore-active-activity-uses-snapshot-state []
  (with-temp-dir
    (fn [dir]
      (local previous-active-world-runtime app.active-world-runtime)
      (local previous-active-world-entry app.active-world-entry)
      (local previous-canvas app.canvas)
      (local previous-board app.board)
      (local previous-board-view app.board-view)
      (local previous-registry app.activity-registry)
      (local previous-activities-changed app.activities-changed)
      (set app.activity-registry nil)
      (set app.activities-changed nil)
      (local fixture (make-activity-canvas))
      (local canvas fixture.canvas)
      (set app.active-world-entry {:dir dir})
      (set app.active-world-runtime {:canvas canvas
                                      :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}} :scene (make-scene-stub)
                                      :board-state {:items [] :connectors []}})
      (set app.canvas canvas)
      (BoardActivityUnit.load-board-activity!)
      (Activities.activate-activity "board")
      (app.board-view:add-string-entity {})
      (local snapshot (Activities.snapshot-active-activity))
      (app.board-view:add-string-entity {})
      (assert (= (length app.board.items-in-order) 2)
              "test setup should have two live board items before restore")
      (Activities.restore-active-activity snapshot)
      (assert (= (length app.board.items-in-order) 1)
              "Activities.restore-active-activity should pass snapshot state to board activity restore")
      (BoardActivityUnit.unload-board-activity!)
      (set app.active-world-runtime previous-active-world-runtime)
      (set app.active-world-entry previous-active-world-entry)
      (set app.canvas previous-canvas)
      (set app.board previous-board)
      (set app.board-view previous-board-view)
      (set app.activity-registry previous-registry)
      (set app.activities-changed previous-activities-changed)
      (fixture:drop)
      true)))

(table.insert tests {:name "Board activity restore-active-activity uses snapshot state"
                     :fn board-activity-restore-active-activity-uses-snapshot-state})

(fn board-view-hydration-retargets-stale-connectors []
  (with-temp-dir
    (fn [dir]
      (local owner {})
      (BoardRegistry.unregister-item-type "test-item" owner)
      (BoardRegistry.register-item-type {:id "test-item"
                                         :label "Test"
                                         :builder dummy-widget}
                                        owner)
      (local root (LayoutRoot))
      (local ctx (BuildContext {:layout-root root}))
      (local board (Board {:state
        {:items [{:id "source" :type "test-item" :subject-key "sk:src"
                  :position [0 0 0] :rotation [1 0 0 0] :size [8 4 0]}
                 {:id "old-target" :type "test-item" :subject-key "sk:old"
                  :position [10 0 0] :rotation [1 0 0 0] :size [8 4 0]}
                 {:id "new-target" :type "test-item" :subject-key "sk:new"
                  :position [20 0 0] :rotation [1 0 0 0] :size [8 4 0]}]
         :connectors [{:id "c1"
                       :source-item-id "source"
                       :target-item-id "old-target"
                       :kind "semantic-link"
                       :semantic-link-id "link-1"}]}}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (link-store:create-entity {:id "link-1"
                                 :source-key "sk:src"
                                 :target-key "sk:new"})
      (local view (BoardView {:board board
                              :canvas {:layout-root root :build-context ctx}
                              :ctx ctx
                              :link-store link-store}))
      (local connector (. board.connectors "c1"))
      (assert connector
              "BoardView should retain connector when link keys match board items")
      (assert (= connector.target-item-id "new-target")
              "BoardView should retarget stale connector endpoints during hydration")
      (view:drop)
      (BoardRegistry.unregister-owner owner)
      true)))

(table.insert tests {:name "BoardView hydration retargets stale connectors"
                     :fn board-view-hydration-retargets-stale-connectors})

(fn board-view-hydration-removes-untargetable-connectors []
  (with-temp-dir
    (fn [dir]
      (local owner {})
      (BoardRegistry.unregister-item-type "test-item" owner)
      (BoardRegistry.register-item-type {:id "test-item"
                                         :label "Test"
                                         :builder dummy-widget}
                                        owner)
      (local root (LayoutRoot))
      (local ctx (BuildContext {:layout-root root}))
      (local board (Board {:state
        {:items [{:id "source" :type "test-item" :subject-key "sk:src"
                  :position [0 0 0] :rotation [1 0 0 0] :size [8 4 0]}
                 {:id "target" :type "test-item" :subject-key "sk:tgt"
                  :position [10 0 0] :rotation [1 0 0 0] :size [8 4 0]}]
         :connectors [{:id "c1"
                       :source-item-id "source"
                       :target-item-id "target"
                       :kind "semantic-link"
                       :semantic-link-id "link-1"}]}}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (link-store:create-entity {:id "link-1"
                                 :source-key "sk:missing-src"
                                 :target-key "sk:missing-tgt"})
      (local view (BoardView {:board board
                              :canvas {:layout-root root :build-context ctx}
                              :ctx ctx
                              :link-store link-store}))
      (assert (not (. board.connectors "c1"))
              "BoardView should remove connector when link keys match no board items")
      (view:drop)
      (BoardRegistry.unregister-owner owner)
      true)))

(table.insert tests {:name "BoardView hydration removes untargetable connectors"
                     :fn board-view-hydration-removes-untargetable-connectors})

(fn board-view-connect-items-rejects-mismatched-link []
  (with-temp-dir
    (fn [dir]
      (local owner {})
      (BoardRegistry.unregister-item-type "test-item" owner)
      (BoardRegistry.register-item-type {:id "test-item"
                                         :label "Test"
                                         :builder dummy-widget}
                                        owner)
      (local root (LayoutRoot))
      (local ctx (BuildContext {:layout-root root}))
      (local board (Board {}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (local view (BoardView {:board board
                              :canvas {:layout-root root :build-context ctx}
                              :ctx ctx
                              :link-store link-store}))
      (local bad-link (link-store:create-entity {:source-key "sk:wrong-src"
                                                  :target-key "sk:wrong-tgt"}))
      (local source (view:add-item {:type "test-item"
                                    :subject-key "sk:src"
                                    :position (glm.vec3 0 0 0)}))
      (local target (view:add-item {:type "test-item"
                                    :subject-key "sk:tgt"
                                    :position (glm.vec3 10 0 0)}))
      (local (ok err)
        (pcall
          (fn []
            (view:connect-items source target {:link bad-link}))))
      (assert (not ok)
              "BoardView.connect-items should reject mismatched link keys")
      (assert (and err (string.find err "source-key does not match source item" 1 true))
              "BoardView.connect-items should report mismatched source-key")
      (view:drop)
      (BoardRegistry.unregister-owner owner)
      true)))

(table.insert tests {:name "BoardView connect-items rejects mismatched link keys"
                     :fn board-view-connect-items-rejects-mismatched-link})

(fn board-view-connect-items-rejects-empty-subject-key []
  (with-temp-dir
    (fn [dir]
      (local owner {})
      (BoardRegistry.unregister-item-type "test-item" owner)
      (BoardRegistry.register-item-type {:id "test-item"
                                          :label "Test"
                                          :builder dummy-widget}
                                         owner)
      (local root (LayoutRoot))
      (local ctx (BuildContext {:layout-root root}))
      (local board (Board {}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (local view (BoardView {:board board
                              :canvas {:layout-root root :build-context ctx}
                              :ctx ctx
                              :link-store link-store}))
      (local source (view:add-item {:type "test-item"
                                    :subject-key ""
                                    :position (glm.vec3 0 0 0)}))
      (local target (view:add-item {:type "test-item"
                                    :subject-key "sk:tgt"
                                    :position (glm.vec3 10 0 0)}))
      (local (ok err)
        (pcall
          (fn []
            (view:connect-items source target))))
      (assert (not ok)
              "BoardView.connect-items should reject empty source subject-key")
      (assert (and err (string.find err "non-empty subject-key" 1 true))
              "BoardView.connect-items should require non-empty subject-key")
      (view:drop)
      (BoardRegistry.unregister-owner owner)
      true)))

(table.insert tests {:name "BoardView connect-items rejects empty subject-key"
                     :fn board-view-connect-items-rejects-empty-subject-key})

(fn board-restore-state-reconciles-stale-semantic-connectors-on-live-view []
  (with-temp-dir
    (fn [dir]
      (local owner {})
      (BoardRegistry.unregister-item-type "test-item" owner)
      (BoardRegistry.register-item-type {:id "test-item"
                                         :label "Test"
                                         :builder dummy-widget}
                                        owner)
      (local root (LayoutRoot))
      (local ctx (BuildContext {:layout-root root}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (link-store:create-entity {:id "link-1"
                                 :source-key "sk:src"
                                 :target-key "sk:tgt"})
      (local board (Board {:state
        {:items [{:id "source" :type "test-item" :subject-key "sk:src"
                  :position [0 0 0] :rotation [1 0 0 0] :size [8 4 0]}
                 {:id "target" :type "test-item" :subject-key "sk:tgt"
                  :position [10 0 0] :rotation [1 0 0 0] :size [8 4 0]}]
         :connectors [{:id "c1"
                       :source-item-id "source"
                       :target-item-id "target"
                       :kind "semantic-link"
                       :semantic-link-id "link-1"}]}}))
      (local view (BoardView {:board board
                              :canvas {:layout-root root :build-context ctx}
                              :ctx ctx
                              :link-store link-store}))
      (assert (. board.connectors "c1")
              "test setup should have live connector before link retarget")
      (link-store:update-entity "link-1" {:source-key "sk:src"
                                          :target-key "sk:gone"})
      (board:restore-state {:items [{:id "source2" :type "test-item" :subject-key "sk:src"
                                      :position [0 0 0] :rotation [1 0 0 0] :size [8 4 0]}]
                             :connectors [{:id "c2"
                                           :source-item-id "source2"
                                           :target-item-id "source2"
                                           :kind "semantic-link"
                                           :semantic-link-id "link-1"}]})
      (assert (not (. board.connectors "c2"))
              "board restore should remove connector when link keys match no board items")
      (view:drop)
      (BoardRegistry.unregister-owner owner)
      true)))

(table.insert tests {:name "board restore-state reconciles stale semantic connectors on live view"
                     :fn board-restore-state-reconciles-stale-semantic-connectors-on-live-view})

(fn with-board-activity-runtime [body opts]
  (local options (or opts {}))
  (local previous-surface app.active-interaction-surface)
  (local previous-preferred-surface app.preferred-interaction-surface)
  (local previous-active-pointer-controls app.active-pointer-controls)
  (local previous-scene-interactive? app.scene-interactive?)
  (local previous-canvas-interactive? app.canvas-interactive?)
  (local previous-canvas-surface-interactive? app.canvas-surface-interactive?)
  (local previous-canvas-visible? app.canvas-visible?)
  (local previous-canvas-controls app.canvas-controls)
  (local previous-first-person-controls app.first-person-controls)
  (local previous-activity app.active-activity-id)
  (local previous-registry app.activity-registry)
  (local previous-activities-changed app.activities-changed)
  (local previous-root app.activity-root-actions)
  (local previous-selection app.activity-selection-actions)
  (local previous-enricher app.activity-context-enricher)
  (local previous-target-enabled app.activity-target-enabled?)
  (local previous-activity-update app.activity-update)
  (local previous-canvas app.canvas)
  (local previous-active-world-runtime app.active-world-runtime)
  (local previous-active-world-entry app.active-world-entry)
  (local previous-board app.board)
  (local previous-board-view app.board-view)
  (set app.activity-registry nil)
  (set app.activities-changed nil)
  (local fixture (make-activity-canvas))
  (local canvas fixture.canvas)
  (local ctx fixture.ctx)
  (local root fixture.root)
  (set app.canvas canvas)
  (set app.active-interaction-surface :canvas)
  (local runtime {:canvas canvas
                  :activity-cameras {:canvas {} :scene {}} :activity-controls {:canvas {} :scene {}} :scene (make-scene-stub)
                  :board-state (or options.board-state {:items [] :connectors []})})
  (when options.stores
    (each [field store (pairs options.stores)] (tset runtime field store))
    (set runtime.reference-lifecycle ((. (require :tests/test-reference-lifecycle-helpers) :ready) options.stores)))
  (when options.object-selector
    (set runtime.object-selector options.object-selector))
  (set app.active-world-runtime runtime)
  (when options.dir
    (set app.active-world-entry {:dir options.dir}))
  (local owner {})
  (BoardRegistry.unregister-item-type "test-item" owner)
  (BoardRegistry.register-item-type {:id "test-item"
                                     :label "Test"
                                     :builder dummy-widget}
                                    owner)
  (BoardActivityUnit.load-board-activity!)
  (Activities.activate-activity "board")
  (local (ok err)
    (pcall (fn []
             (body {:board-view app.board-view
                    :canvas canvas
                    :ctx ctx
                    :root root}))))
  (BoardActivityUnit.unload-board-activity!)
  (set app.active-interaction-surface previous-surface)
  (set app.preferred-interaction-surface previous-preferred-surface)
  (set app.active-pointer-controls previous-active-pointer-controls)
  (set app.scene-interactive? previous-scene-interactive?)
  (set app.canvas-interactive? previous-canvas-interactive?)
  (set app.canvas-surface-interactive? previous-canvas-surface-interactive?)
  (set app.canvas-visible? previous-canvas-visible?)
  (set app.canvas-controls previous-canvas-controls)
  (set app.first-person-controls previous-first-person-controls)
  (set app.active-activity-id previous-activity)
  (set app.activity-registry previous-registry)
  (set app.activities-changed previous-activities-changed)
  (set app.activity-root-actions previous-root)
  (set app.activity-selection-actions previous-selection)
  (set app.activity-context-enricher previous-enricher)
  (set app.activity-target-enabled? previous-target-enabled)
  (set app.activity-update previous-activity-update)
  (set app.canvas previous-canvas)
  (set app.active-world-runtime previous-active-world-runtime)
  (set app.board previous-board)
  (set app.board-view previous-board-view)
  (set app.active-world-entry previous-active-world-entry)
  (BoardRegistry.unregister-owner owner)
  (fixture:drop)
  (when (not ok)
    (error err))
  true)

(fn mock-selector []
  (local changed (Signal))
  (local self {:selectables []
               :changed changed})
  (set self.add-selectables
       (fn [self items]
         (each [_ item (ipairs items)]
           (table.insert self.selectables item))))
  (set self.remove-selectables
       (fn [self items]
         (local keep [])
         (each [_ s (ipairs self.selectables)]
           (var remove? false)
           (each [_ r (ipairs items)]
             (when (= s r)
               (set remove? true)))
           (when (not remove?)
             (table.insert keep s)))
         (set self.selectables keep)))
  self)

(fn board-view-registers-selectables-with-selector []
  (local owner {})
  (BoardRegistry.unregister-item-type "test-item" owner)
  (BoardRegistry.register-item-type {:id "test-item"
                                     :label "Test"
                                     :builder dummy-widget}
                                    owner)
  (local root (LayoutRoot))
  (local ctx (BuildContext {:layout-root root}))
  (local selector (mock-selector))
  (local board (Board {}))
  (local view (BoardView {:board board
                          :canvas {:layout-root root :build-context ctx}
                          :ctx ctx
                          :selector selector}))
  (assert (= (length selector.selectables) 0)
          "BoardView should not register selectables before items are added")
  (local item (view:add-item {:type "test-item"
                              :subject-key "sk:src"
                              :position (glm.vec3 1 2 0)
                              :size (glm.vec3 8 4 0)}))
  (assert (= (length selector.selectables) 1)
          "BoardView should register a selectable when an item is added")
  (local selectable (. selector.selectables 1))
  (assert (= selectable.item item)
          "Selectable should reference the board item")
  (assert (= selectable.position.x 5)
          "Selectable position.x should be item center x")
  (assert (= selectable.position.y 4)
          "Selectable position.y should be item center y")
  (board:remove-item item.id)
  (assert (= (length selector.selectables) 0)
          "BoardView should unregister selectable when item is removed")
  (view:drop)
  (BoardRegistry.unregister-owner owner)
  true)

(fn board-view-selection-tracks-selected-items []
  (local owner {})
  (BoardRegistry.unregister-item-type "test-item" owner)
  (BoardRegistry.register-item-type {:id "test-item"
                                     :label "Test"
                                     :builder dummy-widget}
                                    owner)
  (local root (LayoutRoot))
  (local ctx (BuildContext {:layout-root root}))
  (local selector (mock-selector))
  (local board (Board {}))
  (local view (BoardView {:board board
                          :canvas {:layout-root root :build-context ctx}
                          :ctx ctx
                          :selector selector}))
  (local item-a (view:add-item {:type "test-item"
                                :subject-key "sk:a"
                                :position (glm.vec3 0 0 0)
                                :size (glm.vec3 8 4 0)}))
  (local item-b (view:add-item {:type "test-item"
                                :subject-key "sk:b"
                                :position (glm.vec3 10 0 0)
                                :size (glm.vec3 8 4 0)}))
  (assert (= (length view.selected-items) 0)
          "BoardView should start with empty selected-items")
  (local selectables selector.selectables)
  (selector.changed:emit selectables)
  (assert (= (length view.selected-items) 2)
          "BoardView should track selected items after selector changed")
  (assert (= (. view.selected-items 1) item-a)
          "BoardView selected-items first entry should be item-a")
  (assert (= (. view.selected-items 2) item-b)
          "BoardView selected-items second entry should be item-b")
  (var emitted-count 0)
  (var emitted-items nil)
  (view.selected-items-changed:connect
    (fn [items]
      (set emitted-count (+ emitted-count 1))
      (set emitted-items items)))
  (selector.changed:emit [(. selector.selectables 1)])
  (assert (= emitted-count 1)
          "BoardView selected-items-changed should fire when selector changes")
  (assert (= (length emitted-items) 1)
          "BoardView selected-items-changed should emit only the selected item")
  (view:drop)
  (BoardRegistry.unregister-owner owner)
  true)

(fn board-view-selectable-position-updates-on-transform []
  (local owner {})
  (BoardRegistry.unregister-item-type "test-item" owner)
  (BoardRegistry.register-item-type {:id "test-item"
                                     :label "Test"
                                     :builder dummy-widget}
                                    owner)
  (local root (LayoutRoot))
  (local ctx (BuildContext {:layout-root root}))
  (local selector (mock-selector))
  (local board (Board {}))
  (local view (BoardView {:board board
                          :canvas {:layout-root root :build-context ctx}
                          :ctx ctx
                          :selector selector}))
  (local item (view:add-item {:type "test-item"
                              :subject-key "sk:src"
                              :position (glm.vec3 1 2 0)
                              :size (glm.vec3 8 4 0)}))
  (local selectable (. selector.selectables 1))
  (board:update-item-transform item.id {:position (glm.vec3 20 30 0)})
  (assert (= selectable.position.x 24)
          "Selectable position.x should update after board item moves")
  (assert (= selectable.position.y 32)
          "Selectable position.y should update after board item moves")
  (view:drop)
  (BoardRegistry.unregister-owner owner)
  true)

(fn board-view-drop-cleans-up-selectables []
  (local owner {})
  (BoardRegistry.unregister-item-type "test-item" owner)
  (BoardRegistry.register-item-type {:id "test-item"
                                     :label "Test"
                                     :builder dummy-widget}
                                    owner)
  (local root (LayoutRoot))
  (local ctx (BuildContext {:layout-root root}))
  (local selector (mock-selector))
  (local board (Board {}))
  (local view (BoardView {:board board
                          :canvas {:layout-root root :build-context ctx}
                          :ctx ctx
                          :selector selector}))
  (view:add-item {:type "test-item"
                  :subject-key "sk:a"})
  (assert (= (length selector.selectables) 1)
          "test setup should register selectable")
  (view:drop)
  (assert (= (length selector.selectables) 0)
          "BoardView drop should remove all selectables from selector")
  (BoardRegistry.unregister-owner owner)
  true)

(fn board-selection-action-shows-connect-for-two-connectable-items []
  (with-temp-dir
    (fn [dir]
      (local owner {})
      (BoardRegistry.unregister-item-type "test-item" owner)
      (BoardRegistry.register-item-type {:id "test-item"
                                         :label "Test"
                                         :builder dummy-widget}
                                        owner)
      (local root (LayoutRoot))
      (local ctx (BuildContext {:layout-root root}))
      (local canvas {:layout-root root
                     :build-context ctx})
      (local board (Board {:state {:items [{:id "a" :type "test-item" :subject-key "sk:a"}
                                            {:id "b" :type "test-item" :subject-key "sk:b"}]
                                    :connectors []}}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (local view (BoardView {:board board
                              :canvas canvas
                              :ctx ctx
                              :link-store link-store}))
      (local item-a (. board.items "a"))
      (local item-b (. board.items "b"))
      (assert (= (length board.connectors-in-order) 0)
              "Board should have no connectors before connecting")
      (view:connect-items item-a item-b)
      (assert (= (length board.connectors-in-order) 1)
              "connect-items should create a board connector when exactly two connectable items are given")
      (local connector (. board.connectors-in-order 1))
      (assert (= connector.kind "semantic-link")
              "connect-items should create a semantic-link connector")
      (assert (= connector.source-item-id "a")
              "connect-items should use first item as source")
      (assert (= connector.target-item-id "b")
              "connect-items should use second item as target")
      (local link (link-store:get-entity connector.semantic-link-id))
      (assert link "connect-items should create a persisted link entity")
      (H.assert-reference link-store.identity-store link.source-key
                          "sk:a")
      (H.assert-reference link-store.identity-store link.target-key
                          "sk:b")
      (view:drop)
      (BoardRegistry.unregister-owner owner)
      true)))

(fn board-view-connect-items-is-idempotent []
  (with-temp-dir
    (fn [dir]
      (local owner {})
      (BoardRegistry.unregister-item-type "test-item" owner)
      (BoardRegistry.register-item-type {:id "test-item"
                                         :label "Test"
                                         :builder dummy-widget}
                                        owner)
      (local root (LayoutRoot))
      (local ctx (BuildContext {:layout-root root}))
      (local canvas {:layout-root root
                     :build-context ctx})
      (local board (Board {}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (local view (BoardView {:board board
                              :canvas canvas
                              :ctx ctx
                              :link-store link-store}))
      (local source (view:add-item {:type "test-item"
                                    :subject-key "sk:src"
                                    :position (glm.vec3 0 0 0)}))
      (local target (view:add-item {:type "test-item"
                                    :subject-key "sk:tgt"
                                    :position (glm.vec3 20 0 0)}))
      (local connector1 (view:connect-items source target))
      (assert (= (length board.connectors-in-order) 1)
              "First connect should create one connector")
      (local connector2 (view:connect-items source target))
      (assert (= connector2 connector1)
              "Second connect-items call should return existing connector")
      (assert (= (length board.connectors-in-order) 1)
              "Second connect should not create a duplicate connector")
      (assert (= (length (link-store:list-entities)) 1)
              "Second connect should not create a duplicate link entity")
      (view:drop)
      (BoardRegistry.unregister-owner owner)
      true)))

(fn board-view-connects-items-preserves-direction []
  (with-temp-dir
    (fn [dir]
      (local owner {})
      (BoardRegistry.unregister-item-type "test-item" owner)
      (BoardRegistry.register-item-type {:id "test-item"
                                         :label "Test"
                                         :builder dummy-widget}
                                        owner)
      (local root (LayoutRoot))
      (local ctx (BuildContext {:layout-root root}))
      (local canvas {:layout-root root
                     :build-context ctx})
      (local board (Board {}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (local view (BoardView {:board board
                              :canvas canvas
                              :ctx ctx
                              :link-store link-store}))
      (local source (view:add-item {:type "test-item"
                                    :subject-key "sk:src"
                                    :position (glm.vec3 0 0 0)}))
      (local target (view:add-item {:type "test-item"
                                    :subject-key "sk:tgt"
                                    :position (glm.vec3 20 0 0)}))
      (local connector (view:connect-items source target))
      (local link (link-store:get-entity connector.semantic-link-id))
      (H.assert-reference link-store.identity-store link.source-key
                          "sk:src")
      (H.assert-reference link-store.identity-store link.target-key
                          "sk:tgt")
      (assert (= connector.source-item-id source.id)
              "Board connector source-item-id should match first argument")
      (assert (= connector.target-item-id target.id)
              "Board connector target-item-id should match second argument")
      (view:drop)
      (BoardRegistry.unregister-owner owner)
      true)))

(fn board-view-connector-renders-triangle-line-from-source-to-target []
  (local owner {})
  (BoardRegistry.unregister-item-type "test-item" owner)
  (BoardRegistry.register-item-type {:id "test-item"
                                     :label "Test"
                                     :builder dummy-widget}
                                    owner)
  (local root (LayoutRoot))
  (local ctx (BuildContext {:layout-root root}))
  (local canvas {:layout-root root
                 :build-context ctx})
  (local board (Board {}))
  (local view (BoardView {:board board
                          :canvas canvas
                          :ctx ctx}))
  (local source (view:add-item {:type "test-item"
                                :subject-key "sk:src"
                                :position (glm.vec3 0 0 0)
                                :size (glm.vec3 8 4 0)}))
  (local target (view:add-item {:type "test-item"
                                :subject-key "sk:tgt"
                                :position (glm.vec3 20 10 0)
                                :size (glm.vec3 8 4 0)}))
  (local connector (view:connect-items source target))
  (local record (. view.connector-records connector.id))
  (assert record.line "BoardView connector should render a TriangleLine")
  (assert record.line.start "BoardView connector line should track start position")
  (assert record.line.finish "BoardView connector line should track end position")
  (assert (= record.line.start.x 4)
          "BoardView connector line start should be source item center x")
  (assert (= record.line.start.y 2)
          "BoardView connector line start should be source item center y")
  (assert (= record.line.finish.x 24)
          "BoardView connector line end should be target item center x")
  (assert (= record.line.finish.y 12)
          "BoardView connector line end should be target item center y")
  (view:drop)
  (BoardRegistry.unregister-owner owner)
  true)

(fn board-selection-action-through-activity-hooks []
  (with-temp-dir
    (fn [dir]
      (with-board-activity-runtime
        (fn [env]
          (local item-a (env.board-view:add-item {:type "test-item"
                                                   :subject-key "sk:a"
                                                   :position (glm.vec3 0 0 0)}))
          (local item-b (env.board-view:add-item {:type "test-item"
                                                   :subject-key "sk:b"
                                                   :position (glm.vec3 10 0 0)}))
          (set app.board-view.selected-items [item-a item-b])
          (local actions (app.activity-selection-actions
                           {:surface :canvas
                            :activity "board"}))
          (assert (= (length actions) 2)
                  "activity-selection-actions should return Delete Selected + Connect Items for two items")
          (assert (= (. actions 1 :name) "Delete Selected")
                  "first selection action should be Delete Selected")
          (assert (= (. actions 2 :name) "Connect Items")
                  "second selection action should be Connect Items")
          (assert (= (length app.board.connectors-in-order) 0)
                  "Board should start with no connectors")
          ((. actions 2 :fn) nil nil)
          (assert (= (length app.board.connectors-in-order) 1)
                  "Connect Items action should create a board connector")
          (local connector (. app.board.connectors-in-order 1))
          (assert (= connector.source-item-id item-a.id)
                  "Connector source should be first selected item")
          (assert (= connector.target-item-id item-b.id)
                  "Connector target should be second selected item"))
        {:dir dir}))))

(fn board-selection-action-shows-connect-even-when-already-connected []
  (with-temp-dir
    (fn [dir]
      (with-board-activity-runtime
        (fn [env]
          (local item-a (env.board-view:add-item {:type "test-item"
                                                   :subject-key "sk:a"
                                                   :position (glm.vec3 0 0 0)}))
          (local item-b (env.board-view:add-item {:type "test-item"
                                                   :subject-key "sk:b"
                                                   :position (glm.vec3 10 0 0)}))
          (app.board-view:connect-items item-a item-b)
          (assert (= (length app.board.connectors-in-order) 1)
                  "First connect should create one connector")
          (set app.board-view.selected-items [item-a item-b])
          (local actions (app.activity-selection-actions
                           {:surface :canvas
                            :activity "board"}))
          (assert (= (length actions) 2)
                  "selection actions should include Delete Selected + Connect Items for two items")
          (assert (= (. actions 2 :name) "Connect Items")
                  "second selection action should be Connect Items")
          ((. actions 2 :fn) nil nil)
          (assert (= (length app.board.connectors-in-order) 1)
                  "Connect Items on already-connected items should not create a duplicate connector"))
        {:dir dir}))))

(fn board-selection-action-enriches-context-with-selected-items []
  (with-board-activity-runtime
    (fn [env]
      (local context {})
      (when app.activity-context-enricher
        (app.activity-context-enricher context))
      (assert context.board "Board context enricher should set context.board")
      (assert (= (length context.board.selected-items) 0)
              "Board context should initialize selected-items to empty list")
      (assert context.board.board "Board context should include board")
      (assert context.board.view "Board context should include board view"))))

(fn board-selection-action-uses-selector-wiring-through-runtime []
  (with-temp-dir
    (fn [dir]
      (local selector (mock-selector))
      (with-board-activity-runtime
        (fn [env]
          (local item-a (env.board-view:add-item {:type "test-item"
                                                   :subject-key "sk:a"
                                                   :position (glm.vec3 0 0 0)}))
          (local item-b (env.board-view:add-item {:type "test-item"
                                                   :subject-key "sk:b"
                                                   :position (glm.vec3 10 0 0)}))
          (assert (= (length selector.selectables) 2)
                  "BoardView should register selectables via runtime.object-selector")
          (assert (= (length app.board-view.selected-items) 0)
                  "BoardView should have no selected items before selector change")
          (selector.changed:emit selector.selectables)
          (assert (= (length app.board-view.selected-items) 2)
                  "BoardView should track selected items after selector.changed emit")
          (local actions (app.activity-selection-actions
                           {:surface :canvas
                            :activity "board"}))
          (assert (= (length actions) 2)
                  "selection actions should include Delete Selected + Connect Items for two items")
          (assert (= (. actions 2 :name) "Connect Items"))
          ((. actions 2 :fn) nil nil)
          (assert (= (length app.board.connectors-in-order) 1)
                  "clicking Connect Items via selector wiring should create a connector"))
        {:dir dir :object-selector selector}))))

(fn board-view-remove-item-deletes-string-entity []
  (local H (require :tests/test-reference-lifecycle-helpers))
  (fn rooted [root]
    (local stores (H.stores root))
    (fn action [env]
      (local item (env.board-view:add-string-entity {:value "hello"}))
      (local key (stores.identity-store:resolve-key item.subject-key))
      (local entity-id (assert (BuiltinStringEntity.entity-id-from-subject key)))
      (assert (stores.string-store:get-entity entity-id) "Entity should exist before removal")
      (assert (env.board-view:remove-item item) "remove-item should return truthy on success")
      (assert (not (stores.string-store:get-entity entity-id)) "Entity should be deleted from store after remove-item")
      (assert (not (. app.board.items item.id)) "Board item should be removed after remove-item"))
    (with-board-activity-runtime action {:stores stores}))
  (H.with-root rooted))

(fn board-view-remove-item-does-not-recreate-entity-on-board-failure []
  (local H (require :tests/test-reference-lifecycle-helpers))
  (fn rooted [root]
    (local stores (H.stores root))
    (fn action [env]
      (local item (env.board-view:add-string-entity {:value "keep-me"}))
      (local key (stores.identity-store:resolve-key item.subject-key))
      (local entity-id (assert (BuiltinStringEntity.entity-id-from-subject key)))
      (local handler
        (app.board.item-removed:connect
          (fn [_it]
            (error "item-removed handler failed"))))
      (local (ok _err)
        (pcall
          (fn []
            (env.board-view:remove-item item))))
      (app.board.item-removed:disconnect handler true)
      (assert (not ok) "remove-item should fail when item-removed handler fails")
      (assert (. app.board.items item.id) "Board item should be rolled back after remove-item failure")
      ;; This standalone board is not a loaded WorldOwner runtime. Its local
      ;; listener failure cannot undo an already completed domain operation.
      (assert (= (stores.string-store:get-entity entity-id) nil)
              "board listener failure must never recreate a retired representation"))
    (with-board-activity-runtime action {:stores stores}))
  (H.with-root rooted))

(fn board-view-remove-selected-items-removes-all-selected []
  (with-board-activity-runtime
    (fn [env]
      (local item-a (env.board-view:add-item {:type "test-item" :subject-key "sk:a"}))
      (local item-b (env.board-view:add-item {:type "test-item" :subject-key "sk:b"}))
      (local item-c (env.board-view:add-item {:type "test-item" :subject-key "sk:c"}))
      (set app.board-view.selected-items [item-a item-c])
      (local count (app.board-view:remove-selected-items))
      (assert (= count 2) "Should remove exactly the two selected items")
      (assert (not (. app.board.items item-a.id)) "Item-a should be removed from board")
      (assert (. app.board.items item-b.id) "Unselected item-b should remain on board")
      (assert (not (. app.board.items item-c.id)) "Item-c should be removed from board"))
    {}))

(fn board-delete-selection-hook-removes-selected-items []
  (with-board-activity-runtime
    (fn [env]
      (local item (env.board-view:add-item {:type "test-item" :subject-key "sk:a"}))
      (set app.board-view.selected-items [item])
      (assert (= (length app.board.items-in-order) 1))
      (assert app.activity-delete-selection "delete-selection hook should be registered")
      (local result (app.activity-delete-selection))
      (assert result "delete-selection should return truthy when items were removed")
      (assert (= (length app.board.items-in-order) 0) "Selected items should be removed"))
    {}))

(fn board-selection-action-shows-delete-when-items-selected []
  (with-board-activity-runtime
    (fn [env]
      (local item (env.board-view:add-item {:type "test-item" :subject-key "sk:a"}))
      (set app.board-view.selected-items [item])
      (local actions (app.activity-selection-actions
                       {:surface :canvas :activity "board"}))
      (assert (= (length actions) 1) "Should have one action for one selected item")
      (assert (= (. actions 1 :name) "Delete Selected") "Action should be Delete Selected")
      (assert (= (length app.board.items-in-order) 1))
      ((. actions 1 :fn) nil nil)
      (assert (= (length app.board.items-in-order) 0) "Should delete the selected item"))
    {}))

(fn board-selection-action-shows-delete-and-connect-for-two-items []
  (with-board-activity-runtime
    (fn [env]
      (local item-a (env.board-view:add-item {:type "test-item" :subject-key "sk:a"}))
      (local item-b (env.board-view:add-item {:type "test-item" :subject-key "sk:b"}))
      (set app.board-view.selected-items [item-a item-b])
      (local actions (app.activity-selection-actions
                       {:surface :canvas :activity "board"}))
      (assert (= (length actions) 2) "Should have Delete Selected and Connect Items for two items")
      (assert (= (. actions 1 :name) "Delete Selected") "First action should be Delete Selected")
      (assert (= (. actions 2 :name) "Connect Items") "Second action should be Connect Items"))
    {}))

(fn board-selection-action-shows-delete-when-no-connectable-items []
  (local owner {})
  (BoardRegistry.unregister-item-type "no-subject-item" owner)
  (BoardRegistry.register-item-type {:id "no-subject-item"
                                      :label "NoSubject"
                                      :builder dummy-widget}
                                     owner)
  (with-board-activity-runtime
    (fn [env]
      (local item (env.board-view:add-item {:type "no-subject-item"}))
      (set app.board-view.selected-items [item])
      (local actions (app.activity-selection-actions
                       {:surface :canvas :activity "board"}))
      (assert (= (length actions) 1) "Should have Delete Selected for item without subject-key")
      (assert (= (. actions 1 :name) "Delete Selected") "Action should be Delete Selected")
      ((. actions 1 :fn) nil nil)
      (assert (= (length app.board.items-in-order) 0) "Should delete the item"))
    {})
  (BoardRegistry.unregister-owner owner))

(table.insert tests {:name "BoardView registers selectables with selector"
                     :fn board-view-registers-selectables-with-selector})
(table.insert tests {:name "BoardView selection tracks selected items"
                     :fn board-view-selection-tracks-selected-items})
(table.insert tests {:name "BoardView selectable position updates on transform"
                     :fn board-view-selectable-position-updates-on-transform})
(table.insert tests {:name "BoardView drop cleans up selectables"
                     :fn board-view-drop-cleans-up-selectables})
(table.insert tests {:name "BoardView connects two connectable items"
                     :fn board-selection-action-shows-connect-for-two-connectable-items})
(table.insert tests {:name "BoardView connect-items is idempotent"
                     :fn board-view-connect-items-is-idempotent})
(table.insert tests {:name "BoardView connects items preserves direction"
                     :fn board-view-connects-items-preserves-direction})
(table.insert tests {:name "BoardView connector renders triangle line from source to target"
                     :fn board-view-connector-renders-triangle-line-from-source-to-target})
(table.insert tests {:name "Board selection action through activity hooks"
                     :fn board-selection-action-through-activity-hooks})
(table.insert tests {:name "Board selection action always shows connect (idempotent)"
                     :fn board-selection-action-shows-connect-even-when-already-connected})
(table.insert tests {:name "Board context enricher sets selected-items"
                      :fn board-selection-action-enriches-context-with-selected-items})
(table.insert tests {:name "Board selection action uses selector wiring through runtime"
                       :fn board-selection-action-uses-selector-wiring-through-runtime})
(table.insert tests {:name "BoardView remove-item deletes string entity from store"
                      :fn board-view-remove-item-deletes-string-entity})
(table.insert tests {:name "BoardView remove-item never recreates entity on board failure"
                       :fn board-view-remove-item-does-not-recreate-entity-on-board-failure})
(table.insert tests {:name "BoardView remove-selected-items removes all selected"
                      :fn board-view-remove-selected-items-removes-all-selected})
(table.insert tests {:name "Board delete-selection hook removes selected items"
                      :fn board-delete-selection-hook-removes-selected-items})
(table.insert tests {:name "Board selection action shows Delete Selected when items selected"
                      :fn board-selection-action-shows-delete-when-items-selected})
(table.insert tests {:name "Board selection action shows both Delete Selected and Connect Items for two items"
                      :fn board-selection-action-shows-delete-and-connect-for-two-items})
(table.insert tests {:name "Board selection action shows Delete Selected for non-connectable items"
                      :fn board-selection-action-shows-delete-when-no-connectable-items})

(fn main []
  (runner.run-tests {:name "board"
                     :tests tests}))

{:name "board"
 :tests tests
 :main main}
