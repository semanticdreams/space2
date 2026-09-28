# Hostable Runtime Apps

Hostable runtime apps expose a `create(host) -> runtime` entrypoint. The host supplies capabilities and runtime facets; the app returns the runtime object that owns its lifecycle, commands, and app state.

Apps must not create, start, run, shut down, or drop `Engine` directly. Engine ownership stays with the host so the same app can run in standalone launchers, embedded workspaces, or other host shapes without special-case process control.

Request the capabilities your app needs from the host instead of checking a hosted-vs-standalone flag. For example, an app that needs presentation, scene access, commands, or scheduling should ask for those facets directly and document which ones are required.

Missing required capabilities should fail loudly during creation or capability resolution. Do not silently skip lifecycle hooks, commands, rendering, or scene behavior when a required facet is unavailable; clear failures make host integration problems debuggable.

See [App Module Contract](/sdk/reference/app-module-contract), [Host Capabilities](/sdk/reference/host-capabilities), [Runtime Facets](/sdk/reference/runtime-facets), and [Hosted Runtime Apps](/dev/features/hosted-runtime-apps) for contract details and implementation notes.
