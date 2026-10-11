(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Input (require :input))
(local ListView (require :list-view))
(local Text (require :text))
(local Utils (require :graph/view/utils))

(fn value-or-empty [value]
  (if (= value nil)
      ""
      (tostring value)))

(fn item-count [items]
  (local source (if items items {}))
  (var count 0)
  (each [_key _value (pairs source)]
    (set count (+ count 1)))
  count)

(fn compare-item-rows [a b]
  (< (tostring a.key) (tostring b.key)))

(fn sorted-item-rows [items]
  (local source (if items items {}))
  (local rows [])
  (each [key value (pairs source)]
    (table.insert rows {:key (tostring key)
                        :value (tostring value)}))
  (table.sort rows compare-item-rows)
  rows)

(fn graph-from-app []
  (var graph nil)
  (when app
    (set graph app.graph-map)
    (when (and (not graph) app.graph-view)
      (set graph app.graph-view.graph-map)))
  graph)

(fn maybe-focus-node [node-key]
  (when (and node-key app app.graph-view)
    (local graph (graph-from-app))
    (when graph
      (local node (and graph.lookup (graph:lookup node-key)))
      (when node
        (local focus-node (. app.graph-view.focus-nodes node))
        (when (and focus-node focus-node.request-focus)
          (focus-node:request-focus {:reason :dict-entity}))))))

(fn first-selected-node-key []
  (var selected [])
  (when (and app app.graph-view app.graph-view.selection)
    (set selected app.graph-view.selection.selected-nodes))
  (local node (and selected (. selected 1)))
  (and node node.key))

(fn widget-child [widget]
  (fn build-widget-child [_ctx]
    widget))

(fn update-name-handler [target]
  (fn handle-update-name [_input new-value]
    (when (and target.update-name)
      (target:update-name new-value))))

(fn focus-value-handler [node-key]
  (fn handle-focus-value [_button _event]
    (maybe-focus-node node-key)))

(fn assert-required-item-text [label value]
  (local text (value-or-empty value))
  (assert (> (string.len text) 0)
          (.. "dict entity item " label " is required"))
  text)

(fn save-item-handler [target original-key key-input value-input]
  (fn handle-save-item [_button _event]
    (local final-key (assert-required-item-text "key" (key-input:get-text)))
    (local final-value (assert-required-item-text "value" (value-input:get-text)))
    (when (and target.rename-item (not (= final-key original-key)))
      (target:rename-item original-key final-key))
    (when target.set-item
      (target:set-item final-key final-value))))

(fn remove-item-handler [target item-key]
  (fn handle-remove-item [_button _event]
    (when target.remove-item
      (target:remove-item item-key))))

(fn use-selected-handler [value-input]
  (fn handle-use-selected [_button _event]
    (local selected-key (first-selected-node-key))
    (when selected-key
      (value-input:set-text selected-key))))

(fn set-item-handler [target key-input value-input]
  (fn handle-set-item [_button _event]
    (when target.set-item
      (target:set-item (key-input:get-text)
                       (value-input:get-text)))))

(fn delete-handler [target]
  (fn handle-delete [_button _event]
    (when target.delete-entity
      (target:delete-entity))))

(fn make-input [ctx opts]
  ((Input opts) ctx))

(fn make-button [ctx opts]
  ((Button opts) ctx))

(fn make-name-input [ctx target entity]
  (local input (make-input ctx {:text ""
                                :placeholder "Name..."
                                :on-change (update-name-handler target)}))
  (local initial-name (value-or-empty (and entity entity.name)))
  (when (> (string.len initial-name) 0)
    (input:set-text initial-name {:reset-cursor? false}))
  input)

(fn make-items-label [ctx]
  ((Text {:text ""
          :name "dict-entity-items-label"
          :color (glm.vec4 0.9 0.9 0.9 1)})
   ctx))

(fn make-item-row [target item child-ctx]
  (local original-key (value-or-empty item.key))
  (local original-value (value-or-empty item.value))
  (local key-input (make-input child-ctx {:text original-key
                                          :placeholder "Key..."}))
  (local value-button (make-button child-ctx {:text (Utils.truncate-with-ellipsis original-value 28)
                                              :variant :ghost
                                              :padding [0.35 0.35]
                                              :on-click (focus-value-handler original-value)}))
  (local value-input (make-input child-ctx {:text original-value
                                            :placeholder "Graph key..."}))
  (local save-button (make-button child-ctx {:text "Save"
                                             :variant :ghost
                                             :padding [0.35 0.35]
                                             :on-click (save-item-handler target original-key key-input value-input)}))
  (local remove-button (make-button child-ctx {:text "Remove"
                                               :variant :ghost
                                               :padding [0.35 0.35]
                                               :on-click (remove-item-handler target original-key)}))
  ((Flex {:axis 1
          :xspacing 0.25
          :yalign :center
          :children [(FlexChild (widget-child key-input) 1)
                     (FlexChild (widget-child value-button) 1)
                     (FlexChild (widget-child value-input) 1)
                     (FlexChild (widget-child save-button) 0)
                     (FlexChild (widget-child remove-button) 0)]})
   child-ctx))

(fn item-row-builder [target]
  (fn build-item-row [item child-ctx]
    (make-item-row target item child-ctx)))

(fn make-items-list [ctx target]
  ((ListView {:name "dict-entity-items"
              :items []
              :scroll true
              :paginate false
              :show-head false
              :item-spacing 0.25
              :builder (item-row-builder target)})
   ctx))

(fn make-add-row [ctx target]
  (local key-input (make-input ctx {:text ""
                                    :placeholder "Item key..."}))
  (local value-input (make-input ctx {:text ""
                                      :placeholder "Graph key..."}))
  (local use-selected (make-button ctx {:text "Use Selected"
                                        :variant :ghost
                                        :on-click (use-selected-handler value-input)}))
  (local set-item (make-button ctx {:text "Set Item"
                                    :variant :ghost
                                    :on-click (set-item-handler target key-input value-input)}))
  ((Flex {:axis 1
          :xspacing 0.25
          :yalign :center
          :children [(FlexChild (widget-child key-input) 1)
                     (FlexChild (widget-child value-input) 1)
                     (FlexChild (widget-child use-selected) 0)
                     (FlexChild (widget-child set-item) 0)]})
   ctx))

(fn make-root-flex [ctx widgets]
  ((Flex {:axis 2
          :xalign :stretch
          :yspacing 0.4
          :children [(FlexChild (widget-child widgets.name-input) 0)
                     (FlexChild (widget-child widgets.items-label) 0)
                     (FlexChild (widget-child widgets.list) 1)
                     (FlexChild (widget-child widgets.add-row) 0)
                     (FlexChild (widget-child widgets.delete-button) 0)]})
   ctx))

(fn refresh-view-items [view target]
  (local current (and target.get-entity (target:get-entity)))
  (local items (if (and current current.items) current.items {}))
  (local count (item-count items))
  (view.items-label:set-text (.. "Items (" count "):"))
  (view.list:set-items (sorted-item-rows items)))

(fn connect-items-signal [view target]
  (local signal target.items-changed)
  (local handler (fn handle-items-changed [_payload]
                   (view:refresh-items)))
  (when signal
    (signal:connect handler))
  {:signal signal :handler handler})

(fn DictEntityNodeView [node opts]
  (local options (if opts opts {}))
  (local target (assert (if node node options.node)
                        "DictEntityNodeView requires a target node"))

  (fn build [ctx]
    (local build-ctx (assert (if ctx ctx (if options.ctx options.ctx (and target.graph target.graph.ctx)))
                             "DictEntityNodeView requires a build context"))
    (local entity (and target.get-entity (target:get-entity)))
    (local view {})
    (local widgets {:name-input (make-name-input build-ctx target entity)
                    :items-label (make-items-label build-ctx)
                    :list (make-items-list build-ctx target)
                    :add-row (make-add-row build-ctx target)
                    :delete-button (make-button build-ctx {:text "Delete Dict"
                                                           :variant :ghost
                                                           :on-click (delete-handler target)})})
    (local flex (make-root-flex build-ctx widgets))
    (set view.name-input widgets.name-input)
    (set view.items-label widgets.items-label)
    (set view.list widgets.list)
    (set view.add-row widgets.add-row)
    (set view.delete-button widgets.delete-button)
    (set view.layout flex.layout)
    (set view.refresh-items (fn [self] (refresh-view-items self target)))
    (local connection (connect-items-signal view target))
    (set view.drop
         (fn [_self]
           (when connection.signal
             (connection.signal:disconnect connection.handler true))
           (flex:drop)))
    (view:refresh-items)
    view))

DictEntityNodeView
