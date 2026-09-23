(local fs (require :fs))
(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local StringEntityStore (require :entities/string))
(local ListEntityStore (require :entities/list))
(local IdentityStore (require :entities/identity))
(local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
(local {:register-loader register-list-loader} (require :graph/nodes/list-entity))
(local OrderedListPresenter (require :graph/view/island-presenters/ordered-list))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "ordered-list-islands"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "case-" (os.time) "-" temp-counter)))

(fn with-fixture [f]
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
  (local map (GraphMap.GraphMap {:graph graph :id "ordered-list-islands-test"}))
  (local fixture {:dir dir
                  :graph graph
                  :map map
                  :string-store string-store
                  :list-store list-store
                  :identity-store identity-store})
  (local (ok result) (pcall f fixture))
  (map:drop)
  (graph:drop)
  (fs.remove-all dir)
  (if ok result (error result)))

(fn create-string [fixture id value]
  (local entity (fixture.string-store:create-entity {:id id :value value}))
  (.. "string-entity:" entity.id))

(fn create-list [fixture id items]
  (fixture.list-store:create-entity {:id id :name id :items items}))

(fn assert-members [island expected]
  (assert island "expected island record")
  (assert (= (length island.members) (length expected))
          (.. "expected " (length expected) " island members, got " (length island.members)))
  (for [i 1 (length expected)]
    (assert (= (. island.members i) (. expected i))
            (.. "member " i " should be " (. expected i) ", got " (tostring (. island.members i))))))

(fn assert-position-array [actual expected message]
  (assert actual (or message "expected position array"))
  (for [i 1 3]
    (assert (= (. actual i) (. expected i))
            (.. (or message "position") " component " i " expected " (. expected i)
                ", got " (tostring (. actual i))))))

(fn make-reconcile-host [positions]
  {:position-for-key (fn [_self key]
                        (. positions key))
   :set-member-position (fn [_self _island-id key position]
                          (set (. positions key) position))
    :set-member-pinned (fn [_self _island-id _key _pinned?]
                         nil)})

(fn assert-vec3-position [actual expected message]
  (assert actual (or message "expected position"))
  (assert (= actual.x expected.x)
          (.. (or message "position") " x expected " expected.x ", got " (tostring actual.x)))
  (assert (= actual.y expected.y)
          (.. (or message "position") " y expected " expected.y ", got " (tostring actual.y)))
  (assert (= actual.z expected.z)
          (.. (or message "position") " z expected " expected.z ", got " (tostring actual.z))))

(fn ordered-list-presenter-uses-member-position-for-old-format-island []
  (local list-key "list-entity:list")
  (local member-key "string-entity:a")
  (local positions {})
  (set (. positions list-key) {:x 24 :y 0 :z 0})
  (set (. positions member-key) {:x 300 :y 400 :z 0})
  (local island {:id "ordered-list:list"
                 :kind "ordered-list"
                 :members [member-key]
                 :state {:list-key list-key
                         :spacing 24}})
  (OrderedListPresenter.apply island (make-reconcile-host positions))
  (local first-position (. positions member-key))
  (assert-vec3-position first-position {:x 300 :y 400 :z 0}
                        "old-format island should fall back to existing member position")
  (local list-position (. positions list-key))
  (assert (not (and (= first-position.x list-position.x)
                    (= first-position.y list-position.y)
                    (= first-position.z list-position.z)))
          "old-format island first item should not re-anchor to the list node"))

(fn ordered-list-presenter-prefers-explicit-state-position-over-list-key-anchor []
  (local list-key "list-entity:list")
  (local member-key "string-entity:a")
  (local positions {})
  (set (. positions list-key) {:x 24 :y 0 :z 0})
  (set (. positions member-key) {:x 300 :y 400 :z 0})
  (local island {:id "ordered-list:list"
                 :kind "ordered-list"
                 :members [member-key]
                 :state {:list-key list-key
                         :position [111 222 3]
                         :spacing 24}})
  (OrderedListPresenter.apply island (make-reconcile-host positions))
  (assert-vec3-position (. positions member-key) {:x 111 :y 222 :z 3}
                        "explicit island position should win over list-key anchor"))

(fn list-entity-node-expands-item-nodes-as-ordered-list-island []
  (with-fixture
    (fn [fixture]
      (local key-a (create-string fixture "a" "A"))
      (local key-b (create-string fixture "b" "B"))
      (local entity (create-list fixture "list" [key-a key-b]))
      (local list-node (fixture.map:load-by-key (.. "list-entity:" entity.id)))
      (local island (list-node:expand-items-as-island))
      (assert (= island.id "ordered-list:list") "island id should be derived from list entity id")
      (assert (= island.kind "ordered-list") "island kind should be ordered-list")
      (assert-members island [key-a key-b])
      (assert (= island.state.list-key list-node.key) "island should remember source list node key")
      (assert (= island.state.interaction-policy "snap-back") "island should request snap-back interactions")
      (assert (= island.state.spacing 24) "island should set default spacing")
      (assert-position-array island.state.position [24 0 0]
                             "island should store a JSON-safe stable origin offset from the list node")
      (assert (fixture.map:lookup key-a) "expansion should load first item node")
      (assert (fixture.map:lookup key-b) "expansion should load second item node"))))

(fn list-entity-node-initializes-island-body-near-list-node-then-preserves-it []
  (with-fixture
    (fn [fixture]
      (local key-a (create-string fixture "a" "A"))
      (local key-b (create-string fixture "b" "B"))
      (local key-c (create-string fixture "c" "C"))
      (local entity (create-list fixture "list" [key-a key-b]))
      (local list-node (fixture.map:load-by-key (.. "list-entity:" entity.id)))
      (set fixture.map.presentation-points {})
      (set (. fixture.map.presentation-points list-node.key)
           {:position (glm.vec3 100 200 3)})
      (local island (list-node:expand-items-as-island))
      (assert-position-array island.state.position [124 200 3]
                             "new list-created island should initialize near current list node")
      (set (. fixture.map.presentation-points list-node.key)
           {:position (glm.vec3 900 901 9)})
      (fixture.list-store:reorder-items entity.id [key-c key-b key-a])
      (local refreshed (fixture.map:get-island "ordered-list:list"))
      (assert-members refreshed [key-c key-b key-a])
      (assert-position-array refreshed.state.position [124 200 3]
                             "refresh should preserve island body position instead of re-reading source position"))))

(fn list-entity-node-created-island-keeps-first-item-offset-after-reconcile []
  (with-fixture
    (fn [fixture]
      (local key-a (create-string fixture "a" "A"))
      (local key-b (create-string fixture "b" "B"))
      (local entity (create-list fixture "list" [key-a key-b]))
      (local list-node (fixture.map:load-by-key (.. "list-entity:" entity.id)))
      (local island (list-node:expand-items-as-island))
      (local positions {})
      (set (. positions list-node.key) {:x 0 :y 0 :z 0})
      (set (. positions key-a) {:x 500 :y 500 :z 0})
      (set (. positions key-b) {:x 600 :y 600 :z 0})
      (set (. positions "string-entity:unrelated") {:x -100 :y -100 :z 0})
      (local host (make-reconcile-host positions))
      (OrderedListPresenter.apply island host)
      (local first-position (. positions key-a))
      (local list-position (. positions list-node.key))
      (assert-position-array island.state.position [24 0 0]
                             "list-created island should persist its reconciliation origin")
      (assert (= first-position.x 24) "first item should reconcile to island origin x, not list node x")
      (assert (= first-position.y 0) "first item should reconcile to island origin y")
      (assert (not (and (= first-position.x list-position.x)
                        (= first-position.y list-position.y)
                        (= first-position.z list-position.z)))
              "first item should not overlap the list node after unrelated drag reconciliation"))))

(fn list-entity-node-updates-existing-ordered-list-island-in-store-order []
  (with-fixture
    (fn [fixture]
      (local key-a (create-string fixture "a" "A"))
      (local key-b (create-string fixture "b" "B"))
      (local key-c (create-string fixture "c" "C"))
      (local entity (create-list fixture "list" [key-a key-b]))
      (local list-node (fixture.map:load-by-key (.. "list-entity:" entity.id)))
      (list-node:expand-items-as-island)
      (fixture.list-store:reorder-items entity.id [key-c key-b key-a])
      (local island (fixture.map:get-island "ordered-list:list"))
      (assert-members island [key-c key-b key-a]))))

(fn list-entity-node-preserves-existing-ordered-list-island-position-on-update []
  (with-fixture
    (fn [fixture]
      (local key-a (create-string fixture "a" "A"))
      (local key-b (create-string fixture "b" "B"))
      (local key-c (create-string fixture "c" "C"))
      (local entity (create-list fixture "list" [key-a key-b]))
      (local list-node (fixture.map:load-by-key (.. "list-entity:" entity.id)))
      (list-node:expand-items-as-island)
      (fixture.map:update-island "ordered-list:list" {:state {:list-key list-node.key
                                                               :interaction-policy "snap-back"
                                                               :spacing 24
                                                               :position [111 222 3]}})
      (fixture.list-store:reorder-items entity.id [key-c key-b key-a])
      (local island (fixture.map:get-island "ordered-list:list"))
      (assert-members island [key-c key-b key-a])
      (assert-position-array island.state.position [111 222 3]
                             "refresh should preserve explicit island origin"))))

(fn list-entity-node-resolves-identity-items-to-visible-target-keys []
  (with-fixture
    (fn [fixture]
      (local key-a (create-string fixture "a" "A"))
      (local key-b (create-string fixture "b" "B"))
      (fixture.identity-store:create-entity {:id "alias-a" :target-key key-a})
      (local entity (create-list fixture "list" ["identity:alias-a" key-b]))
      (local list-node (fixture.map:load-by-key (.. "list-entity:" entity.id)))
      (local island (list-node:expand-items-as-island))
      (assert-members island [key-a key-b])
      (assert (= (fixture.map:lookup "identity:alias-a") nil)
              "identity item should materialize visible target, not identity adapter"))))

(fn list-entity-node-refreshes-island-when-identity-target-changes []
  (with-fixture
    (fn [fixture]
      (local key-a (create-string fixture "a" "A"))
      (local key-b (create-string fixture "b" "B"))
      (fixture.identity-store:create-entity {:id "alias-a" :target-key key-a})
      (local entity (create-list fixture "list" ["identity:alias-a"]))
      (local list-node (fixture.map:load-by-key (.. "list-entity:" entity.id)))
      (list-node:expand-items-as-island)
      (assert-members (fixture.map:get-island "ordered-list:list") [key-a])
      (fixture.identity-store:update-entity "alias-a" {:target-key key-b})
      (assert-members (fixture.map:get-island "ordered-list:list") [key-b]))))

(fn list-entity-node-removes-existing-island-when-last-item-is-removed []
  (with-fixture
    (fn [fixture]
      (local key-a (create-string fixture "a" "A"))
      (local entity (create-list fixture "list" [key-a]))
      (local list-node (fixture.map:load-by-key (.. "list-entity:" entity.id)))
      (list-node:expand-items-as-island)
      (assert (fixture.map:get-island "ordered-list:list") "fixture should start with island")
      (list-node:remove-item key-a)
      (assert (not (fixture.map:get-island "ordered-list:list"))
              "existing ordered-list island should be removed when it has no members"))))

(fn removing-ordered-list-island-does-not-delete-list-or-item-entities []
  (with-fixture
    (fn [fixture]
      (local key-a (create-string fixture "a" "A"))
      (local key-b (create-string fixture "b" "B"))
      (local entity (create-list fixture "list" [key-a key-b]))
      (local list-node (fixture.map:load-by-key (.. "list-entity:" entity.id)))
      (list-node:expand-items-as-island)
      (fixture.map:remove-island "ordered-list:list")
      (assert (fixture.list-store:get-entity entity.id) "removing island should not delete list entity")
      (assert (fixture.string-store:get-entity "a") "removing island should not delete first item entity")
      (assert (fixture.string-store:get-entity "b") "removing island should not delete second item entity"))))

(fn list-entity-node-exposes-expand-items-as-island-action []
  (with-fixture
    (fn [fixture]
      (local key-a (create-string fixture "a" "A"))
      (local entity (create-list fixture "list" [key-a]))
      (local list-node (fixture.map:load-by-key (.. "list-entity:" entity.id)))
      (var action nil)
      (each [_ candidate (ipairs list-node.actions)]
        (when (= candidate.name "Expand items as island")
          (set action candidate)))
      (assert action "list node should expose Expand items as island action")
      (assert (= action.icon "format_list_numbered") "action should use validated numbered-list icon")
      (action.fn nil nil)
      (assert-members (fixture.map:get-island "ordered-list:list") [key-a]))))

(table.insert tests {:name "ListEntityNode expands item nodes as ordered-list island"
                     :fn list-entity-node-expands-item-nodes-as-ordered-list-island})
(table.insert tests {:name "ListEntityNode initializes island body near list node then preserves it"
                     :fn list-entity-node-initializes-island-body-near-list-node-then-preserves-it})
(table.insert tests {:name "OrderedListPresenter uses member position for old-format island"
                     :fn ordered-list-presenter-uses-member-position-for-old-format-island})
(table.insert tests {:name "OrderedListPresenter prefers explicit state position over list-key anchor"
                     :fn ordered-list-presenter-prefers-explicit-state-position-over-list-key-anchor})
(table.insert tests {:name "ListEntityNode-created island keeps first item offset after reconcile"
                     :fn list-entity-node-created-island-keeps-first-item-offset-after-reconcile})
(table.insert tests {:name "ListEntityNode updates existing ordered-list island in store order"
                     :fn list-entity-node-updates-existing-ordered-list-island-in-store-order})
(table.insert tests {:name "ListEntityNode preserves existing ordered-list island position on update"
                     :fn list-entity-node-preserves-existing-ordered-list-island-position-on-update})
(table.insert tests {:name "ListEntityNode resolves identity items to visible target keys"
                     :fn list-entity-node-resolves-identity-items-to-visible-target-keys})
(table.insert tests {:name "ListEntityNode refreshes island when identity target changes"
                      :fn list-entity-node-refreshes-island-when-identity-target-changes})
(table.insert tests {:name "ListEntityNode removes existing island when last item is removed"
                     :fn list-entity-node-removes-existing-island-when-last-item-is-removed})
(table.insert tests {:name "Removing ordered-list island does not delete list or item entities"
                      :fn removing-ordered-list-island-does-not-delete-list-or-item-entities})
(table.insert tests {:name "ListEntityNode exposes Expand items as island action"
                     :fn list-entity-node-exposes-expand-items-as-island-action})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "ordered-list-islands" :tests tests})))

{:name "ordered-list-islands"
 :tests tests
 :main main}
