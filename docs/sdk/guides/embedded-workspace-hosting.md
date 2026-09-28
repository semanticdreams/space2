# Embedded Workspace Hosting

Embedded hosts mount an app inside a Space workspace without replacing global renderer state. The workspace provides the host surface, while the embedded app receives only the capabilities it is allowed to use.

Calling `host.lifecycle:quit()` closes the workspace mount for that embedded app. It does not shut down the entire Space process, close unrelated workspaces, or take ownership of global runtime shutdown.

HUD, canvas, and scene adapters own the children they add. When an embedded app creates presentation objects through those adapters, teardown should remove the app-owned children without disturbing objects owned by the surrounding workspace.

Mount teardown is idempotent. Cleanup paths should tolerate repeated close, unload, or failure cleanup calls without double-removing children or reporting false success for missing required operations.

If app creation fails, clean up the embedded host before rethrowing the failure. This keeps partial mounts from leaking presentation objects, scene objects, command registrations, or lifecycle handles while still surfacing the original creation error.

See [Host Capabilities](/sdk/reference/host-capabilities), [Scene Capability](/sdk/reference/scene-capability), and [Hosted Runtime Apps](/dev/features/hosted-runtime-apps) for the current contracts and deeper implementation details.
