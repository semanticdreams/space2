(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local CodeEntityStore (require :entities/code))
(local Utils (require :graph/view/utils))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local CODE_BLUE (glm.vec4 0.2 0.35 0.85 1))
(local CODE_BLUE_ACCENT (glm.vec4 0.3 0.45 0.9 1))

(local SCHEME "code-entity")
(local KEY_PREFIX (KeyLoaderUtils.key-prefix SCHEME))

(fn make-label [entity]
  (local name (or (and entity entity.name) ""))
  (if (> (string.len name) 0)
      (Utils.truncate-with-ellipsis name 50)
      (do
        (local language (or (and entity entity.language) "fnl"))
        (.. "code (" language ")"))))

(fn resolve-reference-lifecycle! [self]
  (local mounted (and self.graph self.graph.reference-lifecycle))
  (assert (or (not self.lifecycle) (not mounted) (= self.lifecycle mounted)) "reference lifecycle node/graph conflict")
  (local service (assert (or self.lifecycle mounted) "node requires reference lifecycle"))
  (assert (service:owns-store? SCHEME self.store) "reference lifecycle store ownership mismatch")
  service)

(fn delete-entity [self]
  (local service (self:resolve-reference-lifecycle!))
  (. (service:delete! self.key) :source-record))

(fn CodeEntityNode [opts]
  (local options (or opts {}))
  (local entity-id (assert options.entity-id "CodeEntityNode requires entity-id"))
  (local store (or options.store (CodeEntityStore.get-default)))
  (local CodeEntityNodeView (require :graph/view/views/code-entity))
  (local CodeEntityNodePreview (require :graph/view/previews/code-entity))

  (local entity (store:get-entity entity-id))
  (local initial-label (make-label entity))

  (local node
    (GraphNode {:key (.. KEY_PREFIX entity-id)
                :label initial-label
                :color CODE_BLUE
                :sub-color CODE_BLUE_ACCENT
                :size 8.0
                :view CodeEntityNodeView
                :preview CodeEntityNodePreview}))

  (set node.entity-id entity-id)
  (set node.store store)
  (set node.lifecycle options.lifecycle)
  (set node.resolve-reference-lifecycle! resolve-reference-lifecycle!)
  (set node.entity-deleted (Signal))
  (set node.changed (Signal))
  (set node.run-result-changed (Signal))
  (set node.last-run-result "")

  (fn format-run-result [result]
    (if (not result)
        ""
        (do
          (local err (or result.error ""))
          (if (> (string.len err) 0)
              (.. "Error: " err)
              (do
                (local output (or result.output ""))
                (if (> (string.len output) 0)
                    output
                    "OK"))))))

  (fn refresh-label [self]
    (local current (self.store:get-entity self.entity-id))
    (set self.label (make-label current))
    (when self.changed
      (self.changed:emit self)))

  (set node.refresh-label refresh-label)

  (set node.get-entity
       (fn [self]
         (self.store:get-entity self.entity-id)))

  (set node.update-name
       (fn [self new-name]
         (self.store:update-entity self.entity-id {:name new-name})
         (self:refresh-label)))

  (set node.update-language
       (fn [self new-language]
         (self.store:update-entity self.entity-id {:language new-language})
         (self:refresh-label)))

  (set node.update-source
       (fn [self new-source]
         (self.store:update-entity self.entity-id {:source new-source})
         (self:refresh-label)))

  (set node.update-kernel
       (fn [self kernel]
         (self.store:update-entity self.entity-id {:kernel kernel})
         (self:refresh-label)))

  (set node.set-kernel-from-selection
       (fn [self]
         (local selected (or (and app.graph-view
                                  app.graph-view.selection
                                  app.graph-view.selection.selected-nodes)
                             []))
         (if (not (= (length selected) 1))
             (do
               (set self.last-run-result "Error: Select exactly one kernel node")
               (self.run-result-changed:emit self.last-run-result)
               false)
             (do
               (local selected-node (. selected 1))
               (local kernel-id
                 (or (and selected-node selected-node.kernel-id)
                     (and selected-node selected-node.kernel_id)))
               (if (= kernel-id nil)
                   (do
                     (set self.last-run-result "Error: Selected node is not a kernel")
                     (self.run-result-changed:emit self.last-run-result)
                     false)
                   (do
                     (self:update-kernel kernel-id)
                     (set self.last-run-result (.. "Kernel set: " (tostring kernel-id)))
                     (self.run-result-changed:emit self.last-run-result)
                     true))))))

  (set node.run-entity
       (fn [self]
         (local entity-current (self:get-entity))
         (if (not (and app app.kernels app.kernels.run-code))
             (do
               (set self.last-run-result "Error: app.kernels is not available")
               (self.run-result-changed:emit self.last-run-result)
               false)
             (do
               (set self.last-run-result "Running...")
               (self.run-result-changed:emit self.last-run-result)
               (app.kernels:run-code
                 {:source (or (and entity-current entity-current.source) "")
                  :language (or (and entity-current entity-current.language) "fnl")
                  :name (or (and entity-current entity-current.name) "")
                  :id (and entity-current entity-current.id)
                  :kernel (if entity-current entity-current.kernel 0)}
                 (fn [result]
                   (set self.last-run-result (format-run-result result))
                   (self.run-result-changed:emit self.last-run-result)))
               true))))

  (set node.delete-entity delete-entity)

  (set node.actions
       [{:name "Delete Entity"
         :icon "delete"
         :fn (fn [_button _event]
                 (node:delete-entity))}])

  (var deleted-handler nil)
  (var updated-handler nil)

  (set deleted-handler
       (store.code-entity-deleted:connect
         (fn [deleted]
           (when (= (tostring deleted.id) (tostring entity-id))
             (node.entity-deleted:emit deleted)
              (when (and node.graph node.graph.remove-nodes)
                (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))

  (set updated-handler
       (store.code-entity-updated:connect
         (fn [updated]
           (when (= (tostring updated.id) (tostring entity-id))
             (node:refresh-label)))))

  (set node.drop
       (fn [self]
         (when deleted-handler
           (store.code-entity-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when updated-handler
           (store.code-entity-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (self.entity-deleted:clear)
         (when self.changed
           (self.changed:clear))
         (when self.run-result-changed
           (self.run-result-changed:clear))))

  node)

(local register-loader
  (KeyLoaderUtils.make-register-loader SCHEME
    CodeEntityStore.get-default
    (fn [entity-id store options]
      (CodeEntityNode {:entity-id entity-id :store store :lifecycle options.lifecycle}))))

{:CodeEntityNode CodeEntityNode
 :register-loader register-loader}
