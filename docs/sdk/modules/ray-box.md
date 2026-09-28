# ray-box

## Canonical Import

```fennel
(local ray-box (require :ray-box))
```

## Source Files

- `src/lua_ray_box.cpp`

## What It Provides

`ray-box` provides a native ray-versus-oriented-box intersection helper for picking and hit testing.

## API Summary

- `ray-box-intersection(ray bounds)` returns `hit?`, `intersection`, and `distance`.
- `ray` should contain `origin` and `direction` as `glm.vec3` values.
- `bounds` may contain `position`, `rotation`, `min-bounds`, `max-bounds` or `size`, and `epsilon`.

## Examples

```fennel
(local ray-box (require :ray-box))
(local glm (require :glm))

(local (hit point distance)
  (ray-box.ray-box-intersection
    {:origin (glm.vec3 0 0 -5) :direction (glm.vec3 0 0 1)}
    {:position (glm.vec3 0 0 0) :size (glm.vec3 2 2 2)}))

(when hit
  (print point distance))
```

## Errors and Platform Notes

Missing `origin` or `direction` returns no hit instead of raising. Bounds default to an unrotated box at the origin with zero size unless `size` or `max-bounds` is supplied.

## Related Modules

- [`glm`](/sdk/modules/glm) for vector and quaternion values.

## Aliases and Search Terms

Search terms: ray box, picking, intersection, hit test, oriented bounds, AABB, OBB.
