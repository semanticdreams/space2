# image-io

## Canonical Import

```fennel
(local image-io (require :image-io))
```

## Source Files

- `src/lua_image_io.cpp`
- `src/image_loader.cpp`
- `assets/lua/tests/test-jpeg-texture-decode.fnl`

## What It Provides

`image-io` provides small image byte utilities for PNG files and raw pixel buffers.

## API Summary

- `read-png(path)` returns a table with `width`, `height`, `channels`, and `bytes`.
- `write-png(path width height channels bytes [flip-y?])` writes raw pixel bytes to a PNG file.
- `flip-vertical(width height channels bytes)` returns a vertically flipped byte string.

## Examples

```fennel
(local image-io (require :image-io))

(local image (image-io.read-png "assets/images/logo.png"))
(local flipped
  (image-io.flip-vertical image.width image.height image.channels image.bytes))
(image-io.write-png "/tmp/logo-flipped.png" image.width image.height image.channels flipped)
```

## Errors and Platform Notes

Dimensions and channel counts must be positive, and pixel buffers must contain at least `width * height * channels` bytes. `write-png` supports 1, 2, 3, and 4 channels. This module exposes PNG read/write; JPEG/JPG decoding is used by the shared image loader for texture paths, but `jpeg` and `jpg` are search terms, not canonical imports.

## Related Modules

- [`textures`](/sdk/modules/textures) for creating GPU textures from image files or bytes.
- [`fs`](/sdk/modules/fs) for reading image bytes yourself.

## Aliases and Search Terms

Search terms: image IO, PNG, pixels, flip vertical, jpeg, jpg, image bytes.
