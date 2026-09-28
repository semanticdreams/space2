# colors

## Canonical Import

```fennel
(local colors (require :colors))
```

## Source Files

- `src/lua_colors.cpp`
- `src/colors.h`
- `src/colorspacious.h`

## What It Provides

`colors` exposes native color conversion, color-difference, spectral, density, color-appearance, and color-vision-deficiency helpers.

## API Summary

- Palette and conversion helpers: `create-color-swatch`, `convert-color`, `conversion-path`, `can-convert`, `rgb-to-upscaled`, `rgb-to-hex`, `rgb-from-hex`, and `clamp-rgb`.
- Color spaces include RGB, XYZ, Lab, LChab, Luv, LChuv, xyY, HSV, HSL, CMY, CMYK, and IPT conversion functions.
- White point and spectral helpers: `get-illuminant`, `adapt-xyz`, `spectral-to-xyz`, `ansi-density`, and `auto-density`.
- Difference metrics: `delta-e-cie1976`, `delta-e-cie1994`, `delta-e-cie2000`, `delta-e-cmc`, and matrix variants.
- Appearance and CVD helpers: `model-nayatani95`, `model-hunt`, `model-rlab`, `model-atd95`, `model-llab`, `model-ciecam02`, `model-ciecam02m1`, `ciecam02-space`, `xyz100-to-ciecam02`, `ciecam02-to-xyz100`, `machado-et-al-2009-matrix`, `cvd-forward`, `cvd-inverse`, `cam02-space`, `jmh-to-jab`, and `jab-to-jmh`.

## Examples

```fennel
(local colors (require :colors))
(local glm (require :glm))

(local rgb (glm.vec3 0.2 0.4 0.8))
(local lab (colors.rgb-to-lab rgb))
(print (colors.rgb-to-hex rgb) (colors.delta-e-cie1976 lab lab))
```

## Errors and Platform Notes

Conversion errors come from the native color conversion layer when an unsupported space, illuminant, observer, density standard, or model option is supplied. Many functions use `glm` vector values.

## Related Modules

- [`glm`](/sdk/modules/glm) for vector inputs and outputs.

## Aliases and Search Terms

Search terms: color, colorspace, Lab, Luv, XYZ, delta E, spectral, CIECAM02, CVD.
