(local fs (require :fs))
(local json (require :json))
(local J (require :json-utils))
(local R (require :reference-lifecycle/record-utils))
(local B (require :board/reference-state))
(local G (require :graph/reference-state))

(fn capabilities! [self]
  (assert (= self.stores.base-dir self.base-dir) "worlds owner canonical root mismatch")
  (assert (= self.manager.root-dir (fs.join-path self.base-dir "worlds")) "worlds owner manager root mismatch")
  (assert (= (type self.manager.list-reference-worlds) :function) "worlds owner requires list-reference-worlds")
  (assert (= self.stores.identity-store.base-dir self.base-dir) "worlds identity root mismatch")
  true)

(fn board-slots! [state visit]
  (when state.board (visit state.board [:board]))
  (local sessions (and state.activity state.activity.sessions))
  (when (and sessions sessions.board sessions.board.board-state)
    (visit sessions.board.board-state [:activity :sessions :board :board-state]))
  (local runtime state.runtime)
  (when runtime
    (when runtime.board-state (visit runtime.board-state [:runtime :board-state]))
    (local board (and runtime.activity-session-state runtime.activity-session-state.board))
    (when (and board board.board-state)
      (visit board.board-state [:runtime :activity-session-state :board :board-state]))))

(fn replace-at! [state field value]
  (var parent state)
  (for [index 1 (- (# field) 1)] (set parent (. parent (. field index))))
  (tset parent (. field (# field)) value))

(fn rewrite-graph [state operation]
  (var out (G.rewrite-view state operation))
  (if out.maps
      (set out.maps (icollect [_ entry (ipairs out.maps)] (G.rewrite-map entry operation)))
      out.graph (set out.graph (G.rewrite-map out.graph operation))
      (set out (G.rewrite-map out operation)))
  out)

(fn rewrite-session! [session operation]
  (when session.graph-view-state
    (set session.graph-view-state (G.rewrite-view session.graph-view-state operation)))
  (when session.graph-view-states
    (each [id state (pairs session.graph-view-states)]
      (tset session.graph-view-states id (G.rewrite-view state operation)))))

(fn rewrite-shell! [shell operation]
  (when (and shell shell.panels)
    (R.require-array shell.panels)
    (local panels [])
    (each [_ panel (ipairs shell.panels)]
      (if (= panel.kind "graph-node-view")
          (each [_ candidate (ipairs (. (G.rewrite-metadata {:panels [panel]} operation) :panels))]
            (table.insert panels candidate))
          (table.insert panels panel)))
    (set shell.panels panels)))

(fn rewrite-world [state operation identity-store]
  (local out (R.clone state))
  (board-slots! out (fn rewrite-board [board field]
    (replace-at! out field (B.rewrite board operation identity-store))))
  (when out.graph (set out.graph (rewrite-graph out.graph operation)))
  (local graph-session (and out.activity out.activity.sessions out.activity.sessions.graph))
  (when graph-session (rewrite-session! graph-session operation))
  (when out.runtime
    (rewrite-session! out.runtime operation)
    (local session (and out.runtime.activity-session-state out.runtime.activity-session-state.graph))
    (when session (rewrite-session! session operation))
    (rewrite-shell! out.runtime.pending-canvas-state operation)
    (rewrite-shell! out.runtime.pending-hud-state operation))
  ;; Only graph-owned shell panels participate; other domain panel data is opaque.
  (each [_ field (ipairs [:canvas :hud])]
    (rewrite-shell! (. out field) operation))
  out)

(fn board-sites! [sites address value]
  (board-slots! value (fn collect-board [board field]
    (R.require-array board.items)
    (each [index item (ipairs board.items)]
      (when item.subject-key
        (assert (= (type item.subject-key) :string) "board subject-key must be string")
        (local location (R.clone field))
        (table.insert location "items") (table.insert location index) (table.insert location "subject-key")
        (table.insert sites {:address address :field location :target-key item.subject-key :kind "board-subject"}))))))

(fn metadata-ids [self entry value]
  (local ids {})
  (when (and value.graph value.graph.maps)
    (R.require-array value.graph.maps)
    (each [_ map (ipairs value.graph.maps)]
      (R.require-id map.id)
      (assert (not (. ids map.id)) "duplicate world map id")
      (tset ids map.id true)))
  (local directory (fs.join-path entry.dir "graph" "maps"))
  (R.record-path self.base-dir directory "metadata" ".json")
  (when (fs.exists directory)
    (local status (fs.stat directory))
    (assert (and (not status.error) status.is-dir) (.. "invalid maps directory: " directory))
    (each [_ child (ipairs (fs.list-dir directory true true))]
      (assert (not child.error) (.. child.path ": " (tostring child.error)))
      (assert (and child.is-dir (not child.is-symlink)) (.. "unsupported map directory: " child.path))
      (R.require-id child.name)
      (tset ids child.name true)))
  (local result (icollect [id _ (pairs ids)] id))
  (table.sort result)
  result)

(fn validate-board-view! [self entry runtime]
  (local view runtime.board-view)
  (local context (.. "reference composition " entry.dir " board-view "))
  (assert runtime.board (.. context "requires runtime.board"))
  (assert (= (type view.reference-providers) :function) (.. context "requires reference-providers"))
  ;; This bounded inspection reads closed-over handles, never lazy defaults.
  (local providers (view:reference-providers))
  (assert (= providers.board runtime.board) (.. context "board instance mismatch"))
  (each [_ field (ipairs [:identity-store :link-store :string-store :code-store])]
    (when (or (= field :identity-store) (= field :link-store) (. providers field))
      (assert (= (. providers field) (. self.stores field)) (.. context field " instance mismatch"))))
  true)

(fn validate-graph! [stores graph]
  (assert (= (type graph) :table) "reference composition requires native graph")
  (each [_ field (ipairs [:identity-store :string-store :link-store :code-store :list-store :dict-store :notebook-store :workflow-store])]
    (local provider (. graph field))
    (when (or provider (= field :identity-store) (= field :string-store) (= field :link-store))
      (assert (= provider (. stores field)) "reference composition canonical store mismatch")
      (assert (= (fs.absolute provider.base-dir) stores.base-dir) "reference composition graph store root mismatch")
      (when provider.identity-store
        (assert (= provider.identity-store stores.identity-store) "reference composition graph identity dependency mismatch"))))
  true)

(fn validate-loaded! [self entry]
  (local world entry.world)
  (assert (and (= world.id entry.id) (= (fs.absolute world.dir) entry.dir))
          "reference composition world root/id mismatch")
  (local runtime world.runtime)
  (when runtime
    (when runtime.board-view (validate-board-view! self entry runtime))
    (when runtime.graph (validate-graph! self.stores runtime.graph))
    (local manager runtime.graph-map-manager)
    (when manager
      (assert (and (= (type manager.data-dir) :string) (= (fs.absolute manager.data-dir) entry.dir))
              "reference composition map manager directory mismatch")
      (validate-graph! self.stores manager.graph)
      (when runtime.graph
        (assert (= runtime.graph manager.graph) "reference composition runtime/manager graph instance mismatch")))
    (when runtime.graph-view
      (local map (assert runtime.graph-map "reference composition requires current native map"))
      (local view runtime.graph-view)
      (assert (and manager (= (manager:get-active-map) map) (= view.graph-map map)
                   view.runtime (= view.runtime.graph-map map)) "reference composition view map instance mismatch")
      (R.require-id map.id)
      (local persistence (assert view.runtime.persistence "reference composition requires native persistence"))
      (local path (assert persistence.metadata-path "reference composition requires native metadata path"))
      (assert (= (fs.absolute path) (fs.join-path entry.dir "graph" "maps" map.id "metadata.json"))
              "reference composition view metadata directory mismatch")))
  true)

(fn inventory [self]
  (capabilities! self)
  (local records {}) (local sites [])
  (each [_ entry (ipairs (self.manager:list-reference-worlds))]
    (when entry.world (validate-loaded! self entry))
    (local path (R.record-path self.base-dir entry.dir "world" ".json"))
    (local snapshot (R.snapshot path "json" json.loads))
    (local loaded (and entry.world (entry.world:snapshot-reference-state)))
    (when (or snapshot.value loaded)
      (local value (if snapshot.value (R.clone snapshot.value) {}))
      (when loaded
        (each [key field (pairs loaded.record)] (tset value key (R.clone field)))
        (when loaded.board.model (set value.board (R.clone loaded.board.model)))
        (when loaded.maps (set value.graph (R.clone loaded.maps)))
        (when loaded.views.current
          (local sessions (assert (and value.activity value.activity.sessions) "loaded world requires activity sessions"))
          (when (not sessions.graph) (set sessions.graph {}))
          (when (not sessions.graph.graph-view-states) (set sessions.graph.graph-view-states {}))
          (tset sessions.graph.graph-view-states loaded.views.map-id (R.clone loaded.views.current))))
       (local address (.. "world:" entry.id))
       ;; Validate documented native arrays even when the operation will be a no-op.
       ;; The pure rewrite is discarded here; no normalization/publication occurs.
       (rewrite-world value {:kind "migrate" :retiring [] :reference-plan {:rewrites [] :identities []}}
                      self.stores.identity-store)
      (tset records address {:address address :value value :snapshot snapshot})
      (board-sites! sites address value)
      (each [_ map-id (ipairs (metadata-ids self entry value))]
        (local directory (fs.join-path entry.dir "graph" "maps" map-id))
        (local metadata-path (R.record-path self.base-dir directory "metadata" ".json"))
        (local metadata (R.snapshot metadata-path "json" json.loads))
         (local cache (and loaded (. loaded.metadata map-id)))
         (when (or cache metadata.value)
           (G.rewrite-metadata (or cache metadata.value) {:kind "migrate"}))
        (local metadata-address (.. "world-metadata:" entry.id ":" map-id))
        (tset records metadata-address {:address metadata-address :value (if cache (R.clone cache) metadata.value)
                                        :snapshot metadata}))))
  {:records records :sites sites})

(fn preflight! [self] (inventory self) true)
(fn expand [_self _inventory _operation] [])
(fn prepare [self inventory operation]
  (assert (or (= operation.kind "delete") (= operation.kind "morph") (= operation.kind "migrate"))
          "unsupported worlds operation")
  (local addresses (icollect [address _ (pairs inventory.records)] address))
  (table.sort addresses)
  (local changes [])
  (each [_ address (ipairs addresses)]
    (local record (. inventory.records address))
    (when record.value
      (local candidate (if (= (string.sub address 1 6) "world:")
                          (rewrite-world record.value operation self.stores.identity-store)
                          (G.rewrite-metadata record.value operation)))
      (local bytes (J.stable-json candidate))
      (when (not (= (R.check-bytes bytes "json") record.snapshot.check))
        (table.insert changes (R.make-change self.id address record.snapshot bytes "json" "incoming")))))
  {:changes changes :runtime-state []})

(fn owned-path [self change]
  (assert (= change.owner self.id) "wrong worlds change owner")
  (assert (= change.format "json") "worlds change format must be json")
  (local (metadata-world-id map-id) (string.match change.address "^world%-metadata:([^:]+):([^:]+)$"))
  (local world-id (or metadata-world-id (string.match change.address "^world:([^:]+)$")))
  (R.require-id world-id)
  (when map-id (R.require-id map-id))
  (local entries (self.manager:list-reference-worlds))
  (local known (accumulate [found false _ entry (ipairs entries)] (or found (= entry.id world-id))))
  (assert known "unknown owned world address")
  (local directory (fs.join-path self.manager.root-dir world-id))
  (local path (if map-id
                 (R.record-path self.base-dir (fs.join-path directory "graph" "maps" map-id) "metadata" ".json")
                 (R.record-path self.base-dir directory "world" ".json")))
  (assert (= path change.path) "worlds change path mismatch")
  path)

(fn verified-candidate [change]
  (assert (not (= change.after-bytes false)) "worlds owner cannot retire owned records")
  (assert (= (R.check-bytes change.after-bytes "json") change.after-check) "worlds after-check mismatch")
  (local candidate (json.loads change.after-bytes))
  (assert (= (type candidate) :table) "worlds candidate must be an object")
  (assert (= (R.check-bytes (J.stable-json candidate) "json") change.after-check) "worlds serialized after-check mismatch")
  candidate)

(fn publish-owned-data! [self change candidate]
  (local (metadata-world map-id) (string.match change.address "^world%-metadata:([^:]+):([^:]+)$"))
  (local world-id (or metadata-world (string.match change.address "^world:([^:]+)$")))
  (assert world-id "invalid worlds publication address")
  (each [_ entry (ipairs (self.manager:list-reference-worlds))]
    (when (and (= entry.id world-id) entry.world)
      (validate-loaded! self entry)
      (if map-id (entry.world:install-reference-metadata! map-id candidate)
          (entry.world:install-reference-record! candidate)))))

(fn apply! [self change]
  (local path (owned-path self change))
  (local candidate (verified-candidate change))
  (local snapshot (R.snapshot path "json" json.loads))
  (assert (or (= snapshot.check change.before-check) (= snapshot.check change.after-check)) "worlds pending conflict")
  (when (not (= snapshot.check change.after-check))
    (fs.create-dirs (fs.parent path))
    (J.write-json! path candidate))
  (publish-owned-data! self change candidate)
  nil)
(fn reconcile! [self intent]
  (each [_ change (ipairs intent.changes)]
    (local path (owned-path self change))
    (local candidate (verified-candidate change))
    (assert (= (. (R.snapshot path "json" json.loads) :check) change.after-check) "worlds reconciliation conflict")
    (publish-owned-data! self change candidate))
  nil)

(fn WorldOwner [options]
  (local stores (assert options.stores "worlds owner requires canonical stores"))
  (local root (fs.absolute stores.base-dir))
  (assert (= root stores.base-dir) "worlds owner requires canonical root")
  (local self {:id "worlds" :base-dir root :stores stores
                :manager (assert options.world-manager "worlds owner requires world-manager")
               :preflight! preflight! :inventory inventory :expand expand :prepare prepare
               :apply! apply! :reconcile! reconcile!})
  (preflight! self)
  self)
;; Shared readonly composition inspection; does not construct another owner or
;; inventory/capture any runtime. The module remains a single callable factory.
(setmetatable {:validate-loaded! (fn [stores entry] (validate-loaded! {:stores stores} entry))}
              {:__call (fn [_ options] (WorldOwner options))})
