(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local LinkEntityStore (require :entities/link))
(local Utils (require :graph/view/utils))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local PALE_YELLOW (glm.vec4 0.7 0.65 0.3 1))
(local PALE_YELLOW_ACCENT (glm.vec4 0.75 0.7 0.35 1))

(local SCHEME "link-entity")
(local KEY_PREFIX (KeyLoaderUtils.key-prefix SCHEME))

(fn endpoint-text [store key]
  (assert store.identity-store "LinkEntityNode requires owning IdentityStore")
  ;; Immediate editing can persist this exact prefix before its record ID exists.
  (local text (if (= key "identity:") key
                  (store.identity-store:resolve-key (if (= key nil) "" key))))
  text)

(fn make-label [store entity]
  (local source (endpoint-text store (and entity entity.source-key)))
  (local target (endpoint-text store (and entity entity.target-key)))
  (if (and (> (string.len source) 0) (> (string.len target) 0))
      (.. (Utils.truncate-with-ellipsis source 20)
          " → "
          (Utils.truncate-with-ellipsis target 20))
      (or (and entity entity.id) "link entity")))

(fn resolve-reference-lifecycle! [self]
  (local mounted (and self.graph self.graph.reference-lifecycle))
  (assert (or (not self.lifecycle) (not mounted) (= self.lifecycle mounted)) "reference lifecycle node/graph conflict")
  (local service (assert (or self.lifecycle mounted) "node requires reference lifecycle"))
  (assert (service:owns-store? SCHEME self.store) "reference lifecycle store ownership mismatch")
  service)

(fn LinkEntityNode [opts]
  (local options (or opts {}))
  (local entity-id (assert options.entity-id "LinkEntityNode requires entity-id"))
  (local store (or options.store (LinkEntityStore.get-default)))
  (local LinkEntityNodeView (require :graph/view/views/link-entity))

  (local entity (store:get-entity entity-id))
  (local initial-label (make-label store entity))

  (local node
    (GraphNode {:key (.. KEY_PREFIX entity-id)
                :label initial-label
                :color PALE_YELLOW
                :sub-color PALE_YELLOW_ACCENT
                :size 8.0
                :view LinkEntityNodeView}))

  (set node.entity-id entity-id)
  (set node.store store)
  (set node.lifecycle options.lifecycle)
  (set node.resolve-reference-lifecycle! resolve-reference-lifecycle!)
  (set node.entity-deleted (Signal))
  (set node.changed (Signal))

  (fn refresh-label [self]
    (local current (self.store:get-entity self.entity-id))
    (set self.label (make-label self.store current))
    (when self.changed
      (self.changed:emit self)))

  (set node.refresh-label refresh-label)

  (set node.get-entity
       (fn [self]
          (self.store:get-entity self.entity-id)))

  (set node.endpoint-text
       (fn [self key]
         (endpoint-text self.store key)))

  (set node.update-source
       (fn [self new-key]
         (self.store:update-entity self.entity-id {:source-key new-key})
         (self:refresh-label)))

  (set node.update-target
       (fn [self new-key]
         (self.store:update-entity self.entity-id {:target-key new-key})
         (self:refresh-label)))

  (set node.update-metadata
       (fn [self new-metadata]
         (self.store:update-entity self.entity-id {:metadata new-metadata})))

  (set node.delete-entity
       (fn [self]
         (local service (self:resolve-reference-lifecycle!))
         (. (service:delete! self.key) :source-record)))

  (set node.actions
       [{:name "Delete Entity"
         :icon "delete"
         :fn (fn [_button _event]
                 (node:delete-entity))}])

  (var deleted-handler nil)
  (var updated-handler nil)

  (set deleted-handler
       (store.link-entity-deleted:connect
         (fn [deleted]
           (when (= (tostring deleted.id) (tostring entity-id))
             (node.entity-deleted:emit deleted)
              (when (and node.graph node.graph.remove-nodes)
                (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))

  (set updated-handler
       (store.link-entity-updated:connect
         (fn [updated]
           (when (= (tostring updated.id) (tostring entity-id))
             (node:refresh-label)))))

  (set node.drop
       (fn [self]
         (when deleted-handler
           (store.link-entity-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when updated-handler
           (store.link-entity-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (self.entity-deleted:clear)
         (when self.changed
           (self.changed:clear))))

  node)

(local register-loader
  (KeyLoaderUtils.make-register-loader SCHEME
    LinkEntityStore.get-default
    (fn [entity-id store options]
      (LinkEntityNode {:entity-id entity-id :store store :lifecycle options.lifecycle}))))

{:LinkEntityNode LinkEntityNode
 :register-loader register-loader}
