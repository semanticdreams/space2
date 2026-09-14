(local Graph {})

(local glm (require :glm))
(local Edge (require :graph/edge))
(local NodeBase (require :graph/node-base))
(local StartNode (require :graph/nodes/start))
(local ClassNode (require :graph/nodes/class))
(local QuitNode (require :graph/nodes/quit))
(local Signal (require :signal))
(local logging (require :logging))
(local LinkEntityStore (require :entities/link))
(local IdentityStore (require :entities/identity))
(local StringEntityStore (require :entities/string))
(local Morphs (require :morphs/init))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local GraphNode NodeBase.GraphNode)
(local GraphEdge Edge.GraphEdge)
(local node-id NodeBase.node-id)

(fn validate-key-loader-scheme [context scheme]
    (assert scheme (.. context " requires a scheme"))
    (assert (= (type scheme) "string") (.. context " requires string scheme"))
    (assert (> (string.len scheme) 0) (.. context " requires non-empty scheme")))

(fn make-key-loader-handle [graph registration]
    {:scheme registration.scheme
     :owner-id registration.owner-id
     :extension-id registration.extension-id
     :registration-id registration.registration-id
     :active? true
     :unregister (fn [handle-self]
                   (graph:unregister-key-loader handle-self))})

(fn register-key-loader [graph key-loaders allocate-registration-id scheme loader-fn opts]
    (validate-key-loader-scheme "register-key-loader" scheme)
    (assert (not (string.find scheme ":" 1 true))
            "register-key-loader scheme must not include ':'")
    (assert loader-fn "register-key-loader requires a loader function")
    (assert (= (type loader-fn) "function") "register-key-loader requires function loader")
    (assert (not (. key-loaders scheme))
            (.. "register-key-loader duplicate scheme: " scheme))
    (local options (or opts {}))
    (local registration {:scheme scheme
                         :loader-fn loader-fn
                         :owner-id options.owner-id
                         :extension-id options.extension-id
                         :registration-id (allocate-registration-id)
                         :active? true})
    (local handle (make-key-loader-handle graph registration))
    (set registration.handle handle)
    (set (. key-loaders scheme) registration)
    handle)

(fn unregister-key-loader-handle [key-loaders handle]
    (validate-key-loader-scheme "unregister-key-loader" handle.scheme)
    (local registration (. key-loaders handle.scheme))
    (if registration
        (do
            (when (not (= registration.registration-id handle.registration-id))
                (error (.. "key loader for scheme " handle.scheme " belongs to another registration")))
            (set registration.active? false)
            (set (. key-loaders handle.scheme) nil)
            (set handle.active? false)
            true)
        (if (not handle.active?)
            true
            (do
                (set handle.active? false)
                true))))

(fn unregister-key-loader-scheme [key-loaders scheme opts]
    (validate-key-loader-scheme "unregister-key-loader" scheme)
    (local options (or opts {}))
    (local registration (. key-loaders scheme))
    (if registration
        (do
            (when (and registration.owner-id
                       (not (= options.owner-id registration.owner-id)))
                (error (.. "key loader for scheme " scheme " belongs to owner " registration.owner-id)))
            (when (and options.registration-id
                       (not (= options.registration-id registration.registration-id)))
                (error (.. "key loader for scheme " scheme " belongs to another registration")))
            (set registration.active? false)
            (when registration.handle
                (set registration.handle.active? false))
            (set (. key-loaders scheme) nil)
            true)
        true))

(fn unregister-key-loader [key-loaders handle-or-scheme opts]
    (assert handle-or-scheme "unregister-key-loader requires a handle or scheme")
    (local kind (type handle-or-scheme))
    (assert (or (= kind "table") (= kind "string"))
            "unregister-key-loader requires table handle or string scheme")
    (if (= kind "table")
        (unregister-key-loader-handle key-loaders handle-or-scheme)
        (unregister-key-loader-scheme key-loaders handle-or-scheme opts)))

(fn create-graph [opts]
    (local options (or opts {}))
    (local nodes {})
    (local edges [])
    (local edge-map {})
    (local key-loaders {})
    (var node-seq 0)
    (var key-loader-registration-seq 0)
    (local node-added (Signal))
    (local node-removed (Signal))
    (local node-replaced (Signal))
    (local node-morphed (Signal))
    (local edge-added (Signal))
    (local edge-removed (Signal))
    (local link-edge-map {}) ;; entity-id -> edge-key
    (local link-edge-loading {}) ;; entity-id -> true
    (var unresolved-restored-node-keys [])
    (var unresolved-restored-edge-list [])

    (var check-link-edges-for-node nil) ;; Forward declaration

    (local entity-events? (if (= options.entity-events? nil) true options.entity-events?))
    (local self {:nodes nodes
                 :edges edges
                 :edge-map edge-map
                 :with-start (if (= options.with-start nil) true options.with-start)
                 :entity-events? entity-events?
                 :node-added node-added
                 :node-removed node-removed
                 :node-replaced node-replaced
                 :node-morphed node-morphed
                 :edge-added edge-added
                 :edge-removed edge-removed})

    (fn ensure-key [node]
        (when (not node.key)
            (set node-seq (+ node-seq 1))
            (set node.key (.. "node-" node-seq))))

    (fn canonical-node [_self node context]
        (assert node (string.format "Graph missing node for %s" context))
        (ensure-key node)
        node)

    (fn edge-key [edge]
        (.. (node-id edge.source) "->" (node-id edge.target)))

    (fn lookup [_self key]
        (and key (. nodes key)))

    (fn replace-node [_self existing node]
        (when existing.unmount
            (existing:unmount))
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
            (error "Graph.add-node requires a node"))
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
	                (when check-link-edges-for-node
	                    (check-link-edges-for-node canonical))
	                (when canonical.added
	                    (canonical:added self))
	                canonical)))

    (fn add-edge [_self edge edge-opts]
        (when (not edge)
            (error "Graph.add-edge requires an edge"))
        (assert edge.source "Graph.add-edge requires edge.source")
        (assert edge.target "Graph.add-edge requires edge.target")
        (set edge.source (canonical-node self edge.source "add-edge source"))
        (set edge.target (canonical-node self edge.target "add-edge target"))
        (local source (self:add-node edge.source))
        (local target (self:add-node edge.target))
        (set edge.source source)
        (set edge.target target)
        (local key (edge-key edge))
        (local existing (. edge-map key))
        (if existing
            (do
                (set (. edge-map key) edge)
                (for [i 1 (length edges)]
                    (when (= (. edges i) existing)
                        (set (. edges i) edge)))
                edge)
            (do
                (table.insert edges edge)
                (set (. edge-map key) edge)
                (edge-added:emit {:edge edge :opts edge-opts})
                edge)))

    (fn remove-nodes [_self nodes-to-remove]
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
                    (each [entity-id mapped-key (pairs link-edge-map)]
                        (when (= mapped-key removed-key)
                            (set (. link-edge-map entity-id) nil)))
                    (edge-removed:emit {:edge edge}))
                (node-removed:emit {:nodes removed :removal-set removal-set})
                (each [_ node (ipairs removed)]
                    (set (. nodes node.key) nil)
                    (when node.unmount
                        (node:unmount))
                    (when node.drop
                        (node:drop)))
                (length removed))))

    (set self.add-node add-node)
    (set self.add-edge add-edge)
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
                    (local visited (or options.visited {}))
                    (local max-depth (or options.max-depth 32))
                    (var current key)
                    (var depth 0)
                    (while true
                        (when (>= depth max-depth)
                            (lua "return current"))
                        (when (. visited current)
                            (error (.. "resolve-key identity cycle detected at " current)))
                        (set (. visited current) true)
                        (local node (or (. nodes current)
                                        (self:load-by-key current)))
                        (if (not (and node node.identity-target-key))
                            (lua "return current")
                            (do
                                (local next-key (tostring (or node.identity-target-key "")))
                                (if (> (string.len next-key) 0)
                                    (do
                                        (set current next-key)
                                        (set depth (+ depth 1)))
                                    (lua "return current")))))))))

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
                (or (. nodes resolved-key)
                    (self:load-by-key resolved-key)))))

    (fn key-scheme [key]
        (KeyLoaderUtils.key-scheme key))

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

    (set self.register-key-loader
        (fn [_self scheme loader-fn opts]
            (register-key-loader self key-loaders
                                 (fn []
                                     (set key-loader-registration-seq (+ key-loader-registration-seq 1))
                                     key-loader-registration-seq)
                                 scheme loader-fn opts)))

    (set self.unregister-key-loader
        (fn [_self handle-or-scheme opts]
            (unregister-key-loader key-loaders handle-or-scheme opts)))

    (set self.key-loader-owner
        (fn [_self scheme]
            (assert (= (type scheme) "string") "key-loader-owner requires string scheme")
            (local registration (. key-loaders scheme))
            (and registration registration.owner-id)))

    (set self.load-by-key
        (fn [_self key]
            (when (not key) (lua "return nil"))
            (assert (= (type key) "string") "load-by-key requires string key")
            (local existing (. nodes key))
            (when existing (lua "return existing"))
            (local scheme (key-scheme key))
            (local registration (. key-loaders scheme))
            (when (not registration) (lua "return nil"))
            (local node (registration.loader-fn key))
            (when node
                (assert (. node :key) "load-by-key loader must return node with key")
                (assert (= (. node :key) key)
                        (.. "load-by-key loader returned mismatched key: expected " key
                            " got " (tostring (. node :key))))
                (add-node self node))
            node))

    (set self.create-node-by-key
        (fn [_self key]
            (when (not key) (lua "return nil"))
            (assert (= (type key) "string") "create-node-by-key requires string key")
            (local scheme (key-scheme key))
            (local registration (. key-loaders scheme))
            (when (not registration) (lua "return nil"))
            (local node (registration.loader-fn key))
            (when node
                (assert (. node :key) "create-node-by-key loader must return node with key")
                (assert (= (. node :key) key)
                        (.. "create-node-by-key loader returned mismatched key: expected " key
                            " got " (tostring (. node :key)))))
            node))

    (set self.has-key-loader-for-key
        (fn [_self key]
            (when (not key) (lua "return false"))
            (assert (= (type key) "string") "has-key-loader-for-key requires string key")
            (local scheme (key-scheme key))
            (not (= (. key-loaders scheme) nil))))

    (set self.capture-state
        (fn [_self]
            (local node-keys
                (icollect [key _ (pairs nodes)]
                    key))
            (table.sort node-keys)
            (local edge-keys {})
            (local edge-list [])
            (each [_ edge (ipairs edges)]
                (local source-key (and edge edge.source edge.source.key))
                (local target-key (and edge edge.target edge.target.key))
                (when (and source-key target-key)
                    (local composite (.. source-key "->" target-key))
                    (when (not (. edge-keys composite))
                        (set (. edge-keys composite) true)
                        (table.insert edge-list {:source source-key
                                                 :target target-key}))))
            (table.sort edge-list
                        (fn [a b]
                            (local a-key (.. (or a.source "") "->" (or a.target "")))
                            (local b-key (.. (or b.source "") "->" (or b.target "")))
                            (< a-key b-key)))
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
            (table.sort edge-list
                        (fn [a b]
                            (local a-key (.. (or a.source "") "->" (or a.target "")))
                            (local b-key (.. (or b.source "") "->" (or b.target "")))
                            (< a-key b-key)))
            {:nodes node-keys
             :edges edge-list}))

    (fn resolve-restored-node [key]
        (local node (or (lookup self key)
                        (self:load-by-key key)))
        (if node
            (for [idx (length unresolved-restored-node-keys) 1 -1]
                (when (= (. unresolved-restored-node-keys idx) key)
                    (table.remove unresolved-restored-node-keys idx)))
            (do
                (record-unresolved-restored-node key)
                (logging.warn (.. "[graph] skipping unresolved restored node: " key))))
        node)

    (set self.restore-state
        (fn [_self state]
            (local payload (or state {}))
            (local node-keys (or payload.nodes []))
            (local edge-list (or payload.edges []))
            (set unresolved-restored-node-keys [])
            (set unresolved-restored-edge-list [])
            (assert (= (type node-keys) :table) "Graph.restore-state requires :nodes table")
            (assert (= (type edge-list) :table) "Graph.restore-state requires :edges table")
            (each [_ key (ipairs node-keys)]
                (assert (= (type key) :string) "Graph.restore-state node keys must be strings")
                (when (not (lookup self key))
                    (resolve-restored-node key)))
            (each [_ edge (ipairs edge-list)]
                (assert (= (type edge) :table) "Graph.restore-state edge entries must be tables")
                (local source-key edge.source)
                (local target-key edge.target)
                (assert (= (type source-key) :string)
                        "Graph.restore-state edge.source must be a string")
                (assert (= (type target-key) :string)
                        "Graph.restore-state edge.target must be a string")
                (local source-node (resolve-restored-node source-key))
                (local target-node (resolve-restored-node target-key))
                (if (not source-node)
                    (do
                        (record-unresolved-restored-edge source-key target-key)
                        (logging.warn (.. "[graph] skipping restored edge with unresolved source: " source-key)))
                    (if (not target-node)
                        (do
                            (record-unresolved-restored-edge source-key target-key)
                            (logging.warn (.. "[graph] skipping restored edge with unresolved target: " target-key)))
                        (self:add-edge (GraphEdge {:source source-node
                                                   :target target-node})))))
            true))

    (set Graph.GraphNode GraphNode)
    (set Graph.GraphEdge GraphEdge)

    ;; Entity store integration
    (local link-store (or options.link-store (LinkEntityStore.get-default)))
    (local identity-store (or options.identity-store (IdentityStore.get-default)))
    (local string-store (or options.string-store (StringEntityStore.get-default)))
    (local morphs (or options.morphs (Morphs.get-default)))
    (set self.link-store link-store)
    (set self.identity-store identity-store)
    (set self.string-store string-store)
    (set self.morphs morphs)
    (set self.create-identity
        (fn [_self target-key opts]
            (local create-opts (or opts {}))
            (local entity (identity-store:create-entity {:id create-opts.id
                                                         :target-key (or target-key "")
                                                         :metadata (or create-opts.metadata {})}))
            (local key (.. "identity:" (tostring entity.id)))
            (var node (. nodes key))
            (when (not node)
                (if self.load-by-key
                    (set node (self:load-by-key key))
                    nil)
                (when (not node)
                    (local {:IdentityNode IdentityNode} (require :graph/nodes/identity))
                    (set node (IdentityNode {:entity-id entity.id
                                             :store identity-store}))
                    (self:add-node node create-opts)))
            (when (and create-opts.source-node node self.add-edge)
                (self:add-edge (GraphEdge {:source create-opts.source-node
                                           :target node})))
            node))

    (set self.ensure-identity-key
        (fn [_self target-key opts]
            (local options (or opts {}))
            (local key (tostring (or target-key "")))
            (if (or (= (string.len key) 0)
                    (= (string.sub key 1 9) "identity:"))
                key
                (do
                    (local existing
                        (if identity-store.find-by-target-key
                            (identity-store:find-by-target-key key)
                            nil))
                    (if existing
                        (.. "identity:" (tostring existing.id))
                        (do
                            (local node (self:create-identity key options))
                            (if (and node node.key)
                                node.key
                                key)))))))

    (fn add-link-edge-for-entity [entity entity-id]
        (local source-key (self:resolve-key entity.source-key))
        (local target-key (self:resolve-key entity.target-key))
        (var source-node (. nodes source-key))
        (var target-node (. nodes target-key))
        (when (and (not source-node) source-key)
            (set source-node (self:load-by-key source-key)))
        (when (and (not target-node) target-key)
            (set target-node (self:load-by-key target-key)))
        (when (and source-node target-node)
            (local label (or (and entity.metadata entity.metadata.name) ""))
            (local edge (GraphEdge {:source source-node
                                    :target target-node
                                    :color (glm.vec4 0.45 0.42 0.3 1)
                                    :label label}))
            (self:add-edge edge {:from-link-entity entity.id})
            (set (. link-edge-map entity-id) (edge-key edge))))

    (fn maybe-add-link-edge [entity]
        (if (not (and entity entity.source-key entity.target-key
                      (> (string.len entity.source-key) 0)
                      (> (string.len entity.target-key) 0)))
            nil
            (do
                (local entity-id (tostring entity.id))
                (when (. link-edge-map entity-id)
                    (lua "return nil"))
                (when (. link-edge-loading entity-id)
                    (lua "return nil"))
                (set (. link-edge-loading entity-id) true)
                (local (ok err)
                    (pcall (fn [] (add-link-edge-for-entity entity entity-id))))
                (set (. link-edge-loading entity-id) nil)
                (assert ok err))))

    (fn maybe-remove-link-edge [entity]
        (local entity-id (tostring (and entity entity.id)))
        (local stored-key (. link-edge-map entity-id))
        (when stored-key
            (local edge (. edge-map stored-key))
            (when edge
                ;; Remove edge from edges list and edge-map
                (for [i (length edges) 1 -1]
                    (when (= (. edges i) edge)
                        (table.remove edges i)))
                (set (. edge-map stored-key) nil)
                (edge-removed:emit {:edge edge}))
            (set (. link-edge-map entity-id) nil)))

    (set check-link-edges-for-node
        (fn [node]
            (when (and node node.key)
                (local all-keys (icollect [k _ (pairs nodes)] k))
                (local link-entities (link-store:find-edges-for-nodes all-keys))
                (each [_ entity (ipairs link-entities)]
                    (when (not (. link-edge-map (tostring entity.id)))
                        (maybe-add-link-edge entity))))))

    (var link-created-handler nil)
    (var link-updated-handler nil)
    (var link-deleted-handler nil)
    (var string-entity-created-handler nil)

    (fn refresh-link-edges-for-key [key]
        (local key-str (tostring (or key "")))
        (when (> (string.len key-str) 0)
            (local entities (link-store:find-entities-for-key key-str))
            (each [_ entity (ipairs (or entities []))]
                (maybe-remove-link-edge entity)
                (maybe-add-link-edge entity))))

    (var identity-updated-handler nil)
    (var identity-deleted-handler nil)
    (var morph-handler nil)

    (when entity-events?
        (set link-created-handler
            (link-store.link-entity-created:connect
                (fn [entity]
                    (maybe-add-link-edge entity))))

        (set link-updated-handler
            (link-store.link-entity-updated:connect
                (fn [entity]
                    (maybe-remove-link-edge entity)
                    (maybe-add-link-edge entity))))

        (set link-deleted-handler
            (link-store.link-entity-deleted:connect
                (fn [entity]
                    (maybe-remove-link-edge entity))))

        (set string-entity-created-handler
            (string-store.string-entity-created:connect
                (fn [entity]
                    (when (and entity entity.id)
                        (self:load-by-key (.. "string-entity:" (tostring entity.id)))))))

        (set identity-updated-handler
            (identity-store.identity-updated:connect
                (fn [entity]
                    (local key (.. "identity:" (tostring entity.id)))
                    (refresh-link-edges-for-key key))))

        (set identity-deleted-handler
            (identity-store.identity-deleted:connect
                (fn [entity]
                    (local key (.. "identity:" (tostring entity.id)))
                    (refresh-link-edges-for-key key))))

        (when (and morphs morphs.morphed)
            (set morph-handler
                (morphs.morphed:connect
                    (fn [payload]
                        (local result (or (and payload payload.result) {}))
                        (local source-key (or payload.source-key result.source-key))
                        (local target-key (or result.target-key result.code-key))
                        (local source-node (and source-key (. nodes source-key)))
                        (when (and source-node self.remove-nodes)
                            (self:remove-nodes [source-node]))
                        (when (and target-key self.load-by-key)
                            (self:load-by-key target-key))
                        (node-morphed:emit {:source-key source-key
                                            :target-key target-key
                                            :payload payload}))))))

    ;; Removed node-added listener as it is now called directly in add-node

    (fn disconnect-entity-handlers []
        (when link-created-handler
            (link-store.link-entity-created:disconnect link-created-handler true)
            (set link-created-handler nil))
        (when link-updated-handler
            (link-store.link-entity-updated:disconnect link-updated-handler true)
            (set link-updated-handler nil))
        (when link-deleted-handler
            (link-store.link-entity-deleted:disconnect link-deleted-handler true)
            (set link-deleted-handler nil))
        (when string-entity-created-handler
            (string-store.string-entity-created:disconnect string-entity-created-handler true)
            (set string-entity-created-handler nil))
        (when identity-updated-handler
            (identity-store.identity-updated:disconnect identity-updated-handler true)
            (set identity-updated-handler nil))
        (when identity-deleted-handler
            (identity-store.identity-deleted:disconnect identity-deleted-handler true)
            (set identity-deleted-handler nil))
        (when (and morphs morphs.morphed morph-handler)
            (morphs.morphed:disconnect morph-handler true)
            (set morph-handler nil)))

    (set self.drop
        (fn [_self]
            (each [_ node (pairs nodes)]
                (when node.unmount
                    (node:unmount))
                (when node.drop
                    (node:drop)))
            (for [i (length edges) 1 -1]
                (table.remove edges i))
            (each [k _ (pairs edge-map)]
                (set (. edge-map k) nil))
            (each [k _ (pairs nodes)]
                (set (. nodes k) nil))
            (node-added:clear)
            (node-removed:clear)
            (node-replaced:clear)
            (node-morphed:clear)
            (edge-added:clear)
            (edge-removed:clear)
            (disconnect-entity-handlers)))

    (when self.with-start
        (local start (StartNode))
        (set start.auto-focus? true)
        (self:add-node start {:auto-focus? true})
        (set self.start start))

    self)

(set Graph.GraphNode GraphNode)
(set Graph.GraphEdge GraphEdge)
(set Graph.StartNode StartNode)
(set Graph.ClassNode ClassNode)
(set Graph.QuitNode QuitNode)
(set Graph.create create-graph)
(setmetatable Graph {:__call (fn [_ opts] (create-graph opts))})

Graph
