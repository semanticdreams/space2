(local R (require :reference-lifecycle/record-utils))
(local glm (require :glm))

(fn edge-address [source target] (.. source "->" target))

;; Native node-view capture is sorted by representation key, not panel order.
;; Retain the owning rows' order/extensions while overlaying current membership
;; and native panel fields. This is a schema merge, never a string traversal.
(fn merge-view-panels [existing current]
  (assert (and existing current) "node-view panel merge requires owning and current rows")
  (R.require-array existing) (R.require-array current)
  (local live {}) (local used {}) (local out [])
  (each [_ row (ipairs current)]
    (assert (= (type row.node-key) :string) "native node-view panel requires node-key")
    (tset live row.node-key row))
  (each [_ row (ipairs existing)]
    (local native (. live row.node-key))
    (when native
      (local merged (R.clone row))
      (each [field value (pairs native)] (tset merged field (R.clone value)))
      (tset used row.node-key true)
      (table.insert out merged)))
  (each [_ row (ipairs current)]
    (when (not (. used row.node-key)) (table.insert out (R.clone row))))
  out)

;; Explicit native edges have endpoint identity. Link/workflow-derived edges keep
;; their existing independent native IDs and never enter the serialized row set.
(fn merge-explicit-edges [existing current]
  (assert (and existing current) "explicit edge merge requires rows")
  (local by-address {})
  (each [_ row (ipairs existing)] (tset by-address (edge-address row.source row.target) row))
  (icollect [_ row (ipairs current)]
    (do
      (local merged (R.clone (or (. by-address (edge-address row.source row.target)) {})))
      (each [field value (pairs row)] (tset merged field (R.clone value)))
      ;; Known live fields are authoritative even when cleared. Only unsupported
      ;; owning extensions may survive their absence from the native row.
      (each [_ field (ipairs [:label :color])] (tset merged field (R.clone (. row field))))
      merged)))

(fn capture-edge-color [color retained]
  (when (not (= retained nil))
    (R.require-array retained)
    (assert (= (# retained) 4) "explicit edge color requires four components")
    (each [_ component (ipairs retained)]
      (assert (= (type component) :number) "explicit edge color components must be numbers")))
  (when (not (= color nil))
    (assert (glm.is-vec4 color) "native explicit edge color must be glm.vec4")
    (local previous (and retained (glm.vec4 (table.unpack retained))))
    ;; Compare at the engine's actual float precision, not an epsilon: preserve
    ;; original JSON numbers exactly when restore rendered the same native color.
    (if (and previous (= color.x previous.x) (= color.y previous.y)
             (= color.z previous.z) (= color.w previous.w))
        (R.clone retained) [color.x color.y color.z color.w])))

(fn capture-explicit-edge [edge retained]
  (assert (= (type edge.label) :string) "native explicit edge label must be string")
  (local row (R.clone (if retained retained {})))
  (R.field row :label :string nil)
  (set row.source edge.source.key) (set row.target edge.target.key)
  ;; Do not add empty defaults to historical endpoint-only rows. A previously
  ;; present label must still record public replacement's deliberate empty reset.
  (when (or (not (= row.label nil)) (not (= edge.label ""))) (set row.label edge.label))
  (set row.color (capture-edge-color edge.color (R.field row :color :table nil)))
  row)

(fn capture-map-state [map derived-keys native-edge-key explicit-rows unresolved-nodes unresolved-edges next-id]
  (assert map "map capture requires native map")
  (local nodes (icollect [key _ (pairs map.nodes)] key))
  (each [_ key (ipairs unresolved-nodes)]
    (when (not (map:lookup key)) (table.insert nodes key)))
  (table.sort nodes)
  (local edges []) (local seen {})
  (each [_ edge (ipairs map.edges)]
    (local key (native-edge-key edge))
    (when (and (not (. derived-keys key)) (not (. seen key)))
      (tset seen key true)
      (table.insert edges (capture-explicit-edge edge (. explicit-rows key)))))
  (each [_ row (ipairs unresolved-edges)]
    (local key (edge-address row.source row.target))
    (when (not (. seen key))
      (tset seen key true)
      (table.insert edges (R.clone row))))
  (table.sort edges (fn by-endpoints [a b] (< (edge-address a.source a.target) (edge-address b.source b.target))))
  {:nodes nodes :edges edges :islands (map:list-islands) :next_island_id next-id
   :selected_node_keys (R.clone map.selected_node_keys) :focused_node_key map.focused_node_key
   :view_mode map.view_mode :outline_root_keys (map:get-outline-root-keys)})

;; Representation keys are concrete graph keys, never stable-reference wrappers.
;; Only documented schema locations are transformed; history/provenance is opaque.
(fn concrete-key [key operation]
  (var result key)
  (when (= operation.kind "delete")
    (each [_ retiring (ipairs operation.retiring)]
      (when (= key retiring) (set result nil))))
  (when (and (= operation.kind "morph") (= key operation.source-key))
    (set result operation.target-key))
  result)

(fn rewrite-keys [keys operation]
  (R.require-array keys)
  (local out [])
  (local seen {})
  (each [_ key (ipairs keys)]
    (local candidate (concrete-key key operation))
    (when (and candidate (not (. seen candidate)))
      (tset seen candidate true)
      (table.insert out candidate)))
  out)

(fn rewrite-selection! [state operation]
  (when state.selected_node_keys
    (set state.selected_node_keys (rewrite-keys state.selected_node_keys operation)))
  (when state.focused_node_key
    (set state.focused_node_key (concrete-key state.focused_node_key operation))
    (when (not (= state.focused_node_key_present? nil))
      (set state.focused_node_key_present? (not (= state.focused_node_key nil))))))

(fn rewrite-panels [panels operation]
  (assert (= (type panels) :table) "graph reference panels must be an array")
  (R.require-array panels)
  (local out [])
  (each [_ panel (ipairs panels)]
    (local key (concrete-key panel.node-key operation))
    (when (or (= panel.node-key nil) key)
      (local candidate (R.clone panel))
      (set candidate.node-key key)
      (when (and candidate.panel candidate.panel.node-key)
        (set candidate.panel.node-key (concrete-key candidate.panel.node-key operation)))
      (table.insert out candidate)))
  out)

(fn rewrite-node-views! [views operation]
  (when views.open-views
    (set views.open-views (rewrite-panels views.open-views operation)))
  (when views.open-node-keys
    (set views.open-node-keys (rewrite-keys views.open-node-keys operation))))

(fn rewrite-view-fields! [state operation]
  (rewrite-selection! state operation)
  (when state.views (rewrite-node-views! state.views operation))
  (when state.extra_panels
    (set state.extra_panels (rewrite-panels state.extra_panels operation))))

(fn rewrite-view [state operation]
  (local out (R.clone state))
  (rewrite-view-fields! out operation)
  (when (and out.mode_states out.mode_states.spatial)
    (rewrite-view-fields! out.mode_states.spatial operation))
  out)

(fn rewrite-islands [islands operation]
  (R.require-array islands)
  (local out [])
  (each [_ island (ipairs islands)]
    (local candidate (R.clone island))
    (set candidate.members (rewrite-keys island.members operation))
    (when (and (= candidate.kind "ordered-list") candidate.state candidate.state.list-key)
      (set candidate.state.list-key (concrete-key candidate.state.list-key operation)))
    ;; GraphIslands requires at least one member for every native island kind.
    (when (> (# candidate.members) 0) (table.insert out candidate)))
  out)

(fn rewrite-edges [edges operation]
  (R.require-array edges)
  (local out [])
  (each [_ edge (ipairs edges)]
    (local source (concrete-key edge.source operation))
    (local target (concrete-key edge.target operation))
    (when (and source target)
      (local candidate (R.clone edge))
      (set candidate.source source)
      (set candidate.target target)
      (table.insert out candidate)))
  out)

(fn rewrite-map [state operation]
  (local out (R.clone state))
  (when out.nodes (set out.nodes (rewrite-keys out.nodes operation)))
  (when out.edges (set out.edges (rewrite-edges out.edges operation)))
  (rewrite-selection! out operation)
  (when out.outline_root_keys
    (set out.outline_root_keys (rewrite-keys out.outline_root_keys operation)))
  (when out.islands (set out.islands (rewrite-islands out.islands operation)))
  out)

(fn rewrite-keyed [items operation]
  (local out {})
  ;; Unaffected target metadata wins if both concrete representations existed.
  (each [key value (pairs items)]
    (when (= key (concrete-key key operation)) (tset out key (R.clone value))))
  (each [key value (pairs items)]
    (local candidate (concrete-key key operation))
    (when (and candidate (= (. out candidate) nil))
      (tset out candidate (R.clone value))))
  out)

(fn rewrite-metadata [metadata operation]
  (local out (R.clone metadata))
  (each [_ field (ipairs [:positions :sizes :presentations])]
    (when (. out field) (tset out field (rewrite-keyed (. out field) operation))))
  (each [_ field (ipairs [:panels :extra_panels])]
    (when (. out field) (tset out field (rewrite-panels (. out field) operation))))
  out)

;; Native managers own the enumerated maps/fields; opaque persisted fields remain
;; owned by the world record. Merge by native ID, never by array position.
(fn merge-reference-map [existing map]
  (assert (= (type map) :table) "reference map merge requires native map record")
  (local entry (R.clone (or existing {})))
  (each [_ key (ipairs [:nodes :edges :islands :next_island_id :selected_node_keys
                        :focused_node_key :view_mode :outline_root_keys])]
    (tset entry key (R.clone (. map key))))
  (each [key value (pairs map)] (tset entry key (R.clone value)))
  (when map.edges (set entry.edges (merge-explicit-edges (or (and existing existing.edges) []) map.edges)))
  entry)

(fn merge-reference-maps [existing captured]
  (assert (and existing captured) "reference map merge requires before and native snapshot")
  (local out (R.clone existing))
  (local by-id {})
  (each [_ map (ipairs (or existing.maps []))] (tset by-id map.id map))
  (each [key value (pairs captured)] (tset out key (R.clone value)))
  (when captured.maps
    (set out.graph nil)
    (set out.maps (icollect [_ map (ipairs captured.maps)]
                   (merge-reference-map (. by-id map.id) map))))
  out)

;; Ordinary HomeWorld capture preserves only unsupported native keys from older
;; snapshots. Lifecycle snapshots do not use this hydration/merge path.
(fn resolve-core [state]
  (assert (= (type state) :table) "graph state requires table")
  (if (= (type state.graph) :table) state.graph
      (and (= (type state.maps) :table) (= (type state.active_map_id) :string))
      (do
        (var entry nil)
        (each [_ map (ipairs state.maps) &until entry]
          (when (= map.id state.active_map_id) (set entry map)))
        {:nodes (or (and entry entry.nodes) []) :edges (or (and entry entry.edges) [])})
      {:nodes (or state.nodes []) :edges (or state.edges [])}))

(fn merge-unsupported-core! [graph existing captured]
  (assert (and existing captured) "graph capture merge requires before/after state")
  (fn supports? [key] (and graph graph.has-key-loader-for-key (graph:has-key-loader-for-key key)))
  (local nodes {}) (local edges {})
  (each [_ key (ipairs (or captured.nodes []))] (tset nodes key true))
  (each [_ edge (ipairs (or captured.edges []))]
    (tset edges (.. (or edge.source "") "->" (or edge.target "")) true))
  (each [_ key (ipairs (or existing.nodes []))]
    (when (and (not (. nodes key)) (not (supports? key))) (table.insert captured.nodes key)))
  (each [_ edge (ipairs (or existing.edges []))]
    (local composite (.. (or edge.source "") "->" (or edge.target "")))
    (when (and (not (. edges composite))
               (or (and edge.source (not (supports? edge.source)))
                   (and edge.target (not (supports? edge.target)))))
      (table.insert captured.edges edge)))
  captured)

(fn merge-preserved-state [graph existing captured]
  (assert (and existing captured) "graph capture merge requires before/after state")
  (if (= (type captured.maps) :table)
      (do
        (local merged (R.clone captured))
        (local by-id {})
        (if (= (type existing.maps) :table)
            (each [_ map (ipairs existing.maps)] (tset by-id map.id map))
            (= (type existing.graph) :table) (tset by-id "main" existing.graph))
        (each [_ map (ipairs merged.maps)]
          (when (and (. by-id map.id) (not (= map.id merged.active_map_id)))
            (merge-unsupported-core! graph (. by-id map.id) map)))
        merged)
      (do
        (local core (resolve-core captured))
        (local merged {:nodes (R.clone (or core.nodes [])) :edges (R.clone (or core.edges []))})
        {:graph (merge-unsupported-core! graph (resolve-core existing) merged)})))

{:rewrite-map rewrite-map :rewrite-metadata rewrite-metadata :rewrite-view rewrite-view
 :resolve-core resolve-core :merge-preserved-state merge-preserved-state :merge-reference-maps merge-reference-maps
 :edge-address edge-address :capture-map-state capture-map-state :merge-explicit-edges merge-explicit-edges
 :merge-view-panels merge-view-panels}
