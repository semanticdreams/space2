(fn assert-required-callback [options key]
    (local callback (. options key))
    (assert (= (type callback) :function)
            (.. "GraphViewIslandHost requires :" key))
    callback)

(fn state-after-member-drag-end [self presenter-for-kind island request]
    (assert island "GraphViewIslandHost.state-after-member-drag-end requires island")
    (assert request "GraphViewIslandHost.state-after-member-drag-end requires request")
    (assert request.member-key "GraphViewIslandHost.state-after-member-drag-end requires request.member-key")
    (assert request.position "GraphViewIslandHost.state-after-member-drag-end requires request.position")
    (local presenter (presenter-for-kind island.kind))
    (when (not presenter)
        (error (.. "GraphViewIslandHost missing presenter for island kind: " (tostring island.kind))))
    (if presenter.member-drag-end-state
        (do
            (local state (presenter.member-drag-end-state island self request))
            (when (and state (not (= (type state) "table")))
                (error "GraphViewIslandHost presenter member-drag-end-state must return table or nil"))
            state)
        nil))

(fn GraphViewIslandHost [opts]
    (local options (or opts {}))
    (local presenters (assert options.presenters "GraphViewIslandHost requires :presenters"))
    (local node-for-key (assert-required-callback options :node-for-key))
    (local position-for-key (assert-required-callback options :position-for-key))
    (local set-node-position (assert-required-callback options :set-node-position))
    (local set-node-pinned (assert-required-callback options :set-node-pinned))
    (local pinned-by-island {})
    (local member-pin-counts {})

    (fn presenter-for-kind [kind]
        (assert (= (type presenters.presenter-for-kind) :function)
                "GraphViewIslandHost presenters must provide presenter-for-kind")
        (presenters.presenter-for-kind kind))

    (fn resolve-node [key]
        (assert (node-for-key options key)
                (.. "GraphViewIslandHost missing node for island member: " (tostring key))))

    (fn member-pin-count [key]
        (if (. member-pin-counts key) (. member-pin-counts key) 0))

    (fn add-member-pin-owner [island-id key]
        (local tracked (if (. pinned-by-island island-id) (. pinned-by-island island-id) {}))
        (set (. pinned-by-island island-id) tracked)
        (when (not (. tracked key))
            (set (. tracked key) true)
            (set (. member-pin-counts key) (+ (member-pin-count key) 1))))

    (fn remove-member-pin-owner [island-id key]
        (local tracked (. pinned-by-island island-id))
        (when (and tracked (. tracked key))
            (set (. tracked key) nil)
            (local next-count (- (member-pin-count key) 1))
            (if (> next-count 0)
                (set (. member-pin-counts key) next-count)
                (do
                    (set (. member-pin-counts key) nil)
                    (when (node-for-key options key)
                        (set-node-pinned options key false))))))

    (fn unpin-island-members [island-id]
        (local tracked (. pinned-by-island island-id))
        (when tracked
            (local member-keys [])
            (each [key _pinned? (pairs tracked)]
                (table.insert member-keys key))
            (each [_ key (ipairs member-keys)]
                (remove-member-pin-owner island-id key))
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
                               (if pinned?
                                   (do
                                       (add-member-pin-owner island-id key)
                                       (set-node-pinned options key true))
                                   (remove-member-pin-owner island-id key)))
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
                                     (remove-member-pin-owner island.id key)))
                             (presenter.apply island self))
         :state-after-member-drag-end (fn [self island request]
                                        (state-after-member-drag-end self presenter-for-kind island request))
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
