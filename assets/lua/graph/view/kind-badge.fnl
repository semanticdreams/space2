(local StatusBadge (require :status-badge))

(local ViewKindBadge {})

(fn ViewKindBadge.titlebar-builder [badge opts]
  (local options (or opts {}))
  (if (or (= badge nil) (= badge false))
      nil
      (do
        (assert (= (type badge) :table) "kind-badge renderer requires normalized badge table")
        (assert badge.text "kind-badge renderer requires badge.text")
        (StatusBadge {:text badge.text
                      :color badge.background-color
                      :foreground badge.foreground-color
                      :scale (or options.scale 0.95)
                      :padding (or options.padding [0.22 0.08])}))))

ViewKindBadge
