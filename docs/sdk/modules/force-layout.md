# force-layout

## Canonical Import

```fennel
(local force-layout (require :force-layout))
```

## Source Files

- `src/lua_force_layout.cpp`
- `src/force_layout.h`

## What It Provides

`force-layout` provides a native graph force simulation with node positions, edges, bounds, update loops, and change/stabilization signals.

## API Summary

- `ForceLayout()` creates a layout with defaults; overloaded constructors accept center, spring, repulsion, stabilization, update interval, and optional bounds settings.
- Layout fields include `spring-rest-length`, `repulsive-force-constant`, `spring-constant`, `delta-t`, `center-force`, stabilization thresholds, `update-interval`, `active`, `center-position`, `bounds`, `auto-center-within-bounds`, `node-count`, and `positions`.
- Layout methods include `clear`, `add-node`, `add-edge`, `set-position`, `pin-node`, `step`, `update`, `start`, `cancel`, `stop`, `run`, `until-stable`, `set-bounds`, `get-bounds`, `get-positions`, `get-results`, and `set-center-position`.
- Signals `changed` and `stabilized` expose `connect`, `disconnect`, `clear`, and `size`.

## Examples

```fennel
(local force-layout (require :force-layout))
(local glm (require :glm))

(local layout (force-layout.ForceLayout))
(layout:add-node :a (glm.vec3 0 0 0))
(layout:add-node :b (glm.vec3 10 0 0))
(layout:add-edge :a :b)
(layout:step)
(print (layout:get-results))
```

## Errors and Platform Notes

Positions are exposed through a 1-based view and raise when indexed out of range. Long-running `start`/`run` operations can accept callbacks and should be managed with `cancel` or `stop` when no longer needed.

## Related Modules

- [`glm`](/sdk/modules/glm) for positions and bounds.
- [`graph-edge-batch`](/sdk/modules/graph-edge-batch) for rendering graph edges.

## Aliases and Search Terms

Search terms: force layout, graph layout, spring layout, node positions, stabilization.
