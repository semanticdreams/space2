# Add a Command

Goal: expose one host-invocable command from a hostable app.

A command facet entry names an action that the host can show, inspect, and invoke. A minimal synchronous command entry looks like this:

```fennel
{:id :reset
 :title "Reset"
 :description "Reset app state"
 :danger-level :normal
 :run reset-fn}
```

For a useful sync command entry, `:id`, `:title`, and `:run` are required. The `:id` is the stable command key inside the app, `:title` is the user-facing label, and `:run` is the function the host invokes.

Use `:danger-level` to describe the risk of the command. Valid values are `:normal`, `:warning`, and `:danger`. Required confirmation is explicit through `:confirmation`; danger does not imply confirmation.

Malformed command metadata should fail loudly so the app author sees bad command shape during development instead of shipping an action the host cannot invoke correctly.

## Next Steps

- [Commands Reference](/sdk/reference/commands) — look up command metadata, payloads, and expected failures.
- [Runtime Facets Reference](/sdk/reference/runtime-facets) — see how command registration fits with other host facets.
- [Hosted Runtime Apps](/dev/features/hosted-runtime-apps) — inspect maintainer-facing implementation details when you need internals.
