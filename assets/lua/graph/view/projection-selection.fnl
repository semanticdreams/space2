(fn copy-array [items]
    (if items
        (icollect [_ value (ipairs items)] value)
        []))

(fn key-set [keys]
    (local lookup {})
    (when keys
        (each [_ key (ipairs keys)]
            (set (. lookup key) true)))
    lookup)

(fn install! [view opts]
    (assert view "ProjectionSelection.install! requires view")
    (local options (assert opts "ProjectionSelection.install! requires opts"))
    (local assert-not-dropped (assert options.assert-not-dropped "ProjectionSelection.install! requires :assert-not-dropped"))
    (local visible-keys (assert options.visible-keys "ProjectionSelection.install! requires :visible-keys"))
    (local selected-keys (assert options.selected-keys "ProjectionSelection.install! requires :selected-keys"))
    (local set-selected-keys! (assert options.set-selected-keys! "ProjectionSelection.install! requires :set-selected-keys!"))
    (local focused-key (assert options.focused-key "ProjectionSelection.install! requires :focused-key"))
    (local focus-key! (assert options.focus-key! "ProjectionSelection.install! requires :focus-key!"))
    (local visible-key? (assert options.visible-key? "ProjectionSelection.install! requires :visible-key?"))
    (local sync-selector! (or options.sync-selector! (fn [_keys] true)))

    (fn apply-selection! [keys]
        (assert-not-dropped "selection")
        (set-selected-keys! keys)
        (sync-selector! keys)
        true)

    (set view.selected-node-count
         (fn [_self]
             (assert-not-dropped "selected-node-count")
             (local visible (key-set (visible-keys)))
             (accumulate [count 0 _ key (ipairs (selected-keys))]
                 (if (. visible key) (+ count 1) count))))
    (set view.select-all-visible-nodes
         (fn [_self]
             (assert-not-dropped "select-all-visible-nodes")
             (local keys (visible-keys))
             (if (> (length keys) 0)
                 (apply-selection! keys)
                 false)))
    (set view.clear-selection
         (fn [_self]
             (assert-not-dropped "clear-selection")
             (if (> (length (selected-keys)) 0)
                 (apply-selection! [])
                 false)))
    (set view.focused-node-selected?
         (fn [_self]
             (assert-not-dropped "focused-node-selected?")
             (local key (focused-key))
             (if key
                 (not (= (. (key-set (selected-keys)) key) nil))
                 false)))
    (set view.select-focused-node-only
         (fn [_self]
             (assert-not-dropped "select-focused-node-only")
             (local key (focused-key))
             (if (and key (visible-key? key))
                 (apply-selection! [key])
                 false)))
    (set view.add-focused-node-to-selection
         (fn [_self]
             (assert-not-dropped "add-focused-node-to-selection")
             (local key (focused-key))
             (if (and key (visible-key? key))
                 (do
                     (local keys [])
                     (local seen {})
                     (each [_ selected-key (ipairs (selected-keys))]
                         (when (visible-key? selected-key)
                             (set (. seen selected-key) true)
                             (table.insert keys selected-key)))
                     (when (not (. seen key))
                         (table.insert keys key))
                     (apply-selection! keys))
                 false)))
    (set view.remove-focused-node-from-selection
         (fn [_self]
             (assert-not-dropped "remove-focused-node-from-selection")
             (local key (focused-key))
             (if key
                 (do
                     (local keys [])
                     (each [_ selected-key (ipairs (selected-keys))]
                         (when (and (not= selected-key key) (visible-key? selected-key))
                             (table.insert keys selected-key)))
                     (apply-selection! keys))
                 false)))
    (set view.toggle-focused-node-selection
         (fn [self]
             (assert-not-dropped "toggle-focused-node-selection")
             (if (self:focused-node-selected?)
                 (self:remove-focused-node-from-selection)
                 (self:add-focused-node-to-selection))))
    (set view.focus-selected-node
         (fn [_self]
             (assert-not-dropped "focus-selected-node")
             (local keys [])
             (each [_ key (ipairs (selected-keys))]
                 (when (visible-key? key)
                     (table.insert keys key)))
             (if (= (length keys) 1)
                 (do
                     (focus-key! (. keys 1) {:reason :selection-command})
                     true)
                 false)))
    view)

{:install! install!
 :copy-array copy-array}
