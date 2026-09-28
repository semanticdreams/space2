# Scene Capability

The `scene` capability lets an app create and manipulate scene objects through app-owned handles instead of raw Space scene entities or backend objects.

Methods include:

- `spawn`
- `despawn`
- `set-transform`
- `get-transform`
- `list-owned`
- `query-volume`
- `height-at`
- `raycast-terrain`
- `drop`

`spawn` returns handles owned by the app. App code passes those handles back to scene methods for later updates, queries, or cleanup. Apps should not retain raw engine scene entities or backend-specific objects because the host remains responsible for scene lifetime and backend selection.

Invalid handles and unsupported spawn kinds fail loudly at the scene capability boundary.

See [UI Surfaces](/sdk/guides/ui-surfaces) for choosing scene presentation targets and [Hosted Runtime Apps](/dev/features/hosted-runtime-apps) for host-side details.
