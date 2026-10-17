(local H (require :tests/test-reference-lifecycle-helpers))
(local fs (require :fs))
(local JsonUtils (require :json-utils))
(local tests [])

(fn add-test [suffix f]
  (fn run [] (H.with-root (fn [root] (f (H.stores root)))))
  (table.insert tests {:name (.. "reference lifecycle writes " suffix) :fn run}))

(fn stable [s key terminal]
  (assert (= (string.sub key 1 9) "identity:") (.. "expected stable reference, got " key))
  (assert (= (s.identity-store:resolve-key key) terminal) "reference must retain terminal meaning"))

(fn same [actual expected]
  (assert (= (JsonUtils.stable-json actual) (JsonUtils.stable-json expected)) "values differ"))

(fn constant [value] (fn [_] value))

(fn forbidden-default [_] (error "must use active owning stores"))

(fn action [actions name]
  (var found nil)
  (each [_ candidate (ipairs actions)]
    (when (= candidate.name name) (set found candidate)))
  (assert found (.. "missing action " name)))

(fn selected-action [s name f]
  (fn run-selected [graph map]
    (s.string-store:create-entity {:id "a" :value "A"})
    (s.string-store:create-entity {:id "b" :value "B"})
    (local a (map:load-by-key "string-entity:a"))
    (local b (map:load-by-key "string-entity:b"))
    (local Actions (require :graph-activity-actions))
    (local List (require :entities/list))
    (local Link (require :entities/link))
    (fn invoke []
      (local selection (if (= name "Create Link Entity") [a b] [a b a]))
      (local actions (Actions.graph-root-actions {:graph {:graph-map map :selected-nodes selection}}))
      ((. (action actions name) :fn) nil nil)
      (f graph map))
    (fn with-link [] (H.with-fields Link {:get-default (constant s.link-store)} invoke))
    (fn with-list [] (H.with-fields List {:get-default (constant s.list-store)} with-link))
    (H.with-fields app {:graph-map map :active-world-runtime {:graph-map map}} with-list))
  (H.with-graph s run-selected))

(fn selected-list [s]
  (selected-action s "Create List Entity" (fn [_graph map]
    (local entity (. (s.list-store:list-entities) 1))
    (assert entity)
    (assert (= (length entity.items) 2))
    (stable s (. entity.items 1) "string-entity:a")
    (stable s (. entity.items 2) "string-entity:b")
    (assert (= (map:node-count) 3) "normalization must not expose identity nodes")
    (assert (= (map:edge-count) 2)))))

(fn selected-link [s]
  (selected-action s "Create Link Entity" (fn [_graph map]
    (local entity (. (s.link-store:list-entities) 1))
    (assert entity)
    (stable s entity.source-key "string-entity:a")
    (stable s entity.target-key "string-entity:b")
    (assert (= (map:node-count) 3))
    (assert (>= (map:edge-count) 1)))))

(fn child [s]
  (H.with-graph s (fn [_graph map]
    (s.string-store:create-entity {:id "parent" :value "parent"})
    (local node (map:load-by-key "string-entity:parent"))
    (local result ((. (action node.actions "Create child") :fn) nil nil))
    (stable s result.link.source-key "string-entity:parent")
    (stable s result.link.target-key result.child-key)
    (assert (map:lookup result.child-key))
    (assert (= (map:node-count) 2))
    (assert (= (map:edge-count) 1)))))

(fn list-add [s]
  (s.string-store:create-entity {:id "a"})
  (local entity (s.list-store:create-entity {:id "l" :items ["string-entity:a"]}))
  (H.with-graph s (fn [_graph map]
    (local node (map:load-by-key "list-entity:l"))
    (node:add-item "string-entity:a")
    (assert (= (length entity.items) 1) "node add must not duplicate a preselected raw member")
    (stable s (. entity.items 1) "string-entity:a")
    (assert (= (map:node-count) 2))
    (assert (= (map:edge-count) 1)))))

(fn notebook-add [s]
  (local entity (s.notebook-store:create-notebook {:id "n"}))
  (H.with-graph s (fn [_graph map]
    (local node (map:load-by-key "notebook:n"))
    (local added ((. (action node.actions "Add String Entity") :fn) nil nil))
    ;; The action returns the entity created by the real notebook node method.
    (local item (. entity.items 1))
    (assert item)
    (local terminal (s.identity-store:resolve-key item))
    (node:add-item terminal)
    (s.notebook-store:add-item "n" terminal)
    (assert (= (length entity.items) 1) "store and node add must share normalization")
    (stable s item terminal)
    (assert (= (map:node-count) 2))
    (assert (= (map:edge-count) 1)))))

(fn dict-edit [s]
  (s.string-store:create-entity {:id "a"})
  (local entity (s.dict-store:create-entity {:id "d" :items {:first "string-entity:a"}}))
  (H.with-graph s (fn [_graph map]
    (local node (map:load-by-key "dict-entity:d"))
    (node:set-item "second" "string-entity:a")
    (stable s entity.items.first "string-entity:a")
    (assert (= entity.items.first entity.items.second) "named slots survive normalization")
    (assert (= (map:node-count) 2)))))

(fn ordered-boundaries [s store create update]
  (s.identity-store:create-entity {:id "a" :target-key "external:a"})
  (s.identity-store:create-entity {:id "z" :target-key "external:a"})
  (local entity (create store {:id "o" :items ["external:a" "identity:a" "identity:z" "external:b"]}))
  (same entity.items ["identity:a" "identity:z" (s.identity-store:ensure-key "external:b")])
  (store:add-item "o" "external:a")
  (assert (= (length entity.items) 3))
  (update store "o" {:items ["external:b" "external:a" "identity:a" "identity:z"]})
  (store:move-item "o" 1 3)
  (same entity.items ["identity:a" "identity:z" (s.identity-store:ensure-key "external:b")])
  (store:reorder-items "o" ["identity:z" "external:a" "identity:a"])
  (same entity.items ["identity:z" "identity:a"])
  (assert (= entity (if store.get-entity (store:get-entity "o") (store:get-notebook "o"))))
  (assert (= entity (. (if store.list-entities (store:list-entities) (store:list-notebooks)) 1))
          "enumeration must preserve held record identity"))

(fn list-boundaries [s]
  (ordered-boundaries s s.list-store s.list-store.create-entity s.list-store.update-entity))

(fn notebook-boundaries [s]
  (ordered-boundaries s s.notebook-store s.notebook-store.create-notebook s.notebook-store.update-notebook))

(fn dict-boundaries [s]
  (local store s.dict-store)
  (local e (store:create-entity {:id "d" :items {:a "external:a" :b "external:a"}}))
  (stable s e.items.a "external:a")
  (assert (= e.items.a e.items.b))
  (store:update-entity "d" {:items {:c "external:c"}})
  (stable s e.items.c "external:c")
  (store:set-item "d" "a" "external:a")
  (stable s e.items.a "external:a")
  (store:rename-item "d" "a" "renamed")
  (stable s e.items.renamed "external:a"))

(fn link-boundaries [s]
  (local store s.link-store)
  (local e (store:create-entity {:id "l" :source-key "external:a" :target-key "external:b"}))
  (stable s e.source-key "external:a")
  (stable s e.target-key "external:b")
  (store:update-entity "l" {:source-key "external:c" :target-key ""})
  (stable s e.source-key "external:c")
  (assert (= e.target-key ""))
  (local draft (store:create-entity {:id "draft"}))
  (assert (= draft.source-key ""))
  (assert (= draft.target-key "")))

(fn injection [s]
  (each [_ field (ipairs [:list-store :dict-store :link-store :notebook-store])]
    (assert (= (. s field :identity-store) s.identity-store)))
  (local Identity (require :entities/identity))
  (local wrong (Identity.IdentityStore {:base-dir (fs.join-path s.base-dir "other")}))
  (each [_ entry (ipairs [["entities/list" :ListEntityStore] ["entities/dict" :DictEntityStore]
                          ["entities/link" :LinkEntityStore] ["notebooks/store" :NotebookStore]])]
    (local factory (. (require (. entry 1)) (. entry 2)))
    (fn mismatched-root [] (factory {:base-dir s.base-dir :identity-store wrong}))
    (H.assert-error "identity-store" mismatched-root))
  (s.list-store:create-entity {:id "l"})
  (s.dict-store:create-entity {:id "d"})
  (s.notebook-store:create-notebook {:id "n"})
  (local other (. (H.stores s.base-dir) :identity-store))
  (each [_ entry (ipairs [["graph/nodes/list-entity" :ListEntityNode s.list-store :entity-id "l"]
                          ["graph/nodes/dict-entity" :DictEntityNode s.dict-store :entity-id "d"]
                          ["graph/nodes/notebook" :NotebookNode s.notebook-store :notebook-id "n"]])]
    (local factory (. (require (. entry 1)) (. entry 2)))
    (local opts {:store (. entry 3) :identity-store other})
    (tset opts (. entry 4) (. entry 5))
    (fn mismatched-node [] (factory opts))
    (H.assert-error "identity-store" mismatched-node)))

(fn defaults [s]
  (each [_ entry (ipairs [["entities/list" :ListEntityStore] ["entities/dict" :DictEntityStore]
                          ["entities/link" :LinkEntityStore] ["notebooks/store" :NotebookStore]])]
    (local name (. entry 1))
    (fn check-default []
      (local module (require name))
      (local standalone ((. module (. entry 2)) {:base-dir s.base-dir}))
      (assert (= standalone.identity-store.base-dir s.base-dir))
      (assert (not (= standalone.identity-store s.identity-store)))
      (local store (module.get-default {:base-dir s.base-dir :identity-store s.identity-store}))
      (assert (= store.identity-store s.identity-store))
      (assert (= store (module.get-default)))
      (fn wrong-root [] (module.get-default {:base-dir "/other"}))
      (fn wrong-identity [] (module.get-default {:identity-store standalone.identity-store}))
      (H.assert-error "base-dir" wrong-root)
      (H.assert-error "identity-store" wrong-identity))
    (H.with-fields package.loaded {name false} check-default)))

(fn legacy [s]
  (local fixtures [[s.list-store.entities-dir "l" {:items ["external:raw"]}]
                  [s.notebook-store.notebooks-dir "n" {:items ["external:raw"]}]
                  [s.dict-store.entities-dir "d" {:items {:slot "external:raw"}}]
                  [s.link-store.entities-dir "k" {:source-key "external:raw" :target-key ""}]])
  (each [_ fixture (ipairs fixtures)]
    (local data (. fixture 3))
    (set data.id (. fixture 2))
    (JsonUtils.write-json! (fs.join-path (. fixture 1) (.. data.id ".json")) data))
  (local before (H.snapshot-tree s.base-dir))
  (same (. (s.list-store:get-entity "l") :items) ["external:raw"])
  (same (. (s.notebook-store:get-notebook "n") :items) ["external:raw"])
  (assert (= (. (s.dict-store:get-entity "d") :items :slot) "external:raw"))
  (assert (= (. (s.link-store:get-entity "k") :source-key) "external:raw"))
  (s.list-store:list-entities)
  (s.notebook-store:list-notebooks)
  (s.dict-store:list-entities)
  (s.link-store:list-entities)
  (same before (H.snapshot-tree s.base-dir))
  (s.list-store:remove-item "l" "external:absent")
  (s.notebook-store:remove-item "n" "external:absent")
  (assert (= (length (s.identity-store:list-entities)) 0))
  (s.list-store:remove-item "l" "external:raw")
  (s.notebook-store:remove-item "n" "external:raw")
  (assert (= (length (s.identity-store:list-entities)) 0))
  (local l (s.list-store:create-entity {:id "stable" :items ["external:a"]}))
  (s.list-store:remove-item "stable" "external:a")
  (assert (= (length l.items) 0)))

(fn query-links [s]
  (local ids s.identity-store)
  (ids:create-entity {:id "inner" :target-key "external:a"})
  (ids:create-entity {:id "outer" :target-key "identity:inner"})
  (ids:create-entity {:id "distinct" :target-key "external:a"})
  (s.link-store:create-entity {:id "one" :source-key "identity:outer" :target-key "external:b"})
  (s.link-store:create-entity {:id "two" :source-key "identity:distinct" :target-key "external:b"})
  (assert (= (length (s.link-store:find-edges-for-nodes ["external:a" "external:b"])) 2))
  (assert (= (length (s.link-store:find-entities-for-key "identity:inner")) 2))
  (ids:update-entity "inner" {:target-key "external:c"})
  (assert (= (length (s.link-store:find-entities-for-key "identity:inner")) 1))
  (assert (= (length (s.link-store:find-edges-for-nodes ["external:c" "external:b"])) 1)))

(fn query-refresh [s]
  (s.identity-store:create-entity {:id "inner" :target-key "string-entity:a"})
  (s.identity-store:create-entity {:id "outer" :target-key "identity:inner"})
  (each [_ id (ipairs ["a" "b" "c"])] (s.string-store:create-entity {:id id}))
  (each [_ id (ipairs ["one" "two"])]
    (s.link-store:create-entity {:id id :source-key "identity:outer" :target-key "string-entity:b"}))
  (H.with-graph s (fn [_graph map]
    (map:load-by-key "string-entity:a")
    (map:load-by-key "string-entity:b")
    (map:load-by-key "string-entity:c")
    (assert (= (map:edge-count) 2) "per-link parallel edges must remain distinct")
    (s.identity-store:update-entity "inner" {:target-key "string-entity:c"})
    (assert (= (map:edge-count) 2))
    (each [_ edge (ipairs map.edges)]
      (assert (= edge.source.key "string-entity:c"))
      (assert (= edge.target.key "string-entity:b"))))))

(fn show-links [s]
  (s.string-store:create-entity {:id "a"})
  (s.string-store:create-entity {:id "b"})
  (s.link-store:create-entity {:id "one" :source-key "string-entity:a" :target-key "string-entity:b"})
  (fn run-show [_graph map]
    (local a (map:load-by-key "string-entity:a"))
    (local b (map:load-by-key "string-entity:b"))
    (local Actions (require :graph-activity-actions))
    (local Link (require :entities/link))
    (fn invoke []
      (local actions (Actions.graph-root-actions {:graph {:graph-map map :selected-nodes [a b]}}))
      ((. (action actions "Show link entities") :fn) nil nil)
      (assert (map:lookup "link-entity:one")))
    (fn reject-default []
      (H.with-fields Link {:get-default forbidden-default} invoke))
    (H.with-fields app {:graph-map map :active-world-runtime {:graph-map map}} reject-default))
  (H.with-graph s run-show))

(fn failure-case [s field create update get signal]
  (local store (. s field))
  (local held (create store {:id "held" :name "before"}))
  (local before (JsonUtils.stable-json held))
  (var publications 0)
  (local changed (. store signal))
  (local handler (changed:connect (fn [_] (set publications (+ publications 1)))))
  (local dir (if store.entities-dir store.entities-dir store.notebooks-dir))
  (fn fail-write [id f]
    (local path (fs.join-path dir (.. id ".json")))
    (H.with-fs-failure :write-file (.. path ".tmp")
      (fn [] (H.assert-error "permission denied" f))))
  (fail-write "new" (fn [] (create store {:id "new" :name "new"})))
  (assert (= (get store "new") nil))
  (fail-write "held" (fn [] (update store "held" {:name "after" :source-key "external:a"
                                                   :items ["external:a"]})))
  (assert (= (JsonUtils.stable-json held) before))
  (assert (= (get store "held") held))
  (changed:disconnect handler true)
  (assert (= publications 0)))

(fn list-failure [s]
  (local store s.list-store)
  (failure-case s :list-store store.create-entity store.update-entity store.get-entity :list-entity-updated))
(fn notebook-failure [s]
  (local store s.notebook-store)
  (failure-case s :notebook-store store.create-notebook store.update-notebook store.get-notebook :notebook-updated))
(fn dict-failure [s]
  (local store s.dict-store)
  (failure-case s :dict-store store.create-entity store.update-entity store.get-entity :dict-entity-updated))
(fn link-failure [s]
  (local store s.link-store)
  (failure-case s :link-store store.create-entity store.update-entity store.get-entity :link-entity-updated))

(fn ordered-failures [s]
  (each [_ entry (ipairs [[s.list-store s.list-store.create-entity s.list-store.entities-dir]
                          [s.notebook-store s.notebook-store.create-notebook s.notebook-store.notebooks-dir]])]
    (local store (. entry 1))
    (local held ((. entry 2) store {:id "o" :items ["external:a" "external:b"]}))
    (local array held.items)
    (local before (JsonUtils.stable-json held))
    (local path (fs.join-path (. entry 3) "o.json.tmp"))
    (local operations [(fn [] (store:add-item "o" "external:c"))
                      (fn [] (store:remove-item "o" "external:a"))
                      (fn [] (store:move-item "o" 1 2))
                      (fn [] (store:reorder-items "o" ["external:b" "external:a"]))])
    (each [_ operation (ipairs operations)]
      (fn reject-write [] (H.assert-error "permission denied" operation))
      (H.with-fs-failure :write-file path reject-write)
      (assert (= held.items array))
      (assert (= (JsonUtils.stable-json held) before)))))

(fn io-errors [s]
  (each [_ entry (ipairs [[s.list-store s.list-store.list-entities s.list-store.get-entity s.list-store.entities-dir]
                          [s.dict-store s.dict-store.list-entities s.dict-store.get-entity s.dict-store.entities-dir]
                          [s.link-store s.link-store.list-entities s.link-store.get-entity s.link-store.entities-dir]
                          [s.notebook-store s.notebook-store.list-notebooks s.notebook-store.get-notebook s.notebook-store.notebooks-dir]])]
    (local store (. entry 1))
    (fn enumerate [] ((. entry 2) store))
    (fn reject-enumeration [] (H.assert-error "permission denied" enumerate))
    (H.with-fs-failure :list-dir (. entry 4) reject-enumeration)
    (local path (fs.join-path (. entry 4) "bad.json"))
    (fs.write-file path "{invalid")
    (H.assert-error path (fn [] ((. entry 3) store "bad")))))

(fn dict-mutations-failure [s]
  (local store s.dict-store)
  (local held (store:create-entity {:id "slots" :items {:a "external:a" :b "external:b"}}))
  (local slots held.items)
  (local before (JsonUtils.stable-json held))
  (local counts {:updated 0 :items 0})
  (local updated (store.dict-entity-updated:connect (fn [_] (set counts.updated (+ counts.updated 1)))))
  (local changed (store.dict-entity-items-changed:connect (fn [_] (set counts.items (+ counts.items 1)))))
  (local operations [(fn [] (store:set-item "slots" "a" "external:c"))
                    (fn [] (store:remove-item "slots" "a"))
                    (fn [] (store:rename-item "slots" "a" "renamed"))])
  (fn exercise []
    (each [_ operation (ipairs operations)]
      (H.assert-error "permission denied" operation)
      (assert (= held.items slots))
      (assert (= (JsonUtils.stable-json held) before))))
  (local path (fs.join-path store.entities-dir "slots.json.tmp"))
  (local (ok result) (pcall H.with-fs-failure :write-file path exercise))
  (store.dict-entity-updated:disconnect updated true)
  (store.dict-entity-items-changed:disconnect changed true)
  (assert ok (tostring result))
  (same counts {:updated 0 :items 0}))

(fn dict-enumeration-failure [s]
  (local store s.dict-store)
  (local held [])
  (each [_ id (ipairs ["first" "second"])]
    (local record (store:create-entity {:id id :name "held"}))
    (table.insert held record)
    (JsonUtils.write-json! (fs.join-path store.entities-dir (.. id ".json"))
                          {:id id :name "external change" :items {} :created-at 1 :updated-at 2}))
  (local entries (fs.list-dir store.entities-dir false))
  (assert (= (length entries) 2))
  (fn enumerate [] (store:list-entities))
  (fn reject-read [] (H.assert-error "permission denied" enumerate))
  (H.with-fs-failure :read-file (. entries 2 :path) reject-read)
  (each [_ record (ipairs held)]
    (assert (= record.name "held") "failed enumeration must not partially publish candidate records")
    (assert (= record (store:get-entity record.id))))
  (store:list-entities)
  (each [_ record (ipairs held)] (assert (= record.name "external change"))))

(fn removal-aliases [s]
  (s.string-store:create-entity {:id "a" :value "physical target"})
  (s.identity-store:create-entity {:id "inner" :target-key "string-entity:a"})
  (s.identity-store:create-entity {:id "outer" :target-key "identity:inner"}))

(fn ordered-store [s notebook?]
  (local store (if notebook? s.notebook-store s.list-store))
  (local create (if notebook? store.create-notebook store.create-entity))
  (values store create))

(fn explicit-removal [s notebook?]
  (removal-aliases s)
  (local (store create) (ordered-store s notebook?))
  (local held (create store {:id "members" :items ["identity:outer" "identity:inner"]}))
  (same held.items ["identity:outer" "identity:inner"])
  (local before (H.snapshot-tree s.identity-store.entities-dir))
  (local result (store:remove-item held.id "identity:inner"))
  (assert (= result held) "successful member removal must preserve held record identity")
  (assert (= (length held.items) 1))
  (assert (= (. held.items 1) "identity:outer") "explicit removal must remove inner, not its preceding upstream alias")
  (same before (H.snapshot-tree s.identity-store.entities-dir)))

(fn absent-explicit-removal [s notebook?]
  (removal-aliases s)
  (local (store create) (ordered-store s notebook?))
  (local held (create store {:id "members" :items ["identity:outer"]}))
  (local items held.items)
  (local before (H.snapshot-tree s.base-dir))
  (local signal (if notebook? store.notebook-updated store.list-entity-updated))
  (var updates 0)
  (fn observe [_] (set updates (+ updates 1)))
  (local handler (signal:connect observe))
  (local (ok result) (pcall store.remove-item store held.id "identity:inner"))
  (signal:disconnect handler true)
  (assert ok (tostring result))
  (assert (= (length held.items) 1) "absent explicit membership must be a no-op, not remove its upstream alias")
  (assert (= (. held.items 1) "identity:outer"))
  (assert (= held.items items) "a no-op must preserve the held member array")
  (assert (= updates 0) "absent explicit removal must not publish an update")
  (same before (H.snapshot-tree s.base-dir)))

(fn mounted-explicit-retirement [s notebook?]
  (removal-aliases s)
  (local (store create) (ordered-store s notebook?))
  (local held (create store {:id "members" :items ["identity:outer" "identity:inner"]}))
  (fn mounted [_graph map]
    (local key (if notebook? "notebook:members" "list-entity:members"))
    (local node (map:load-by-key key))
    (assert (= node.graph map) "cleanup regression requires an actually mounted GraphMap adapter")
    (assert (= node.identity-store s.identity-store))
    (local deleted [])
    (fn observe [record] (table.insert deleted record.id))
    (local handler (s.identity-store.identity-deleted:connect observe))
    (local before (if notebook? (store:snapshot-notebook "members") (store:snapshot-entity "members")))
    (local (ok result) (pcall s.identity-store.retire-entity! s.identity-store "inner"))
    (s.identity-store.identity-deleted:disconnect handler true)
    (assert ok (tostring result))
    (same deleted ["inner"])
    (assert (= (s.identity-store:get-entity "inner") nil))
    (assert (= (. (s.identity-store:get-entity "outer") :target-key) "identity:inner")
            "physical retirement is not coordinated upstream-alias deletion")
    (same held.items ["identity:outer" "identity:inner"])
    (local after (if notebook? (store:snapshot-notebook "members") (store:snapshot-entity "members")))
    (assert (= after.bytes before.bytes) "physical retirement callback must not author owning membership")
    (assert (s.string-store:get-entity "a") "physical identity retirement must not delete its former target")
    (assert (= (map:lookup key) node)))
  (H.with-graph s mounted))

(fn list-explicit-removal [s] (explicit-removal s false))
(fn notebook-explicit-removal [s] (explicit-removal s true))
(fn list-absent-explicit-removal [s] (absent-explicit-removal s false))
(fn notebook-absent-explicit-removal [s] (absent-explicit-removal s true))
(fn list-mounted-explicit-retirement [s] (mounted-explicit-retirement s false))
(fn notebook-mounted-explicit-retirement [s] (mounted-explicit-retirement s true))

(add-test "selected Create List Entity normalizes before dedupe" selected-list)
(add-test "selected Create Link Entity stores stable endpoints" selected-link)
(add-test "Create child stores stable endpoints and stays visible" child)
(add-test "list node add dedupes an existing raw selection" list-add)
(add-test "notebook Add String Entity and add dedupe" notebook-add)
(add-test "dict node edit delegates normalization" dict-edit)
(add-test "list insertion and replacement boundaries" list-boundaries)
(add-test "notebook insertion and replacement boundaries" notebook-boundaries)
(add-test "dict insertion and replacement boundaries" dict-boundaries)
(add-test "link insertion and replacement boundaries" link-boundaries)
(add-test "canonical injection and explicit mismatches" injection)
(add-test "standalone factories and default conflicts" defaults)
(add-test "legacy reads and removals allocate no identities" legacy)
(add-test "link queries follow terminal and upstream aliases" query-links)
(add-test "alias retarget refresh preserves visible parallel links" query-refresh)
(add-test "Show link entities uses active owning stores" show-links)
(add-test "list failed writes preserve held records and signals" list-failure)
(add-test "notebook failed writes preserve held records and signals" notebook-failure)
(add-test "dict failed writes preserve held records and signals" dict-failure)
(add-test "link failed writes preserve held records and signals" link-failure)
(add-test "ordered mutation failures preserve held arrays" ordered-failures)
(add-test "required holder IO errors surface" io-errors)
(add-test "dict mutation failures preserve held slots and signals" dict-mutations-failure)
(add-test "dict enumeration failure never partially publishes" dict-enumeration-failure)
(add-test "list explicit removal preserves upstream aliases" list-explicit-removal)
(add-test "notebook explicit removal preserves upstream aliases" notebook-explicit-removal)
(add-test "list absent explicit removal is a no-op" list-absent-explicit-removal)
(add-test "notebook absent explicit removal is a no-op" notebook-absent-explicit-removal)
(add-test "list mounted physical identity retirement preserves membership" list-mounted-explicit-retirement)
(add-test "notebook mounted physical identity retirement preserves membership" notebook-mounted-explicit-retirement)

{:name "reference-lifecycle-writes" :tests tests}
