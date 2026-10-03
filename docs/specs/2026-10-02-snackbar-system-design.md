# Snackbar System Design

## Context

Space needs a production-ready snackbar system for brief, actionable UI feedback. The system should serve the main Space HUD and also be reusable by independent Space-based GUI apps that may want different snackbar policies. Existing UI frameworks split this problem into hosts, providers, state, data, and options. Space should adopt that separation while fitting its retained Fennel widget model and HUD layout rules.

The existing HUD already has layout-native regions for control/status panels, side docks, the center scene stack, middle overlays, and full overlays. The snackbar system must use those layout boundaries rather than fixed offsets: control panels, status panels, toolbars, and side rails can change size dynamically. The default Space host should therefore live inside the dynamically measured center/middle HUD region, not in the full-screen overlay.

## Requirements

- Provide a modern snackbar/toast system with clean manager, host, content, policy, and theme boundaries.
- Support independently scoped snackbar managers and hosts from the beginning. The global HUD snackbar scope is only the default, not the only supported usage.
- Default HUD placement is top-right and theme-configurable.
- Default HUD snackbars must not cover the control panel, status panel, top toolbar, or side rails/docks.
- Do not rely on static offsets to avoid HUD chrome; placement must follow dynamic layout bounds.
- Snackbar content may be simple text, text plus action buttons, or arbitrary widget content supplied by a builder.
- The manager must remain widget-free: it owns entries, queue policy, timers, handles, and change notifications, not rendered widgets.
- The host must own rendered snackbar widgets and drop them exactly once following Space widget ownership rules.
- Support extensible policies: max visible, max queued, newest-first display, priority ordering, replacement/deduplication, drop/queue overflow modes, persistence, and per-entry duration.
- Initial implementation should not include a scrollable snackbar host. Overflow is handled by policy, not by making transient snackbars a scroll view.
- Theme tokens should configure placement, spacing, padding, max width, default duration, visible/queued limits, and variant colors.
- Preserve existing HUD panel, overlay, command-hints, and layout behavior.

## Approach Options

### Option 1: Global HUD overlay queue

A singleton snackbar manager could create overlay children through `Hud.add-overlay-child` and position them with top-right offsets.

Pros: small implementation surface; similar to the command-hints overlay manager pattern.

Cons: rejected. It bakes in global ownership, cannot support scoped hosts cleanly, and cannot reliably avoid dynamically changing control/status panels or side rails without fragile placement math.

### Option 2: Layout-native scoped manager and host

Each snackbar scope owns a `SnackbarManager`. A `SnackbarHost` widget renders visible manager entries inside whatever layout region contains the host. The default HUD host is mounted inside the center/middle HUD stack so existing layout computation already excludes top/bottom chrome and side rails.

Pros: recommended. It matches Space widget ownership, supports scoped hosts from day one, separates policy from rendering, accepts arbitrary widget content, and solves dynamic HUD placement by composition instead of offsets.

Cons: requires new manager/host modules plus HUD layout integration and thorough tests.

### Option 3: Central snackbar broker with registered portal hosts

A global broker could route requests to named host scopes such as `:global`, `:world`, or `:panel-id`.

Pros: powerful for future cross-app routing and hosted app integration.

Cons: not recommended for the first version. It adds registry lifetime and routing concerns before the product needs them. Independently instantiated managers/hosts provide the required flexibility with clearer ownership.

The recommended approach is option 2.

## Design

### Manager and scope model

`SnackbarManager` is a pure state/policy object. It owns:

- normalized snackbar entries;
- stable ids and sequence ordering;
- visible and queued lists;
- timer handles for auto-dismissed entries;
- dismissal, replacement, and clear operations;
- a change signal or equivalent subscription API;
- terminal `drop` behavior that cancels timers and rejects later public mutation.

The default creation API should make scopes explicit. A small facade such as `Snackbar.create-scope(opts)` can return a manager and a host builder configured with the same policy/theme defaults. Apps can create multiple independent scopes without sharing queues or timers.

The HUD creates one default scope and exposes convenience methods such as `hud:show-snackbar(request)` and `hud:dismiss-snackbar(id, reason)`. These are convenience APIs only; independent Space GUI apps can instantiate their own manager and host directly.

### Entry data and handles

Snackbar requests are tables normalized into entries with fields such as:

- `:id` — caller-supplied or generated stable id;
- `:text` or `:message` — simple text content;
- `:content-builder` — optional arbitrary widget builder for rich content;
- `:actions` — optional action descriptors for the default content builder;
- `:variant` — semantic style such as `:info`, `:success`, `:warning`, or `:error`;
- `:priority` — numeric or symbolic ordering input;
- `:duration-ms` — auto-dismiss duration when not persistent;
- `:persistent?` — disables auto-dismiss;
- `:replace-key` — replaces an existing visible or queued entry with the same key;
- `:mode` — overflow behavior such as `:queue`, `:drop`, or `:replace`;
- `:metadata` — application-specific data that manager policy preserves but does not interpret.

`show` should return a handle containing the entry id and a dismiss method. Handles may later grow update/action-result helpers, but the first design only requires stable dismissal.

### Policy

Policy belongs to the manager, not the host. The host renders whatever the manager marks visible.

The Space default policy should be a non-scrollable stack:

- newest visible entries appear at the top;
- visible count is capped by theme/policy, with a default suitable for unobtrusive HUD use;
- overflow queues by default rather than becoming scrollable;
- replacement via `:replace-key` prevents noisy duplicate progress/status messages;
- higher-priority entries can be ordered before lower-priority entries when a priority policy is enabled;
- persistent entries remain until dismissed and count against visible capacity.

Other apps can choose a single FIFO snackbar policy, a small fixed stack, a priority stack, or a drop/replace policy by configuring the manager.

### Host and content rendering

`SnackbarHost` is a widget builder that consumes a manager. It subscribes to manager changes, reconciles visible entries by id, builds/drops child widgets, and marks its own layout dirty when the visible set changes.

The host owns all rendered snackbar widgets. It must disconnect from manager change notifications and drop direct children on `drop`. It should assert on missing required options such as `:manager` rather than silently falling back.

Content rendering has two paths:

1. If an entry supplies `:content-builder`, the host uses that builder directly.
2. Otherwise, a default snackbar content builder creates a card-like widget from text, variant styling, and optional action buttons.

Action callbacks receive enough context to dismiss or inspect the entry, for example `(entry handle button event)`. Timed snackbars should not be the only path to critical actions; application code remains responsible for safe action semantics.

### HUD layout integration

The default HUD host should be mounted in `hud-layout.make-hud-builder` as a child of the center/middle scene stack, in a layer above normal tiles/floating panels but within the center column that excludes side docks and above/below chrome. This gives it dynamically measured bounds that move with control panels, status panels, top toolbar, and rails.

The existing `Hud.add-overlay-child` API remains useful for modal/full overlays and command hints. It should not be the primary snackbar surface because full overlays and offset-based middle overlays do not encode the required safe area semantics.

Theme rebuilds should rebuild the host with current context while preserving manager state owned by the HUD scope. `Hud:drop` drops the default snackbar scope exactly once.

### Theming

Theme tokens should live under `ctx.theme.snackbar` and include:

- `:placement`, default `:top-right`;
- `:max-visible` and `:max-queued` defaults;
- `:duration-ms` default;
- `:spacing`, `:padding`, and `:max-width`;
- background/foreground/border tokens;
- variant colors for `:info`, `:success`, `:warning`, and `:error`;
- optional action button style tokens consumed by the default content builder.

Theme options configure defaults, but per-manager and per-entry options can override policy where appropriate.

## Testing

Focused tests should cover:

- manager normalization rejects missing content;
- generated and caller-supplied ids are stable;
- newest-first visible ordering;
- max visible and max queued behavior;
- queued promotion after dismiss;
- priority ordering when enabled;
- replace-key deduplication for visible and queued entries;
- auto-dismiss timers start only when entries become visible;
- persistent entries do not auto-dismiss;
- `drop` cancels timers and public mutation after drop asserts;
- host requires a manager;
- host renders visible entries and drops removed children exactly once;
- host supports simple text, text/actions, and arbitrary content builders;
- host marks layout dirty on manager changes;
- host disconnects subscriptions on drop;
- HUD host bounds exclude control/status panels, top toolbar, and side docks;
- HUD convenience APIs delegate to the default manager;
- theme tokens affect host placement/style defaults.

Validation should follow the Space Fennel ladder: compile check, constraints, focused snackbar/HUD tests, then broader validation because HUD layout and theme tokens are shared UI infrastructure.

## Non-Goals

- OS-level desktop notifications.
- Scrollable snackbar history or notification center UI.
- Cross-process or global portal broker routing.
- Animation system work beyond static layout-ready placement.
- Persistence of snackbar history across HUD/app reloads.
- Replacing command hints, dialogs, menus, or panel persistence.
