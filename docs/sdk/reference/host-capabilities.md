# Host Capabilities

Host capabilities are named services an app asks for instead of inferring behavior from where it is running. Apps should not branch on a hosted-vs-standalone mode flag; they should request the capabilities they need and adapt only when optional capabilities are explicitly absent.

Current capability names include:

- `viewport`
- `surfaces`
- `presentation`
- `scheduler`
- `input`
- `inspectors`
- `commands`
- `assets`
- `logging`
- `lifecycle`
- `hud`
- `canvas`
- `scene`

Required missing capabilities fail loudly during app creation or mounting. Optional capabilities must be checked explicitly by app code before use, with a deliberate fallback or feature omission.

Use [Hosted Runtime Apps](/dev/features/hosted-runtime-apps) for host implementation details and [Remote Control](/dev/remote-control) when debugging host/app behavior in a running Space process.
