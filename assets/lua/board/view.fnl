(global app (or app {}))

(local glm (require :glm))
(local Signal (require :signal))
(local FloatLayer (require :float-layer))
(local Registry (require :board/registry))
(local LinkEntityStore (require :entities/link))
(local fs (require :fs))

(fn validate-store [store identity-store label]
  (assert (and store store.base-dir) (.. "BoardView requires " label " base-dir"))
  (assert (= (fs.absolute store.base-dir) (fs.absolute identity-store.base-dir))
          (.. "BoardView " label " root mismatch"))
  (when store.identity-store
    (assert (= store.identity-store identity-store) (.. "BoardView " label " identity-store mismatch")))
  store)

(fn resolved-item-key [item identity-store]
  (assert (and item identity-store) "Board subject binding requires item and identity-store")
  (if (or (= item.type "string-entity") (= item.type "code-entity"))
      (identity-store:resolve-key item.subject-key)
      item.subject-key))

(fn build-item-body [item view]
  (local item-type (assert (Registry.item-type item.type)
                          (.. "Unknown board item type: " (tostring item.type))))
  (local builder ((assert item-type.builder "Board item type missing builder") item view))
  (local element (builder view.ctx))
  (assert (and element element.layout) "Board item builder must return widget with layout")
  element)

(fn replace-item-body [view record build unregister register-movable register-resizable]
  ;; Construct before detaching: unsupported/missing data cannot erase a held body.
  (local element (build record.item))
  (local old record.element)
  (unregister record)
  (set record.element element)
  (set record.metadata.element element)
  (set record.metadata.target nil)
  (view.layer.layout:set-children (icollect [_ entry (ipairs view.layer.children)] entry.element.layout))
  (register-movable record.item record.metadata)
  (register-resizable record.item record.metadata)
  (old:drop)
  (set record.subject-key record.item.subject-key)
  (set record.item-type record.item.type)
  (set record.resolved-key (resolved-item-key record.item view.identity-store)))

(fn acquire-item-provider! [item view providers]
  (assert item "Board provider acquisition requires item")
  (local key (resolved-item-key item providers.identity-store))
  (local kind (and (or (= item.type "string-entity") (= item.type "code-entity")) key (string.match key "^([^:]+):")))
  (local field (if (= kind "string-entity") :string-store (= kind "code-entity") :code-store))
  (when field
    (local store (or (. providers field)
                     (if (= field :string-store) ((. (require :entities/string) :get-default))
                         ((. (require :entities/code) :get-default)))))
    (validate-store store providers.identity-store field)
    (tset providers field store)
    (tset view field store)))

(fn ensure-board-transform-target [board layer item metadata]
  (when metadata
    (local target (layer:ensure-transform-target metadata))
    (when (and target (not target.__board_transform_target))
      (local original-set-position target.set-position)
      (local original-set-size target.set-size)
      (set target.__board_transform_target true)
      (set target.set-position
           (fn [self position]
             (board:update-item-transform item.id {:position position})
             (original-set-position self position)
             self))
      (set target.set-size
           (fn [self size]
             (board:update-item-transform item.id {:size size})
             (original-set-size self size)
             self))
      (set target.set-transform
           (fn [self transform]
             (board:update-item-transform item.id transform)
             (when transform.position (original-set-position self transform.position))
             (when transform.size (original-set-size self transform.size))
             self)))
    target))

(fn item-center [item]
  (local position (or item.position (glm.vec3 0 0 0)))
  (local size (or item.size (glm.vec3 0 0 0)))
  (+ position (glm.vec3 (* size.x 0.5)
                       (* size.y 0.5)
                        0)))

(fn sync-record-transform [layer record item]
  (assert item "Board transform requires item")
  (when (and record record.metadata)
    (set record.metadata.world-position item.position)
    (set record.metadata.world-rotation item.rotation)
    (set record.metadata.size item.size)
    (layer.layout:mark-layout-dirty)
    (when record.element.layout
      (set record.element.layout.size item.size)
      (record.element.layout:mark-layout-dirty)))
  (when (and record record.selectable)
    (set record.selectable.position (item-center item))))

  (fn subject-key [item]
  (and item item.subject-key))

(fn require-lifecycle! [view providers scheme store]
  (local service (assert view.lifecycle "BoardView requires reference lifecycle"))
  (assert (and (service:owns-store? "identity" providers.identity-store)
               (service:owns-store? "link-entity" providers.link-store)
               (service:owns-store? scheme store)) "BoardView reference lifecycle store ownership mismatch")
  service)

(fn authoring-options [view providers opts]
  (local store (assert (or providers.string-store ((. (require :entities/string) :get-default)))
                       "Board authoring requires string-store"))
  (validate-store store providers.identity-store "string-store")
  (when view.lifecycle (require-lifecycle! view providers "string-entity" store))
  (local options (collect [key value (pairs (or opts {}))] key value))
  (set options.string-store store) (set options.identity-store providers.identity-store)
  options)

(fn delete-subject! [view providers item]
  (local key (assert (providers.identity-store:resolve-key item.subject-key) "Board subject cannot resolve"))
  (local scheme (string.match key "^([^:]+):"))
  (local store (if (= scheme "string-entity") providers.string-store
                  (= scheme "code-entity") providers.code-store))
  (local service (require-lifecycle! view providers scheme store))
  (service:delete! key))

(fn BoardView [opts]
  (local options (or opts {}))
  (local board (assert options.board "BoardView requires :board"))
  (local canvas (assert options.canvas "BoardView requires :canvas"))
  (local ctx (assert (or options.ctx canvas.build-context)
                     "BoardView requires build context"))
  (local link-store (or options.link-store (LinkEntityStore.get-default)))
  (local identity-store (assert link-store.identity-store "BoardView link-store requires identity-store"))
  (when options.identity-store
    (assert (= options.identity-store identity-store) "BoardView identity-store conflicts with link-store"))
  (validate-store link-store identity-store "link-store")
  (each [_ key (ipairs [:string-store :code-store])]
    (when (. options key) (validate-store (. options key) identity-store key)))
  (local providers {:identity-store identity-store :link-store link-store
                    :string-store options.string-store :code-store options.code-store})
  (fn same-key? [left right]
    (and left right (not (= left "")) (not (= right ""))
         (= (identity-store:resolve-key left) (identity-store:resolve-key right))))
  (fn same-subject? [item key]
    (and item (same-key? item.subject-key key)))
  (local layer ((FloatLayer {:name "board-layer"
                             :depth-layer-step 8}) ctx))
  (local pointer-target (or (and ctx ctx.pointer-target) canvas))
  (local item-records {})
  (local connector-records {})
  (local selector (or options.selector (and ctx ctx.object-selector)))
  (local selected-items [])
  (local selected-items-changed (Signal))
  (var dropped? false)
  (var self nil)

  (layer.layout:set-root (or (and ctx ctx.layout-root) canvas.layout-root))

  (fn assert-not-dropped [context]
    (assert (not dropped?) (.. "BoardView " context " called after drop")))

  (fn build-body [item]
    (acquire-item-provider! item self providers)
    (build-item-body item self))

  (fn reference-providers [_self]
    (assert (not dropped?) "BoardView reference-providers called after drop")
    {:board board :identity-store identity-store :link-store link-store
     :string-store (or providers.string-store false) :code-store (or providers.code-store false)})

  (fn create-selectable [item]
    {:item item
     :position (item-center item)
     :pointer-target pointer-target})

  (fn find-existing-semantic-connector [source-item target-item]
    (var found nil)
    (each [_ connector (ipairs board.connectors-in-order) &until found]
      (when (and (= connector.kind "semantic-link")
                 (= connector.source-item-id source-item.id)
                 (= connector.target-item-id target-item.id))
        (set found connector)))
    found)

  (fn update-connector-line [connector]
    (local record (. connector-records connector.id))
    (when record
      (local source (. board.items connector.source-item-id))
      (local target (. board.items connector.target-item-id))
      (when (and source target record.line)
        (record.line:update (item-center source) (item-center target)))))

  (fn update-connectors-for-item [item]
    (each [_ connector (ipairs board.connectors-in-order)]
      (when (or (= connector.source-item-id item.id)
                (= connector.target-item-id item.id))
        (update-connector-line connector))))

  (fn find-item-by-subject [key]
    (var found nil)
    (each [_ item (ipairs board.items-in-order) &until found]
      (when (same-subject? item key)
        (set found item)))
    found)

  (fn reconcile-semantic-connector [connector]
    (when (= connector.kind "semantic-link")
      (local link (link-store:get-entity connector.semantic-link-id))
      (when link
        (local source (. board.items connector.source-item-id))
        (local target (. board.items connector.target-item-id))
        (when (or (not (same-subject? source link.source-key))
                 (not (same-subject? target link.target-key)))
          (local next-source (find-item-by-subject link.source-key))
          (local next-target (find-item-by-subject link.target-key))
          (if (and next-source next-target)
              (do
                (set connector.source-item-id next-source.id)
                (set connector.target-item-id next-target.id))
              (board:remove-connector connector.id))))))

  (fn register-movable [item metadata]
    (when (and app.movables metadata)
      (local target (ensure-board-transform-target board layer item metadata))
      (app.movables:register metadata.element {:target target
                                                :handle metadata.element.layout
                                                :key metadata.element
                                                :pointer-target pointer-target})))

  (fn unregister-movable [record]
    (when (and app.movables record record.element)
      (app.movables:unregister record.element)))

  (fn register-resizable [item metadata]
    (when (and app.resizables metadata)
      (local target (ensure-board-transform-target board layer item metadata))
      (app.resizables:register metadata.element {:target target
                                                  :handle metadata.element.layout
                                                  :key metadata.element
                                                  :min-size metadata.element.layout.min-size
                                                  :pointer-target pointer-target})))

  (fn unregister-resizable [record]
    (when (and app.resizables record record.element)
      (app.resizables:unregister record.element)))

  (fn unregister-interactions [record]
    (unregister-movable record)
    (unregister-resizable record))

  (fn add-item-view [item]
    (assert-not-dropped "add-item-view")
    (var element nil)
    (var metadata nil)
    (local (ok result)
      (pcall
        (fn []
          (set element (build-body item))
          (set metadata (layer:attach-child element {:position item.position
                                                     :rotation item.rotation
                                                     :size item.size}))
          (register-movable item metadata)
          (register-resizable item metadata)
          (set (. item-records item.id) {:item item
                                          :subject-key item.subject-key :item-type item.type
                                          :resolved-key (resolved-item-key item identity-store)
                                          :element element
                                          :metadata metadata})
          (when selector
            (local selectable (create-selectable item))
            (set (. item-records item.id :selectable) selectable)
            (selector:add-selectables [selectable]))
          (update-connectors-for-item item)
          element)))
    (when (not ok)
      (if metadata
          (do
            (unregister-interactions {:element element})
            (layer:remove-child element))
          (when (and element element.drop)
            (element:drop)))
      (error result))
    result)

  (fn remove-item-view [item]
    (local record (and item (. item-records item.id)))
    (when record
      (when (and selector record.selectable)
        (selector:remove-selectables [record.selectable]))
      (unregister-interactions record)
      (layer:remove-child record.element)
      (set (. item-records item.id) nil)))

  (fn sync-item-transform [item]
    (assert item "Board item update requires item")
    (local record (and item (. item-records item.id)))
    (when (and record (or (not (= record.subject-key item.subject-key))
                          (not (= record.item-type item.type))
                          (not (= record.resolved-key (resolved-item-key item identity-store)))))
      (replace-item-body self record build-body unregister-interactions register-movable register-resizable))
    (sync-record-transform layer record item)
    (update-connectors-for-item item))

  (fn refresh-identities [_entity]
    (each [_ item (ipairs board.items-in-order)] (sync-item-transform item)))

  (fn add-connector-view [connector]
    (assert-not-dropped "add-connector-view")
    (when (= connector.kind "semantic-link")
      (assert connector.semantic-link-id
              "Semantic board connector requires semantic-link-id")
      (assert (link-store:get-entity connector.semantic-link-id)
              (.. "Semantic board connector missing link entity: "
                  (tostring connector.semantic-link-id)))
      (reconcile-semantic-connector connector))
    (when (. board.connectors connector.id)
      (local TriangleLine (require :triangle-line))
      (local line (TriangleLine ctx {:color (glm.vec4 0.45 0.42 0.3 1)
                                     :thickness 2.0
                                     :depth-offset 1.0
                                     :label connector.id}))
      (set (. connector-records connector.id) {:connector connector
                                               :line line})
      (update-connector-line connector)
      line))

  (fn remove-connector-view [connector]
    (local record (and connector (. connector-records connector.id)))
    (when record
      (when record.line
        (record.line:drop))
      (set (. connector-records connector.id) nil)))

  (var item-added-handler nil)
  (var item-removed-handler nil)
  (var item-updated-handler nil)
  (var connector-added-handler nil)
  (var connector-removed-handler nil)
  (var link-updated-handler nil)
  (var link-deleted-handler nil)
  (var selection-handler nil)
  (var identity-handler nil)

  (fn connectors-for-link [link-id]
    (local out [])
    (each [_ connector (ipairs board.connectors-in-order)]
      (when (and (= connector.kind "semantic-link")
                 (= (tostring (or connector.semantic-link-id ""))
                    (tostring (or link-id ""))))
        (table.insert out connector)))
    out)

  (fn handle-link-deleted [entity]
    (each [_ connector (ipairs (connectors-for-link (and entity entity.id)))]
      (board:remove-connector connector.id)))

  (fn handle-link-updated [entity]
    (each [_ connector (ipairs (connectors-for-link (and entity entity.id)))]
      (local source (. board.items connector.source-item-id))
      (local target (. board.items connector.target-item-id))
      (if (and (same-subject? source entity.source-key)
               (same-subject? target entity.target-key))
          (update-connector-line connector)
          (do
            (local next-source (find-item-by-subject entity.source-key))
            (local next-target (find-item-by-subject entity.target-key))
            (if (and next-source next-target)
                (do
                  (set connector.source-item-id next-source.id)
                  (set connector.target-item-id next-target.id)
                  (update-connector-line connector))
                (board:remove-connector connector.id))))))

  (fn add-item [self spec]
    (assert-not-dropped "add-item")
    (board:add-item spec))

  (fn add-string-entity [self opts]
    (assert-not-dropped "add-string-entity")
    (local item-type (assert (Registry.item-type "string-entity")
                             "Board string-entity item type is not registered"))
    ((assert item-type.create "Board string-entity item type requires :create") board (authoring-options self providers opts)))

  (fn connect-items [self source-item target-item opts]
    (assert-not-dropped "connect-items")
    (local options (or opts {}))
    (local source-candidate (assert source-item "BoardView.connect-items requires source item"))
    (local target-candidate (assert target-item "BoardView.connect-items requires target item"))
    (local source (. board.items source-candidate.id))
    (assert source (.. "BoardView.connect-items source item not found on board: " (tostring source-candidate.id)))
    (local target (. board.items target-candidate.id))
    (assert target (.. "BoardView.connect-items target item not found on board: " (tostring target-candidate.id)))
    (local source-key (assert (subject-key source-candidate)
                               "BoardView.connect-items source item requires subject-key"))
    (assert (and (= (type source-key) :string) (> (# (tostring source-key)) 0))
            "BoardView.connect-items source item requires non-empty subject-key")
    (assert (same-subject? source source-key)
            "BoardView.connect-items source item subject-key does not match board item")
    (local target-key (assert (subject-key target-candidate)
                               "BoardView.connect-items target item requires subject-key"))
    (assert (and (= (type target-key) :string) (> (# (tostring target-key)) 0))
            "BoardView.connect-items target item requires non-empty subject-key")
    (assert (same-subject? target target-key)
            "BoardView.connect-items target item subject-key does not match board item")
    (local existing (find-existing-semantic-connector source target))
    (when (and existing (not options.link))
      (lua "return existing"))
    (local created? (= options.link nil))
    (var link nil)
    (local (ok connector-or-err)
      (pcall
        (fn []
          (when created?
            (set link (link-store:create-entity {:source-key source-key
                                                 :target-key target-key
                                                 :metadata (or options.metadata {})})))
          (set link (or options.link link))
          (assert (and link link.id) "BoardView.connect-items requires link entity with id")
          (local persisted-link (link-store:get-entity link.id))
          (assert persisted-link "BoardView.connect-items link entity missing from store")
          (assert (same-key? persisted-link.source-key source-key)
                  "BoardView.connect-items link source-key does not match source item")
          (assert (same-key? persisted-link.target-key target-key)
                  "BoardView.connect-items link target-key does not match target item")
          (board:add-connector {:source-item-id source.id
                                :target-item-id target.id
                                :kind "semantic-link"
                                :semantic-link-id link.id}))))
    (when (not ok)
      (when (and created? link link.id)
        (link-store:retire-entity! link.id))
      (error connector-or-err))
    connector-or-err)

  (fn remove-item [self item-or-id]
    (assert-not-dropped "remove-item")
    (local id (if (= (type item-or-id) :table) item-or-id.id item-or-id))
    (local item (and id (. board.items id)))
    (when item
      (when (or (= item.type "string-entity") (= item.type "code-entity"))
        (delete-subject! self providers item))
      (when (. board.items id)
        (assert (board:remove-item item) "BoardView.remove-item failed to remove native item"))
      item))

  (fn remove-selected-items [self]
    (local items-to-remove [])
    (for [i (length self.selected-items) 1 -1]
      (table.insert items-to-remove 1 (. self.selected-items i)))
    (var count 0)
    (each [_ item (ipairs items-to-remove)]
      (when (self:remove-item item)
        (set count (+ count 1))))
    count)

  (fn capture-state [_self]
    (assert-not-dropped "capture-state")
    (board:capture-state))

  (fn update [_self _delta]
    (assert-not-dropped "update")
    (each [_ connector (ipairs board.connectors-in-order)]
      (update-connector-line connector))
    nil)

  (fn drop [_self]
    (assert-not-dropped "drop")
    (set dropped? true)
    (board.item-added:disconnect item-added-handler true)
    (board.item-removed:disconnect item-removed-handler true)
    (board.item-updated:disconnect item-updated-handler true)
    (board.connector-added:disconnect connector-added-handler true)
    (board.connector-removed:disconnect connector-removed-handler true)
    (identity-store.identity-updated:disconnect identity-handler true)
    (when link-updated-handler
      (link-store.link-entity-updated:disconnect link-updated-handler true)
      (set link-updated-handler nil))
    (when link-deleted-handler
      (link-store.link-entity-deleted:disconnect link-deleted-handler true)
      (set link-deleted-handler nil))
    (when (and selector selection-handler)
      (selector.changed:disconnect selection-handler true)
      (set selection-handler nil))
    (when selector
      (each [_ record (pairs item-records)]
        (when record.selectable
          (selector:remove-selectables [record.selectable]))))
    (each [_ record (pairs connector-records)]
      (when record.line
        (record.line:drop)))
    (each [_ record (pairs item-records)]
      (unregister-interactions record))
    (selected-items-changed:clear)
    (layer:drop))

  (set self {:board board
              :string-store options.string-store
              :code-store options.code-store
              :identity-store identity-store :lifecycle options.lifecycle
              :canvas canvas
              :ctx ctx
              :layer layer
              :item-records item-records
              :connector-records connector-records
              :selected-items selected-items
              :selected-items-changed selected-items-changed
              :add-item add-item
              :add-string-entity add-string-entity
              :connect-items connect-items
              :remove-item remove-item
              :remove-selected-items remove-selected-items
              :capture-state capture-state
              :reference-providers reference-providers
              :update update
              :drop drop})
  (when selector
    (set selection-handler
         (selector.changed:connect
           (fn [new-selected]
             (local items [])
             (each [_ sel (ipairs new-selected)]
                (when (and sel.item (= (. board.items sel.item.id) sel.item))
                 (table.insert items sel.item)))
             (for [i (length selected-items) 1 -1]
               (table.remove selected-items i))
             (each [_ it (ipairs items)]
               (table.insert selected-items it))
             (selected-items-changed:emit selected-items)))))
  (set item-added-handler (board.item-added:connect add-item-view))
  (set item-removed-handler (board.item-removed:connect remove-item-view))
  (set item-updated-handler (board.item-updated:connect sync-item-transform))
  (set connector-added-handler (board.connector-added:connect add-connector-view))
  (set connector-removed-handler (board.connector-removed:connect remove-connector-view))
  (set link-updated-handler (link-store.link-entity-updated:connect handle-link-updated))
  (set link-deleted-handler (link-store.link-entity-deleted:connect handle-link-deleted))
  (set identity-handler (identity-store.identity-updated:connect refresh-identities))
  (local (hydrate-ok hydrate-err)
    (pcall
      (fn []
        (for [idx (length board.connectors-in-order) 1 -1]
          (reconcile-semantic-connector (. board.connectors-in-order idx)))
        (each [_ item (ipairs board.items-in-order)]
          (add-item-view item))
        (each [_ connector (ipairs board.connectors-in-order)]
            (add-connector-view connector)))))
  (when (not hydrate-ok)
    (self:drop)
    (error hydrate-err))
  self)

BoardView
