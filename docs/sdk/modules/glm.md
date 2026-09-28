# glm

## Canonical Import

```fennel
(local glm (require :glm))
```

## Source Files

- `src/lua_glm.cpp`

## What It Provides

`glm` exposes native GLM vector, quaternion, matrix, transform, projection, and interop helpers.

## API Summary

- Constructors and usertypes: `vec2`, `vec3`, `vec4`, `quat`, and `mat4` with arithmetic operators and component access.
- Vector functions: `normalize`, `dot`, `cross`, and `length`.
- Transform helpers: `translate`, `rotate`, `scale`, `mat4-trs-z`, `mat4-trs`, `mat4-render-trs`, `mat4-world-to-render`, `mat4-mul`, `strip-translation`, `mat4-clip-from-render`, and `mat4-clip-from-bounds`.
- Projection helpers: `perspective`, `ortho`, `lookAt`, `project`, and `unproject`.
- Interop helpers: `value-ptr-vec2`, `value-ptr-vec3`, `value-ptr-vec4`, `value-ptr-mat4`, `is-vec3`, `is-vec4`, `is-mat4`, `mat4-key`, and `mat4-hash-key`.

## Examples

```fennel
(local glm (require :glm))

(local position (glm.vec3 1 2 3))
(local rotation (glm.quat 0.0 (glm.vec3 0 0 1)))
(local model (glm.mat4-trs position.x position.y position.z rotation))
(print (glm.mat4-hash-key model))
```

## Errors and Platform Notes

`vec3` components must be finite and stay below the native magnitude threshold. Indexing `vec3` uses Lua/Fennel 1-based indices and raises on out-of-range access.

## Related Modules

- [`shaders`](/sdk/modules/shaders) for passing matrices and vectors to uniforms.
- [`vector-buffer`](/sdk/modules/vector-buffer) for writing GLM values into render buffers.
- [`bt`](/sdk/modules/bt) for Bullet physics math types.

## Aliases and Search Terms

Search terms: GLM, vec2, vec3, vec4, quat, mat4, transform, projection, matrix.
