(local SearchView (require :search-view))

(fn CodeEntityListNodeView [node _opts]
  (local target (assert node "CodeEntityListNodeView requires node"))

  (fn build [ctx]
    (local build-ctx (assert ctx "CodeEntityListNodeView requires a build context"))
    (local search ((SearchView {:items [] :name "code-entity-list-node-view" :num-per-page 10}) build-ctx))
    (var dropped? false)

    (fn on-items [items] (search:set-items items))
    (fn on-submitted [item] (target:add-entity-node (. item 1)))
    (local items-handler (target.items-changed:connect on-items))
    (local submitted-handler (search.submitted:connect on-submitted))

    (fn refresh-items [_self]
      (assert (not dropped?) "CodeEntityListNodeView refresh-items after drop")
      (target:emit-items))

    (fn drop [_self]
      (when (not dropped?)
        (set dropped? true)
        ;; Node teardown may clear this signal before the map notifies view owners.
        (target.items-changed:disconnect items-handler true)
        (search.submitted:disconnect submitted-handler)
        (search:drop)))

    (local self {:search search :layout search.layout :refresh-items refresh-items :drop drop})
    (self:refresh-items)
    self)
  build)

CodeEntityListNodeView
