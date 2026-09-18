# Orthographic UI Surface

`orthographic-ui-surface` is a small retained presentation surface for
standalone Space UI examples and simple apps. It owns a `LayoutRoot`, a
`BuildContext`, viewport-scaled world units, and a HUD-like renderer
presentation target.

Use it when an example needs normal Space widgets, text, rectangles, and
layout without importing the full product HUD shell.

Do not use it for product HUD panels, command hints, focus/movable/resizable
registries, activity slots, world cameras, or Canvas rendering.

## API

```fennel
(local OrthographicUiSurface (require :orthographic-ui-surface))
(local surface (OrthographicUiSurface.create {:viewport viewport}))
(local entity (surface:build builder))
(surface:update-viewport viewport)
(surface:update)
(surface:presentation-target)
(surface:drop)
```

`builder` receives the surface `BuildContext` and should return a retained
widget/entity with `:layout`, optional `:update`, and optional `:drop`.

## Coordinates

The surface uses a lower-left origin and non-inverted Y projection:

```fennel
(glm.ortho 0 world-width 0 world-height -100.0 100.0)
```

Higher world Y renders higher on screen. Text remains upright.

## Example

`examples/snake` uses this surface for its board, title, status, and controls
while remaining a standalone example app.
