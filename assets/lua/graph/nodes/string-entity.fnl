(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local StringEntityStore (require :entities/string))
(local Utils (require :graph/view/utils))
(local KeyLoaderUtils (require :graph/key-loader-utils))

(local DARK_BLUE (glm.vec4 0.1 0.2 0.5 1))
(local DARK_BLUE_ACCENT (glm.vec4 0.15 0.25 0.55 1))

(local SCHEME "string-entity")
(local KEY_PREFIX (KeyLoaderUtils.key-prefix SCHEME))

(fn make-label [entity]
  (if (and entity entity.value (> (string.len entity.value) 0))
      (do
        (local first-line (or (string.match entity.value "([^\r\n]+)") entity.value))
        (Utils.truncate-with-ellipsis first-line 50))
      (or (and entity entity.id) "string entity")))

(local LinkEntityStore (require :entities/link))

(fn require-graph-map [node]
  (local graph-map node.graph)
  (assert graph-map "StringEntityNode.create-child requires mounted GraphMap")
  (assert (= (type graph-map.load-by-key) "function")
          "StringEntityNode.create-child requires mounted GraphMap with load-by-key")
  graph-map)

(fn resolve-link-store [graph-map]
  (local store
    (if (and graph-map graph-map.graph graph-map.graph.link-store)
        graph-map.graph.link-store
        (and graph-map graph-map.link-store)
        graph-map.link-store
        (LinkEntityStore.get-default)))
  (assert store "StringEntityNode.create-child requires link store"))

(fn require-created-entity [entity context]
  (assert entity (.. context " failed to create entity"))
  (assert entity.id (.. context " created entity is missing id"))
  entity)

(fn StringEntityNode [opts]
  (local options (or opts {}))
  (local entity-id (assert options.entity-id "StringEntityNode requires entity-id"))
  (local store (or options.store (StringEntityStore.get-default)))
  (local StringEntityNodeView (require :graph/view/views/string-entity))
  (local StringEntityNodePreview (require :graph/view/previews/string-entity))

  (local entity (store:get-entity entity-id))
  (local initial-label (make-label entity))

  (local node
    (GraphNode {:key (.. KEY_PREFIX entity-id)
                :label initial-label
                :color DARK_BLUE
                :sub-color DARK_BLUE_ACCENT
                :size 8.0
                :view StringEntityNodeView
                :preview StringEntityNodePreview}))

  (set node.entity-id entity-id)
  (set node.store store)
  (set node.entity-deleted (Signal))
  (set node.changed (Signal))

  (fn refresh-label [self]
    (local current (self.store:get-entity self.entity-id))
    (set self.label (make-label current))
    (when self.changed
      (self.changed:emit self)))

  (set node.refresh-label refresh-label)

  (set node.get-entity
       (fn [self]
         (self.store:get-entity self.entity-id)))

  (set node.update-value
       (fn [self new-value]
         (self.store:update-entity self.entity-id {:value new-value})
         (self:refresh-label)))

  (set node.delete-entity
       (fn [self]
         (self.store:delete-entity self.entity-id)))

  (set node.create-child
       (fn [self]
         (local graph-map (require-graph-map self))
         (local child (require-created-entity
                        (self.store:create-entity {})
                        "StringEntityNode.create-child string store"))
         (local child-key (.. KEY_PREFIX (tostring child.id)))
         (local link-store (resolve-link-store graph-map))
         (local link (require-created-entity
                       (link-store:create-entity {:source-key self.key
                                                  :target-key child-key})
                       "StringEntityNode.create-child link store"))
         (local child-node (graph-map:load-by-key child-key))
         (assert child-node
                 (.. "StringEntityNode.create-child failed to load child key into GraphMap: " child-key))
         {:child child
          :child-key child-key
          :child-node child-node
          :link link}))

  (set node.actions
       [{:name "Create child"
         :icon "subdirectory_arrow_right"
         :fn (fn [_button _event]
               (node:create-child))}
        {:name "Delete Entity"
         :icon "delete"
         :fn (fn [_button _event]
               (node:delete-entity))}])

  (var deleted-handler nil)
  (var updated-handler nil)

  (set deleted-handler
       (store.string-entity-deleted:connect
         (fn [deleted]
           (when (= (tostring deleted.id) (tostring entity-id))
             (node.entity-deleted:emit deleted)
              (when (and node.graph node.graph.remove-nodes)
                (node.graph:remove-nodes [node] {:cause "shared-delete"}))))))

  (set updated-handler
       (store.string-entity-updated:connect
         (fn [updated]
           (when (= (tostring updated.id) (tostring entity-id))
             (node:refresh-label)))))

  (set node.drop
       (fn [self]
         (when deleted-handler
           (store.string-entity-deleted:disconnect deleted-handler true)
           (set deleted-handler nil))
         (when updated-handler
           (store.string-entity-updated:disconnect updated-handler true)
           (set updated-handler nil))
         (self.entity-deleted:clear)
         (when self.changed
           (self.changed:clear))))

  node)

(local register-loader
  (KeyLoaderUtils.make-register-loader SCHEME
    StringEntityStore.get-default
    (fn [entity-id store]
      (StringEntityNode {:entity-id entity-id :store store}))))

{:StringEntityNode StringEntityNode
 :register-loader register-loader}
