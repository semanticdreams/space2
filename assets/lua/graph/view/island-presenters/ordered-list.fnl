(local glm (require :glm))

(local kind "ordered-list")
(local default-spacing 24)

(fn vec3-copy [position]
    (when position
        (glm.vec3 position.x position.y position.z)))

(fn fallback-origin []
    (glm.vec3 0 0 0))

(fn base-position [island host]
    (local state (if island.state island.state {}))
    (local state-position (vec3-copy state.position))
    (local list-position (if state.list-key
                             (vec3-copy (host:position-for-key state.list-key))))
    (local first-member-key (. island.members 1))
    (local member-position (if first-member-key
                               (vec3-copy (host:position-for-key first-member-key))))
    (if state-position
        state-position
        list-position
        list-position
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
