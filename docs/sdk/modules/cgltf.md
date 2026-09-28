# cgltf

## Canonical Import

```fennel
(local cgltf (require :cgltf))
```

## Source Files

- `src/lua_cgltf.cpp`
- `src/lua_cgltf.h`

## What It Provides

`cgltf` wraps the native cgltf parser for reading glTF/GLB data and converting parsed data into Lua/Fennel tables.

## API Summary

- `parse(data)` and `parse(options data)` parse glTF/GLB bytes.
- `parse-file(path)` and `parse-file(options path)` parse a glTF/GLB file.
- `load-buffer-base64([options] size base64)` decodes a base64 buffer through cgltf allocation hooks.
- `decode-string(input)`, `decode-uri(input)`, and `num-components(type)` expose cgltf utility helpers.
- `malloc(size)` and `free(pointer)` expose the allocation helpers used by option callbacks.
- `enums` contains cgltf enum tables for file types, result values, component types, primitive types, alpha modes, animation paths, interpolation, camera types, light types, and meshopt options.
- `CgltfData` exposes `valid`, `drop`, `json`, and `to-table`.

## Examples

```fennel
(local cgltf (require :cgltf))

(local data (cgltf.parse-file "assets/models/example.gltf"))
(when (data:valid)
  (local model (data:to-table))
  (print (: "mesh count: %d" :format (length model.meshes))))
```

## Errors and Platform Notes

Parsing errors include cgltf result names such as `invalid-json`, `invalid-gltf`, `file-not-found`, `io-error`, or `out-of-memory`. `to-table` requires the handle to remain valid; call `drop` only after consumers are finished.

## Related Modules

- [`glm`](/sdk/modules/glm) for consuming numeric vectors and transforms after conversion.
- [`textures`](/sdk/modules/textures) for loading textures referenced by models.

## Aliases and Search Terms

Search terms: glTF, GLB, cgltf, model parser, mesh, scene, accessor.
