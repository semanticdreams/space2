# textures

## Canonical Import

```fennel
(local textures (require :textures))
```

## Source Files

- `src/lua_textures.cpp`
- `src/image_loader.cpp`
- `assets/lua/tests/test-jpeg-texture-decode.fnl`

## What It Provides

`textures` manages OpenGL texture resources through the Space resource manager. It can load textures from paths, decoded image bytes, raw pixel bytes, and cubemap face files.

## API Summary

- `load-texture(name path)` and `load-texture-async(name path [callback])` load image files into `Texture2D` resources.
- `load-texture-from-bytes(name bytes [already-flipped?])` and `load-texture-from-bytes-async(name bytes [already-flipped?] [callback])` decode image bytes in memory and create textures.
- `load-texture-from-pixels(name width height channels bytes [already-flipped?])` creates a texture from raw pixel bytes.
- `allocate-texture(name width height channels)`, `get-texture(name)`, and `drop-texture(name)` manage named texture resources.
- `load-cubemap(files)` and `load-cubemap-async(files [callback])` load cubemap faces.
- `Texture2D` exposes `id`, `width`, `height`, `n`, `ready`, wrapping/filter fields, `load`, `allocate`, `generate`, `update-full`, `update-sub-rect`, and `setActive`.
- `TextureCubemap` exposes `id`, `ready`, `load-faces`, and `drop`.

## Examples

```fennel
(local textures (require :textures))

(local tex (textures.load-texture :logo "assets/images/logo.png"))
(when tex.ready
  (tex:setActive))
```

## Errors and Platform Notes

Decode failures raise errors such as `Failed to decode texture bytes`. Dimensions and channel counts must be positive, and raw pixel buffers must contain enough bytes. JPEG/JPG decoding is available through the texture/image loader path, but `jpeg` and `jpg` are search terms, not importable module names.

## Related Modules

- [`image-io`](/sdk/modules/image-io) for PNG read/write and byte flipping utilities.
- [`gl`](/sdk/modules/gl) for binding and drawing with texture IDs.

## Aliases and Search Terms

Search terms: texture, Texture2D, cubemap, image texture, jpeg, jpg, PNG, graphics, rendering.
