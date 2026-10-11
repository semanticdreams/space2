(local SearchView (require :search-view))
(local Button (require :button))
(local {: Flex : FlexChild} (require :flex))

(fn widget-child [widget]
  (fn build-widget-child [_ctx]
    widget))

(fn copy-items [items]
  (local source (if items items []))
  (local copied [])
  (each [_ item (ipairs source)]
    (table.insert copied item))
  copied)

(fn set-search-items-preserving-order [search new-items]
  (set search.items (copy-items new-items))
  (search:update-list-view))

(fn create-entity-handler [target]
  (fn handle-create-entity [_button _event]
    (when (and target.create-entity target.add-entity-node)
      (local entity (target:create-entity {}))
      (target:add-entity-node entity))))

(fn add-entity-handler [target item]
  (fn handle-add-entity [_button _event]
    (when target.add-entity-node
      (target:add-entity-node (. item 1)))))

(fn make-create-button [ctx target]
  ((Button {:icon "add"
            :text "Create"
            :variant :ghost
            :on-click (create-entity-handler target)})
   ctx))

(fn search-row-builder [target]
  (fn build-search-row [item child-ctx]
    (local label (tostring (. item 2)))
    ((Button {:text label
              :variant :ghost
              :on-click (add-entity-handler target item)})
     child-ctx)))

(fn make-search [ctx target]
  ((SearchView {:items []
                :name "dict-entity-list-view"
                :num-per-page 10
                :builder (search-row-builder target)})
   ctx))

(fn make-root-flex [ctx create-button search]
  ((Flex {:axis 2
          :xalign :stretch
          :yspacing 0.3
          :children [(FlexChild (widget-child create-button) 0)
                     (FlexChild (widget-child search) 1)]})
   ctx))

(fn refresh-items [view target fallback-items]
  (local refreshed
    (if target.emit-items
        (target:emit-items)
        fallback-items))
  (view:set-items refreshed))

(fn connect-items-signal [view target]
  (local signal target.items-changed)
  (local handler (fn handle-items-changed [new-items]
                   (view:set-items new-items)))
  (when signal
    (signal:connect handler))
  {:signal signal :handler handler})

(fn connect-search-submit [search target]
  (search.submitted:connect
    (fn handle-search-submit [item]
      (when (and target.add-entity-node item)
        (target:add-entity-node (. item 1))))))

(fn DictEntityListNodeView [node opts]
  (local options (if opts opts {}))
  (local target (assert (if node node options.node)
                        "DictEntityListNodeView requires a target node"))
  (local items (if options.items options.items []))

  (fn build [ctx]
    (local build-ctx (assert (if ctx ctx (if options.ctx options.ctx (and target.graph target.graph.ctx)))
                             "DictEntityListNodeView requires a build context"))
    (local view {})
    (local create-button (make-create-button build-ctx target))
    (local search (make-search build-ctx target))
    (local flex (make-root-flex build-ctx create-button search))
    (set view.search search)
    (set view.create-button create-button)
    (set view.layout flex.layout)
    (set view.set-items (fn [_self new-items] (set-search-items-preserving-order search new-items)))
    (set view.refresh-items (fn [self] (refresh-items self target items)))
    (local connection (connect-items-signal view target))
    (set view.drop
         (fn [_self]
           (when connection.signal
             (connection.signal:disconnect connection.handler true))
           (flex:drop)))
    (connect-search-submit search target)
    (view:refresh-items)
    view))

DictEntityListNodeView
