(local Signal (require :signal))
(local Edge (require :graph/edge))
(local NodeBase (require :graph/node-base))
(local LinkEntityStore (require :entities/link))
(local IdentityStore (require :entities/identity))
(local KeyLoaderUtils (require :graph/key-loader-utils))
(local glm (require :glm))

(local GraphEdge Edge.GraphEdge)
(local node-id NodeBase.node-id)

(fn refresh-adapters-by-scheme [graph-map shared-graph nodes lookup replace-node scheme]
    (assert scheme "GraphMap.refresh-adapters-by-scheme requires scheme")
    (assert (= (type scheme) "string")
            "GraphMap.refresh-adapters-by-scheme requires string scheme")
    (assert (> (string.len scheme) 0)
            "GraphMap.refresh-adapters-by-scheme requires non-empty scheme")
    (local keys
        (icollect [key _node (pairs nodes)]
            (if (= (KeyLoaderUtils.key-scheme key) scheme)
                key)))
    (table.sort keys)
    (local replacements [])
    (local failed [])
    (each [_ key (ipairs keys)]
        (local replacement (shared-graph:create-node-by-key key))
        (if replacement
            (table.insert replacements {:key key :node replacement})
            (table.insert failed key)))
    (when (> (length failed) 0)
        (error (.. "failed to refresh graph nodes for scheme " scheme)))
    (local refreshed [])
    (each [_ item (ipairs replacements)]
        (local existing (lookup graph-map item.key))
        (when existing
            (replace-node graph-map existing item.node)
            (table.insert refreshed item.key)))
    {:scheme scheme
     :refreshed refreshed
     :failed failed})

(fn create-graph-map [opts]
    (local options (or opts {}))
    (local shared-graph (assert options.graph "GraphMap requires :graph (shared Graph)"))
    (local id (or options.id "main"))
    (local name (or options.name "Main"))
    (local nodes {})
    (local edges [])
    (local edge-map {})
    (local derived-edge-keys {})
    (local node-added (Signal))
    (local node-removed (Signal))
    (local node-replaced (Signal))
    (local node-morphed (Signal))
    (local edge-added (Signal))
    (local edge-removed (Signal))
    (var unresolved-restored-node-keys [])
    (var unresolved-restored-edge-list [])
    (var add-edge nil)
    (var recompute-link-edges-for-node nil)

    (local self {:id id
                 :name name
                 :graph shared-graph
                 :nodes nodes
                 :edges edges
                 :edge-map edge-map
                :selected_node_keys []
                :focused_node_key nil
                 :node-added node-added
                 :node-removed node-removed
                 :node-replaced node-replaced
                 :node-morphed node-morphed
                 :edge-added edge-added
                 :edge-removed edge-removed})

    (fn canonical-node [_self node context]
        (assert node (string.format "GraphMap missing node for %s" context))
        (assert (= (type node.key) :string)
                (string.format "GraphMap %s requires a node with a string key" context))
        (assert (and shared-graph.has-key-loader-for-key
                     (shared-graph:has-key-loader-for-key node.key))
                (string.format "GraphMap %s node key is not loader-backed: %s"
                               context
                               node.key))
        node)

    (fn derived-edge-id [edge edge-opts]
        (or (and edge-opts edge-opts.from-link-entity)
            (and edge-opts edge-opts.from-workflow-edge)
            (and edge edge._opts edge._opts.from-link-entity)
            (and edge edge._opts edge._opts.from-workflow-edge)))

    (fn edge-key [edge edge-opts]
        (local base (.. (node-id edge.source) "->" (node-id edge.target)))
        (local derived-id (derived-edge-id edge edge-opts))
        (if derived-id
            (.. base "#link:" (tostring derived-id))
            base))

    (fn lookup [_self key]
        (and key (. nodes key)))

    (fn replace-node [_self existing node]
        (when existing.unmount
            (existing:unmount))
        (when existing.drop
            (existing:drop))
        (when node.mount
            (node:mount self))
        (set (. nodes node.key) node)
        (each [_ edge (ipairs edges)]
            (when (= edge.source existing)
                (set edge.source node))
            (when (= edge.target existing)
                (set edge.target node)))
        (node-replaced:emit {:old existing :new node})
        node)

    (fn add-node [_self node node-opts]
        (when (not node)
            (error "GraphMap.add-node requires a node"))
        (when (and node.graph (not (= node.graph self)))
            (error (.. "GraphMap.add-node: node " (or node.key "?")
                       " is already mounted to another graph/map")))
        (local canonical (canonical-node self node "add-node"))
        (local existing (. nodes canonical.key))
        (if existing
            (if (= existing canonical)
                existing
                (replace-node self existing canonical))
            (do
                (when canonical.mount
                    (canonical:mount self))
                (set (. nodes canonical.key) canonical)
                (node-added:emit {:node canonical :opts node-opts})
                (when canonical.added
                    (canonical:added self))
                (recompute-link-edges-for-node self canonical.key)
                canonical)))

    (set recompute-link-edges-for-node
        (fn [self node-key]
            (local link-store (or (and shared-graph shared-graph.link-store)
                                  (LinkEntityStore.get-default)))
            (local entities (link-store:find-entities-for-key node-key))
            (each [_ entity (ipairs (or entities []))]
                (local source-key (self:resolve-key entity.source-key))
                (local target-key (self:resolve-key entity.target-key))
                (when (and source-key target-key (not (= source-key target-key)))
                    (local source-node (lookup self source-key))
                    (local target-node (lookup self target-key))
                    (when (and source-node target-node)
                        (local existing-key (.. source-key "->" target-key
                                               "#link:" (tostring entity.id)))
                        (when (not (. derived-edge-keys existing-key))
                            (local edge (GraphEdge {:source source-node
                                                    :target target-node
                                                    :label (or (and entity.metadata entity.metadata.name) "")
                                                    :color (glm.vec4 0.45 0.42 0.3 1)}))
                            (add-edge self edge {:from-link-entity (tostring entity.id)})))))))

    (set add-edge
        (fn [_self edge edge-opts]
            (when (not edge)
                (error "GraphMap.add-edge requires an edge"))
            (assert edge.source "GraphMap.add-edge requires edge.source")
            (assert edge.target "GraphMap.add-edge requires edge.target")
            (set edge.source (canonical-node self edge.source "add-edge source"))
            (set edge.target (canonical-node self edge.target "add-edge target"))
            (local source (self:add-node edge.source))
            (local target (self:add-node edge.target))
            (set edge.source source)
            (set edge.target target)
            (var options edge-opts)
            (when (and (= (derived-edge-id edge options) nil)
                       source.author-domain-edge)
                (local authored-options (source:author-domain-edge edge options))
                (when authored-options
                    (set options authored-options)))
            (local key (edge-key edge options))
            (local existing (. edge-map key))
            (local derived? (not (= (derived-edge-id edge options) nil)))
            (if existing
                (do
                    (when (not (and (not (. derived-edge-keys key))
                                    derived?))
                        (set (. edge-map key) edge)
                        (if derived?
                            (set (. derived-edge-keys key) true)
                            (set (. derived-edge-keys key) nil))
                        (set edge._opts options)
                        (for [i 1 (length edges)]
                            (when (= (. edges i) existing)
                                (set (. edges i) edge)))
                        (edge-added:emit {:edge edge :opts options}))
                    edge)
                (do
                    (table.insert edges edge)
                    (set (. edge-map key) edge)
                    (when derived?
                        (set (. derived-edge-keys key) true))
                    (when options
                        (set edge._opts options))
                    (edge-added:emit {:edge edge :opts options})
                    edge))))

    (fn remove-edge [_self edge-or-key opts]
        (local edge
            (if (= (type edge-or-key) :string)
                (. edge-map edge-or-key)
                edge-or-key))
        (if (not edge)
            nil
            (do
                (local identity-options edge._opts)
                (local key (edge-key edge identity-options))
                (for [i (length edges) 1 -1]
                    (when (= (. edges i) edge)
                        (table.remove edges i)))
                (set (. edge-map key) nil)
                (set (. derived-edge-keys key) nil)
                (edge-removed:emit {:edge edge :opts opts})
                (when (and edge.source edge.source.remove-domain-edge)
                    (edge.source:remove-domain-edge edge identity-options))
                edge)))

    (fn remove-nodes [_self nodes-to-remove opts]
        (local options (or opts {}))
        (local map-only? (not (= options.cause "shared-delete")))
        (local removal-set {})
        (local removed [])
        (each [_ node (ipairs (or nodes-to-remove []))]
            (when (and node node.key (= (. nodes node.key) node))
                (set (. removal-set node) true)
                (table.insert removed node)))
        (if (= (next removal-set) nil)
            0
            (do
                (local kept [])
                (local removed-edges [])
                (each [_ edge (ipairs edges)]
                    (if (or (rawget removal-set edge.source)
                            (rawget removal-set edge.target))
                        (table.insert removed-edges edge)
                        (table.insert kept edge)))
                (for [i (length edges) 1 -1]
                    (table.remove edges i))
                (each [_ edge (ipairs kept)]
                    (table.insert edges edge))
                (each [_ edge (ipairs removed-edges)]
                    (local removed-key (edge-key edge))
                    (set (. edge-map removed-key) nil)
                    (set (. derived-edge-keys removed-key) nil)
                    (edge-removed:emit {:edge edge}))
                (each [_ node (ipairs removed)]
                    (when node.unmount
                        (node:unmount))
                    (when node.drop
                        (node:drop)))
                (node-removed:emit {:nodes removed :removal-set removal-set :map-only? map-only?})
                (each [_ node (ipairs removed)]
                    (set (. nodes node.key) nil))
                (local removed-keys {})
                (each [_ node (ipairs removed)]
                    (when node.key
                        (set (. removed-keys node.key) true)))
                (when (> (length self.selected_node_keys) 0)
                    (local kept-selection [])
                    (each [_ key (ipairs self.selected_node_keys)]
                        (when (not (. removed-keys key))
                            (table.insert kept-selection key)))
                    (set self.selected_node_keys kept-selection))
                (when (and self.focused_node_key (. removed-keys self.focused_node_key))
                    (set self.focused_node_key nil))
                (length removed))))

    (set self.add-node add-node)
    (set self.add-edge add-edge)
    (set self.remove-edge remove-edge)
    (set self.remove-nodes remove-nodes)

    (set self.edge-count (fn [_self] (length edges)))
    (set self.node-count (fn [_self] (length (icollect [_ _ (pairs nodes)] true))))
    (set self.lookup (fn [_self key] (lookup self key)))

    (set self.resolve-key
        (fn [_self key opts]
            (local options (or opts {}))
            (if (or (not key) (not (= (type key) "string")))
                key
                (do
                    (local identity-store (and shared-graph shared-graph.identity-store))
                    (var current key)
                    (var depth 0)
                    (local max-depth (or options.max-depth 32))
                    (local visited (or options.visited {}))
                    (local identity-prefix "identity:")
                    (while true
                        (when (>= depth max-depth)
                            (lua "return current"))
                        (when (. visited current)
                            (error (.. "resolve-key identity cycle detected at " current)))
                        (set (. visited current) true)
                        (if (not (= (string.sub current 1 (string.len identity-prefix)) identity-prefix))
                            (lua "return current")
                            (do
                                (local entity-id (string.sub current (+ (string.len identity-prefix) 1)))
                                (local entity (and identity-store
                                                   identity-store.get-entity
                                                   (identity-store:get-entity entity-id)))
                                (if (not (and entity entity.target-key
                                             (> (string.len (tostring entity.target-key)) 0)))
                                    (lua "return current")
                                    (do
                                        (set current (tostring entity.target-key))
                                        (set depth (+ depth 1)))))))))))

    (set self.resolve-node
        (fn [_self key-or-node opts]
            (local options (or opts {}))
            (local key
                (if (= (type key-or-node) "table")
                    (and key-or-node key-or-node.key)
                    key-or-node))
            (local resolved-key (self:resolve-key key options))
            (if (not resolved-key)
                nil
                (or (lookup self resolved-key)
                    (self:load-by-key resolved-key)))))

    (set self.load-by-key
        (fn [_self key]
            (when (not key) (lua "return nil"))
            (assert (= (type key) "string") "GraphMap.load-by-key requires string key")
            (local existing (. nodes key))
            (when existing (lua "return existing"))
            (local node (shared-graph:create-node-by-key key))
            (when node
                (add-node self node))
            node))

    (set self.refresh-adapters-by-scheme
        (fn [_self scheme]
            (refresh-adapters-by-scheme self shared-graph nodes lookup replace-node scheme)))

    (fn record-unresolved-restored-node [key]
        (when (and key (= (type key) :string))
            (var exists? false)
            (each [_ current (ipairs unresolved-restored-node-keys)]
                (when (= current key)
                    (set exists? true)))
            (when (not exists?)
                (table.insert unresolved-restored-node-keys key))))

    (fn record-unresolved-restored-edge [source-key target-key]
        (when (and (= (type source-key) :string)
                   (= (type target-key) :string))
            (var exists? false)
            (each [_ edge (ipairs unresolved-restored-edge-list)]
                (when (and (= edge.source source-key)
                           (= edge.target target-key))
                    (set exists? true)))
            (when (not exists?)
                (table.insert unresolved-restored-edge-list {:source source-key
                                                             :target target-key}))))

    (set self.capture-state
        (fn [_self]
            (local node-keys
                (icollect [key _ (pairs nodes)]
                    key))
            (table.sort node-keys)
            (local edge-keys {})
            (local edge-list [])
            (each [_ edge (ipairs edges)]
                (local source-key (and edge.source edge.source.key))
                (local target-key (and edge.target edge.target.key))
                (when (and source-key target-key)
                    (local composite (edge-key edge))
                    (when (and (not (. edge-keys composite))
                               (not (. derived-edge-keys composite)))
                        (set (. edge-keys composite) true)
                        (table.insert edge-list {:source source-key
                                                  :target target-key}))))
            (table.sort edge-list
                        (fn [a b]
                            (local a-key (.. (or a.source "") "->" (or a.target "")))
                            (local b-key (.. (or b.source "") "->" (or b.target "")))
                            (< a-key b-key)))
            ;; Preserve unresolved restored keys/edges so they survive through
            ;; capture/restore cycles until hydration explicitly prunes them.
            (each [_ key (ipairs unresolved-restored-node-keys)]
                (when (and (= (type key) :string)
                           (not (lookup self key)))
                    (table.insert node-keys key)))
            (each [_ edge (ipairs unresolved-restored-edge-list)]
                (local source-key edge.source)
                (local target-key edge.target)
                (local composite (.. (or source-key "") "->" (or target-key "")))
                (when (and (= (type source-key) :string)
                           (= (type target-key) :string)
                           (not (. edge-keys composite)))
                    (set (. edge-keys composite) true)
                    (table.insert edge-list {:source source-key
                                              :target target-key})))
            (table.sort node-keys)
            (local captured-selected-keys
                (icollect [_ key (ipairs (or self.selected_node_keys []))]
                    key))
            {:nodes node-keys
             :edges edge-list
             :selected_node_keys captured-selected-keys
             :focused_node_key self.focused_node_key}))

    (set self.restore-state
        (fn [_self state]
            (local payload (or state {}))
            (local node-keys (or payload.nodes []))
            (local edge-list (or payload.edges []))
            (assert (= (type node-keys) :table) "GraphMap.restore-state requires :nodes table")
            (assert (= (type edge-list) :table) "GraphMap.restore-state requires :edges table")
            (local restored-node-key-set {})
            (each [_ key (ipairs node-keys)]
                (when (= (type key) :string)
                    (tset restored-node-key-set key true)))
            (each [_ edge (ipairs edges)]
                (edge-removed:emit {:edge edge}))
            (each [_ node (pairs nodes)]
                (when node.unmount
                    (node:unmount))
                (when node.drop
                    (node:drop)))
            (local all-existing-nodes (icollect [_ node (pairs nodes)] node))
            (when (> (length all-existing-nodes) 0)
                (local removal-set {})
                (each [_ node (ipairs all-existing-nodes)]
                    (set (. removal-set node) true))
                (node-removed:emit {:nodes all-existing-nodes :removal-set removal-set :map-only? true}))
            (for [i (length edges) 1 -1]
                (table.remove edges i))
            (each [k _ (pairs edge-map)]
                (set (. edge-map k) nil))
            (each [k _ (pairs nodes)]
                (set (. nodes k) nil))
            (each [k _ (pairs derived-edge-keys)]
                (set (. derived-edge-keys k) nil))
            (set unresolved-restored-node-keys [])
            (set unresolved-restored-edge-list [])
            (each [_ key (ipairs node-keys)]
                (assert (= (type key) :string) "GraphMap.restore-state node keys must be strings")
                (local node (self:load-by-key key))
                (if (not node)
                    (record-unresolved-restored-node key)))
            (each [_ edge (ipairs edge-list)]
                (assert (= (type edge) :table) "GraphMap.restore-state edge entries must be tables")
                (local source-key edge.source)
                (local target-key edge.target)
                (assert (= (type source-key) :string)
                        "GraphMap.restore-state edge.source must be a string")
                (assert (= (type target-key) :string)
                        "GraphMap.restore-state edge.target must be a string")
                (when (and (. restored-node-key-set source-key)
                           (. restored-node-key-set target-key))
                    (local source-node (lookup self source-key))
                    (local target-node (lookup self target-key))
                    (if (not (and source-node target-node))
                        (record-unresolved-restored-edge source-key target-key)
                        (self:add-edge (GraphEdge {:source source-node
                                                    :target target-node})))))
            (each [key _ (pairs nodes)]
                (recompute-link-edges-for-node self key))
            (set self.selected_node_keys
                 (or (and (= (type payload.selected_node_keys) :table)
                          (icollect [_ key (ipairs payload.selected_node_keys)]
                              (if (and (= (type key) :string)
                                       (lookup self key))
                                  key)))
                     []))
            (set self.focused_node_key
                 (and (= (type payload.focused_node_key) :string)
                      (lookup self payload.focused_node_key)
                      payload.focused_node_key))
            true))

    (set self.clear-unresolved-restored-state
        (fn [_self]
            (set unresolved-restored-node-keys [])
            (set unresolved-restored-edge-list [])
            true))

    (var shared-node-removed-handler nil)
    (var shared-node-replaced-handler nil)
    (var shared-node-morphed-handler nil)
    (var shared-edge-added-handler nil)
    (var shared-edge-removed-handler nil)

    (fn sync-shared-node-removed [payload]
        (local to-remove [])
        (each [_ node (ipairs (or (and payload payload.nodes) []))]
            (local map-node (lookup self (and node node.key)))
            (when map-node
                (table.insert to-remove map-node)))
        (when (> (length to-remove) 0)
            (self:remove-nodes to-remove {:cause "shared-delete"})))

    (fn sync-shared-edge-added [payload]
        (local shared-edge (and payload payload.edge))
        (when shared-edge
            (local source-key (and shared-edge.source shared-edge.source.key))
            (local target-key (and shared-edge.target shared-edge.target.key))
            (when (and source-key target-key)
                (local source-node (lookup self source-key))
                (local target-node (lookup self target-key))
                (when (and source-node target-node)
                    (self:add-edge (GraphEdge {:source source-node
                                                :target target-node
                                                :label (or shared-edge.label "")
                                                :color shared-edge.color})
                                   (and payload payload.opts))))))

    (fn sync-shared-edge-removed [payload]
        (local shared-edge (and payload payload.edge))
        (when shared-edge
            (local source-key (and shared-edge.source shared-edge.source.key))
            (local target-key (and shared-edge.target shared-edge.target.key))
            (when (and source-key target-key)
                (local entity-id (derived-edge-id shared-edge (and payload payload.opts)))
                (for [i (length edges) 1 -1]
                    (local edge (. edges i))
                    (local key (edge-key edge))
                    (local edge-entity-id (derived-edge-id edge nil))
                    (when (and (. derived-edge-keys key)
                               (= (and edge.source edge.source.key) source-key)
                               (= (and edge.target edge.target.key) target-key)
                               (or (not entity-id)
                                   (= (tostring edge-entity-id) (tostring entity-id))))
                        (table.remove edges i)
                        (set (. edge-map key) nil)
                        (set (. derived-edge-keys key) nil)
                        (edge-removed:emit {:edge edge}))))))

    (fn sync-shared-node-replaced [payload]
        (local existing (and payload payload.old))
        (local replacement (and payload payload.new))
        (when (and existing replacement
                   existing.key replacement.key
                   (= existing.key replacement.key))
            (local map-node (lookup self existing.key))
            (when map-node
                (local map-adapter (shared-graph:create-node-by-key replacement.key))
                (when map-adapter
                    (replace-node self map-node map-adapter)))))

    (fn sync-shared-node-morphed [payload]
        (local source-key (or payload.source-key
                              (and payload.result payload.result.source-key)))
        (local target-key (or payload.target-key
                              (and payload.result payload.result.target-key)
                              (and payload.result payload.result.code-key)))
        (local had-source? (and source-key (lookup self source-key)))
        (when had-source?
            (sync-shared-node-removed {:nodes [{:key source-key}]}))
        (when (and had-source? target-key)
            (self:load-by-key target-key))
        (when had-source?
            (node-morphed:emit payload)))

    (set shared-node-removed-handler
         (shared-graph.node-removed:connect sync-shared-node-removed))
    (set shared-node-replaced-handler
         (shared-graph.node-replaced:connect sync-shared-node-replaced))
    (set shared-node-morphed-handler
         (shared-graph.node-morphed:connect sync-shared-node-morphed))
    (set shared-edge-added-handler
         (shared-graph.edge-added:connect sync-shared-edge-added))
    (set shared-edge-removed-handler
         (shared-graph.edge-removed:connect sync-shared-edge-removed))

    (var morph-handler nil)
    (when (and (not shared-graph.entity-events?)
               shared-graph shared-graph.morphs shared-graph.morphs.morphed)
        (set morph-handler
             (shared-graph.morphs.morphed:connect
                 (fn [payload]
                     (local source-key (or payload.source-key
                                           (and payload.result payload.result.source-key)))
                      (local target-key (or (and payload.result payload.result.target-key)
                                            (and payload.result payload.result.code-key)))
                     (sync-shared-node-morphed {:source-key source-key
                                                 :target-key target-key
                                                 :payload payload})))))

    (var link-created-handler nil)
    (var link-updated-handler nil)
    (var link-deleted-handler nil)

    (var identity-updated-handler nil)
    (var identity-deleted-handler nil)

    (fn remove-derived-link-edges-by-id [entity-id]
        (local id-str (tostring entity-id))
        (local to-remove [])
        (each [_ edge (ipairs edges)]
            (when (= (and edge._opts edge._opts.from-link-entity) id-str)
                (table.insert to-remove edge)))
        (each [_ edge (ipairs to-remove)]
            (for [i (length edges) 1 -1]
                (when (= (. edges i) edge)
                    (table.remove edges i)))
            (local removed-key (edge-key edge))
            (set (. edge-map removed-key) nil)
            (set (. derived-edge-keys removed-key) nil)
            (edge-removed:emit {:edge edge}))
        (length to-remove))

    (fn matching-derived-link-edge [entity source-key target-key label]
        (local entity-id (tostring entity.id))
        (var matched nil)
        (var count 0)
        (each [_ edge (ipairs edges)]
            (when (and (= (and edge._opts edge._opts.from-link-entity) entity-id)
                       (= (and edge.source edge.source.key) source-key)
                       (= (and edge.target edge.target.key) target-key)
                       (= (or edge.label "") (or label "")))
                (set matched edge))
            (when (= (and edge._opts edge._opts.from-link-entity) entity-id)
                (set count (+ count 1))))
        (and matched (= count 1)))

    (fn upsert-link-entity-edge [entity]
        (when (and entity entity.id)
            (local entity-id (tostring entity.id))
            (local source-key (self:resolve-key entity.source-key))
            (local target-key (self:resolve-key entity.target-key))
            (local label (or (and entity.metadata entity.metadata.name) ""))
            (local source-node (and source-key (lookup self source-key)))
            (local target-node (and target-key (lookup self target-key)))
            (if (and source-key target-key
                     (not (= source-key target-key))
                     source-node target-node
                     (matching-derived-link-edge entity source-key target-key label))
                true
                (do
                    (remove-derived-link-edges-by-id entity-id)
                    (when (and source-key target-key
                               (not (= source-key target-key))
                               source-node target-node)
                        (local edge (GraphEdge {:source source-node
                                                :target target-node
                                                :label label
                                                :color (glm.vec4 0.45 0.42 0.3 1)}))
                        (add-edge self edge {:from-link-entity entity-id}))))))

    (fn handle-link-entity-created [entity]
        (upsert-link-entity-edge entity))

    (fn handle-link-entity-updated [entity]
        (upsert-link-entity-edge entity))

    (fn handle-link-entity-deleted [entity]
        (when (and entity entity.id)
            (remove-derived-link-edges-by-id entity.id)))

    (fn refresh-link-edges-for-key [key]
        (local link-store (or (and shared-graph shared-graph.link-store)
                              (LinkEntityStore.get-default)))
        (local entities (link-store:find-entities-for-key key))
        (each [_ entity (ipairs (or entities []))]
            (handle-link-entity-updated entity)))

    (local link-store (or (and shared-graph shared-graph.link-store)
                          (LinkEntityStore.get-default)))
    (local identity-store (or (and shared-graph shared-graph.identity-store)
                               (IdentityStore.get-default)))
    (set link-created-handler
         (link-store.link-entity-created:connect handle-link-entity-created))
    (set link-updated-handler
         (link-store.link-entity-updated:connect handle-link-entity-updated))
    (set link-deleted-handler
         (link-store.link-entity-deleted:connect handle-link-entity-deleted))
    (set identity-updated-handler
         (identity-store.identity-updated:connect
             (fn [entity]
                 (refresh-link-edges-for-key (.. "identity:" (tostring entity.id))))))
    (set identity-deleted-handler
         (identity-store.identity-deleted:connect
             (fn [entity]
                 (refresh-link-edges-for-key (.. "identity:" (tostring entity.id))))))

    (set self.drop
        (fn [_self]
            (when shared-node-removed-handler
                (shared-graph.node-removed:disconnect shared-node-removed-handler true)
                (set shared-node-removed-handler nil))
            (when shared-node-replaced-handler
                (shared-graph.node-replaced:disconnect shared-node-replaced-handler true)
                (set shared-node-replaced-handler nil))
            (when shared-node-morphed-handler
                (shared-graph.node-morphed:disconnect shared-node-morphed-handler true)
                (set shared-node-morphed-handler nil))
            (when shared-edge-added-handler
                (shared-graph.edge-added:disconnect shared-edge-added-handler true)
                (set shared-edge-added-handler nil))
            (when shared-edge-removed-handler
                (shared-graph.edge-removed:disconnect shared-edge-removed-handler true)
                (set shared-edge-removed-handler nil))
            (when link-created-handler
                (link-store.link-entity-created:disconnect link-created-handler true)
                (set link-created-handler nil))
            (when link-updated-handler
                (link-store.link-entity-updated:disconnect link-updated-handler true)
                (set link-updated-handler nil))
            (when link-deleted-handler
                (link-store.link-entity-deleted:disconnect link-deleted-handler true)
                (set link-deleted-handler nil))
            (when morph-handler
                (shared-graph.morphs.morphed:disconnect morph-handler true)
                (set morph-handler nil))
            (when identity-updated-handler
                (identity-store.identity-updated:disconnect identity-updated-handler true)
                (set identity-updated-handler nil))
            (when identity-deleted-handler
                (identity-store.identity-deleted:disconnect identity-deleted-handler true)
                (set identity-deleted-handler nil))
            (each [_ node (pairs nodes)]
                (when node.unmount
                    (node:unmount))
                (when node.drop
                    (node:drop)))
            (for [i (length edges) 1 -1]
                (table.remove edges i))
            (each [k _ (pairs edge-map)]
                (set (. edge-map k) nil))
            (each [k _ (pairs derived-edge-keys)]
                (set (. derived-edge-keys k) nil))
            (each [k _ (pairs nodes)]
                (set (. nodes k) nil))
            (node-added:clear)
            (node-removed:clear)
            (node-replaced:clear)
            (node-morphed:clear)
            (edge-added:clear)
            (edge-removed:clear)))

    self)

{:GraphMap create-graph-map}
