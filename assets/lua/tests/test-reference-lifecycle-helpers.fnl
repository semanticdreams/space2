(local fs (require :fs))
(local tempfile (require :tempfile))

(fn with-root [f]
  (local resource (tempfile.TemporaryDirectory {:prefix "reference-lifecycle-"}))
  (local (ok result) (pcall f (fs.absolute resource.path)))
  (local (cleanup-ok cleanup-error) (pcall resource.drop resource))
  (if (not ok) (error result)
      (not cleanup-ok) (error cleanup-error)
      result))

(fn stores [root]
  (local base-dir (fs.absolute root))
  (local Identity (require :entities/identity))
  (local identity-store (Identity.IdentityStore {:base-dir base-dir}))
  (local options {:base-dir base-dir :identity-store identity-store})
  {:base-dir base-dir
   :identity-store identity-store
   :string-store ((. (require :entities/string) :StringEntityStore) options)
   :code-store ((. (require :entities/code) :CodeEntityStore) options)
   :list-store ((. (require :entities/list) :ListEntityStore) options)
   :dict-store ((. (require :entities/dict) :DictEntityStore) options)
   :link-store ((. (require :entities/link) :LinkEntityStore) options)
   :notebook-store ((. (require :notebooks/store) :NotebookStore) options)
   :workflow-store ((. (require :workflows/store) :WorkflowStore) options)})

(fn assert-error [fragment f]
  (local (ok result) (pcall f))
  (assert (not ok) (.. "expected error containing: " fragment))
  (local message (tostring result))
  (assert (string.find message fragment 1 true)
          (.. "expected error containing " fragment ", got: " message))
  message)

(fn snapshot-tree [root]
  (local out {})
  (fn visit [path prefix]
    (each [_ entry (ipairs (fs.list-dir path true))]
      (local relative (.. prefix entry.name))
      (if entry.is-dir
          (visit entry.path (.. relative "/"))
          entry.is-file
          (set (. out relative) (fs.read-file entry.path)))))
  (visit root "")
  out)

(fn with-fs-failure [method path f]
  (local original (assert (. fs method) (.. "missing native fs method: " method)))
  (local target (fs.absolute path))
  (tset fs method
        (fn [candidate ...]
          (if (= (fs.absolute candidate) target)
              (error (.. "injected permission denied: " method " " path))
              (original candidate ...))))
  (local (ok result) (pcall f))
  (tset fs method original)
  (if ok result (error result)))

(fn with-graph [s f opts]
  (local Graph (require :graph/core))
  (local GraphMap (require :graph/map))
  (local Entities (require :graph/extensions/builtins/entities))
  (local Catalog (require :entities/type-catalog))
  (local options (collect [key value (pairs s)] key value))
  (each [key value (pairs (or opts {:morphs {} :entity-events? false}))]
    (tset options key value))
  (local graph (Graph options))
  (set options.entity-type-catalog (Catalog.EntityTypeCatalog {:types (Entities.entity-types)}))
  (local descriptor (. (Entities.descriptors options) 1))
  (descriptor.install-loaders graph {:owner-id descriptor.unit-id :extension-id descriptor.id})
  (local map (GraphMap.GraphMap {:graph graph}))
  (local (ok result) (pcall f graph map))
  (local (cleanup-ok cleanup-error) (pcall (fn [] (map:drop) (graph:drop))))
  (if (not ok) (error result)
      (not cleanup-ok) (error cleanup-error)
      result))

(fn with-fields [target fields f]
  (local previous {})
  (each [key value (pairs fields)]
    (tset previous key (. target key))
    (tset target key value))
  (local (ok result) (pcall f))
  (each [key _ (pairs fields)] (tset target key (. previous key)))
  (if ok result (error result)))

(fn cold-lifecycle [s]
  (local manager ((require :world-manager) {:root-dir (fs.join-path s.base-dir "worlds")}))
  (local options {:stores s :world-manager manager})
  (local world ((require :reference-lifecycle/world-owner) options))
  (local runtime ((require :reference-lifecycle/runtime-owner) options))
  (local owners [((require :reference-lifecycle/entities-owner) s)
                ((require :reference-lifecycle/identities-owner) s)
                ((require :reference-lifecycle/workflows-owner) s) world runtime])
  {:service ((require :reference-lifecycle) {:stores s :owners owners})
   :manager manager :world-owner world :runtime-owner runtime})

(fn with-canonical-stores [root f]
  (local cleared {})
  (each [_ name (ipairs [:entities/identity :entities/string :entities/code :entities/list
                         :entities/dict :entities/link :notebooks/store :workflows/store])]
    (require name)
    (tset cleared name false))
  (fn scoped []
    (local composition (require :graph/extensions/builtins/composition))
    (local s (composition.init-reference-stores! {:user-data-dir root}))
    (f s))
  (with-fields package.loaded cleared scoped))

;; Real native model/manager composition. init reads the durable world normally;
;; no inactive-map hydration, fake owner, or alternate persistence directory.
(fn with-native-world [s id f]
  (local HomeWorld (require :home-world))
  (local dir (fs.join-path s.base-dir "worlds" id))
  (local world (HomeWorld {:id id :dir dir}))
  (world:init {})
  (local manager ((require :world-manager)
    {:root-dir (fs.join-path s.base-dir "worlds") :context-fn (fn native-context [] {})
     :create-world (fn native-world [opts] (assert (= opts.id id)) world)}))
  (local options {:stores s :world-manager manager})
  (local world-owner ((require :reference-lifecycle/world-owner) options))
  (local runtime-owner ((require :reference-lifecycle/runtime-owner) options))
  (local owners [((require :reference-lifecycle/entities-owner) s)
                ((require :reference-lifecycle/identities-owner) s)
                ((require :reference-lifecycle/workflows-owner) s) world-owner runtime-owner])
  (local service ((require :reference-lifecycle) {:stores s :owners owners}))
  (fn native [graph _unused]
    (local maps ((. (require :graph/map-manager) :GraphMapManager)
                 {:graph graph :data-dir dir :state world.state.graph}))
    (local board ((. (require :board/core) :Board) {:state world.state.board}))
    (set world.runtime {:graph graph :graph-map-manager maps :board board})
    (manager:get-world-entry id)
    (local fixture {:stores s :world world :manager manager :maps maps :board board :graph graph
                    :service service :world-owner world-owner :runtime-owner runtime-owner})
    (local (ok result) (pcall f fixture))
    (set world.runtime nil)
    (local (drop-ok drop-error) (pcall maps.drop maps))
    (if (not ok) (error result) (not drop-ok) (error drop-error) result))
  (with-graph s native {:lifecycle service :morphs {}}))

(fn assert-reference [identity-store key terminal]
  (assert (= (string.sub key 1 9) "identity:") (.. "expected stable reference, got " key))
  (assert (= (identity-store:resolve-key key) terminal) "stable reference must preserve terminal meaning"))

(fn domain-owners [stores]
  (local EntitiesOwner (require :reference-lifecycle/entities-owner))
  (local IdentitiesOwner (require :reference-lifecycle/identities-owner))
  (local WorkflowsOwner (require :reference-lifecycle/workflows-owner))
  [(EntitiesOwner stores) (IdentitiesOwner stores) (WorkflowsOwner stores)])
(fn empty-owner [id root]
  (fn preflight! [_self] true)
  (fn inventory [_self] {:records {} :sites []})
  (fn expand [_self _inventory _operation] [])
  (fn prepare [_self _inventory _operation] {:changes [] :runtime-state []})
  (fn apply! [_self _change] nil)
  (fn reconcile! [_self _intent] nil)
  {:id id :base-dir (fs.absolute root) :preflight! preflight! :inventory inventory
   :expand expand :prepare prepare :apply! apply! :reconcile! reconcile!})
(fn apply-preparation! [owners preparation]
  (local indexed (collect [_ owner (ipairs owners)] owner.id owner))
  (each [_ phase (ipairs ["replacement" "incoming" "retire"])]
    (each [_ change (ipairs preparation.changes)]
      (when (= change.phase phase)
        (local owner (assert (. indexed change.owner) "missing owner"))
        (owner:apply! change))))
  nil)

(fn owners [s world runtime]
  (assert s.base-dir "test owners require canonical stores")
  (local out (domain-owners s))
  (table.insert out (or world (empty-owner "worlds" s.base-dir)))
  (table.insert out (or runtime (empty-owner "runtime" s.base-dir)))
  out)
(fn lifecycle [s world runtime]
  ((require :reference-lifecycle) {:stores s :owners (owners s world runtime)}))
(fn ready [s world runtime]
  (local service (lifecycle s world runtime))
  (service:start!)
  service)
(fn no-writes [f]
  (fn forbidden [...] (error "unexpected durable write during reconciliation"))
  (with-fields fs {:write-file forbidden :rename forbidden :remove forbidden :create-dirs forbidden} f))
(fn raw-list [s id items]
  ((. (require :json-utils) :write-json!) (fs.join-path s.list-store.entities-dir (.. id ".json"))
    {:id id :name "" :items items :created-at 1 :updated-at 1}))

;; Metadata-only dependency injection for native GraphView fixtures. Never scope
;; application directories or domain defaults; graph/ctx are intentionally shallow.
(fn metadata-scoped-factory [constructor]
  (var directory nil)
  (fn create [options]
    (local scoped (collect [key value (pairs options)] key value))
    (when (= scoped.data-dir nil) (set scoped.data-dir directory))
    (constructor scoped))
  (fn with-data-dir [root f]
    (local previous directory)
    (set directory root)
    (local (ok result) (pcall f))
    (set directory previous)
    (if ok result (error result)))
  (setmetatable {:with-data-dir with-data-dir}
                {:__call (fn [_self options] (create options))}))

(fn observe-metadata-view [options root explicit]
  (local graph (options.graph))
  (local ctx (options.ctx))
  (local opts {:graph-map graph :ctx ctx})
  (when explicit (set opts.data-dir explicit))
  (local view (options.view opts))
  (local (ok result) (pcall (fn observe []
    (assert (= view.graph-map graph) "metadata factory must retain native graph pointer")
    (assert (= view.ctx ctx) "metadata factory must retain native context pointer")
    (assert (= opts.data-dir explicit) "metadata factory must not mutate caller options")
    (view:capture-state)
    (view.persistence:persist view.points true)
    (assert (fs.exists (fs.join-path (or explicit root) "graph" "maps" graph.id "metadata.json"))
            "native metadata must persist under the selected fixture directory")
    graph.graph.identity-store.base-dir)))
  (local (drop-ok drop-error) (pcall (fn cleanup [] (view:drop) (graph:drop) (graph.graph:drop))))
  (if (not ok) (error result) (not drop-ok) (error drop-error) result))

(fn check-nested-metadata-scope [options root nested]
  (options.with-data-dir nested #(observe-metadata-view options nested nil))
  (assert-error "metadata scope sentinel"
    #(options.with-data-dir nested (fn fail [] (error "metadata scope sentinel"))))
  (observe-metadata-view options root nested))

(fn assert-domain-root! [actual expected metadata]
  (assert (= actual expected)
          (.. "native graph default identity root must be canonical; actual=" actual
              "; expected=" expected "; metadata=" metadata
              "; actual-exists=" (tostring (fs.exists actual)))))

(fn check-graph-view-metadata-fixture [options]
  (local appdirs (require :appdirs))
  (local getter appdirs.user-data-dir)
  (local canonical (fs.absolute (getter "space")))
  (var identity-root nil)
  (options.with-temp-dir (fn outer [root]
    (options.with-data-dir root (fn scoped []
      ;; This assertion must run before any default-store acquisition.
      (assert (= appdirs.user-data-dir getter) "metadata fixture must not replace appdirs getter")
      (set identity-root (observe-metadata-view options root nil))
      (assert-domain-root! identity-root canonical root)
      (options.with-temp-dir #(check-nested-metadata-scope options root $1))
      (observe-metadata-view options root nil)))))
  (assert (= appdirs.user-data-dir getter) "metadata scopes must retain appdirs getter after cleanup")
  (assert (and (= identity-root canonical) (fs.exists identity-root))
          "canonical identity root must survive metadata fixture cleanup"))

(fn append-graph-view-metadata-test! [tests options]
  (table.insert tests {:name "GraphView metadata fixture keeps domain defaults canonical"
                      :fn #(check-graph-view-metadata-fixture options)}))

;; Diagnostic observations use cold owning snapshots, not cached identities,
;; ensure-key, graph loaders, or a store constructor that creates directories.
(fn observe-cold-reference [store key]
  (assert (= (type key) :string) "cold reference observation requires native subject key")
  (local chain []) (local seen {})
  (var terminal key) (var status "resolved")
  (while (and (= status "resolved") (= (string.sub terminal 1 9) "identity:"))
    (assert (not (. seen terminal)) "cold reference observation found identity cycle")
    (assert (< (# chain) 32) "cold reference observation exceeded native identity depth")
    (tset seen terminal true)
    (local snapshot (store:snapshot-entity (string.sub terminal 10)))
    (table.insert chain {:identity-key terminal :snapshot snapshot})
    (if (= snapshot.value false) (set status "missing-identity")
        (= snapshot.value.target-key "") (set status "empty-target")
        (set terminal snapshot.value.target-key)))
  {:subject-key key :terminal-key terminal :status status :cold-chain chain})

(fn observe-board-reference-state [store board]
  (if (= board nil) false
      (do
        (assert (= (type board) :table) "board observation requires native state")
        (local R (require :reference-lifecycle/record-utils))
        {:state (R.clone board)
         :survivors (icollect [_ item (ipairs board.items)]
                      (when (or (= item.id "a") (= item.id "b"))
                        {:item-id item.id :reference (observe-cold-reference store item.subject-key)}))})))

(fn observe-world-board-roles [store record]
  (assert (= (type record) :table) "world observation requires native owning record")
  (local sessions (and record.activity record.activity.sessions))
  (local rt record.runtime)
  {:root (observe-board-reference-state store record.board)
   :activity (observe-board-reference-state store (and sessions sessions.board sessions.board.board-state))
   :retained (observe-board-reference-state store (and rt rt.board-state))
   :runtime-session (observe-board-reference-state store
                     (and rt rt.activity-session-state rt.activity-session-state.board
                          rt.activity-session-state.board.board-state))})

(fn observe-read-only [root read]
  (assert (= (type read) :function) "read-only observation requires callback")
  (local before (snapshot-tree root))
  (local state (no-writes read))
  (local after (snapshot-tree root))
  (local J (require :json-utils))
  {:state state :cold-io {:owning-tree-before before :owning-tree-after after
                          :equal? (= (J.stable-json before) (J.stable-json after))}})

(fn same-reference-value [before after]
  (local J (require :json-utils))
  (assert (= (J.stable-json before) (J.stable-json after))
          "native reference stage values must match exactly"))

(fn reference-stage-boards [stage]
  (assert stage.state "reference stage requires captured native state")
  (local state stage.state)
  (local roles {:native-model state.native-board})
  (each [_ id (ipairs [:loaded :unopened])]
    (each [role board (pairs (. state id :board-roles))]
      (tset roles (.. id ".persisted." role) board)))
  (each [role board (pairs state.loaded-reference.board-roles)]
    (tset roles (.. "loaded.reference." role) board))
  roles)

(fn raw-board-role [roles role]
  (local before (. roles role))
  (if before before
      ;; These persisted mirrors first materialize at startup publication; their
      ;; separate native retained/session records already exist before start.
      (= role "loaded.persisted.retained") (. roles "loaded.reference.retained")
      (= role "loaded.persisted.runtime-session") (. roles "loaded.reference.runtime-session")
      (error (.. "missing raw native board role: " role))))

(fn assert-cold-subject [store actual original]
  (assert (= (string.sub actual 1 9) "identity:") "migrated fixture subject must be stable")
  (local cold (observe-cold-reference store actual))
  (assert (= cold.status "resolved") "stable subject must have actual cold owning records")
  (assert (> (# cold.cold-chain) 0) "stable subject must traverse an owning identity record")
  (assert (= cold.terminal-key original) "stable subject must retain its original owning target"))

(fn assert-board-subject-migration [before after store]
  (local R (require :reference-lifecycle/record-utils))
  (R.require-array before.items) (R.require-array after.items)
  (assert (= (# before.items) (# after.items)) "migration must retain item count")
  (local expected (R.clone before))
  (each [index original (ipairs before.items)]
    (local migrated (. after.items index))
    (assert (= migrated.id original.id) "migration must retain native item order")
    (assert-cold-subject store migrated.subject-key original.subject-key)
    ;; Only this canonical representation field may differ during migration.
    (set (. expected.items index :subject-key) migrated.subject-key))
  (same-reference-value expected after))

(fn assert-stage-strings [raw stage]
  (each [_ id (ipairs [:a :b])]
    (local before (. raw.state.strings id))
    (local after (. stage.state.strings id))
    (assert (and before.value after.value) "A/B owning string records must exist")
    (assert (= after.value.id id) "A/B owning string record id must be unchanged")
    (assert (= after.bytes before.bytes) "A/B owning string bytes must remain unchanged")
    (same-reference-value before after))
  (assert stage.cold-io.equal? "native reference stage observation must not write")
  (same-reference-value stage.cold-io.owning-tree-before stage.cold-io.owning-tree-after))

(fn assert-migration-stages [raw migrated store]
  (local before (reference-stage-boards raw))
  (each [role board (pairs (reference-stage-boards migrated))]
    (when board
      (assert-board-subject-migration (. (raw-board-role before role) :state) board.state store)))
  (assert-stage-strings raw raw)
  (assert-stage-strings raw migrated))

(fn board-survivors [board]
  (assert board.items "survivor comparison requires native board items")
  (icollect [_ item (ipairs board.items)]
    (when (or (= item.id "a") (= item.id "b")) item)))

(fn assert-survivor-board [before migrated after store]
  (local expected (board-survivors migrated))
  (local actual (board-survivors after))
  (assert (= (# expected) 2) "migration baseline must retain both A/B survivors")
  ;; The action gets no subject-key exception: stable IDs and every other field
  ;; must equal the frozen post-start, pre-operation records in native order.
  (same-reference-value expected actual)
  (each [_ survivor (ipairs actual)]
    (local originals (icollect [_ item (ipairs before.items)] (when (= item.id survivor.id) item)))
    (assert (= (# originals) 1) "survivor must have exactly one original raw native row")
    (assert-cold-subject store survivor.subject-key (. originals 1 :subject-key))))

(fn assert-operation-survivors [raw migrated after store]
  (local original (reference-stage-boards raw))
  (local actual (reference-stage-boards after))
  (each [role baseline (pairs (reference-stage-boards migrated))]
    (local current (. actual role))
    (assert (= (type baseline) (type current)) "operation must retain native board-role presence")
    (when baseline
      (assert-survivor-board (. (raw-board-role original role) :state) baseline.state current.state store)))
  (assert-stage-strings raw after))

{:with-root with-root
 :stores stores
 :assert-error assert-error
 :snapshot-tree snapshot-tree
 :with-fs-failure with-fs-failure
 :with-graph with-graph
 :with-fields with-fields
 :cold-lifecycle cold-lifecycle :with-native-world with-native-world :with-canonical-stores with-canonical-stores
 :assert-reference assert-reference
 :domain-owners domain-owners :empty-owner empty-owner :apply-preparation! apply-preparation!
  :owners owners :lifecycle lifecycle :ready ready :no-writes no-writes :raw-list raw-list
  :append-graph-view-metadata-test! append-graph-view-metadata-test!
   :metadata-scoped-factory metadata-scoped-factory
   :observe-board-reference-state observe-board-reference-state
   :observe-world-board-roles observe-world-board-roles :observe-read-only observe-read-only
   :assert-migration-stages assert-migration-stages :assert-operation-survivors assert-operation-survivors}
