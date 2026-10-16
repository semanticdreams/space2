(local H (require :tests/test-reference-lifecycle-helpers))
(local fs (require :fs))
(local json (require :json))
(local J (require :json-utils))
(local {: Board} (require :board/core))
(local HomeWorld (require :home-world))
(local {: GraphMapManager} (require :graph/map-manager))
(local tests [])
(local source-key "string-entity:s")
(local source-text " \n(+ 1 2)\n ")

(fn same [actual expected]
  (assert (= (J.stable-json actual) (J.stable-json expected))
          (.. "values differ: " (J.stable-json actual) " != " (J.stable-json expected))))

(fn board-state []
  {:items [{:id "source" :type "string-entity" :subject-key source-key
            :position [11 12 0] :rotation [1 0 0 0] :size [33 17 0]
            :state {:marker "source state"}}
           {:id "a" :type "string-entity" :subject-key "string-entity:a"
            :position [50 0 0] :rotation [1 0 0 0] :size [32 16 0] :state {:marker "A"}}
           {:id "b" :type "string-entity" :subject-key "string-entity:b"
            :position [90 0 0] :rotation [1 0 0 0] :size [32 16 0] :state {:marker "B"}}]
   :connectors [{:id "K" :source-item-id "a" :target-item-id "b"
                 :kind "semantic-link" :semantic-link-id "k" :state {:marker "semantic"}}
                {:id "T" :source-item-id "source" :target-item-id "a"
                 :kind "visual" :state {:marker "incident"}}]})

(fn graph-state []
  {:active_map_id "main" :next_map_id 3
   :maps [{:id "main" :name "Main" :nodes [] :edges []}
          {:id "reserve" :name "Reserve" :nodes [source-key "string-entity:a"]
           :edges [{:source source-key :target "string-entity:a" :weight 7 :label "explicit"}]
           :selected_node_keys [source-key] :focused_node_key source-key
           :view_mode "outline" :outline_root_keys [source-key]
           :islands [{:id "island-s" :kind "ordered-list" :members [source-key "string-entity:a"]
                      :state {:list-key source-key :marker "island"}}]}]})

(fn metadata []
  {:positions {source-key [11 12 0] :string-entity:a [50 0 0]}
   :sizes {source-key [33 17] :string-entity:a [32 16]}
   :presentations {source-key "expanded"}
   :panels [{:kind "graph-node-view" :graph-map-id "reserve" :node-key source-key
             :target-kind "canvas" :panel {:node-key source-key :position [4 5 0] :extra false}}]
   :extra_panels [{:kind "graph-node-view" :graph-map-id "reserve" :node-key source-key
                   :target-kind "hud" :panel {:node-key source-key :extra "keep"}}]
   :camera {:position [1 2 100]}
   :view_modes {:spatial {:camera {:position [1 2 100]}}
                :outline {:camera {:position [7 8 100]}}}
   :unknown {:text source-key :enabled? false}})

(fn write-world [s id]
  (local dir (fs.join-path s.base-dir "worlds" id))
  (fs.create-dirs dir)
  (local world (HomeWorld {:id id :dir dir}))
  (set world.state.board (board-state))
  (set world.state.graph (graph-state))
  (set world.state.activity.sessions.board {:board-state (board-state)})
  (world:save-state)
  (local metadata-path (fs.join-path dir "graph" "maps" "reserve" "metadata.json"))
  (fs.create-dirs (fs.parent metadata-path))
  (J.write-json! metadata-path (metadata))
  {:world world :metadata-path metadata-path})

(fn retain-baseline-evidence [fixture]
  (when (os.getenv "SPACE_TASK5_BASELINE_EVIDENCE")
    (local data {:board fixture.baseline-board :world-bytes fixture.baseline-world
                 :metadata-bytes fixture.baseline-metadata :graph (graph-state)})
    (print (.. "[REFERENCE-WORLDS-BASELINE] " (J.stable-json data)))))

(fn with-fixture [s f]
  (s.string-store:create-entity {:id "s" :value source-text})
  (s.string-store:create-entity {:id "a" :value "A"})
  (s.string-store:create-entity {:id "b" :value "B"})
  (s.link-store:create-entity {:id "k" :source-key "string-entity:a" :target-key "string-entity:b"})
  (local loaded (write-world s "loaded"))
  (local unopened (write-world s "unopened"))
  (local board (Board {:state (board-state)}))
  (H.with-graph s (fn with-native-graph [graph active-map]
    (local manager (GraphMapManager {:graph graph :data-dir loaded.world.dir :state (graph-state)}))
    (set loaded.world.runtime {:board board :board-state (board-state)
                               :graph graph :graph-map-manager manager
                               :activity-session-state {:board {:board-state (board-state)}}})
    (local fixture {:stores s :loaded loaded :unopened unopened :board board
                    :graph graph :active-map active-map :manager manager
                    :baseline-board (board:capture-state)
                    :baseline-world (fs.read-file loaded.world.state-path)
                    :baseline-metadata (fs.read-file loaded.metadata-path)})
    (retain-baseline-evidence fixture)
    (local (ok result) (pcall f fixture))
    ;; This scope owns these components, not the runner's engine. In particular
    ;; do not call HomeWorld drop on this deliberately domain-only runtime.
    (set loaded.world.runtime nil)
    (local (drop-ok drop-error) (pcall manager.drop manager))
    (if (not ok) (error result)
        (not drop-ok) (error drop-error)
        result))))

;; Only these trigger functions change at coordinator cutover. Assertions below
;; deliberately observe native loaded state and persisted bytes first.
(var fixture-lifecycle nil)

(fn observe-world-record [entry store]
  (local bytes (fs.read-file entry.world.state-path))
  (local value (json.loads bytes))
  {:path entry.world.state-path :bytes bytes :value value
   :metadata-bytes (fs.read-file entry.metadata-path)
   :board-roles (H.observe-world-board-roles store value)})

(fn observe-loaded-reference [fixture store]
  (local state (fixture.loaded.world:snapshot-reference-state))
  (local boards (collect [_ role (ipairs [:state :activity :model :retained :runtime-session])]
                  role (H.observe-board-reference-state store (. state.board role))))
  {:state state :board-roles boards})

(fn observe-fixture-stage [fixture phase operation]
  (local observed (H.observe-read-only fixture.stores.base-dir (fn read-native-stage []
      (local store fixture.stores.identity-store)
      {:phase phase :operation operation
       :original-raw {:board fixture.baseline-board :world-bytes fixture.baseline-world
                      :metadata-bytes fixture.baseline-metadata}
       :native-board (H.observe-board-reference-state store (fixture.board:capture-state))
       :loaded (observe-world-record fixture.loaded store)
       :unopened (observe-world-record fixture.unopened store)
       :loaded-reference (observe-loaded-reference fixture store)
       :strings {:a (fixture.stores.string-store:snapshot-entity "a")
                  :b (fixture.stores.string-store:snapshot-entity "b")}})))
  (when (os.getenv "SPACE_TASK5_BASELINE_EVIDENCE")
    (print (.. "[REFERENCE-WORLDS-STAGE] " (J.stable-json observed))))
  observed)

(fn morph-source [fixture]
  (local service (fixture-lifecycle fixture))
  (local result (service:replace! source-key {:name "" :language "fnl" :source source-text :kernel 0}))
  (local after (observe-fixture-stage fixture "operation-after" {:kind "morph" :source-key source-key :code-key result.code-key}))
  (H.no-writes #(H.assert-operation-survivors fixture.raw-baseline fixture.migration-baseline after fixture.stores.identity-store))
  (assert (= (fixture.stores.string-store:get-entity "s") nil) "native morph must retire source")
  (assert (= result.code-entity.source source-text) "native morph must preserve source bytes")
  result)
(fn delete-source [fixture]
  (local service (fixture-lifecycle fixture))
  (service:delete! source-key)
  (local after (observe-fixture-stage fixture "operation-after" {:kind "delete" :source-key source-key}))
  (H.no-writes #(H.assert-operation-survivors fixture.raw-baseline fixture.migration-baseline after fixture.stores.identity-store))
  (assert (= (fixture.stores.string-store:get-entity "s") nil) "native delete must retire source"))

(fn assert-morphed-board [fixture state result migrated]
  (local item (. state.items 1))
  (assert (= (fixture.stores.identity-store:resolve-key item.subject-key) result.code-key)
          "board raw subject must retain morphed source meaning")
  (assert (= item.type "code-entity") "morphed board item must render as code")
  (same (icollect [_ current (ipairs state.items)] current.id) ["source" "a" "b"])
  (each [_ field (ipairs [:id :position :rotation :size :state])]
    (same (. item field) (. fixture.baseline-board.items 1 field)))
  (same state.connectors fixture.baseline-board.connectors)
  (same (. state.items 2) (. migrated.items 2))
  (same (. state.items 3) (. migrated.items 3))
  (assert (= result.code-entity.source source-text)))

(fn assert-morphed-map [state result]
  (local inactive (. state.maps 2))
  (assert (= (. inactive.nodes 1) result.code-key) "inactive map must retain replacement participation")
  (same inactive.nodes [result.code-key "string-entity:a"])
  (same inactive.edges [{:source result.code-key :target "string-entity:a" :weight 7 :label "explicit"}])
  (same inactive.selected_node_keys [result.code-key])
  (assert (= inactive.focused_node_key result.code-key))
  (same inactive.outline_root_keys [result.code-key])
  (same (. inactive.islands 1 :members) [result.code-key "string-entity:a"])
  (assert (= (. inactive.islands 1 :state :list-key) result.code-key)))

(fn assert-morphed-metadata [value result]
  (each [_ field (ipairs [:positions :sizes :presentations])]
    (same (. value field result.code-key) (. (metadata) field source-key))
    (assert (= (. value field source-key) nil)))
  (each [_ field (ipairs [:panels :extra_panels])]
    (assert (= (. value field 1 :node-key) result.code-key))
    (assert (= (. value field 1 :panel :node-key) result.code-key)))
  (same value.unknown (. (metadata) :unknown))
  (same value.camera (. (metadata) :camera))
  (same value.view_modes (. (metadata) :view_modes)))

(fn add [name f]
  (fn with-stores [root]
    (local s (H.stores root))
    (with-fixture s f))
  (fn run [] (H.with-root with-stores))
  (table.insert tests {:name (.. "reference lifecycle worlds " name) :fn run}))

(add "morph loaded board current model" (fn loaded-board [fixture]
  (local result (morph-source fixture))
  (assert-morphed-board fixture (fixture.board:capture-state) result
                        (. fixture.migration-baseline :state :native-board :state))))
(add "morph inactive native map participation" (fn inactive-map [fixture]
  (local result (morph-source fixture))
  ;; Observe the installed owning cache without inactive-map hydration.
  (assert-morphed-map (fixture.manager:snapshot-reference-state) result)))
(add "morph unopened world and metadata files" (fn unopened-files [fixture]
  (local result (morph-source fixture))
  (local persisted (json.loads (fs.read-file fixture.unopened.world.state-path)))
  (assert-morphed-board fixture persisted.board result (. fixture.migration-baseline :state :unopened :value :board))
  (assert-morphed-board fixture persisted.activity.sessions.board.board-state result
                        (. fixture.migration-baseline :state :unopened :value :activity :sessions :board :board-state))
  (assert-morphed-map persisted.graph result)
  (assert-morphed-metadata (json.loads (fs.read-file fixture.unopened.metadata-path)) result)))
(add "delete loaded board raw subjects" (fn delete-board [fixture]
  (delete-source fixture)
  (local state (fixture.board:capture-state))
  (local migrated (. fixture.migration-baseline :state :native-board :state))
  (assert (= (length state.items) 2) "genuine delete must remove board raw subject without activation")
  (same state.items [(. migrated.items 2) (. migrated.items 3)])
  (same state.connectors [(. fixture.baseline-board.connectors 1)])
  (assert (fixture.stores.string-store:get-entity "a"))
  (assert (fixture.stores.string-store:get-entity "b"))
   (assert (fixture.stores.link-store:get-entity "k"))))

(fn operation [kind]
  {:kind kind :source-key source-key :target-key "code-entity:c"
   :retiring [source-key "identity:retiring" "link-entity:k"]
   :updated-identity-keys [] :timestamp 123 :replacement false
   :reference-plan (if (= kind "delete") {:rewrites [] :identities []}
                       {:rewrites [{:from-key source-key :to-key "identity:reserved"}]
                        :identities [{:id "reserved" :target-key "code-entity:c"
                                      :created-at 123 :updated-at 123 :metadata {}}]})})

(add "pure map morph retains concrete keys and provenance" (fn pure-map [_fixture]
  (local G (require :graph/reference-state))
  (local before (. (graph-state) :maps 2))
  (set before.history [{:source source-key :target source-key}])
  (local frozen (J.stable-json before))
  (local after (G.rewrite-map before (operation "morph")))
  (assert-morphed-map {:maps [{} after]} {:code-key "code-entity:c"})
  (same after.history before.history)
  (assert (= (J.stable-json before) frozen))))
(add "pure map delete removes only explicit closure" (fn pure-delete [_fixture]
  (local G (require :graph/reference-state))
  (local before (. (graph-state) :maps 2))
  (local after (G.rewrite-map before (operation "delete")))
  (same after.nodes ["string-entity:a"])
  (same after.edges [])
  (same after.selected_node_keys [])
  (assert (= after.focused_node_key nil))
  (same after.outline_root_keys [])
  (same (. after.islands 1 :members) ["string-entity:a"])
  (assert (= (. after.islands 1 :state :list-key) nil))
  (assert (= (. before.nodes 1) source-key))))
(add "pure metadata morph preserves unrelated fields" (fn pure-metadata [_fixture]
  (local G (require :graph/reference-state))
  (local before (metadata))
  (local after (G.rewrite-metadata before (operation "morph")))
  (assert-morphed-metadata after {:code-key "code-entity:c"})
  (assert (. before.positions source-key))))
(add "pure view mirrors use native schema fields" (fn pure-view [_fixture]
  (local G (require :graph/reference-state))
  (local panels (. (metadata) :panels))
  (local spatial {:views {:open-views panels} :extra_panels panels
                  :selected_node_keys [source-key] :focused_node_key source-key
                  :camera {:position [3 4 100]}})
  (local before {:views {:open-views panels :open-node-keys [source-key]}
                :extra_panels panels :selected_node_keys [source-key]
                :focused_node_key source-key :focused_node_key_present? true
                :mode_states {:spatial spatial} :history [{:node-key source-key}]})
  (local after (G.rewrite-view before (operation "morph")))
  (assert (= (. after.views.open-views 1 :node-key) "code-entity:c"))
  (assert (= (. after.views.open-views 1 :panel :node-key) "code-entity:c"))
  (same after.views.open-node-keys ["code-entity:c"])
  (assert (= (. after.extra_panels 1 :node-key) "code-entity:c"))
  (same after.selected_node_keys ["code-entity:c"])
  (assert (= after.focused_node_key "code-entity:c"))
  (local mode (. after.mode_states :spatial))
  (same mode.selected_node_keys ["code-entity:c"])
  (assert (= mode.focused_node_key "code-entity:c"))
  (assert (= (. mode.extra_panels 1 :node-key) "code-entity:c"))
  (assert (= (. mode.views.open-views 1 :node-key) "code-entity:c"))
  (same mode.camera spatial.camera)
  (same after.history before.history)
  (local deleted (G.rewrite-view before (operation "delete")))
  (same deleted.views.open-views [])
  (same deleted.extra_panels [])
  (assert (= deleted.focused_node_key nil))
  (assert (= deleted.focused_node_key_present? false))))
(add "pure board reservations resolve planned code kind" (fn board-reservation [fixture]
  (local B (require :board/reference-state))
  (local before (board-state))
  (local after (B.rewrite before (operation "morph") fixture.stores.identity-store))
  (assert (= (. after.items 1 :subject-key) "identity:reserved"))
  (assert (= (. after.items 1 :type) "code-entity"))
  (same (. after.items 1 :state) (. before.items 1 :state))
  (same after.connectors before.connectors)
  (assert (= (. before.items 1 :subject-key) source-key))
  (assert (= (fixture.stores.identity-store:get-entity "reserved") nil))))
(add "pure board distinct aliases and dangling subjects survive" (fn board-alias [fixture]
  (local B (require :board/reference-state))
  (local store fixture.stores.identity-store)
  (store:create-entity {:id "alias-a" :target-key source-key})
  (store:create-entity {:id "alias-b" :target-key source-key})
  (local before (board-state))
  (set (. before.items 1 :subject-key) "identity:alias-a")
  (set (. before.items 2 :subject-key) "identity:alias-b")
  (set (. before.items 3 :subject-key) "string-entity:historical-missing")
  (local after (B.rewrite before (operation "morph") store))
  (assert (= (. after.items 1 :subject-key) "identity:alias-a"))
  (assert (= (. after.items 2 :subject-key) "identity:alias-b"))
  (assert (= (. after.items 1 :type) "code-entity"))
  (assert (= (. after.items 2 :type) "code-entity"))
  (same (. after.items 3) (. before.items 3))))
(add "pure board delete removes semantic link connectors only" (fn board-link-delete [fixture]
  (local B (require :board/reference-state))
  (local op (operation "delete"))
  (set op.retiring ["link-entity:k"])
  (local before (board-state))
  (local after (B.rewrite before op fixture.stores.identity-store))
  (same after.items before.items)
  (same after.connectors [(. before.connectors 2)])))
(add "map snapshot is nondestructive and nonpersisting" (fn snapshot [fixture]
  (local baseline (H.snapshot-tree fixture.stores.base-dir))
  (local captured (H.no-writes #(fixture.manager:snapshot-reference-state)))
  (same (. captured.maps 2 :nodes) [source-key "string-entity:a"])
  (same (. captured.maps 2 :islands 1 :members) [source-key "string-entity:a"])
  (same (H.snapshot-tree fixture.stores.base-dir) baseline)))
(add "inactive map install survives ordinary capture" (fn install-map [fixture]
  (local G (require :graph/reference-state))
  (local state (fixture.manager:snapshot-reference-state))
  ;; Use an existing concrete node so native ordinary capture can hydrate it.
  (local op (operation "morph"))
  (set op.target-key "string-entity:b")
  (set (. state.maps 2) (G.rewrite-map (. state.maps 2) op))
  (H.no-writes #(fixture.manager:install-reference-state! state))
  (same (. (fixture.manager:capture-state) :maps 2 :nodes)
        ["string-entity:a" "string-entity:b"])))
(add "metadata cache install is nonpersisting and survives save" (fn install-metadata [fixture]
  (local P (require :graph/view/persistence))
  (local G (require :graph/reference-state))
  (local persistence (P {:data-dir fixture.loaded.world.dir :map-id "reserve"}))
  (local before (fs.read-file fixture.loaded.metadata-path))
  (local snapshot (H.no-writes #(persistence:snapshot-state)))
  (local after (G.rewrite-metadata snapshot (operation "morph")))
  (H.no-writes #(persistence:install-state! after))
  (assert (= (fs.read-file fixture.loaded.metadata-path) before))
  (same (persistence:snapshot-state) after)
  (persistence:persist {} true)
  (assert-morphed-metadata (json.loads (fs.read-file fixture.loaded.metadata-path))
                          {:code-key "code-entity:c"})
  (local retained (persistence:snapshot-state))
  (set retained.view_modes.outline.note source-key)
  (persistence:install-state! retained)
  (persistence:persist {} true)
  (local reopened (P {:data-dir fixture.loaded.world.dir :map-id "reserve"}))
  (assert (= (. (reopened:snapshot-state) :view_modes :outline :note) source-key)
          "ordinary reopen must retain unrelated mode metadata")
  (local invalid (reopened:snapshot-state))
  (set invalid.view_modes false)
  (H.assert-error "view_modes" #(H.no-writes #(reopened:install-state! invalid)))
  (same (reopened:snapshot-state) retained)))

(add "Board subject update preserves native identities and rolls back signals" (fn subject-update [fixture]
  (local board fixture.board)
  (local item (. board.items "source"))
  (local state item.state)
  (local position item.position)
  (local connector (. board.connectors "T"))
  (var signals 0)
  (local handler (board.item-updated:connect (fn changed [current]
    (set signals (+ signals 1))
    (assert (= current item))
    (when (= current.subject-key "code-entity:fail") (error "subject publication failed")))))
  (local (ok result) (pcall (fn update []
    (assert (= (board:update-item-subject "source" "identity:stable" "code-entity") item))
    (assert (= (. board.items-in-order 1) item))
    (assert (= item.state state))
    (assert (= item.position position))
    (assert (= (. board.connectors "T") connector))
    (assert (= signals 1))
    (board:update-item-subject "source" "identity:stable" "code-entity")
    (assert (= signals 1) "idempotent publication must not rebuild widgets")
    (H.assert-error "subject publication failed"
                    #(board:update-item-subject "source" "code-entity:fail" "code-entity"))
    (assert (= item.subject-key "identity:stable"))
    (assert (= item.type "code-entity")))))
  (board.item-updated:disconnect handler true)
  (when (not ok) (error result))))

(fn world-manager [fixture]
  (local root (fs.join-path fixture.stores.base-dir "worlds"))
  (J.write-json! (fs.join-path root "index.json")
                {:worlds [{:id "loaded" :type "home" :name "Loaded"}
                          {:id "indexed" :type "home" :name "Indexed"}]})
  (local manager ((require :world-manager)
    {:root-dir root :context-fn (fn context [] {})
     :create-world (fn create [opts]
       (assert (= opts.id "loaded") "reference enumeration must not instantiate unopened worlds")
       fixture.loaded.world)}))
  ;; This is the native, already-created domain runtime owned by with-fixture.
  (set fixture.loaded.world.initialized? true)
  (manager:get-world-entry "loaded")
  manager)

(fn world-owner [fixture manager]
  (assert fixture.stores "world owner fixture requires canonical stores")
  ((require :reference-lifecycle/world-owner)
     {:stores fixture.stores :world-manager (or manager (world-manager fixture))}))

(set fixture-lifecycle (fn [fixture]
  (set fixture.raw-baseline (observe-fixture-stage fixture "raw-baseline" false))
  (local service (H.lifecycle fixture.stores (world-owner fixture)))
  (service:start!)
  (set fixture.migration-baseline (observe-fixture-stage fixture "migration-baseline" false))
  (H.no-writes #(H.assert-migration-stages fixture.raw-baseline fixture.migration-baseline fixture.stores.identity-store))
  service))

(add "owner enumeration includes persisted indexed and loaded without activation" (fn enumerate [fixture]
  (local manager (world-manager fixture))
  (local before (H.snapshot-tree fixture.stores.base-dir))
  (local worlds (H.no-writes #(manager:list-reference-worlds)))
  (same (icollect [_ entry (ipairs worlds)] entry.id) ["indexed" "loaded" "unopened"])
  (assert (= (. worlds 2 :world) fixture.loaded.world))
  (assert (= (. worlds 1 :world) nil))
  (assert (= (. worlds 3 :world) nil))
  (assert (= (manager:active-world-id) nil))
  (same (H.snapshot-tree fixture.stores.base-dir) before)))
(add "owner rejects mismatched canonical root" (fn root-mismatch [fixture]
  (local manager ((require :world-manager) {:root-dir (fs.join-path fixture.stores.base-dir "other")}))
  (H.assert-error "root" #(world-owner fixture manager))))
(add "owner rejects unsafe indexed world ids" (fn unsafe-id [fixture]
  (local manager (world-manager fixture))
  (J.write-json! (fs.join-path fixture.stores.base-dir "worlds" "index.json")
                {:worlds [{:id "../escape"}]})
  (H.assert-error "id" #(H.no-writes #(manager:list-reference-worlds)))))
(add "owner inventory is read only and checks original bytes" (fn inventory-purity [fixture]
  (local R (require :reference-lifecycle/record-utils))
  (local owner (world-owner fixture))
  (local before (H.snapshot-tree fixture.stores.base-dir))
  (local inventory (H.no-writes #(owner:inventory)))
  (local record (assert (. inventory.records "world:unopened")))
  (assert (= record.snapshot.bytes (fs.read-file fixture.unopened.world.state-path)))
  (assert (= record.snapshot.check (R.check-bytes record.snapshot.bytes "json")))
  (same record.snapshot.value (json.loads record.snapshot.bytes))
  (assert (> (# inventory.sites) 0))
  (assert (. inventory.records "world-metadata:unopened:reserve"))
  (same (H.no-writes #(owner:inventory)) inventory)
  (same (H.snapshot-tree fixture.stores.base-dir) before)))
(add "owner rejects malformed world and metadata before writes" (fn malformed [fixture]
  (local owner (world-owner fixture))
  (local path fixture.unopened.world.state-path)
  (local original (fs.read-file path))
  (fs.write-file path "{broken")
  (H.assert-error path #(H.no-writes #(owner:inventory)))
  (fs.write-file path original)
  (fs.write-file fixture.unopened.metadata-path "{\"positions\":null}")
  (H.assert-error "null" #(H.no-writes #(owner:inventory)))))
(add "owner surfaces enumeration and required read failures" (fn io-errors [fixture]
  (local owner (world-owner fixture))
  (H.with-fs-failure "list-dir" (fs.join-path fixture.stores.base-dir "worlds")
    #(H.assert-error "permission denied" #(H.no-writes #(owner:inventory))))
  (H.with-fs-failure "read-file" fixture.unopened.metadata-path
    #(H.assert-error fixture.unopened.metadata-path #(H.no-writes #(owner:inventory))))))
(add "owner aggregates frozen changes per owned path" (fn aggregate [fixture]
  (local owner (world-owner fixture))
  (local R (require :reference-lifecycle/record-utils))
  (local before (H.snapshot-tree fixture.stores.base-dir))
  (local inventory (H.no-writes #(owner:inventory)))
  (local prepared (H.no-writes #(owner:prepare inventory (operation "morph"))))
  (same prepared.runtime-state [])
  (assert (= (# prepared.changes) 4) "two worlds plus two metadata files must aggregate once")
  (local paths {})
  (each [_ change (ipairs prepared.changes)]
    (assert (not (. paths change.path)) "duplicate durable writer")
    (tset paths change.path true)
    (assert (= change.owner "worlds"))
    (assert (= change.format "json"))
    (assert (= change.phase "incoming"))
    (assert (= change.after-check (R.check-bytes change.after-bytes "json")))
    (when (= change.address "world:unopened")
      (local value (json.loads change.after-bytes))
      (assert (= (. value.board.items 1 :subject-key) "identity:reserved"))
      (assert-morphed-map value.graph {:code-key "code-entity:c"})))
  (same (H.snapshot-tree fixture.stores.base-dir) before)))
(add "owner confines replay addresses and verifies frozen bytes" (fn replay-path [fixture]
  (local owner (world-owner fixture))
  (local prepared (owner:prepare (owner:inventory) (operation "morph")))
  (local change (. prepared.changes 1))
  (set change.path fixture.stores.string-store.entities-dir)
  (H.assert-error "path" #(H.no-writes #(owner:apply! change)))
  (set change.path (. (owner:inventory) :records change.address :snapshot :path))
  (set change.after-check "tampered")
  (H.assert-error "after-check" #(H.no-writes #(owner:apply! change)))))
(add "owner migration reports historical dangling board subjects" (fn dangling [fixture]
  (local world fixture.unopened.world)
  (set (. world.state.board.items 1 :subject-key) "string-entity:historical-missing")
  (world:save-state)
  (local owner (world-owner fixture))
  (local service (H.lifecycle fixture.stores owner))
  (local report (service:start!))
  (assert (> (# report.dangling) 0))
  (assert (= (. (json.loads (fs.read-file world.state-path)) :board :items 1 :subject-key)
             "string-entity:historical-missing"))))
(add "owner cold recovery preserves source on write failure" (fn cold-recovery [fixture]
  (local s fixture.stores)
  (local owner (world-owner fixture))
  (local service (H.ready s owner))
  (H.with-fs-failure "write-file" (.. fixture.unopened.world.state-path ".tmp")
    #(H.assert-error "permission denied" #(service:delete! source-key)))
  (assert (s.string-store:get-entity "s") "source must survive failed incoming write")
  (local pending ((require :reference-lifecycle/pending) s.base-dir))
  (local intent (assert (pending:read)))
  (assert (> (# intent.changes) 0))
  (local cold (H.stores s.base-dir))
  (local manager ((require :world-manager) {:root-dir (fs.join-path s.base-dir "worlds")}))
  (local cold-owner ((require :reference-lifecycle/world-owner) {:stores cold :world-manager manager}))
  (local restarted (H.lifecycle cold cold-owner))
  (restarted:start!)
  (assert (= (cold.string-store:get-entity "s") nil))
  (assert (= (pending:read) nil))
  (local reopened (json.loads (fs.read-file fixture.unopened.world.state-path)))
  (assert (= (# reopened.board.items) 2))))

(add "HomeWorld snapshot retains separate native roles without writes" (fn home-snapshot [fixture]
  (local R (require :reference-lifecycle/record-utils))
  (local world fixture.loaded.world)
  (set (. world.runtime.board-state.items 1 :state :marker) "retained")
  (set (. world.runtime.activity-session-state.board.board-state.items 1 :state :marker) "runtime session")
  (local before (H.snapshot-tree fixture.stores.base-dir))
  (local snapshot (H.no-writes #(world:snapshot-reference-state)))
  (same snapshot.board.model (fixture.board:capture-state))
  (assert (= (. snapshot.board.retained.items 1 :state :marker) "retained"))
  (assert (= (. snapshot.board.runtime-session.items 1 :state :marker) "runtime session"))
  (assert (= (. snapshot.board.state.items 1 :state :marker) "source state"))
  (same (. snapshot.maps.maps 2 :nodes) [source-key "string-entity:a"])
  (same (R.decode-json (J.stable-json snapshot)) snapshot)
  (same (. snapshot.board.model.items 1 :position) [11 12 0])
  (same (. snapshot.board.model.items 1 :rotation) [1 0 0 0])
  (same (H.snapshot-tree fixture.stores.base-dir) before)))
(add "owner merges unsaved owning model before preparing bytes" (fn unsaved-model [fixture]
  (local owner (world-owner fixture))
  (fixture.board:add-item {:id "unsaved" :type "string-entity" :subject-key source-key
                           :position [101 102 0] :state {:note "unsaved native item"}})
  (local before (H.snapshot-tree fixture.stores.base-dir))
  (local inventory (H.no-writes #(owner:inventory)))
  (local prepared (H.no-writes #(owner:prepare inventory (operation "morph"))))
  (var found false)
  (each [_ change (ipairs prepared.changes)]
    (when (= change.address "world:loaded")
      (set found true)
      (local value (json.loads change.after-bytes))
      (assert (= (# value.board.items) 4))
      (assert (= (. value.board.items 4 :id) "unsaved"))
      (assert (= (. value.board.items 4 :subject-key) "identity:reserved"))
      (same (. value.board.items 4 :position) [101 102 0])))
  (assert found)
  (same (H.snapshot-tree fixture.stores.base-dir) before)))
(add "HomeWorld supplied install survives ordinary save without recapture" (fn install-home [fixture]
  (local B (require :board/reference-state))
  (local G (require :graph/reference-state))
  (local world fixture.loaded.world)
  (local state (world:snapshot-reference-state))
  (local op (operation "delete"))
  (set state.record.board (B.rewrite state.record.board op fixture.stores.identity-store))
  (each [role board (pairs state.board)]
    (tset state.board role (B.rewrite board op fixture.stores.identity-store)))
  (set state.maps.maps (icollect [_ map (ipairs state.maps.maps)] (G.rewrite-map map op)))
  (local held (. fixture.board.items "a"))
  (H.no-writes #(world:install-reference-state! state))
  (assert (= (. fixture.board.items "a") held) "surviving native item identity must remain")
  (assert (= (. fixture.board.items "source") nil))
  (assert (= (# world.runtime.board-state.items) 2))
  (assert (= (# world.runtime.activity-session-state.board.board-state.items) 2))
  (world:save-state)
  (assert (= (# (. (json.loads (fs.read-file world.state-path)) :board :items)) 2))
  (same (. (fixture.manager:capture-state) :maps 2 :nodes) ["string-entity:a"])))

(fn native-view-icons []
  (local glyph {:advance 1})
  (local font {:metadata {:metrics {:ascender 1 :descender -1} :atlas {:width 1 :height 1}}
               :glyph-map {65533 glyph 4242 glyph}})
  (local names {:open_in_new true :close_fullscreen true :more_vert true :content_copy true
                :tag true :delete true :table true :code true :close true :my_location true :play_arrow true})
  (fn resolve [_self name]
    (assert (. names name)
            (.. "unexpected reference fixture icon: " name))
    {:type :font :codepoint 4242 :font font})
  {:resolve resolve})

(fn with-native-view [fixture f directory]
  (local glm (require :glm))
  (local BuildContext (require :build-context))
  (local Clickables (require :clickables))
  (local FocusManager (. (require :focus) :FocusManager))
  (local focus (FocusManager {:root-name "reference-world-snapshot"}))
  (local scope (focus:create-scope {:name "reference-world-snapshot-scope"}))
  (local camera ((require :camera) {:position (glm.vec3 7 8 100)}))
  (local ctx (BuildContext {:clickables (Clickables) :focus-manager focus :focus-scope scope
                            :layout-root ((. (require :layout) :LayoutRoot) {:log-dirt? false})
                            :hoverables app.hoverables
                           :theme {:graph {:selection-border-color (glm.vec4 1 0.6 0.2 1)
                                           :label-color (glm.vec4 1 1 1 1) :label-target-pixels 13
                                           :label-min-scale 4 :edge-color (glm.vec4 0.6 0.6 0.6 1)}
                                    :input {:focus-outline (glm.vec4 0.2 0.6 1 1)}}}))
  (set ctx.icons (native-view-icons))
  (local view ((require :graph/view) {:graph-map (fixture.manager:get-active-map) :ctx ctx
                                      :camera camera :data-dir (or directory fixture.loaded.world.dir)}))
  (local (ok result) (pcall f view))
  (local (drop-ok drop-error) (pcall (fn cleanup [] (view:drop) (camera:drop) (focus:drop))))
  (if (not ok) (error result) (not drop-ok) (error drop-error) result))

(add "GraphView native snapshot does not persist metadata" (fn view-snapshot [fixture]
  (with-native-view fixture (fn observe [view]
    (local before (H.snapshot-tree fixture.stores.base-dir))
    (local state (H.no-writes #(view:snapshot-reference-state)))
    (local R (require :reference-lifecycle/record-utils))
    (same (R.decode-json (J.stable-json state)) state)
    (assert state.mode_states.spatial)
    (same (H.snapshot-tree fixture.stores.base-dir) before)))))
(add "owner failed write leaves loaded record and model unchanged" (fn failed-publication [fixture]
  (local owner (world-owner fixture))
  (local service (H.ready fixture.stores owner))
  (local world fixture.loaded.world)
  (local before (J.stable-json world.state))
  (local board-before (fixture.board:capture-state))
  (H.with-fs-failure "write-file" (.. world.state-path ".tmp")
    #(H.assert-error "permission denied" #(service:delete! source-key)))
  (assert (= (J.stable-json world.state) before))
  (same (fixture.board:capture-state) board-before)))
(add "owner partial recovery rejects edited world without clobbering" (fn conflict [fixture]
  (local owner (world-owner fixture))
  (local service (H.ready fixture.stores owner))
  (H.with-fs-failure "write-file" (.. fixture.unopened.world.state-path ".tmp")
    #(H.assert-error "permission denied" #(service:delete! source-key)))
  (local path fixture.loaded.world.state-path)
  (local edited (json.loads (fs.read-file path)))
  (set edited.external "conflicting edit")
  (J.write-json! path edited)
  (local bytes (fs.read-file path))
  (H.assert-error "conflict" #(service:delete! source-key))
  (assert (= (fs.read-file path) bytes))
  (assert (fixture.stores.string-store:get-entity "s"))
  (local pending ((require :reference-lifecycle/pending) fixture.stores.base-dir))
  (assert (pending:read))))
(add "owner rejects symlink world directories" (fn symlink-world [fixture]
  (local owner (world-owner fixture))
  (local root (fs.join-path fixture.stores.base-dir "worlds"))
  (when (= (string.sub package.config 1 1) "\\") (lua "return true"))
  (local result ((. (require :process) :run)
                {:args ["ln" "-s" fixture.unopened.world.dir (fs.join-path root "linked-world")]}))
  (assert (= result.exit-code 0) "native symlink fixture creation failed")
  (H.assert-error "symlink" #(H.no-writes #(owner:preflight!)))))

(fn native-view-state [marker]
  {:views {:open-views (. (metadata) :panels)} :marker marker
   :selected_node_keys [source-key] :focused_node_key source-key
   :focused_node_key_present? true
   :mode_states {:spatial {:extra_panels (. (metadata) :extra_panels)
                           :camera {:position [7 8 100]} :note source-key}}})

(fn retain-view-roles! [fixture]
  (local world fixture.loaded.world)
  (local rt world.runtime)
  (set world.state.activity.sessions.graph {:graph-view-state (native-view-state "activity single")
    :graph-view-states {:reserve (native-view-state "activity indexed")}})
  (set rt.graph-view-state (native-view-state "retained single"))
  (set rt.graph-view-states {:reserve (native-view-state "retained indexed")})
  (set rt.activity-session-state.graph {:graph-view-state (native-view-state "runtime single")
    :graph-view-states {:reserve (native-view-state "runtime indexed")}})
  (set rt.pending-canvas-state {:panels (. (metadata) :panels) :note source-key})
  (set rt.pending-hud-state {:panels (. (metadata) :extra_panels) :note source-key}))

(fn assert-rewritten-view [view marker]
  (assert (= view.marker marker))
  (assert (= (. view.views.open-views 1 :node-key) "code-entity:c"))
  (same view.selected_node_keys ["code-entity:c"])
  (assert (= view.focused_node_key "code-entity:c"))
  (assert (= view.mode_states.spatial.note source-key) "opaque mode strings must not be rewritten"))

(add "owner merges retained view session and pending role mirrors" (fn merge-view-roles [fixture]
  (retain-view-roles! fixture)
  (local owner (world-owner fixture))
  (local prepared (H.no-writes #(owner:prepare (owner:inventory) (operation "morph"))))
  (local changes (icollect [_ change (ipairs prepared.changes)]
                   (when (= change.address "world:loaded") change)))
  (assert (= (# changes) 1))
  (local record (json.loads (. changes 1 :after-bytes)))
  (local rt (assert record.runtime "loaded native runtime mirrors must be in the frozen owning record"))
  (assert-rewritten-view rt.graph-view-state "retained single")
  (assert-rewritten-view (. rt.graph-view-states :reserve) "retained indexed")
  (assert-rewritten-view rt.activity-session-state.graph.graph-view-state "runtime single")
  (assert-rewritten-view record.activity.sessions.graph.graph-view-state "activity single")
  (assert (= (. rt.pending-canvas-state.panels 1 :node-key) "code-entity:c"))
  (assert (= (. rt.pending-hud-state.panels 1 :node-key) "code-entity:c"))
  (assert (= rt.pending-canvas-state.note source-key))))

(add "HomeWorld supplied install retains separate view roles without IO" (fn install-view-roles [fixture]
  (retain-view-roles! fixture)
  (local world fixture.loaded.world)
  (local snapshot (world:snapshot-reference-state))
  (local G (require :graph/reference-state))
  (local op (operation "morph"))
  (set snapshot.views.retained-single (G.rewrite-view snapshot.views.retained-single op))
  (set snapshot.views.retained.reserve (G.rewrite-view snapshot.views.retained.reserve op))
  (set snapshot.views.runtime-session.graph-view-state
       (G.rewrite-view snapshot.views.runtime-session.graph-view-state op))
  (set snapshot.views.pending-canvas (G.rewrite-metadata snapshot.views.pending-canvas op))
  (set snapshot.views.pending-hud (G.rewrite-metadata snapshot.views.pending-hud op))
  (H.no-writes #(world:install-reference-state! snapshot))
  (assert-rewritten-view world.runtime.graph-view-state "retained single")
  (assert-rewritten-view world.runtime.graph-view-states.reserve "retained indexed")
  (assert-rewritten-view world.runtime.activity-session-state.graph.graph-view-state "runtime single")
  (assert (= (. world.runtime.pending-canvas-state.panels 1 :node-key) "code-entity:c"))
  (assert (= (. world.runtime.pending-hud-state.panels 1 :node-key) "code-entity:c"))))

(add "GraphView supplied install retains opaque native mode data without IO" (fn install-native-view [fixture]
  (with-native-view fixture (fn observe [view]
    (set view.runtime.mode-states.spatial {:note source-key :camera {:position [7 8 100]}})
    (local state (H.no-writes #(view:snapshot-reference-state)))
    (assert (= state.mode_states.spatial.note source-key) "snapshot must retain unrelated native mode fields")
    (set state.mode_states.spatial.note "installed")
    (H.no-writes #(view:install-reference-state! state))
    (assert (= view.runtime.mode-states.spatial.note "installed"))
    (assert (= (. (H.no-writes #(view:snapshot-reference-state)) :mode_states :spatial :note) "installed"))
    (assert (= (. (view:capture-state) :mode_states :spatial :note) "installed")
            "ordinary capture must retain installed native mode extras")))))

(add "owner rejects sparse native reference arrays before preparation" (fn sparse-roles [fixture]
  (local owner (world-owner fixture))
  (local world fixture.loaded.world)
  (set world.runtime.graph-view-states {:reserve {:views {:open-views {2 (. (metadata) :panels 1)}}}})
  (H.assert-error "array" #(H.no-writes #(owner:inventory)))))

(add "owner repeated after image preparation is a no op" (fn no-op [fixture]
  (retain-view-roles! fixture)
  (local owner (world-owner fixture))
  (local op (operation "morph"))
  (local prepared (owner:prepare (owner:inventory) op))
  (each [_ change (ipairs prepared.changes)] (owner:apply! change))
  (local before (H.snapshot-tree fixture.stores.base-dir))
  (local again (H.no-writes #(owner:prepare (owner:inventory) op)))
  (same again.changes [])
  (same (H.snapshot-tree fixture.stores.base-dir) before)))

(add "owner loaded map snapshot retains unrelated persisted fields" (fn map-extras [fixture]
  (local world fixture.loaded.world)
  (set world.state.graph.note source-key)
  (set (. world.state.graph.maps 2 :provenance) {:node-key source-key :enabled? false})
  (local owner (world-owner fixture))
  (local changes (. (H.no-writes #(owner:prepare (owner:inventory) (operation "morph"))) :changes))
  (var found false)
  (each [_ change (ipairs changes)]
    (when (= change.address "world:loaded")
      (set found true)
      (local state (. (json.loads change.after-bytes) :graph))
      (assert (= state.note source-key) "native capture must retain unrelated graph fields")
      (same (. state.maps 2 :provenance) {:node-key source-key :enabled? false})
      (assert-morphed-map state {:code-key "code-entity:c"})))
  (assert found)))

(fn assert-owning-board-opaque [store value raw source-target]
  (same value.opaqueRoot raw.opaqueRoot)
  (same (. value.items 1 :sourceOpaque) (. raw.items 1 :sourceOpaque))
  (same (. value.items 2 :survivorOpaque) (. raw.items 2 :survivorOpaque))
  (same (. value.connectors 1 :connectorOpaque) (. raw.connectors 1 :connectorOpaque))
  (local expected ((. (require :reference-lifecycle/record-utils) :clone) raw))
  (each [index item (ipairs expected.items)]
    (local subject (. value.items index :subject-key))
    (H.assert-reference store subject (if (= item.id "source") source-target item.subject-key))
    (set item.subject-key subject)
    (when (= item.id "source") (set item.type (string.match source-target "^([^:]+):"))))
  (same value expected))

(fn retain-fix-evidence [kind value]
  (when (os.getenv "SPACE_TASK5_BASELINE_EVIDENCE")
    (print (.. "[REFERENCE-DATAFIX-" kind "] " (J.stable-json value)))))

(add "loaded board owning opaque fields survive native projection" (fn owning-board [fixture]
  (local world fixture.loaded.world)
  (local raw (board-state))
  (set raw.opaqueRoot {:subject source-key :flag false :camera {:position [8 9 100]}})
  (set (. raw.items 1 :sourceOpaque) {:text source-key :flag false})
  (set (. raw.items 2 :survivorOpaque) [source-key false])
  (set (. raw.connectors 1 :connectorOpaque) {:text source-key :flag false})
  (set world.state.board raw)
  (world:save-state)
  (retain-fix-evidence "OPAQUE-RAW" {:bytes (fs.read-file world.state-path) :board raw})
  ;; Native Board is already loaded and deliberately does not expose extensions.
  (assert (= (. (fixture.board:capture-state) :items 1 :sourceOpaque) nil))
  (local service (H.ready fixture.stores (world-owner fixture)))
  (assert-owning-board-opaque fixture.stores.identity-store (. (json.loads (fs.read-file world.state-path)) :board) raw source-key)
  (local result (service:replace! source-key {:name "" :language "fnl" :source source-text :kernel 0}))
  (world:save-state)
  (local cold (json.loads (fs.read-file world.state-path)))
  (assert-owning-board-opaque fixture.stores.identity-store cold.board raw result.code-key)
  (retain-fix-evidence "OPAQUE-COLD" cold.board)
  (H.assert-reference fixture.stores.identity-store (. cold.board.items 1 :subject-key) result.code-key)
  (assert (= (. cold.board.items 1 :type) "code-entity"))
  (fixture.board:remove-item "b")
  (local owner (world-owner fixture))
  (local inventory (owner:inventory))
  (same (icollect [_ item (ipairs (. inventory.records :world:loaded :value :board :items))] item.id) ["source" "a"])
  (same (. inventory.records :world:loaded :value :board :connectors) [(. cold.board.connectors 2)])))

(fn assert-explicit-edge [state key]
  (same (. state.maps 2 :edges) [{:source key :target "string-entity:a" :weight 7 :label "explicit"
                                :opaque {:text source-key :enabled? false}}]))

(add "active explicit edge attributes survive ordinary persistence" (fn active-attributes [fixture]
  (local world fixture.loaded.world)
  (local state (graph-state))
  (set (. state.maps 2 :edges 1 :opaque) {:text source-key :enabled? false})
  (set world.state.graph state)
  (fixture.manager:switch-map! "reserve")
  (local active (fixture.manager:get-active-map))
  (active:restore-state (. state.maps 2))
  (local service (H.ready fixture.stores (world-owner fixture)))
  (assert-explicit-edge (. (json.loads (fs.read-file world.state-path)) :graph) source-key)
  (local result (service:replace! source-key {:name "" :language "fnl" :source source-text :kernel 0}))
  (assert-explicit-edge (fixture.manager:snapshot-reference-state) result.code-key)
  (set world.state.graph (fixture.manager:capture-state))
  (world:save-state)
  (local persisted (. (json.loads (fs.read-file world.state-path)) :graph))
  (assert-explicit-edge persisted result.code-key)
  (local reopened (GraphMapManager {:graph fixture.graph :data-dir world.dir :state persisted}))
  (local (ok err) (pcall #(assert-explicit-edge (reopened:capture-state) result.code-key)))
  (reopened:drop)
  (when (not ok) (error err))))

(fn assert-preflight-pure [fixture f]
  (local before (H.snapshot-tree fixture.stores.base-dir))
  (H.assert-error "reference composition" #(H.no-writes f))
  (same (H.snapshot-tree fixture.stores.base-dir) before)
  (local pending ((require :reference-lifecycle/pending) fixture.stores.base-dir))
  (assert (= (pending:read) nil)))

(add "rejects actual view metadata directory mismatch before effects" (fn wrong-view-dir [fixture]
  (with-native-view fixture (fn inspect [view]
    (local manager (world-manager fixture))
    (H.with-fields fixture.loaded.world.runtime {:graph-view view :graph-map (fixture.manager:get-active-map)}
      #(assert-preflight-pure fixture #(world-owner fixture manager)))) fixture.unopened.world.dir)))

(add "rejects actual map manager directory mismatch before effects" (fn wrong-manager-dir [fixture]
  (local wrong (GraphMapManager {:graph fixture.graph :data-dir fixture.unopened.world.dir :state (graph-state)}))
  (local manager (world-manager fixture))
  (local (ok err) (pcall #(H.with-fields fixture.loaded.world.runtime {:graph-map-manager wrong}
    #(assert-preflight-pure fixture #(world-owner fixture manager)))))
  (wrong:drop)
  (when (not ok) (error err))))

(fn active-cache-case [fixture view]
  (local world fixture.loaded.world)
  (local map (fixture.manager:get-active-map))
  (local survivor (assert (map:lookup "string-entity:a")))
  (local survivor-edge (assert (. map.edge-map "string-entity:a->string-entity:b")))
  (local point (assert (. view.points survivor)))
  (set point.position ((. (require :glm) :vec3) 50 0 0))
  (set (. view.points (map:lookup source-key) :position) ((. (require :glm) :vec3) 11 12 0))
  (local persistence view.runtime.persistence)
  (view.views:open (map:lookup source-key))
  (view.views:open survivor)
  (local survivor-view (. view.views.node-views survivor))
  (local before (metadata))
  (tset before.presentations source-key nil)
  (tset before.presentations "string-entity:a" "expanded")
  (tset before.sizes "string-entity:a" [43 21])
  (set before.panels (. (view.views:capture-state) :open-views))
  (each [_ field (ipairs [:panels :extra_panels])]
    (set (. before field 1 :graph-map-id) "main"))
  (persistence:install-state! before)
  (persistence:persist {} true)
  (local owner (world-owner fixture))
  (local service (H.ready fixture.stores owner))
  (local metadata-before (H.no-writes #(view:snapshot-reference-metadata)))
  (local view-before (H.no-writes #(view:snapshot-reference-state)))
  (local result (service:replace! source-key {:name "" :language "fnl" :source source-text :kernel 0}))
  (local frozen (json.loads (fs.read-file persistence.metadata-path)))
  (local op {:kind "morph" :source-key source-key :target-key result.code-key})
  (same frozen ((. (require :graph/reference-state) :rewrite-metadata) metadata-before op))
  (same (persistence:snapshot-state) frozen)
  (assert (= (map:lookup "string-entity:a") survivor) "survivor adapter must not be removed and recreated")
  (assert (= (. map.edge-map "string-entity:a->string-entity:b") survivor-edge) "unrelated explicit edge must remain held through actual view publication")
  (assert (= (. view.points survivor) point) "survivor native point must remain mounted")
  (same (. frozen.positions :string-entity:a) [50 0 0])
  (same (. frozen.sizes :string-entity:a) [43 21])
  (assert (= (. frozen.presentations "string-entity:a") "expanded"))
  (same frozen.unknown before.unknown)
  (local current (view:snapshot-reference-state))
  (local expected-view ((. (require :graph/reference-state) :rewrite-view) view-before op))
  ;; Native node-view capture sorts by the current representation key; morph may
  ;; change that sort order. Owning metadata panel order is checked separately.
  (table.sort expected-view.views.open-views (fn by-key [a b] (< a.node-key b.node-key)))
  (same current expected-view)
  (assert (= current.focused_node_key result.code-key))
  (same current.selected_node_keys [result.code-key])
  (local sorted-panels ((. (require :reference-lifecycle/record-utils) :clone) frozen.panels))
  (table.sort sorted-panels (fn by-key [a b] (< a.node-key b.node-key)))
  (same current.views.open-views sorted-panels)
  (assert (= (. view.views.node-views survivor) survivor-view))
  (H.no-writes #(owner:reconcile! {:changes []}))
  ;; Replay actual frozen after-images, including the already-after zero-write path.
  (local R (require :reference-lifecycle/record-utils))
  (local snapshot (R.snapshot persistence.metadata-path "json" json.loads))
  (local change (R.make-change "worlds" "world-metadata:loaded:main" snapshot snapshot.bytes "json" "incoming"))
  (local world-snapshot (R.snapshot world.state-path "json" json.loads))
  (local world-change (R.make-change "worlds" "world:loaded" world-snapshot world-snapshot.bytes "json" "incoming"))
  (H.no-writes #(owner:apply! change))
  (H.no-writes #(owner:apply! world-change))
  (H.no-writes #(owner:reconcile! {:changes [change world-change]}))
  (same (persistence:snapshot-state) frozen)
  (assert (= (. map.edge-map "string-entity:a->string-entity:b") survivor-edge))
  (assert (= (. view.views.node-views survivor) survivor-view))
  (view:capture-state)
  (same (json.loads (fs.read-file persistence.metadata-path)) frozen)
  (same (persistence:snapshot-state) frozen)
  (assert (not (. frozen.positions source-key)))
  (assert (map:lookup result.code-key))
  frozen)

(add "active publication preserves survivor cache across replay and save" (fn active-cache [fixture]
  (local map (fixture.manager:get-active-map))
  (map:restore-state {:nodes [source-key "string-entity:a" "string-entity:b"]
                      :edges [{:source "string-entity:a" :target "string-entity:b" :label "survivor"}]
                      :focused_node_key source-key
                      :selected_node_keys [source-key]})
  (local frozen (with-native-view fixture (fn inspect [view]
    (H.with-fields fixture.loaded.world.runtime {:graph-view view :graph-map map}
      #(active-cache-case fixture view)))))
  (same (json.loads (fs.read-file (fs.join-path fixture.loaded.world.dir "graph" "maps" "main" "metadata.json"))) frozen)))

(add "native map delta is nonpersisting and preserves parallel provenance" (fn native-delta [fixture]
  (local s fixture.stores)
  (s.code-store:create-entity {:id "c" :name "" :source source-text :language "fnl" :kernel 0})
  (s.link-store:create-entity {:id "parallel" :source-key "string-entity:a" :target-key "string-entity:b"})
  (local map (fixture.manager:get-active-map))
  (local opaque-options {:from-link-entity "not-runtime-provenance"})
  (map:restore-state {:nodes [source-key "string-entity:a" "string-entity:b"]
                      :edges [{:source source-key :target "string-entity:a" :label "source" :opaque false}
                              {:source "string-entity:a" :target "string-entity:b" :weight 7 :label "keep" :_opts opaque-options}]})
  (local a (map:lookup "string-entity:a"))
  (local edge (. map.edge-map "string-entity:a->string-entity:b"))
  (local link-k (. map.edge-map "string-entity:a->string-entity:b#link:k"))
  (local parallel (. map.edge-map "string-entity:a->string-entity:b#link:parallel"))
  (assert (and edge link-k parallel))
  (assert (= edge._opts nil) "opaque persisted options must never become runtime derived tags")
  (local after ((. (require :graph/reference-state) :rewrite-map) (map:capture-state) (operation "morph")))
  (local tree (H.snapshot-tree s.base-dir))
  (H.no-writes #(map:install-reference-state! after))
  (assert (= (map:lookup "string-entity:a") a))
  (assert (= (. map.edge-map "string-entity:a->string-entity:b") edge))
  (assert (= (. map.edge-map "string-entity:a->string-entity:b#link:k") link-k))
  (assert (= (. map.edge-map "string-entity:a->string-entity:b#link:parallel") parallel))
  (local captured (map:capture-state))
  (same (. captured.edges 2) {:source "string-entity:a" :target "string-entity:b" :weight 7 :label "keep" :_opts opaque-options})
  (assert (= (# captured.edges) 2) "derived links must stay excluded from the explicit serialized rows")
  (local removed (map.node-removed:connect (fn unexpected [_] (error "already-after native delta removed a node"))))
  (local (ok err) (pcall #(H.no-writes #(map:install-reference-state! after))))
  (map.node-removed:disconnect removed true)
  (when (not ok) (error err))
  (same (H.snapshot-tree s.base-dir) tree)
  (same (map:capture-state) captured)))

(fn assert-native-edge-attributes [map source target label color]
  (local edge (assert (. map.edge-map (.. source "->" target))))
  (assert (= edge.label label) "cold native edge must use persisted label")
  (if (= color nil) (assert (= edge.color nil) "cold native color must remain absent")
      (do
        (local expected ((. (require :glm) :vec4) (table.unpack color)))
        (assert (and (= edge.color.x expected.x) (= edge.color.y expected.y)
                     (= edge.color.z expected.z) (= edge.color.w expected.w))
                "cold native edge must use persisted color"))))

(fn save-and-reopen-native-edges [fixture expected]
  (local world fixture.loaded.world)
  (set world.state.graph (fixture.manager:capture-state))
  (world:save-state)
  (local cold ((. (require :reference-lifecycle/record-utils) :decode-json) (fs.read-file world.state-path)))
  (same (. cold.graph.maps 1 :edges) expected)
  (local reopened (GraphMapManager {:graph fixture.graph :data-dir world.dir :state cold.graph}))
  (local (ok err) (pcall (fn inspect []
    (same (. (reopened:capture-state) :maps 1 :edges) expected)
    (each [_ row (ipairs expected)]
      (assert-native-edge-attributes (reopened:get-active-map) row.source row.target (if (= row.label nil) "" row.label) row.color)))))
  (reopened:drop)
  (when (not ok) (error err)))

(add "explicit edge replacement keeps live attributes" (fn live-edge-replacement [fixture]
  (local map (fixture.manager:get-active-map))
  (local Edge (. (require :graph/edge) :GraphEdge))
  (local raw {:source source-key :target "string-entity:a" :label "before" :color [1 0 0 1]
              :weight 7 :opaque {:text source-key :enabled? false} :_opts {:from-link-entity "opaque"}})
  (map:restore-state {:nodes [source-key "string-entity:a"] :edges [raw]})
  (set fixture.loaded.world.state.graph (fixture.manager:capture-state))
  (map:add-edge (Edge {:source (map:lookup source-key) :target (map:lookup "string-entity:a")
                       :label "after" :color [0 1 0 1]}))
  (local row (. (map:capture-state) :edges 1))
  (assert (= row.label "after") "public replacement must capture live label after, not cached before")
  (local expected ((. (require :reference-lifecycle/record-utils) :clone) raw))
  (set expected.label "after") (set expected.color [0 1 0 1])
  (same row expected)
  (same (. (fixture.loaded.world:snapshot-reference-state) :maps :maps 1 :edges) [expected])
  (save-and-reopen-native-edges fixture [expected])
  ;; Public replacement resets the known native values; owning merge must not
  ;; resurrect old color/label while preserving opaque extensions and false data.
  (map:add-edge (Edge {:source (map:lookup source-key) :target (map:lookup "string-entity:a")}))
  (set expected.label "") (set expected.color nil)
  (same (. (map:capture-state) :edges) [expected])
  (same (. (fixture.loaded.world:snapshot-reference-state) :maps :maps 1 :edges) [expected])
  (save-and-reopen-native-edges fixture [expected])))

(add "ordinary added edge persists native attributes" (fn new-edge-attributes [fixture]
  (fixture.stores.link-store:create-entity {:id "parallel" :source-key "string-entity:a" :target-key "string-entity:b"})
  (local map (fixture.manager:get-active-map))
  (local Edge (. (require :graph/edge) :GraphEdge))
  (map:restore-state {:nodes [source-key "string-entity:a" "string-entity:b"] :edges []})
  (map:add-edge (Edge {:source (map:lookup "string-entity:a") :target (map:lookup "string-entity:b")
                       :label "added" :color [0 0.25 0.75 1]}))
  (map:add-edge (Edge {:source (map:lookup source-key) :target (map:lookup "string-entity:a")}))
  (local state (map:capture-state))
  (assert (= (. state.edges 1 :label) "added") "ordinary new edge must persist its native label")
  (local expected [{:source "string-entity:a" :target "string-entity:b" :label "added" :color [0 0.25 0.75 1]}
                  {:source source-key :target "string-entity:a"}])
  (same state.edges expected)
  (assert (. map.edge-map "string-entity:a->string-entity:b#link:k"))
  (assert (. map.edge-map "string-entity:a->string-entity:b#link:parallel"))
  (save-and-reopen-native-edges fixture expected)))

(add "native edge color capture preserves unchanged precision" (fn edge-color-precision [fixture]
  (local map (fixture.manager:get-active-map))
  (local raw {:source source-key :target "string-entity:a" :label "precision" :color [0.1 0.2 0.3 0.4] :weight 7})
  (map:restore-state {:nodes [source-key "string-entity:a"] :edges [raw]})
  (assert-native-edge-attributes map source-key "string-entity:a" "precision" raw.color)
  (same (. (map:capture-state) :edges) [raw])
  (H.ready fixture.stores (world-owner fixture))
  (same (. (fixture.loaded.world:snapshot-reference-state) :maps :maps 1 :edges) [raw])
  (save-and-reopen-native-edges fixture [raw])
  (local edge (. map.edge-map (.. source-key "->string-entity:a")))
  (set edge.color ((. (require :glm) :vec4) 0.6 0.7 0.8 0.9))
  (local expected ((. (require :reference-lifecycle/record-utils) :clone) raw))
  (set expected.color [edge.color.x edge.color.y edge.color.z edge.color.w])
  (same (. (map:capture-state) :edges) [expected])
  (save-and-reopen-native-edges fixture [expected])
  ;; False is not an absent/default known field; never silently normalize it.
  (set raw.label false)
  (map:restore-state {:nodes [source-key "string-entity:a"] :edges [raw]})
  (H.assert-error "label" #(H.no-writes #(map:capture-state)))
  (set raw.label "precision") (set raw.color false)
  (map:restore-state {:nodes [source-key "string-entity:a"] :edges [raw]})
  (H.assert-error "color" #(H.no-writes #(map:capture-state)))))

tests
