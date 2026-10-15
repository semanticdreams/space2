(local H (require :tests/test-reference-lifecycle-helpers))
(local fs (require :fs))
(local JsonUtils (require :json-utils))
(local tests [])

(fn add-test [suffix f]
  (fn run []
    (H.with-root (fn [root] (f (H.stores root)))))
  (table.insert tests {:name (.. "reference lifecycle identity " suffix) :fn run}))

(fn same-tree [s before]
  (assert (= (JsonUtils.stable-json (H.snapshot-tree s.base-dir))
             (JsonUtils.stable-json before)) "persisted bytes must remain unchanged"))

(fn with-graph [s f]
  (local Graph (require :graph/core))
  (local GraphMap (require :graph/map))
  (local Entities (require :graph/extensions/builtins/entities))
  (local Catalog (require :entities/type-catalog))
  (local graph (Graph {:identity-store s.identity-store :link-store s.link-store
                      :string-store s.string-store :morphs {} :entity-events? false}))
  (local options {})
  (each [key value (pairs s)] (tset options key value))
  (set options.entity-type-catalog (Catalog.EntityTypeCatalog {:types (Entities.entity-types)}))
  (local descriptor (. (Entities.descriptors options) 1))
  (descriptor.install-loaders graph {:owner-id descriptor.unit-id :extension-id descriptor.id})
  (local map (GraphMap.GraphMap {:graph graph}))
  (local (ok result) (pcall f graph map))
  (local (cleanup-ok cleanup-error)
    (pcall (fn [] (map:drop) (graph:drop))))
  (if (not ok) (error result)
      (not cleanup-ok) (error cleanup-error)
      result))

(fn with-publications [store f]
  (local counts {:created 0 :updated 0 :deleted 0})
  (local records [])
  (each [name signal (pairs {:created store.identity-created
                             :updated store.identity-updated :deleted store.identity-deleted})]
    (fn record-publication [_] (tset counts name (+ (. counts name) 1)))
    (local handler (signal:connect record-publication))
    (table.insert records {:signal signal :handler handler}))
  (local (ok result) (pcall f counts))
  (each [_ record (ipairs records)] (record.signal:disconnect record.handler true))
  (if ok result (error result)))

(fn identity-path [s id]
  (fs.join-path s.identity-store.entities-dir (.. id ".json")))

(fn make-chain [store count]
  (for [i count 1 -1]
    (store:create-entity {:id (tostring i)
                          :target-key (if (= i count) "external:terminal"
                                          (.. "identity:" (+ i 1)))})))

(fn fixtures [s]
  (local other (H.stores s.base-dir))
  (assert (not (= s.identity-store other.identity-store)))
  (each [_ name (ipairs [:string-store :code-store :list-store :dict-store :link-store
                         :identity-store :notebook-store :workflow-store])]
    (assert (= (. s name :base-dir) (fs.absolute s.base-dir))))
  (local nested (fs.join-path s.base-dir "nested"))
  (fs.create-dirs nested)
  (fs.write-file (fs.join-path nested "fixture") "exact bytes\n")
  (assert (= (. (H.snapshot-tree s.base-dir) "nested/fixture") "exact bytes\n")))

(fn failure-guard [s]
  (local original fs.write-file)
  (local path (fs.join-path s.base-dir "blocked"))
  (fn fail-callback []
    (H.assert-error "permission denied" (fn [] (fs.write-file path "bad")))
    (fs.write-file (fs.join-path s.base-dir "allowed") "ok")
    (error "callback failed"))
  (H.assert-error "callback failed"
    (fn [] (H.with-fs-failure :write-file path fail-callback)))
  (assert (= original fs.write-file))
  (fs.write-file path "restored")
  (assert (= (fs.read-file path) "restored")))

(fn aliases [s]
  (local store s.identity-store)
  (local z (store:create-entity {:id "z" :target-key "string-entity:s" :updated-at 20}))
  (local a (store:create-entity {:id "a" :target-key "string-entity:s" :updated-at 1}))
  (local before (H.snapshot-tree s.base-dir))
  (assert (= (store:ensure-key "string-entity:s") "identity:a"))
  (assert (= (store:ensure-key "identity:z") "identity:z"))
  (assert (= (store:ensure-key "identity:absent") "identity:absent"))
  (assert (= (store:get-entity "z") z))
  (assert (= (store:get-entity "a") a))
  (same-tree s before)
  (local key (store:ensure-key "external:new" {:id "new" :metadata {:name "stable"}}))
  (assert (= key "identity:new"))
  (assert (= (. (store:get-entity "new") :metadata :name) "stable"))
  (assert (= (store:ensure-key "external:new") key))
  (assert (= (store:ensure-key "") "")))

(fn graph-ensure [s]
  (with-graph s (fn [graph map]
    (local before (JsonUtils.stable-json (graph:capture-state)))
    (local key (graph:ensure-identity-key "external:new" {:id "hidden"}))
    (assert (= key "identity:hidden"))
    (assert (= before (JsonUtils.stable-json (graph:capture-state)))
            "ensure must not expose an identity node")
    (assert (= (map:node-count) 0))
    (assert (= (graph:ensure-identity-key "external:new") key))
    (local node (graph:create-identity "external:new" {:id "explicit"}))
    (assert (= node.key "identity:explicit"))
    (assert (= (graph:node-count) 1) "explicit create remains exposure"))))

(fn graph-free-resolution [s use-map?]
  (s.identity-store:create-entity {:id "a" :target-key "external:terminal"})
  (with-graph s (fn [graph map]
    (var loads 0)
    (fn load-external [_] (set loads (+ loads 1)) nil)
    (graph:register-key-loader "external" load-external)
    (local before (H.snapshot-tree s.base-dir))
    (local subject (if use-map? map graph))
    (local (terminal chain) (subject:resolve-key "identity:a"))
    (assert (= terminal "external:terminal"))
    (assert (= loads 0) "resolution must not call key loaders")
    (assert (= (graph:node-count) 0) "resolution must not expose wrappers")
    (assert (= (map:node-count) 0))
    (assert (= (. chain 1) "identity:a"))
    (same-tree s before))))

(fn graph-resolve [s] (graph-free-resolution s false))
(fn map-resolve [s] (graph-free-resolution s true))

(fn upstream [s]
  (local store s.identity-store)
  (store:create-entity {:id "a" :target-key "identity:z"})
  (store:create-entity {:id "z" :target-key "external:terminal"})
  (local before (H.snapshot-tree s.base-dir))
  (local (terminal chain) (store:resolve-key "identity:a"))
  (assert (= terminal "external:terminal"))
  (assert (= (table.concat chain ",") "identity:a,identity:z"))
  (same-tree s before))

(fn assert-cycle [subject key]
  (H.assert-error "resolve-key identity cycle detected" (fn [] (subject:resolve-key key))))

(fn cycles [s]
  (each [_ pair (ipairs [["self" "self"] ["a" "b"] ["b" "a"] ["up" "a"]])]
    (s.identity-store:create-entity {:id (. pair 1) :target-key (.. "identity:" (. pair 2))}))
  (with-graph s (fn [graph map]
    (local before (H.snapshot-tree s.base-dir))
    (each [_ subject (ipairs [graph map s.identity-store])]
      (each [_ key (ipairs ["identity:self" "identity:a" "identity:up"])]
        (assert-cycle subject key)))
    (assert (= (graph:node-count) 0))
    (assert (= (map:node-count) 0))
    (same-tree s before))))

(fn depth-32 [s]
  (make-chain s.identity-store 32)
  (with-graph s (fn [graph map]
    (each [_ subject (ipairs [graph map s.identity-store])]
      (local (key chain) (subject:resolve-key "identity:1"))
      (assert (= key "external:terminal"))
      (assert (= (length chain) 32))))))

(fn assert-depth-error [subject opts]
  (H.assert-error "resolve-key identity depth exhausted"
    (fn [] (subject:resolve-key "identity:1" opts))))

(fn depth-33 [s]
  (make-chain s.identity-store 33)
  (with-graph s (fn [graph map]
    (local before (H.snapshot-tree s.base-dir))
    (each [_ subject (ipairs [map graph s.identity-store])]
      (assert-depth-error subject {}))
    (assert (= (graph:node-count) 0))
    (assert (= (map:node-count) 0))
    (same-tree s before))))

(fn explicit-limits [s]
  (make-chain s.identity-store 3)
  (with-graph s (fn [graph map]
    (each [_ subject (ipairs [map graph s.identity-store])]
      (fn resolve-visited [] (subject:resolve-key "identity:1" {:visited {:identity:2 true}}))
      (assert-depth-error subject {:max-depth 2})
      (assert (= (subject:resolve-key "identity:1" {:max-depth 3}) "external:terminal"))
      (H.assert-error "resolve-key identity cycle detected"
        resolve-visited)))))

(fn assert-terminal [subject key]
  (local (terminal chain) (subject:resolve-key key {:max-depth 0}))
  (assert (= terminal key))
  (assert (= (length chain) (if (string.match key "^identity:") 1 0))))

(fn terminal-keys [s]
  (s.identity-store:create-entity {:id "draft"})
  (with-graph s (fn [graph map]
    (local before (H.snapshot-tree s.base-dir))
    (each [_ subject (ipairs [graph map s.identity-store])]
      (each [_ key (ipairs ["identity:missing" "identity:draft" "external:raw" ""])]
        (assert-terminal subject key)))
    (assert (= (graph:node-count) 0))
    (same-tree s before))))

(fn failed-create [s]
  (local before (H.snapshot-tree s.base-dir))
  (fn attempt-create []
    (H.assert-error "permission denied" (fn []
      (s.identity-store:create-entity {:id "failed" :target-key "external:old"}))))
  (with-publications s.identity-store (fn [counts]
    (H.with-fs-failure :write-file (.. (identity-path s "failed") ".tmp") attempt-create)
    (assert (= (s.identity-store:get-entity "failed") nil) "failed create must not cache")
    (assert (= counts.created 0))
    (same-tree s before))))

(fn failed-update [s]
  (local held (s.identity-store:create-entity {:id "held" :target-key "external:old"
                                              :updated-at 1 :metadata {:name "old"}}))
  (local before (H.snapshot-tree s.base-dir))
  (fn attempt-update []
    (H.assert-error "permission denied" (fn []
      (s.identity-store:update-entity "held" {:target-key "external:new" :metadata {:name "new"}}))))
  (with-publications s.identity-store (fn [counts]
    (H.with-fs-failure :write-file (.. (identity-path s "held") ".tmp") attempt-update)
    (assert (= held.target-key "external:old") "failed update must not mutate held record")
    (assert (= held.updated-at 1))
    (assert (= held.metadata.name "old"))
    (assert (= (s.identity-store:get-entity "held") held))
    (assert (= counts.updated 0))
    (same-tree s before))))

(fn failed-retirement [s]
  (local held (s.identity-store:create-entity {:id "held" :target-key "external:old"}))
  (local before (H.snapshot-tree s.base-dir))
  (fn attempt-retire []
    (H.assert-error "permission denied" (fn [] (s.identity-store:delete-entity "held"))))
  (with-publications s.identity-store (fn [counts]
    (H.with-fs-failure :remove (identity-path s "held") attempt-retire)
    (assert (= (s.identity-store:get-entity "held") held))
    (assert (= counts.deleted 0))
    (same-tree s before))))

(fn successful-updates [s]
  (local store s.identity-store)
  (local held (store:create-entity {:id "held" :target-key "external:old"}))
  (store:list-entities)
  (assert (= (store:get-entity "held") held) "enumeration must not replace cached record")
  (with-publications store (fn [counts]
    (assert (= (store:update-entity "held" {:target-key "external:new"}) held))
    (assert (= held.target-key "external:new"))
    (assert (= counts.updated 1))
    (local cold (. (H.stores s.base-dir) :identity-store))
    (assert (= (. (cold:get-entity "held") :target-key) "external:new"))
    (assert (= (store:delete-entity "held") held))
    (assert (= counts.deleted 1))
    (assert (= (store:get-entity "held") nil)))))

(fn directory-failure [s]
  (local Identity (require :entities/identity))
  (fn create-store [] (Identity.IdentityStore {:base-dir s.base-dir}))
  (H.with-fs-failure :create-dirs s.identity-store.entities-dir (fn []
    (H.assert-error "permission denied" create-store))))

(fn enumeration-failure [s]
  (fn list-records [] (s.identity-store:list-entities))
  (H.with-fs-failure :list-dir s.identity-store.entities-dir (fn []
    (H.assert-error "permission denied" list-records))))

(fn read-failure [s]
  (s.identity-store:create-entity {:id "held"})
  (local cold (. (H.stores s.base-dir) :identity-store))
  (local path (identity-path s "held"))
  (fn get-record [] (cold:get-entity "held"))
  (fn list-records [] (cold:list-entities))
  (H.with-fs-failure :read-file path (fn []
    (H.assert-error path get-record)
    (H.assert-error path list-records))))

(fn malformed [s]
  (local path (identity-path s "broken"))
  (fs.write-file path "{broken json")
  (H.assert-error path (fn [] (s.identity-store:get-entity "broken")))
  (H.assert-error path (fn [] (s.identity-store:list-entities))))

(fn rename-failure [s]
  (local held (s.identity-store:create-entity {:id "held" :target-key "external:old"}))
  (local before (H.snapshot-tree s.base-dir))
  (fn attempt-update []
    (H.assert-error "json-utils failed to rename" (fn []
      (s.identity-store:update-entity "held" {:target-key "external:new"}))))
  (with-publications s.identity-store (fn [counts]
    (H.with-fs-failure :rename (.. (identity-path s "held") ".tmp") attempt-update)
    (assert (= held.target-key "external:old"))
    (assert (= (s.identity-store:get-entity "held") held))
    (assert (= counts.updated 0))
    (same-tree s before))))

(add-test "fixtures isolate roots and explicit dependencies" fixtures)
(add-test "failure guard restores native fs after exceptions" failure-guard)
(add-test "preserves aliases and deterministic reuse" aliases)
(add-test "graph ensure does not expose wrappers" graph-ensure)
(add-test "graph resolution never loads nodes" graph-resolve)
(add-test "map resolution never loads nodes" map-resolve)
(add-test "returns ordered upstream traversal" upstream)
(add-test "rejects cycles without files or topology changes" cycles)
(add-test "allows exactly 32 traversals" depth-32)
(add-test "rejects 33 traversals instead of partial resolution" depth-33)
(add-test "honors explicit depth and visited limits" explicit-limits)
(add-test "terminates at missing empty and generic keys" terminal-keys)
(add-test "failed create never publishes cache or success" failed-create)
(add-test "failed update preserves held cache and success signals" failed-update)
(add-test "failed retirement preserves record and success signals" failed-retirement)
(add-test "successful updates preserve cached record identity" successful-updates)
(add-test "surfaces required directory failures" directory-failure)
(add-test "surfaces required enumeration failures" enumeration-failure)
(add-test "surfaces required read failures" read-failure)
(add-test "surfaces malformed records with their path" malformed)
(add-test "atomic rename failure leaves cache and bytes unchanged" rename-failure)

{:name "reference-lifecycle-identity" :tests tests}
