# shaders

## Canonical Import

```fennel
(local shaders (require :shaders))
```

## Source Files

- `src/lua_shaders.cpp`

## What It Provides

`shaders` loads GLSL shader programs through the native resource manager and exposes the `Shader` usertype for binding programs and setting uniforms.

## API Summary

- `load-shader(name vertex-code fragment-code [geometry-code])` compiles shader source strings and registers the result by name.
- `load-shader-from-files(name vertex-path fragment-path [geometry-path])` loads shader source from files.
- `get-shader(name)` returns a previously registered shader.
- `Shader` fields and methods: `id`, `use`, `setFloat`, `setInteger`, `setVector2f`, `setVector3f`, `setVector4f`, and `setMatrix4`.

## Examples

```fennel
(local shaders (require :shaders))

(local shader
  (shaders.load-shader-from-files
    :flat-color
    "assets/shaders/flat.vert"
    "assets/shaders/flat.frag"))

(shader:use)
(shader:setFloat "uOpacity" 0.85)
```

## Errors and Platform Notes

Compilation, file loading, and lookup errors come from the native resource manager and shader implementation. Use this module only when an OpenGL context is available.

## Related Modules

- [`gl`](/sdk/modules/gl) for low-level OpenGL calls.
- [`glm`](/sdk/modules/glm) for vector and matrix values passed to shader uniforms.

## Aliases and Search Terms

Search terms: shader, GLSL, program, uniform, graphics, rendering.
