(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local Signal (require :signal))
(local IdentityStore (require :entities/identity))
(local Utils (require :graph/view/utils))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local ORANGE (glm.vec4 0.8 0.45 0.2 1))
(local ORANGE_ACCENT (glm.vec4 0.85 0.5 0.25 1))

(local SCHEME "identity")
(local KEY_PREFIX (KeyLoaderUtils.key-prefix SCHEME))

(fn make-label [entity]
  (local target-key (or (and entity entity.target-key) ""))
  (if (> (string.len target-key) 0)
      (.. "identity -> " (Utils.truncate-with-ellipsis target-key 36))
      (or (and entity entity.id) "identity")))

(fn resolve-reference-lifecycle! [self]
  (local mounted (and self.graph self.graph.reference-lifecycle))
  (assert (or (not self.lifecycle) (not mounted) (= self.lifecycle mounted)) "reference lifecycle node/graph conflict")
  (local service (assert (or self.lifecycle mounted) "node requires reference lifecycle"))
  (assert (service:owns-store? SCHEME self.store) "reference lifecycle store ownership mismatch")
  service)

(fn IdentityNode [opts]
  (local options (or opts {}))
  (local entity-id (assert options.entity-id "IdentityNode requires entity-id"))
  (local store (or options.store (IdentityStore.get-default)))
  (local IdentityNodeView (require :graph/view/views/identity))

  (local entity (store:get-entity entity-id))
  (local initial-label (make-label entity))

  (local node
    (GraphNode {:key (.. KEY_PREFIX entity-id)
                :label initial-label
                :color ORANGE
                :sub-color ORANGE_ACCENT
                :size 8.0
                :view IdentityNodeView}))

  (set node.identity-id entity-id)
  (set node.store store)
  (set node.lifecycle options.lifecycle)
  (set node.resolve-reference-lifecycle! resolve-reference-lifecycle!)
  (set node.identity-deleted (Signal))
  (set node.changed (Signal))
  (set node.identity-target-key (or (and entity entity.target-key) ""))

  (fn refresh-state [self]
    (local current (self.store:get-entity self.identity-id))
    (set self.identity-target-key (or (and current current.target-key) ""))
    (set self.label (make-label current))
    (when self.changed
      (self.changed:emit self)))

  (set node.refresh-state refresh-state)

  (set node.get-entity
       (fn [self]
         (self.store:get-entity self.identity-id)))

  (set node.update-target
       (fn [self new-key]
         (self.store:update-entity self.identity-id {:target-key (or new-key "")})
         (self:refresh-state)))

  (set node.open-target
       (fn [self]
        (local graph self.graph)
        (when (and graph graph.resolve-node)
           (local target (graph:resolve-node self.key))
           (when (and target (not (= target self)) graph.add-edge)
             (graph:add-edge (GraphEdge {:source self :target target}))
             target))))

  (set node.delete-entity
       (fn [self]
         (local service (self:resolve-reference-lifecycle!))
         (. (service:delete! self.key) :source-record)))

  (set node.actions
       [{:name "Open Target"
         :icon "open_in_new"
         :fn (fn [_button _event]
                 (node:open-target))}
        {:name "Delete Identity"
         :icon "delete"
         :fn (fn [_button _event]
                 (node:delete-entity))}])

  (var deleted-handler nil)
  (var updated-handler nil)

  (set deleted-handler
       (store.identity-deleted:connect
         (fn [deleted]
           (when (= (tostring deleted.id) (tostring entity-id))
             (node.identity-deleted:emit deleted)
             (when (and node.graph node.graph.remove-nodes)
                (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))

  (set updated-handler
       (store.identity-updated:connect
         (fn [updated]
           (when (= (tostring updated.id) (tostring entity-id))
             (node:refresh-state)))))

  (set node.drop
       (fn [self]
         (when deleted-handler
           (store.identity-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when updated-handler
           (store.identity-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (self.identity-deleted:clear)
         (when self.changed
           (self.changed:clear))))

  node)

(local register-loader
  (KeyLoaderUtils.make-register-loader SCHEME
    IdentityStore.get-default
    (fn [entity-id store options]
      (IdentityNode {:entity-id entity-id :store store :lifecycle options.lifecycle}))))

{:IdentityNode IdentityNode
 :register-loader register-loader}
