(local fs (require :fs))
(local Graph (require :graph/init))
(local GraphMap (require :graph/map))
(local StringEntityStore (require :entities/string))
(local ListEntityStore (require :entities/list))
(local IdentityStore (require :entities/identity))
(local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
(local {:register-loader register-list-loader} (require :graph/nodes/list-entity))

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
      (assert (fixture.map:lookup key-a) "expansion should load first item node")
      (assert (fixture.map:lookup key-b) "expansion should load second item node"))))

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
(table.insert tests {:name "ListEntityNode updates existing ordered-list island in store order"
                     :fn list-entity-node-updates-existing-ordered-list-island-in-store-order})
(table.insert tests {:name "ListEntityNode resolves identity items to visible target keys"
                     :fn list-entity-node-resolves-identity-items-to-visible-target-keys})
(table.insert tests {:name "ListEntityNode refreshes island when identity target changes"
                     :fn list-entity-node-refreshes-island-when-identity-target-changes})
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
