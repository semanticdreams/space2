# perlin-terrain-native

## Canonical Import

```fennel
(local perlin-terrain-native (require :perlin-terrain-native))
```

## Source Files

- `src/lua_perlin_terrain.cpp`

## What It Provides

`perlin-terrain-native` generates native Perlin-style terrain meshes for rendering buffers and Bullet triangle meshes.

## API Summary

- `PerlinTerrainMesh([options])` creates terrain. Options include `:width`, `:length`, `:seed`, `:n1div`, `:n2div`, `:n3div`, `:n1scale`, `:n2scale`, `:n3scale`, `:zroot`, and `:zpower`.
- Mesh query methods: `width`, `length`, `point-count`, `triangle-count`, `vertex-count`, `float-count`, `min-height`, `max-height`, and `point-height(x z)`.
- Output methods: `write-to-vector-buffer(vector handle position rotation scale opacity depth)` and `add-to-triangle-mesh(mesh position rotation scale remove-duplicate-vertices?)`.

## Examples

```fennel
(local terrain (require :perlin-terrain-native))
(local vector-buffer (require :vector-buffer))
(local glm (require :glm))

(local mesh (terrain.PerlinTerrainMesh {:width 32 :length 32 :seed 42}))
(local buffer (vector-buffer.VectorBuffer (mesh:float-count)))
(local handle (buffer:allocate (mesh:float-count)))
(mesh:write-to-vector-buffer buffer handle (glm.vec3 0 0 0) (glm.quat) (glm.vec3 1 1 1) 1.0 0.0)
```

## Errors and Platform Notes

`point-height` raises on out-of-bounds coordinates. `write-to-vector-buffer` requires a handle whose size exactly equals `float-count` and whose range fits the buffer.

## Related Modules

- [`vector-buffer`](/sdk/modules/vector-buffer) for render buffer allocation.
- [`glm`](/sdk/modules/glm) for transforms.
- [`bt`](/sdk/modules/bt) for triangle mesh collision data.

## Aliases and Search Terms

Search terms: terrain, Perlin terrain, world mesh, heightfield, triangle mesh, procedural world.
