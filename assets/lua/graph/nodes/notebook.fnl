(local glm (require :glm))
(local {:GraphNode GraphNode
        :node-id node-id} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local NotebookStore (require :notebooks/store))
(local StringEntityStore (require :entities/string))
(local {:StringEntityNode StringEntityNode} (require :graph/nodes/string-entity))
(local Utils (require :graph/view/utils))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local BLUE (glm.vec4 0.35 0.45 0.9 1))
(local BLUE_ACCENT (glm.vec4 0.45 0.55 0.95 1))

(local SCHEME "notebook")
(local KEY_PREFIX (KeyLoaderUtils.key-prefix SCHEME))
(local STRING_ENTITY_KEY_PREFIX (KeyLoaderUtils.key-prefix "string-entity"))
(local IDENTITY_KEY_PREFIX (KeyLoaderUtils.key-prefix "identity"))

(fn make-label [notebook]
  (local name (or (and notebook notebook.name) ""))
  (if (> (string.len name) 0)
      (Utils.truncate-with-ellipsis name 50)
      (Utils.truncate-with-ellipsis (or (and notebook notebook.id) "notebook") 50)))

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

(fn notebook-contains-node-key? [notebook node-key]
  (local key (tostring node-key))
  (var found? false)
  (each [_ value (ipairs (or (and notebook notebook.items) []))]
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

(fn notebook-affected-by-morph? [notebook payload]
  (local items (or (and notebook notebook.items) []))
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

(fn remove-target-items! [self removed-key]
  (local current (self:get-notebook))
  (when current
    (each [_ item-key (ipairs current.items)]
      (when (= (self.identity-store:resolve-key item-key) removed-key)
        (self:remove-item item-key)))))

(fn NotebookNode [opts]
  (local options (or opts {}))
  (local notebook-id (assert options.notebook-id "NotebookNode requires notebook-id"))
  (local store (or options.store (NotebookStore.get-default)))
  (local identity-store (assert store.identity-store "NotebookNode store requires identity-store"))
  (assert (or (not options.identity-store) (= options.identity-store identity-store))
          "NotebookNode identity-store mismatch with owning store")
  (local string-store (or options.string-store (StringEntityStore.get-default)))
  (local NotebookNodeView (require :graph/view/views/notebook))

  (local notebook (store:get-notebook notebook-id))
  (local initial-label (make-label notebook))

  (local node
    (GraphNode {:key (.. KEY_PREFIX notebook-id)
                :label initial-label
                :color BLUE
                :sub-color BLUE_ACCENT
                :size 8.0
                :view NotebookNodeView}))

  (set node.notebook-id notebook-id)
  (set node.store store)
  (set node.identity-store identity-store)
  (set node.string-store string-store)
  (set node.notebook-deleted (Signal))
  (set node.changed (Signal))
  (set node.items-changed (Signal))
  (set node.notebook-item-edge-keys {})

  (fn refresh-label [self]
    (local current (self.store:get-notebook self.notebook-id))
    (set self.label (make-label current))
    (when self.changed
      (self.changed:emit self)))

  (set node.refresh-label refresh-label)

  (set node.get-notebook
       (fn [self]
         (self.store:get-notebook self.notebook-id)))

  (set node.add-item-nodes
       (fn [self]
         (local graph self.graph)
         (when (and graph graph.load-by-key graph.add-edge)
           (local current (self:get-notebook))
           (local items (or (and current current.items) []))
           (local desired {})
           (fn resolve-item-target [item-key]
             (local resolved
               (if graph.resolve-node
                   (graph:resolve-node item-key)
                   (or (graph:lookup item-key)
                       (graph:load-by-key item-key))))
             (if resolved
                 resolved
                 (do
                   (local identity-id (identity-id-from-key item-key))
                   (if (and identity-id self.identity-store self.identity-store.get-entity)
                       (do
                         (local identity-entity (self.identity-store:get-entity identity-id))
                         (local target-key (and identity-entity identity-entity.target-key))
                         (when (and target-key (> (string.len (tostring target-key)) 0))
                           (if graph.resolve-node
                               (graph:resolve-node target-key)
                               (or (graph:lookup target-key)
                                   (graph:load-by-key target-key)))))
                       nil))))
           (each [_ item-key (ipairs items)]
             (local target (resolve-item-target item-key))
             (when target
               (graph:add-edge (GraphEdge {:source self :target target})
                               {:from-notebook self.notebook-id})
               (set (. desired (edge-key self target)) true)))
           (each [k _ (pairs (or self.notebook-item-edge-keys {}))]
             (when (not (. desired k))
               (remove-edge-by-key graph k)))
           (set self.notebook-item-edge-keys desired))))

  (set node.update-name
       (fn [self new-name]
         (self.store:update-notebook self.notebook-id {:name new-name})
         (self:refresh-label)))

  (set node.add-item
       (fn [self node-key]
          (self.store:add-item self.notebook-id node-key)
         (self:add-item-nodes)))

  (set node.remove-item
       (fn [self node-key]
         (self.store:remove-item self.notebook-id node-key)
         (self:add-item-nodes)))

  (set node.move-item
       (fn [self from-index to-index]
         (self.store:move-item self.notebook-id from-index to-index)
         (self:add-item-nodes)))

  (set node.delete-notebook
       (fn [self]
         (self.store:delete-notebook self.notebook-id)))

  (set node.add-string-entity
       (fn [self opts]
         (local entity (self.string-store:create-entity (or opts {})))
         (local entity-key (.. STRING_ENTITY_KEY_PREFIX (tostring entity.id)))
         (self:add-item entity-key)
         (local graph self.graph)
         (when (and graph (not (graph:lookup entity-key)))
           (local entity-node (StringEntityNode {:entity-id entity.id
                                                 :store self.string-store}))
           (graph:add-edge (GraphEdge {:source self :target entity-node})
                           {:from-notebook self.notebook-id})
           (set (. self.notebook-item-edge-keys (edge-key self entity-node)) true))
         entity))

  (set node.actions
       [{:name "Refresh Items"
         :icon "refresh"
         :fn (fn [_button _event]
                 (node:add-item-nodes))}
        {:name "Add String Entity"
         :icon "add"
         :fn (fn [_button _event]
                 (node:add-string-entity {}))}
        {:name "Delete Notebook"
         :icon "delete"
         :fn (fn [_button _event]
               (node:delete-notebook))}])

  (var deleted-handler nil)
  (var updated-handler nil)
  (var items-handler nil)
  (var identity-updated-handler nil)
  (var identity-deleted-handler nil)

  (set deleted-handler
       (store.notebook-deleted:connect
         (fn [deleted]
           (when (= (tostring deleted.id) (tostring notebook-id))
             (node.notebook-deleted:emit deleted)
              (when (and node.graph node.graph.remove-nodes)
                (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))

  (set updated-handler
       (store.notebook-updated:connect
         (fn [updated]
           (when (= (tostring updated.id) (tostring notebook-id))
             (node:refresh-label)))))

  (fn handle-items-changed [payload]
    (local id (or (and payload payload.id) ""))
    (when (= (tostring id) (tostring notebook-id))
      (node.items-changed:emit payload)
      (node:add-item-nodes)))

  (set items-handler
       (store.notebook-items-changed:connect handle-items-changed))

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
         ;; Connect notebook item edges when matching nodes are added later.
         (when (and signal (not graph-node-added-handler))
           (set graph-node-added-signal signal)
           (set graph-node-added-handler
                (signal:connect
                  (fn [payload]
                    (local added (and payload payload.node))
                    (when (and added (not (= (tostring added.key) (tostring self.key))))
                      (local notebook (self:get-notebook))
                      (when notebook
                        (if (notebook-contains-node-key? notebook added.key)
                            (self:add-item-nodes)
                            (when (contains-identity-item? notebook.items)
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
                           (local notebook (self:get-notebook))
                            (when notebook
                              (remove-target-items! self removed-key)))))))))
         (local morphed-signal (and graph graph.node-morphed))
         (when (and morphed-signal (not graph-node-morphed-handler))
           (set graph-node-morphed-signal morphed-signal)
           (set graph-node-morphed-handler
                (morphed-signal:connect
                  (fn [payload]
                    (local notebook (self:get-notebook))
                    (when (and notebook (notebook-affected-by-morph? notebook payload))
                      ;; Morph can transiently resolve old type during identity update.
                      ;; Refresh once more after graph finishes node replacement.
                      (self.items-changed:emit {:id self.notebook-id :items notebook.items})
                      (self:add-item-nodes))))))
         (when (and self.identity-store self.identity-store.identity-updated (not identity-updated-handler))
           (set identity-updated-handler
                (self.identity-store.identity-updated:connect
                  (fn [entity]
                    (local identity-key (.. IDENTITY_KEY_PREFIX (tostring entity.id)))
                    (local notebook (self:get-notebook))
                    (when (and notebook (notebook-contains-node-key? notebook identity-key))
                      (self.items-changed:emit {:id self.notebook-id :items notebook.items})
                      (self:add-item-nodes))))))
         (when (and self.identity-store self.identity-store.identity-deleted (not identity-deleted-handler))
           (set identity-deleted-handler
                (self.identity-store.identity-deleted:connect
                  (fn [entity]
                    (local identity-key (.. IDENTITY_KEY_PREFIX (tostring entity.id)))
                    (local notebook (self:get-notebook))
                    (when (and notebook (notebook-contains-node-key? notebook identity-key))
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
           (store.notebook-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when updated-handler
           (store.notebook-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (when items-handler
           (store.notebook-items-changed:disconnect items-handler true)
           (set items-handler nil))
         (when identity-updated-handler
           (self.identity-store.identity-updated:disconnect identity-updated-handler true)
           (set identity-updated-handler nil))
         (when identity-deleted-handler
           (self.identity-store.identity-deleted:disconnect identity-deleted-handler true)
           (set identity-deleted-handler nil))
         (self.notebook-deleted:clear)
         (self.items-changed:clear)
         (when self.changed
           (self.changed:clear))))

  node)

(local register-loader
  (fn [graph opts]
    (local options (or opts {}))
    (local store (or options.store (NotebookStore.get-default)))
    (local identity-store (or options.identity-store store.identity-store))
    (local string-store (or options.string-store (StringEntityStore.get-default)))
    (graph:register-key-loader SCHEME
      (fn [key]
        (local notebook-id (KeyLoaderUtils.extract-id SCHEME key))
        (when notebook-id
          (local notebook (store:get-notebook notebook-id))
          (when notebook
            (NotebookNode {:notebook-id notebook-id
                           :store store
                           :identity-store identity-store
                           :string-store string-store})))))))

{:NotebookNode NotebookNode
 :register-loader register-loader}
