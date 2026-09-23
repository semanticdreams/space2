(local glm (require :glm))
(local MathUtils (require :math-utils))

(local kind "ordered-list")
(local default-spacing 24)

(fn position-array? [position]
    (and (= (type position) "table")
         (= (type (. position 1)) "number")
         (= (type (. position 2)) "number")
         (= (type (. position 3)) "number")))

(fn vec3-components [position]
    (pcall (fn [] (values position.x position.y position.z))))

(fn vec3-like? [position]
    (when position
        (local (ok x y z) (vec3-components position))
        (and ok
             (= (type x) "number")
             (= (type y) "number")
             (= (type z) "number"))))

(fn vec3-copy [position label]
    (when position
        (if (position-array? position)
            (MathUtils.array->vec3 position)
            (vec3-like? position)
            (glm.vec3 position.x position.y position.z)
            (error (.. label " must be a [x y z] array or vec3-like value")))))

(fn vec3-array [position label]
    (local value (vec3-copy position label))
    [value.x value.y value.z])

(fn copy-state [state]
    (local next {})
    (each [k v (pairs (if state state {}))]
        (set (. next k) v))
    next)

(fn member-index [island member-key]
    (var found nil)
    (each [index key (ipairs (if island.members island.members []))]
        (when (and (not found) (= key member-key))
            (set found index)))
    found)

(fn fallback-origin []
    (glm.vec3 0 0 0))

(fn base-position [island host]
    (local state (if island.state island.state {}))
    (local state-position (vec3-copy state.position "OrderedListPresenter state.position"))
    (local first-member-key (. island.members 1))
    (local member-position (if first-member-key
                               (vec3-copy (host:position-for-key first-member-key)
                                          "OrderedListPresenter member position")))
    (if state-position
        state-position
        member-position
        member-position
        (fallback-origin)))

(fn layout-island [island host]
    (assert island "OrderedListPresenter.layout-island requires island")
    (assert host "OrderedListPresenter.layout-island requires host")
    (local state (if island.state island.state {}))
    (local spacing (if state.spacing state.spacing default-spacing))
    (local base (base-position island host))
    (local placements {})
    (local members (if island.members island.members []))
    (each [index key (ipairs members)]
        (set (. placements key) (glm.vec3 base.x
                                         (- base.y (* spacing (- index 1)))
                                         base.z)))
    placements)

(fn apply [island host]
    (local placements (layout-island island host))
    (local members (if island.members island.members []))
    (each [_ key (ipairs members)]
        (host:set-member-position island.id key (. placements key))
        (host:set-member-pinned island.id key true))
    placements)

(fn member-drag-end-state [island host request]
    (assert island "OrderedListPresenter.member-drag-end-state requires island")
    (assert host "OrderedListPresenter.member-drag-end-state requires host")
    (assert request "OrderedListPresenter.member-drag-end-state requires request")
    (assert request.member-key "OrderedListPresenter.member-drag-end-state requires request.member-key")
    (assert request.position "OrderedListPresenter.member-drag-end-state requires request.position")
    (if (not (member-index island request.member-key))
        nil
        (do
            (local placements (layout-island island host))
            (local current-placement (vec3-copy (. placements request.member-key)
                                                "OrderedListPresenter current member placement"))
            (local dropped-position (vec3-copy request.position
                                               "OrderedListPresenter dropped member position"))
            (local base (base-position island host))
            (local delta (- dropped-position current-placement))
            (local next-origin (+ base delta))
            (local next-state (copy-state island.state))
            (set next-state.position (vec3-array next-origin
                                                 "OrderedListPresenter next origin"))
            next-state)))

{:kind kind
  :layout-island layout-island
  :member-drag-end-state member-drag-end-state
  :apply apply}
