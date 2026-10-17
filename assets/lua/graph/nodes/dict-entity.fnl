(local glm (require :glm))
(local {:GraphNode GraphNode
        :node-id node-id} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local DictEntityStore (require :entities/dict))
(local Utils (require :graph/view/utils))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local TEAL (glm.vec4 0.0 0.55 0.45 1))
(local TEAL_ACCENT (glm.vec4 0.05 0.65 0.55 1))

(local SCHEME "dict-entity")
(local KEY_PREFIX (KeyLoaderUtils.key-prefix SCHEME))
(local IDENTITY_KEY_PREFIX (KeyLoaderUtils.key-prefix "identity"))

(fn options-table [opts]
  (if (= (type opts) "table") opts {}))

(fn entity-items [entity]
  (if (and entity (= (type entity.items) "table")) entity.items {}))

(fn fallback-string [value fallback]
  (if value value fallback))

(fn custom-name [entity]
  (local name (and entity entity.name))
  (if (and name (> (string.len name) 0)) name nil))

(fn item-values [entity]
  (local result [])
  (each [_ value (pairs (entity-items entity))]
    (table.insert result (tostring value)))
  result)

(fn item-value-set [entity]
  (local result {})
  (each [_ value (ipairs (item-values entity))]
    (set (. result value) true))
  result)

(fn make-label [entity]
  (local name (custom-name entity))
  (if name
      (Utils.truncate-with-ellipsis name 50)
      (fallback-string (and entity entity.id) "dict entity")))

(fn make-compact-label [entity]
  (local name (custom-name entity))
  (if name
      (Utils.truncate-with-ellipsis name 50)
      false))

(fn edge-key [source target]
  (.. (node-id source) "->" (node-id target)))

(fn remove-edge-by-key [graph key]
  (when (and graph graph.edges graph.edge-map key)
    (local existing (. graph.edge-map key))
    (when existing
      (for [i (length graph.edges) 1 -1]
        (when (= (. graph.edges i) existing)
          (table.remove graph.edges i)))
      (set (. graph.edge-map key) nil)
      (when (and graph.edge-removed graph.edge-removed.emit)
        (graph.edge-removed:emit {:edge existing})))))

(fn identity-key? [key]
  (and (= (type key) "string")
       (= (string.sub key 1 (string.len IDENTITY_KEY_PREFIX)) IDENTITY_KEY_PREFIX)))

(fn identity-id-from-key [key]
  (if (identity-key? key)
      (string.sub key (+ (string.len IDENTITY_KEY_PREFIX) 1))
      nil))

(fn identity-target-key [identity-store item-key]
  (local identity-id (identity-id-from-key item-key))
  (if (and identity-id identity-store identity-store.get-entity)
      (do
        (local identity-entity (identity-store:get-entity identity-id))
        (local target-key (and identity-entity identity-entity.target-key))
        (if (and target-key (> (string.len (tostring target-key)) 0))
            target-key
            nil))
      nil))

(fn load-visible-node [graph key]
  (if (not graph)
      nil
      (if graph.resolve-node
          (graph:resolve-node key)
          (if graph.load-by-key
              (graph:load-by-key key)
              nil))))

(fn resolve-item-target [self item-key]
  (local graph self.graph)
  (local direct (load-visible-node graph item-key))
  (if direct
      direct
      (do
        (local target-key (identity-target-key self.identity-store item-key))
        (if target-key
            (load-visible-node graph target-key)
            nil))))

(fn entity-contains-value? [entity node-key]
  (local key (tostring node-key))
  (var found? false)
  (each [_ value (pairs (entity-items entity))]
    (when (= (tostring value) key)
      (set found? true)))
  found?)

(fn contains-identity-value? [items]
  (var found? false)
  (each [_ value (pairs (if (= (type items) "table") items {}))]
    (when (identity-key? value)
      (set found? true)))
  found?)

(fn node-options [opts]
  (local options (options-table opts))
  (local entity-id (assert options.entity-id "DictEntityNode requires entity-id"))
  (local store (if options.store options.store (DictEntityStore.get-default)))
  (local identity-store (assert store.identity-store "DictEntityNode store requires identity-store"))
  (assert (or (not options.identity-store) (= options.identity-store identity-store))
          "DictEntityNode identity-store mismatch with owning store")
  (values options entity-id identity-store store))

(fn refresh-label [self]
  (local current (self.store:get-entity self.entity-id))
  (set self.label (make-label current))
  (set self.compact-label (make-compact-label current))
  (self.changed:emit self))

(fn refresh-items [self resolve-target]
  (assert self.dict-item-edge-keys "dictionary projection requires native edge ownership bookkeeping")
  (local graph self.graph)
  (when (and graph graph.add-edge)
    (local current (self:get-entity))
    (local desired {})
    (each [item-key item-value (pairs (entity-items current))]
      (local target (resolve-target self item-value))
      (when target
        (local key (edge-key self target))
        (local existing (. graph.edge-map key))
        (local edge (or existing (graph:add-edge (GraphEdge {:source self :target target})
                                               {:from-dict-entity self.entity-id :item-key item-key})))
        (when (or (not existing) (= existing (. self.dict-item-edge-keys key))) (tset desired key edge))))
    (each [k owned (pairs (if self.dict-item-edge-keys self.dict-item-edge-keys {}))]
      (when (and (not (. desired k)) (= (. graph.edge-map k) owned))
        (remove-edge-by-key graph k)))
    (set self.dict-item-edge-keys desired)))

(fn add-item-nodes [self] (refresh-items self resolve-item-target))
(fn refresh-reference-projection! [self]
  (fn participating-target [owner key]
    (owner.graph:lookup (owner.identity-store:resolve-key key)))
  (refresh-items self participating-target))

(fn added [self _graph]
  (self:add-item-nodes)
  self)

(fn make-deleted-handler [node entity-id]
  (fn [deleted]
    (when (= (tostring deleted.id) (tostring entity-id))
      (node.entity-deleted:emit deleted)
      (when (and node.graph node.graph.remove-nodes)
        (node.graph:remove-nodes [node] {:cause "shared-delete"})))))

(fn make-updated-handler [node entity-id]
  (fn [updated]
    (when (= (tostring updated.id) (tostring entity-id))
      (node:refresh-label))))

(fn payload-id [payload]
  (if (and payload payload.id) payload.id ""))

(fn make-items-handler [node entity-id]
  (fn [payload]
    (when (= (tostring (payload-id payload)) (tostring entity-id))
      (node.items-changed:emit payload)
      (node:add-item-nodes))))

(fn should-refresh-for-added? [self added]
  (if (and added (not (= (tostring added.key) (tostring self.key))))
      (do
        (local current (self:get-entity))
        (and current
             (if (entity-contains-value? current added.key)
                 true
                 (contains-identity-value? current.items))))
      false))

(fn make-graph-node-added-handler [self]
  (fn [payload]
    (local added (and payload payload.node))
    (when (should-refresh-for-added? self added)
      (self:refresh-reference-projection!))))

(fn make-identity-updated-handler [self]
  (fn [identity]
    (local identity-key (.. IDENTITY_KEY_PREFIX (tostring identity.id)))
    (local current (self:get-entity))
    (when (and current (entity-contains-value? current identity-key))
      (self.items-changed:emit {:id self.entity-id :items current.items}))
    (self:refresh-reference-projection!)))

(fn install-store-handlers [node store entity-id]
  {:deleted (store.dict-entity-deleted:connect (make-deleted-handler node entity-id))
   :updated (store.dict-entity-updated:connect (make-updated-handler node entity-id))
   :items (store.dict-entity-items-changed:connect (make-items-handler node entity-id))})

(fn disconnect-handler [signal handler]
  (when handler
    (signal:disconnect handler true)))

(fn install-node-methods [node]
  (set node.refresh-label refresh-label)
  (set node.get-entity (fn [self] (self.store:get-entity self.entity-id)))
  (set node.get-item (fn [self item-key] (self.store:get-item self.entity-id item-key)))
  (set node.update-name
       (fn [self new-name]
         (self.store:update-entity self.entity-id {:name new-name})
         (self:refresh-label)))
  (set node.set-item
       (fn [self item-key node-key]
          (self.store:set-item self.entity-id item-key node-key)
         (self:add-item-nodes)))
  (set node.remove-item
       (fn [self item-key]
         (self.store:remove-item self.entity-id item-key)
         (self:add-item-nodes)))
  (set node.rename-item
       (fn [self old-key new-key]
         (self.store:rename-item self.entity-id old-key new-key)
         (self:add-item-nodes)))
  (set node.delete-entity (fn [self]
    (local service (self:resolve-reference-lifecycle!))
    (. (service:delete! self.key) :source-record)))
  (set node.add-item-nodes add-item-nodes)
  (set node.refresh-reference-projection! refresh-reference-projection!)
  (set node.added added)
  node)

(fn resolve-reference-lifecycle! [self]
  (local mounted (and self.graph self.graph.reference-lifecycle))
  (assert (or (not self.lifecycle) (not mounted) (= self.lifecycle mounted)) "reference lifecycle node/graph conflict")
  (local service (assert (or self.lifecycle mounted) "node requires reference lifecycle"))
  (assert (service:owns-store? SCHEME self.store) "reference lifecycle store ownership mismatch")
  service)

(fn DictEntityNode [opts]
  (local (options entity-id identity-store store) (node-options opts))
  (local DictEntityNodeView (require :graph/view/views/dict-entity))
  (local entity (store:get-entity entity-id))
  (local node
    (GraphNode {:key (.. KEY_PREFIX entity-id)
                :label (make-label entity)
                :color TEAL
                :sub-color TEAL_ACCENT
                :size 8.0
                :view DictEntityNodeView}))

  (set node.entity-id entity-id)
  (set node.compact-label (make-compact-label entity))
  (set node.identity-store identity-store)
  (set node.store store)
  (set node.lifecycle options.lifecycle)
  (set node.resolve-reference-lifecycle! resolve-reference-lifecycle!)
  (set node.entity-deleted (Signal))
  (set node.changed (Signal))
  (set node.items-changed (Signal))
  (set node.dict-item-edge-keys {})

  (install-node-methods node)

  (set node.actions
       [{:name "Refresh Items"
         :icon "refresh"
         :fn (fn [_button _event] (node:add-item-nodes))}
        {:name "Delete Entity"
         :icon "delete"
         :fn (fn [_button _event] (node:delete-entity))}])

  (local store-handlers (install-store-handlers node store entity-id))
  (var graph-node-added-handler nil)
  (var graph-node-added-signal nil)
  (var identity-updated-handler nil)

  (local mount node.mount)
  (set node.mount
       (fn [self graph]
         (mount self graph)
         (local signal (and graph graph.node-added))
         (when (and signal (not graph-node-added-handler))
           (set graph-node-added-signal signal)
           (set graph-node-added-handler
                (signal:connect (make-graph-node-added-handler self))))
         (when (and self.identity-store self.identity-store.identity-updated (not identity-updated-handler))
           (set identity-updated-handler
                (self.identity-store.identity-updated:connect (make-identity-updated-handler self))))
         self))

  (set node.drop
       (fn [self]
         (when (and graph-node-added-signal graph-node-added-handler)
           (graph-node-added-signal:disconnect graph-node-added-handler true)
           (set graph-node-added-handler nil))
         (disconnect-handler store.dict-entity-deleted store-handlers.deleted)
         (disconnect-handler store.dict-entity-updated store-handlers.updated)
         (disconnect-handler store.dict-entity-items-changed store-handlers.items)
         (when identity-updated-handler
           (self.identity-store.identity-updated:disconnect identity-updated-handler true)
           (set identity-updated-handler nil))
         (self.entity-deleted:clear)
         (self.items-changed:clear)
         (self.changed:clear)))

  node)

(local register-loader
  (fn [graph opts]
    (local options (options-table opts))
    (local store (if options.store options.store (DictEntityStore.get-default)))
    (local identity-store (if options.identity-store options.identity-store store.identity-store))
    (graph:register-key-loader SCHEME
      (fn [key]
        (local entity-id (KeyLoaderUtils.extract-id SCHEME key))
        (when entity-id
          (local entity (store:get-entity entity-id))
          (when entity
            (DictEntityNode {:entity-id entity-id
                             :store store
                             :identity-store identity-store :lifecycle options.lifecycle})))))))

{:DictEntityNode DictEntityNode
 :register-loader register-loader
 :item-values item-values
 :item-value-set item-value-set}
