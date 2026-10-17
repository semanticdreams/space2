(local fs (require :fs))
(local J (require :json-utils))
(local R (require :reference-lifecycle/record-utils))
(local G (require :graph/reference-state))
(local B (require :board/reference-state))
(local WorldOwner (require :reference-lifecycle/world-owner))

(fn preflight! [self]
  (assert (= self.stores.base-dir self.base-dir) "runtime canonical root mismatch")
  (assert (= self.manager.root-dir (fs.join-path self.base-dir "worlds")) "runtime manager root mismatch")
  (each [_ entry (ipairs (self.manager:list-reference-worlds))]
    (when entry.world (WorldOwner.validate-loaded! self.stores entry)))
  true)

(fn inventory [self]
  (preflight! self)
  (local contexts [])
  (each [_ entry (ipairs (self.manager:list-reference-worlds))]
    (when (and entry.world entry.world.runtime)
      (table.insert contexts entry)))
  {:records {} :sites [] :loaded-contexts contexts})

(fn rewrite-views [views operation]
  (assert (= (type views) :table) "runtime view roles require table")
  (local out (R.clone views))
  (each [_ role (ipairs [:activity :runtime-session])]
    (local session (. out role))
    (when session
      (when session.graph-view-state (set session.graph-view-state (G.rewrite-view session.graph-view-state operation)))
      (each [id state (pairs (or session.graph-view-states {}))]
        (tset session.graph-view-states id (G.rewrite-view state operation)))))
  (each [id state (pairs (or out.retained {}))] (tset out.retained id (G.rewrite-view state operation)))
  (each [_ role (ipairs [:retained-single :current])]
    (when (. out role) (tset out role (G.rewrite-view (. out role) operation))))
  (each [_ role (ipairs [:pending-canvas :pending-hud])]
    (when (. out role) (tset out role (G.rewrite-metadata (. out role) operation))))
  out)

(fn rewrite-roles [roles operation identity-store]
  (assert (= (type roles) :table) "runtime reference roles require table")
  (local out (R.clone roles))
  (each [role state (pairs (or out.board {}))] (tset out.board role (B.rewrite state operation identity-store)))
  (when out.maps
    (when out.maps.shared (set out.maps.shared (G.rewrite-map out.maps.shared operation)))
    (set out.maps.maps (icollect [_ state (ipairs out.maps.maps)] (G.rewrite-map state operation))))
  (when out.views (set out.views (rewrite-views out.views operation)))
  (each [id state (pairs (or out.metadata {}))] (tset out.metadata id (G.rewrite-metadata state operation)))
  out)

(fn append-capture! [self captures world-id map-id before operation]
  (local after (rewrite-roles before operation self.stores.identity-store))
  (when (not (= (J.stable-json before) (J.stable-json after)))
    (local capture {:owner self.id :world-id world-id :map-id map-id :before before :after after})
    (R.decode-json (J.stable-json capture))
    (table.insert captures capture)))

(fn select-session [session map-id current?]
  (when session
    (local out {})
    (when (and session.graph-view-states (. session.graph-view-states map-id))
      (set out.graph-view-states {map-id (R.clone (. session.graph-view-states map-id))}))
    (when (and current? session.graph-view-state)
      (set out.graph-view-state (R.clone session.graph-view-state)))
    out))

(fn select-panels [shell map-id active-id]
  (assert map-id "runtime panel selection requires native map ID")
  (when shell
    (local panels (icollect [_ panel (ipairs (or shell.panels []))]
      (when (and (= panel.kind "graph-node-view") (= (or panel.graph-map-id active-id) map-id)) (R.clone panel))))
    {:panels panels}))

(fn map-roles [snapshot record active-id]
  (assert record.id "runtime map capture requires native map ID")
  (local id record.id)
  (local current? (= id active-id))
  (local all snapshot.views)
  (local views {:map-id id
               :activity (select-session all.activity id current?)
               :runtime-session (select-session all.runtime-session id current?)
               :pending-canvas (select-panels all.pending-canvas id active-id)
               :pending-hud (select-panels all.pending-hud id active-id)})
  (when (and all.retained (. all.retained id)) (set views.retained {id (R.clone (. all.retained id))}))
  (when current?
    (set views.retained-single (R.clone all.retained-single))
    (when (= all.map-id id) (set views.current (R.clone all.current))))
  {:maps {:maps [(R.clone record)]} :views views
   :metadata (when (. snapshot.metadata id) {id (R.clone (. snapshot.metadata id))})})

(fn prepare [self inventory operation]
  (local captures [])
  (each [_ entry (ipairs inventory.loaded-contexts)]
    (local snapshot (entry.world:snapshot-reference-state))
    (local graph entry.world.runtime.graph)
    (local before {:board snapshot.board})
    (when graph (set before.maps {:shared (graph:snapshot-reference-state) :maps []}))
    (append-capture! self captures entry.id false before operation)
    (local manager entry.world.runtime.graph-map-manager)
    (when manager
      (each [_ record (ipairs snapshot.maps.maps)]
        (when (manager:get-instantiated-map record.id)
          (append-capture! self captures entry.id record.id
                           (map-roles snapshot record manager.active-map-id) operation)))))
  {:changes [] :runtime-state captures})

(fn install-session! [session incoming map-id current?]
  (when (and session incoming)
    (when incoming.graph-view-states
      (when (not session.graph-view-states) (set session.graph-view-states {}))
      (tset session.graph-view-states map-id (R.clone (. incoming.graph-view-states map-id))))
    (when (and current? incoming.graph-view-state)
      (set session.graph-view-state (R.clone incoming.graph-view-state)))))

(fn install-panels! [shell incoming map-id active-id]
  (when (and shell incoming)
    (assert (= (type shell.panels) :table) "runtime shell requires native panels")
    (local panels [])
    (var installed? false)
    (each [_ panel (ipairs shell.panels)]
      (if (and (= panel.kind "graph-node-view") (= (or panel.graph-map-id active-id) map-id))
          (when (not installed?)
            (each [_ row (ipairs incoming.panels)] (table.insert panels (R.clone row)))
            (set installed? true))
          (table.insert panels panel)))
    (when (not installed?) (each [_ row (ipairs incoming.panels)] (table.insert panels (R.clone row))))
    (set shell.panels panels)))

(fn install-map-roles! [world capture]
  (local rt world.runtime)
  (local id capture.map-id)
  (local roles capture.after)
  (assert roles.maps "runtime map installation requires frozen topology")
  (local current? (= rt.graph-map-manager.active-map-id id))
  (rt.graph-map-manager:install-reference-state! roles.maps)
  (local graph-map (rt.graph-map-manager:get-instantiated-map id))
  (graph-map:reconcile-link-projections!)
  (each [_ node (pairs graph-map.nodes)]
    (when node.refresh-reference-projection! (node:refresh-reference-projection!)))
  (local views roles.views)
  (when views
    (when views.retained
      (when (not rt.graph-view-states) (set rt.graph-view-states {}))
      (tset rt.graph-view-states id (R.clone (. views.retained id))))
    (when (and current? views.retained-single) (set rt.graph-view-state (R.clone views.retained-single)))
    (install-session! (and world.state.activity world.state.activity.sessions.graph) views.activity id current?)
    (install-session! (and rt.activity-session-state rt.activity-session-state.graph) views.runtime-session id current?)
    (install-panels! rt.pending-canvas-state views.pending-canvas id rt.graph-map-manager.active-map-id)
    (install-panels! rt.pending-hud-state views.pending-hud id rt.graph-map-manager.active-map-id))
  (each [map-id metadata (pairs (or roles.metadata {}))] (world:install-reference-metadata! map-id metadata))
  (when (and views views.current current? rt.graph-view (= rt.graph-view.graph-map graph-map))
    (rt.graph-view:install-reference-state! (R.clone views.current))))

(fn install-world-roles! [world capture]
  (local rt world.runtime)
  (local roles (R.clone capture.after))
  (when (and roles.maps roles.maps.shared rt.graph)
    (rt.graph:install-reference-state! roles.maps.shared)
    (rt.graph:reconcile-link-projections!)
    (each [_ node (pairs rt.graph.nodes)]
      (when node.refresh-reference-projection! (node:refresh-reference-projection!)))
    (set roles.maps.shared nil))
  (world:install-reference-roles! roles)
  (when roles.board
    (when roles.board.state (set world.state.board (R.clone roles.board.state)))
    (when roles.board.activity
      (local session (assert (and world.state.activity world.state.activity.sessions.board)
                             "frozen board activity role requires native session"))
      (set session.board-state (R.clone roles.board.activity)))))

(fn reconcile! [self intent]
  (assert (= (type intent.runtime-state) :table) "runtime reconcile requires frozen captures")
  (local loaded (collect [_ entry (ipairs (self.manager:list-reference-worlds))] entry.id entry))
  (each [_ capture (ipairs intent.runtime-state)]
    (when (= capture.owner self.id)
      (local entry (. loaded capture.world-id))
      (local runtime (and entry entry.world entry.world.runtime))
      (when (and runtime
                 (or (= capture.map-id false)
                     (and runtime.graph-map-manager (runtime.graph-map-manager:get-instantiated-map capture.map-id))))
        (WorldOwner.validate-loaded! self.stores entry)
        (if (not (= capture.map-id false)) (install-map-roles! entry.world capture)
            (install-world-roles! entry.world capture)))))
  nil)

(fn expand [_self _inventory _operation] [])
(fn apply! [_self _change] (error "runtime owner cannot apply durable changes"))

(fn RuntimeOwner [options]
  (local stores (assert options.stores "runtime owner requires canonical stores"))
  (local manager (assert options.world-manager "runtime owner requires world-manager"))
  (local root (fs.absolute stores.base-dir))
  (assert (= root stores.base-dir) "runtime owner requires canonical root")
  (local self {:id "runtime" :base-dir root :stores stores :manager manager
               :preflight! preflight! :inventory inventory :expand expand :prepare prepare
               :apply! apply! :reconcile! reconcile!})
  (preflight! self)
  self)

RuntimeOwner
