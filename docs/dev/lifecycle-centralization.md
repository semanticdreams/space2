---
type: tech-debt
impact: high
effort: large
status: resolved
tags:
  - tech-debt
  - lifecycle
  - centralization
created: 2026-07-14
updated: 2026-10-15
---

# Lifecycle ownership centralization

## Summary

The April 2026 push to replace implicit, signal-driven ownership with explicit,
centralized lifecycle management. Ownership is a prerequisite for hot reload,
activities and reliable teardown, not proof of independently fresh replacement.
See the [reload boundary contract](/dev/reloadable-units) before enabling a
smaller boundary.

## What was done

1. **Centralized frame update** — single update entry point owns the full update pass (`2026-04-15`)
2. **Signal lifecycle hardening** — explicitly managed connections disconnect on owner teardown; graph views explicitly cleaned up before rebuild (`2026-04-16`)
3. **Double-drop fix** — composite view children teardown clarified (`2026-04-16`)
4. **UnitManager** — explicit unit registry, SourceUnit, and runtime unit lifecycle (`2026-05-08`)
5. **Activity lifecycle centralization** — workspace shell owns activate/deactivate lifecycle (`2026-04-30`, migrated from canvas modes in July 2026)

## Results

- Reduced stale-callback-after-drop failures through explicit teardown ownership.
- Enabled lifecycle reload operations; controller-driven development reloads now
  default to app-root. Built-in child lifecycles and experimental narrow fixtures
  do not establish that every retained consumer uses fresh code.
- Activity activation supports explicit cleanup stacks and staged runtime hooks;
  panel transfer has its own scoped transaction behavior. Neither is universal
  side-effect rollback for unit reloads.

`Unit:connect-signal` tracks named connections and disconnects them on unload or
failed-load cleanup. It does not automatically own arbitrary `signal:connect`
calls, pending callbacks, timers or async work. Authors must register cleanup,
order consumer/provider teardown, and address retained executable references.
Direct Unit/manager/agent/MCP reloads do not inherit controller root eligibility
or its tracked-module recovery. These limits remain even with centralized
lifecycle ownership.

## Related

- [Lifecycle Ownership](/dev/project/tech-debt/tech-debt-lifecycle-ownership) — the bugs this fixed
- [Lifecycle Hardening Plan](/dev/lifecycle-hardening-plan) — the full plan and strategy options
- [Lifecycle Invariants](/dev/lifecycle-invariants) — the finalized rules
- [Widget Ownership](/dev/widget-ownership-and-teardown) — teardown ownership model
- [Hot Reload Units](/dev/features/hot-reload-units) — dependent on lifecycle safety
- [Activities Architecture](/dev/features/activities) — dependent on lifecycle safety

## See also

- Goal: [Core Platform](/dev/features/core-platform)
