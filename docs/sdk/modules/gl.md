# gl

## Canonical Import

```fennel
(local gl (require :gl))
```

## Source Files

- `src/lua_opengl.cpp`

## What It Provides

`gl` exposes the Space runtime's low-level OpenGL and SDL clipboard binding. It is intended for renderer code that already owns an active GL context.

## API Summary

- Constants for common GL modes, buffers, textures, framebuffers, formats, and state such as `GL_COLOR_BUFFER_BIT`, `GL_TRIANGLES`, `GL_ARRAY_BUFFER`, `GL_TEXTURE_2D`, `GL_RGBA`, and `GL_UNSIGNED_BYTE`.
- Draw and state helpers: `glClear`, `glClearColor`, `glViewport`, `getViewport`, `glDrawArrays`, `glDrawArraysInstanced`, `glDrawElementsInstanced`, `glMultiDrawArrays`, `glEnable`, `glDisable`, `glDepthFunc`, and `glDepthMask`.
- Object helpers for vertex arrays, buffers, queries, framebuffers, renderbuffers, and textures: `glGen*`, `glDelete*`, `glBind*`, `glTexImage2D`, `glTexParameteri`, `glFramebufferTexture2D`, and `glBlitFramebuffer`.
- Buffer upload helpers: `glBufferData`, `glBufferDataUInt`, `glBufferSubData`, `bufferDataFromVectorBuffer`, `bufferSubDataFromVectorBuffer`, `bufferDataUIntFromVectorBuffer`, and `bufferSubDataUIntFromVectorBuffer`.
- Readback helpers: `glReadPixels` and `glGetTexImage` return byte strings for `GL_RGB` or `GL_RGBA` with `GL_UNSIGNED_BYTE`.
- Clipboard helpers: `clipboard-has`, `clipboard-get`, and `clipboard-set`.

## Examples

```fennel
(local gl (require :gl))

(gl.glViewport 0 0 1280 720)
(gl.glClearColor 0.05 0.05 0.08 1.0)
(gl.glClear gl.GL_COLOR_BUFFER_BIT)
```

## Errors and Platform Notes

The binding raises when accessing undefined keys. `glReadPixels` and `glGetTexImage` only support `GL_UNSIGNED_BYTE` with `GL_RGB` or `GL_RGBA`. Clipboard helpers initialize the SDL video subsystem when needed and raise SDL-prefixed errors on failures.

## Related Modules

- [`shaders`](/sdk/modules/shaders) for shader resource loading and uniform helpers.
- [`textures`](/sdk/modules/textures) for managed texture resources.
- [`vector-buffer`](/sdk/modules/vector-buffer) for CPU-side float buffers used by GL upload helpers.

## Aliases and Search Terms

Search terms: OpenGL, GL, graphics, rendering, framebuffer, texture, vertex buffer, clipboard.
