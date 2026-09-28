# vector-buffer

## Canonical Import

```fennel
(local vector-buffer (require :vector-buffer))
```

## Source Files

- `src/lua_vector_buffer.cpp`
- `src/vector_buffer.h`

## What It Provides

`vector-buffer` provides a native float buffer with allocation handles, dirty-range tracking, and helpers for writing GLM values into contiguous render data.

## API Summary

- `VectorBuffer([size])` creates a buffer.
- `VectorHandle` exposes `index` and `size`.
- `VectorBuffer` methods include `allocate`, `reallocate`, `delete`, `length`, `capacity`, `free-count`, `free-size`, `clear-dirty`, `dirty-range`, `view`, and `view-ptr`.
- GLM write helpers include `set-glm-vec2`, `set-glm-vec3`, `set-glm-vec4`, `set-glm-mat4`, `set-glm-mat4-diff`, `set-glm-mat4-batch`, and `set-glm-mat4-diff-batch`.
- Float write helpers include `set-float`, `set-floats-from-bytes`, `set-floats-batch`, `set-floats-diff`, and `set-float-fill-diff`.

## Examples

```fennel
(local vector-buffer (require :vector-buffer))
(local glm (require :glm))

(local buffer (vector-buffer.VectorBuffer 64))
(local handle (buffer:allocate 8))
(buffer:set-glm-vec3 handle 0 (glm.vec3 1 2 3))
(buffer:set-float handle 7 0.5)
```

## Errors and Platform Notes

Handle operations validate ranges and raise `VectorBuffer.<method>` errors for empty handles, out-of-bounds writes, mismatched batch sizes, or non-float-aligned byte strings.

## Related Modules

- [`gl`](/sdk/modules/gl) for uploading vector buffers to OpenGL.
- [`glm`](/sdk/modules/glm) for vector and matrix values.

## Aliases and Search Terms

Search terms: vector buffer, float buffer, dirty range, render buffer, instance data.
