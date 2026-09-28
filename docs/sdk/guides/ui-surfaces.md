# UI Surfaces

SDK-facing UI surfaces are host-provided presentation targets and adapters. Apps ask the host for presentation capabilities, then render into the surfaces the host exposes instead of reaching into concrete Space views.

HUD and canvas are generic surfaces exposed by a host. Use them for app-owned overlays, panels, controls, and 2D presentation that should remain independent from a specific workspace implementation.

When an app needs 3D objects, scene access should go through `host.scene`. Treat scene behavior as a capability with required inputs and expected failures rather than assuming every host exposes the same renderer or world state.

Presentation facets can expose render targets, input controls, screen-position rays, and camera access. Document which facets your app requires and fail loudly when a host cannot provide them.

Keep app logic decoupled from concrete Space views. App state, commands, and lifecycle behavior should be testable without a specific HUD, canvas, scene view, or workspace implementation.

See [Runtime Facets](/sdk/reference/runtime-facets), [Scene Capability](/sdk/reference/scene-capability), [Orthographic UI Surface](/dev/features/orthographic-ui-surface), and [Layout Widget Engine](/dev/features/layout-widget-engine) for related contracts and implementation details.
