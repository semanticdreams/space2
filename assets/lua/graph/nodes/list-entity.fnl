(local glm (require :glm))
(local {:GraphNode GraphNode
        :node-id node-id} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local IdentityStore (require :entities/identity))
(local ListEntityStore (require :entities/list))
(local Utils (require :graph/view/utils))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local CYAN (glm.vec4 0.0 0.6 0.7 1))
(local CYAN_ACCENT (glm.vec4 0.05 0.65 0.75 1))

(local SCHEME "list-entity")
(local KEY_PREFIX (KeyLoaderUtils.key-prefix SCHEME))
(local IDENTITY_KEY_PREFIX (KeyLoaderUtils.key-prefix "identity"))

(fn make-label [entity]
  (local name (or (and entity entity.name) ""))
  (if (> (string.len name) 0)
      (Utils.truncate-with-ellipsis name 50)
      (or (and entity entity.id) "list entity")))

(fn edge-key [source target]
  (.. (node-id source) "->" (node-id target)))

(fn ordered-list-island-id [entity-id]
  (.. "ordered-list:" (tostring entity-id)))

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

(fn entity-contains-node-key? [entity node-key]
  (local key (tostring node-key))
  (var found? false)
  (each [_ value (ipairs (or (and entity entity.items) []))]
    (when (= (tostring value) key)
      (set found? true)))
  found?)

(fn payload-updated-identity-key-set [payload]
  (local result (or (and payload payload.payload payload.payload.result)
                    (and payload payload.result)
                    {}))
  (local keys (or result.updated-identity-keys []))
  (local key-set {})
  (each [_ key (ipairs keys)]
    (set (. key-set (tostring key)) true))
  key-set)

(fn entity-affected-by-morph? [entity payload]
  (local items (or (and entity entity.items) []))
  (local updated-keys (payload-updated-identity-key-set payload))
  (if (next updated-keys)
      (do
        (var affected? false)
        (each [_ key (ipairs items)]
          (when (. updated-keys (tostring key))
            (set affected? true)))
        affected?)
      false))

(fn identity-key? [key]
  (and (= (type key) "string")
       (= (string.sub key 1 (string.len IDENTITY_KEY_PREFIX)) IDENTITY_KEY_PREFIX)))

(fn contains-identity-item? [items]
  (var found? false)
  (each [_ value (ipairs (or items []))]
    (when (identity-key? value)
      (set found? true)))
  found?)

(fn identity-id-from-key [key]
  (if (identity-key? key)
      (string.sub key (+ (string.len IDENTITY_KEY_PREFIX) 1))
      nil))

(fn load-visible-node [graph key]
  (if (not graph)
      nil
      (if graph.resolve-node
          (graph:resolve-node key)
          (if graph.load-by-key
              (graph:load-by-key key)
              nil))))

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

(fn ListEntityNode [opts]
  (local options (or opts {}))
  (local entity-id (assert options.entity-id "ListEntityNode requires entity-id"))
  (local identity-store (or options.identity-store (IdentityStore.get-default)))
  (local store (or options.store (ListEntityStore.get-default)))
  (local ListEntityNodeView (require :graph/view/views/list-entity))

  (local entity (store:get-entity entity-id))
  (local initial-label (make-label entity))

  (local node
    (GraphNode {:key (.. KEY_PREFIX entity-id)
                :label initial-label
                :color CYAN
                :sub-color CYAN_ACCENT
                :size 8.0
                :view ListEntityNodeView}))

  (set node.entity-id entity-id)
  (set node.identity-store identity-store)
  (set node.store store)
  (set node.entity-deleted (Signal))
  (set node.changed (Signal))
  (set node.items-changed (Signal))
  (set node.list-item-edge-keys {})

  (fn refresh-label [self]
    (local current (self.store:get-entity self.entity-id))
    (set self.label (make-label current))
    (when self.changed
      (self.changed:emit self)))

  (set node.refresh-label refresh-label)

  (set node.get-entity
       (fn [self]
         (self.store:get-entity self.entity-id)))

  (fn ensure-identity-key [self node-key]
    (local key (tostring (or node-key "")))
    (if (= (string.len key) 0)
        key
        (if (= (string.sub key 1 (string.len IDENTITY_KEY_PREFIX)) IDENTITY_KEY_PREFIX)
            key
            (do
              (local graph self.graph)
              (if (and graph graph.ensure-identity-key)
                  (graph:ensure-identity-key key)
                  (do
                    (local existing
                      (if self.identity-store.find-by-target-key
                          (self.identity-store:find-by-target-key key)
                          nil))
                    (if existing
                        (.. IDENTITY_KEY_PREFIX (tostring existing.id))
                        (.. IDENTITY_KEY_PREFIX
                            (tostring (. (self.identity-store:create-entity {:target-key key}) :id))))))))))

  (set node.add-item-nodes
       (fn [self]
         (local graph self.graph)
         (when (and graph graph.load-by-key graph.add-edge)
            (local current (self:get-entity))
            (local items (or (and current current.items) []))
            (local desired {})
            (each [_ item-key (ipairs items)]
              (local target (resolve-item-target self item-key))
              (when target
                (graph:add-edge (GraphEdge {:source self :target target})
                                {:from-list-entity self.entity-id})
               (set (. desired (edge-key self target)) true)))
           (each [k _ (pairs (or self.list-item-edge-keys {}))]
             (when (not (. desired k))
               (remove-edge-by-key graph k)))
            (set self.list-item-edge-keys desired))))

  (set node.expand-items-as-island
       (fn [self _opts]
         (local graph self.graph)
         (assert (and graph graph.load-by-key graph.upsert-island)
                 "ListEntityNode.expand-items-as-island requires mounted graph map with load-by-key and upsert-island")
         (local current (self:get-entity))
         (local items (or (and current current.items) []))
         (local members [])
         (each [_ item-key (ipairs items)]
           (local target (resolve-item-target self item-key))
           (when (and target target.key)
             (table.insert members (tostring target.key))))
         (graph:upsert-island {:id (ordered-list-island-id self.entity-id)
                               :kind "ordered-list"
                               :members members
                               :state {:list-key self.key
                                       :interaction-policy "snap-back"
                                       :spacing 24}})))

  (set node.update-name
       (fn [self new-name]
         (self.store:update-entity self.entity-id {:name new-name})
         (self:refresh-label)))

  (set node.add-item
       (fn [self node-key]
         (local stable-key (ensure-identity-key self node-key))
         (self.store:add-item self.entity-id stable-key)
         (self:add-item-nodes)))

  (set node.remove-item
       (fn [self node-key]
         (self.store:remove-item self.entity-id node-key)
         (self:add-item-nodes)))

  (set node.move-item
       (fn [self from-index to-index]
         (self.store:move-item self.entity-id from-index to-index)
         (self:add-item-nodes)))

  (set node.delete-entity
       (fn [self]
         (self.store:delete-entity self.entity-id)))

  (set node.actions
        [{:name "Refresh Items"
          :icon "refresh"
          :fn (fn [_button _event]
                  (node:add-item-nodes))}
         {:name "Expand items as island"
          :icon "format_list_numbered"
          :fn (fn [_button _event]
                  (node:expand-items-as-island))}
         {:name "Delete Entity"
          :icon "delete"
          :fn (fn [_button _event]
                 (node:delete-entity))}])

  (var deleted-handler nil)
  (var updated-handler nil)
  (var items-handler nil)
  (var identity-updated-handler nil)
  (var identity-deleted-handler nil)

  (set deleted-handler
       (store.list-entity-deleted:connect
         (fn [deleted]
           (when (= (tostring deleted.id) (tostring entity-id))
             (node.entity-deleted:emit deleted)
              (when (and node.graph node.graph.remove-nodes)
                (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))

  (set updated-handler
       (store.list-entity-updated:connect
         (fn [updated]
           (when (= (tostring updated.id) (tostring entity-id))
             (node:refresh-label)))))

  (fn refresh-existing-island [self]
    (local graph self.graph)
    (when (and graph graph.get-island (graph:get-island (ordered-list-island-id self.entity-id)))
      (self:expand-items-as-island)))

  (fn handle-items-changed [payload]
    (local id (or (and payload payload.id) ""))
    (when (= (tostring id) (tostring entity-id))
      (node.items-changed:emit payload)
      (node:add-item-nodes)
      (refresh-existing-island node)))

  (set items-handler
       (store.list-entity-items-changed:connect handle-items-changed))

  (set node.added
       (fn [self _graph]
         (self:add-item-nodes)
         self))

  (var graph-node-added-handler nil)
  (var graph-node-added-signal nil)
  (var graph-node-removed-handler nil)
  (var graph-node-removed-signal nil)
  (var graph-node-morphed-handler nil)
  (var graph-node-morphed-signal nil)

  (local mount node.mount)
  (set node.mount
       (fn [self graph]
         (mount self graph)
         (local signal (and graph graph.node-added))
         ;; When item nodes are added later, attach edges from this list node if relevant.
         (when (and signal (not graph-node-added-handler))
           (set graph-node-added-signal signal)
           (set graph-node-added-handler
                (signal:connect
                  (fn [payload]
                    (local added (and payload payload.node))
                    (when (and added (not (= (tostring added.key) (tostring self.key))))
                      (local entity (self:get-entity))
                      (when entity
                        (if (entity-contains-node-key? entity added.key)
                            (self:add-item-nodes)
                            (when (contains-identity-item? entity.items)
                              ;; Identity targets can appear after identity store updates.
                              (self:add-item-nodes)))))))))
          (local removed-signal (and graph graph.node-removed))
          (when (and removed-signal (not graph-node-removed-handler))
            (set graph-node-removed-signal removed-signal)
            (set graph-node-removed-handler
                 (removed-signal:connect
                   (fn [payload]
                     (when (not payload.map-only?)
                       (each [_ removed-node (ipairs (or (and payload payload.nodes) []))]
                         (local removed-key (and removed-node removed-node.key))
                         (when (and removed-key (not (identity-key? removed-key)))
                           (local entity (self:get-entity))
                           (when (and entity (entity-contains-node-key? entity removed-key))
                             (self:remove-item removed-key)))))))))
         (local morphed-signal (and graph graph.node-morphed))
         (when (and morphed-signal (not graph-node-morphed-handler))
           (set graph-node-morphed-signal morphed-signal)
           (set graph-node-morphed-handler
                (morphed-signal:connect
                  (fn [payload]
                    (local current (self:get-entity))
                    (when (and current (entity-affected-by-morph? current payload))
                       ;; Morph can transiently resolve old type during identity update.
                       ;; Refresh once more after graph finishes node replacement.
                       (self.items-changed:emit {:id self.entity-id :items current.items})
                       (self:add-item-nodes)
                       (refresh-existing-island self))))))
         (when (and self.identity-store self.identity-store.identity-updated (not identity-updated-handler))
           (set identity-updated-handler
                (self.identity-store.identity-updated:connect
                  (fn [entity]
                     (local identity-key (.. IDENTITY_KEY_PREFIX (tostring entity.id)))
                     (local current (self:get-entity))
                     (when (and current (entity-contains-node-key? current identity-key))
                       (self.items-changed:emit {:id self.entity-id :items current.items})
                       (self:add-item-nodes)
                       (refresh-existing-island self))))))
         (when (and self.identity-store self.identity-store.identity-deleted (not identity-deleted-handler))
           (set identity-deleted-handler
                (self.identity-store.identity-deleted:connect
                  (fn [entity]
                    (local identity-key (.. IDENTITY_KEY_PREFIX (tostring entity.id)))
                    (local current (self:get-entity))
                    (when (and current (entity-contains-node-key? current identity-key))
                      (self:remove-item identity-key))))))
         self))

  (set node.drop
       (fn [self]
         (when (and graph-node-added-signal graph-node-added-handler)
           (graph-node-added-signal:disconnect graph-node-added-handler true)
           (set graph-node-added-handler nil))
         (when (and graph-node-removed-signal graph-node-removed-handler)
           (graph-node-removed-signal:disconnect graph-node-removed-handler true)
           (set graph-node-removed-handler nil))
         (when (and graph-node-morphed-signal graph-node-morphed-handler)
           (graph-node-morphed-signal:disconnect graph-node-morphed-handler true)
           (set graph-node-morphed-handler nil))
         (when deleted-handler
           (store.list-entity-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when updated-handler
           (store.list-entity-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (when items-handler
           (store.list-entity-items-changed:disconnect items-handler true)
           (set items-handler nil))
         (when identity-updated-handler
           (self.identity-store.identity-updated:disconnect identity-updated-handler true)
           (set identity-updated-handler nil))
         (when identity-deleted-handler
           (self.identity-store.identity-deleted:disconnect identity-deleted-handler true)
           (set identity-deleted-handler nil))
         (self.entity-deleted:clear)
         (self.items-changed:clear)
         (when self.changed
           (self.changed:clear))))

  node)

(local register-loader
  (fn [graph opts]
    (local options (or opts {}))
    (local store (or options.store (ListEntityStore.get-default)))
    (local identity-store (or options.identity-store (IdentityStore.get-default)))
    (graph:register-key-loader SCHEME
      (fn [key]
        (local entity-id (KeyLoaderUtils.extract-id SCHEME key))
        (when entity-id
          (local entity (store:get-entity entity-id))
          (when entity
            (ListEntityNode {:entity-id entity-id
                             :store store
                             :identity-store identity-store})))))))

{:ListEntityNode ListEntityNode
 :register-loader register-loader}
