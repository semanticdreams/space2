# Runtime Facets

Runtime facets are the pieces an app returns to a host after creation. They let the host present, schedule, inspect, and operate the app without handing over engine lifecycle ownership.

- `metadata` — app identity, title, host API expectations, and other discovery data.
- `presentation` — host-visible surfaces or presentation model data.
- `lifecycle` — startup, teardown, pause, resume, or cleanup hooks the host invokes.
- `scheduler` — per-frame, timed, or deferred work the host schedules.
- `inspectors` — debug or introspection panels exposed by the app.
- `commands` — actions the host can present to users or automation.

Malformed or unsupported facet data should fail at the host boundary rather than silently disappearing. This keeps authoring errors visible and prevents hosts from presenting a partially mounted app as healthy.

See [Commands](/sdk/reference/commands) for command-specific facet data and [Hosted Runtime Apps](/dev/features/hosted-runtime-apps) for implementation details.
