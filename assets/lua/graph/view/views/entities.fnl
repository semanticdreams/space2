(local SearchView (require :search-view))

(fn EntitiesNodeView [node _opts]
  (local target (assert node "EntitiesNodeView requires node"))

  (fn build [ctx]
    (local build-ctx (assert ctx "EntitiesNodeView requires a build context"))
    (local search ((SearchView {:items [] :name "entities-view" :num-per-page 10}) build-ctx))
    (var dropped? false)

    (fn on-types [items] (search:set-items items))
    (fn on-submitted [item] (target:add-type-node (. item 1)))
    (local types-handler (target.types-changed:connect on-types))
    (local submitted-handler (search.submitted:connect on-submitted))

    (fn refresh-items [_self]
      (assert (not dropped?) "EntitiesNodeView refresh-items after drop")
      (target:emit-types))

    (fn drop [_self]
      (when (not dropped?)
        (set dropped? true)
        ;; GraphMap drops the node before notifying the view owner.
        (target.types-changed:disconnect types-handler true)
        (search.submitted:disconnect submitted-handler)
        (search:drop)))

    (local self {:search search :layout search.layout :refresh-items refresh-items :drop drop})
    (self:refresh-items)
    self)
  build)

EntitiesNodeView
