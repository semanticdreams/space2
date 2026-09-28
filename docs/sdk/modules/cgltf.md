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
- `CgltfData` exposes lifecycle and conversion methods:
  - `valid()` reports whether the native parse handle is still live.
  - `drop()` releases the native parse handle; other methods error after drop.
  - `to-table()` converts parsed scenes, nodes, meshes, materials, textures, buffers, accessors, extras, and extension metadata to Lua/Fennel tables.
  - `json()` returns the embedded JSON chunk as a string, or `nil` when unavailable.
  - `bin()` returns the embedded GLB binary chunk as a string, or `nil` when unavailable.
  - `load-buffers(options path)` loads external, data URI, and GLB buffer payloads for the parsed asset. Pass `nil` for default options; `path` may be omitted or `nil` when no base path is needed.
  - `validate()` runs cgltf validation and raises a cgltf result error on invalid data.
  - `buffer-data(index)` returns loaded buffer bytes for a 1-based buffer index, or `nil` when that buffer has no loaded data.
  - `buffer-view-data(index)` returns loaded bytes for a 1-based buffer view index, using view-local data or the parent buffer plus offset, or `nil` when unavailable.
  - `accessor-unpack-floats(index)` returns all values from a 1-based accessor as a flat float table.
  - `accessor-read-float(accessor-index element-index [element-size])` reads one accessor element as floats.
  - `accessor-read-uint(accessor-index element-index [element-size])` reads one accessor element as unsigned integers.
  - `accessor-read-index(accessor-index element-index)` reads one index element from an index accessor.
  - `node-transform-local(node-index)` and `node-transform-world(node-index)` return 16-number local/world transform matrices for a 1-based node index.
  - `extras-json(extras-table)` copies raw extras JSON for a table containing `start-offset` and `end-offset`, such as an `extras` table returned by `to-table()`.

## Examples

```fennel
(local cgltf (require :cgltf))

(local data (cgltf.parse-file "assets/models/example.gltf"))
(when (data:valid)
  (data:load-buffers nil "assets/models/example.gltf")
  (data:validate)
  (local model (data:to-table))
  (print (: "mesh count: %d" :format (length model.meshes)))
  (when (> (length model.nodes) 0)
    (local matrix (data:node-transform-world 1))
    (print (: "node[1] m00: %.3f" :format (. matrix 1)))))
```

## Errors and Platform Notes

Parsing, loading, and validation errors include cgltf result names such as `invalid-json`, `invalid-gltf`, `file-not-found`, `io-error`, or `out-of-memory`. `to-table`, buffer/accessor readers, transform helpers, and `extras-json` require the handle to remain valid; call `drop` only after consumers are finished. Buffer and buffer-view byte readers return `nil` until payloads are available, so call `load-buffers` before reading external or data URI buffers. Index arguments are 1-based and out-of-range buffer, buffer-view, accessor, element, or node indexes raise explicit errors. Accessor reads delegate to cgltf conversion helpers and may return empty tables when cgltf cannot read the requested element. `extras-json` needs the source JSON chunk retained by the handle and an extras table with `start-offset`/`end-offset` fields.

## Related Modules

- [`glm`](/sdk/modules/glm) for consuming numeric vectors and transforms after conversion.
- [`textures`](/sdk/modules/textures) for loading textures referenced by models.

## Aliases and Search Terms

Search terms: glTF, GLB, cgltf, model parser, mesh, scene, accessor.
