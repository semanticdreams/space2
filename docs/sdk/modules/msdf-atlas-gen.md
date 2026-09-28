# msdf-atlas-gen

## Canonical Import

```fennel
(local msdf-atlas-gen (require :msdf-atlas-gen))
```

## Source Files

- `src/lua_msdf_atlas_gen.cpp`

## What It Provides

`msdf-atlas-gen` wraps msdf-atlas-gen to build signed-distance-field font atlases and optional metadata files.

## API Summary

- `generate(options)` generates an atlas from one or more font inputs and returns a table with `width`, `height`, `em-size`, `px-range`, and `glyph-count`.
- Font options include `:font`, `:varfont`, charset inputs (`:charset`, `:glyphset`, `:chars`, `:glyphs`, `:allglyphs`), `:fontscale`, and `:fontname`.
- Atlas options include `:type`, `:format`, `:dimensions`, `:size`, `:pxrange`, packing constraints, padding, `:yorigin`, coloring, error correction, `:threads`, and output filenames such as `:imageout`, `:json`, `:csv`, `:arfont`, or `:shadronpreview`.
- Supported image types include `hardmask`, `softmask`, `sdf`, `psdf`, `msdf`, and `mtsdf`; supported output formats include `png`, `bmp`, `tiff`, raw/text formats, and binary formats.

## Examples

```fennel
(local msdf-atlas-gen (require :msdf-atlas-gen))

(local result
  (msdf-atlas-gen.generate
    {:font "assets/fonts/Inter-Regular.ttf"
     :charset "Hello, Space!"
     :type :msdf
     :format :png
     :imageout "/tmp/inter-msdf.png"
     :json "/tmp/inter-msdf.json"}))

(print result.width result.height result.glyph-count)
```

## Errors and Platform Notes

The module validates font paths, enum strings, dimensions, output paths, and charset settings and raises errors prefixed with `msdf-atlas-gen:`. Available output features depend on how the native msdf-atlas-gen library was built.

## Related Modules

- [`textures`](/sdk/modules/textures) for loading generated atlas images.
- [`json`](/sdk/modules/json) for reading generated metadata.

## Aliases and Search Terms

Search terms: MSDF, SDF font, font atlas, glyph atlas, msdf-atlas-gen, typography.
