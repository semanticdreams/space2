# graph-edge-batch

## Canonical Import

```fennel
(local graph-edge-batch (require :graph-edge-batch))
```

## Source Files

- `src/lua_graph_edge_batch.cpp`

## What It Provides

`graph-edge-batch` writes batches of graph edge triangle vertex data into a `vector-buffer` for rendering.

## API Summary

- `write-triangle-batch(buffer handles starts ends colors thicknesses depths)` writes one 3-vertex triangle per handle.
- Each handle must have room for at least 24 floats: three vertices with position, color, and depth attributes.
- The input arrays must all have the same length.

## Examples

```fennel
(local graph-edge-batch (require :graph-edge-batch))
(local vector-buffer (require :vector-buffer))
(local glm (require :glm))

(local buffer (vector-buffer.VectorBuffer 24))
(local handle (buffer:allocate 24))
(graph-edge-batch.write-triangle-batch
  buffer [handle]
  [(glm.vec3 0 0 0)] [(glm.vec3 1 1 0)]
  [(glm.vec4 1 1 1 1)] [2.0] [0.0])
```

## Errors and Platform Notes

The function raises if input array sizes differ, if handles are too small, or if handle ranges exceed the buffer length.

## Related Modules

- [`vector-buffer`](/sdk/modules/vector-buffer) for allocation and dirty tracking.
- [`glm`](/sdk/modules/glm) for position and color vectors.

## Aliases and Search Terms

Search terms: graph edge, edge batch, triangle edge, render batch, graph rendering.
