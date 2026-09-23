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

{:kind kind
 :layout-island layout-island
 :apply apply}
