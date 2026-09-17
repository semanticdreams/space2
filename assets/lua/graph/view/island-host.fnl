(fn assert-required-callback [options key]
    (local callback (. options key))
    (assert (= (type callback) :function)
            (.. "GraphViewIslandHost requires :" key))
    callback)

(fn GraphViewIslandHost [opts]
    (local options (or opts {}))
    (local presenters (assert options.presenters "GraphViewIslandHost requires :presenters"))
    (local node-for-key (assert-required-callback options :node-for-key))
    (local position-for-key (assert-required-callback options :position-for-key))
    (local set-node-position (assert-required-callback options :set-node-position))
    (local set-node-pinned (assert-required-callback options :set-node-pinned))
    (local pinned-by-island {})

    (fn presenter-for-kind [kind]
        (assert (= (type presenters.presenter-for-kind) :function)
                "GraphViewIslandHost presenters must provide presenter-for-kind")
        (presenters.presenter-for-kind kind))

    (fn resolve-node [key]
        (assert (node-for-key options key)
                (.. "GraphViewIslandHost missing node for island member: " (tostring key))))

    (fn unpin-member [island-id key]
        (resolve-node key)
        (set-node-pinned options key false))

    (fn unpin-island-members [island-id]
        (local tracked (. pinned-by-island island-id))
        (when tracked
            (each [key _pinned? (pairs tracked)]
                (unpin-member island-id key))
            (set (. pinned-by-island island-id) nil)))

    (local self
        {:position-for-key (fn [_self key]
                             (position-for-key options key))
         :set-member-position (fn [_self island-id key position]
                                 (assert island-id "set-member-position requires island id")
                                 (assert key "set-member-position requires member key")
                                 (assert position "set-member-position requires position")
                                 (resolve-node key)
                                 (set-node-position options key position))
         :set-member-pinned (fn [_self island-id key pinned?]
                               (assert island-id "set-member-pinned requires island id")
                               (assert key "set-member-pinned requires member key")
                               (resolve-node key)
                               (local tracked (or (. pinned-by-island island-id) {}))
                               (set (. pinned-by-island island-id) tracked)
                               (if pinned?
                                   (do
                                       (set (. tracked key) true)
                                       (set-node-pinned options key true))
                                   (do
                                       (set (. tracked key) nil)
                                       (set-node-pinned options key false))))
         :reconcile-island (fn [self island]
                             (assert island "reconcile-island requires island")
                             (local presenter (presenter-for-kind island.kind))
                             (when (not presenter)
                                 (error (.. "missing graph island presenter kind: " (tostring island.kind))))
                             (local previous (or (. pinned-by-island island.id) {}))
                             (local current {})
                             (each [_ key (ipairs (or island.members []))]
                                 (set (. current key) true))
                             (each [key _pinned? (pairs previous)]
                                 (when (not (. current key))
                                     (unpin-member island.id key)))
                             (set (. pinned-by-island island.id) {})
                             (presenter.apply island self))
         :reconcile-all (fn [self islands]
                          (local seen {})
                          (each [_ island (ipairs (or islands []))]
                              (set (. seen island.id) true)
                              (self:reconcile-island island))
                          (local removed-island-ids [])
                          (each [island-id _tracked (pairs pinned-by-island)]
                              (when (not (. seen island-id))
                                  (table.insert removed-island-ids island-id)))
                          (each [_ island-id (ipairs removed-island-ids)]
                              (unpin-island-members island-id)))
         :drop-island (fn [_self island-id]
                        (assert island-id "drop-island requires island id")
                        (unpin-island-members island-id))
         :drop (fn [_self]
                 (local island-ids [])
                 (each [island-id _tracked (pairs pinned-by-island)]
                     (table.insert island-ids island-id))
                 (each [_ island-id (ipairs island-ids)]
                     (unpin-island-members island-id)))})
    self)

{:GraphViewIslandHost GraphViewIslandHost}
