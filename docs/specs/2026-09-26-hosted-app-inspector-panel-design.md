# Hosted App Inspector Panel Design

## Context

Hosted apps can now mount into workspaces, expose shared host capabilities, and
mirror app-owned scene objects through `host.scene`. The current workspace panel
is still intentionally minimal: it mounts an app, adds one HUD child descriptor,
and exposes pause/resume/step/close controls. The next useful tooling layer is a
generic, read-only inspector slice that makes mounted app state visible without
introducing a full editor protocol.

The host already has inspector and command registries. Apps such as Snake
register plain-data inspector facets through those registries. This subproject
should surface those existing facets through the workspace panel rather than
adding app-specific APIs.

## Goals

- Add a first read-only hosted app inspector panel slice.
- Preserve `WorkspacePanel.open(opts)` and the existing session API:
  `mount`, `pause`, `resume`, `step`, and idempotent `close`.
- Read inspector and command data from the embedded host registries.
- Represent plain-data inspectors in a stable snapshot shape.
- Surface inspector read failures explicitly instead of silently omitting them.
- Keep command entries metadata-only; do not execute commands in this slice.
- Preserve existing workspace mount ownership and teardown behavior.
- Document the new read-only inspector capability and follow-up boundaries.

## Non-goals

- Do not add a new hosted app entrypoint method.
- Do not add app-specific inspector methods or Snake-specific UI.
- Do not add mutation/editing controls.
- Do not execute commands from the panel.
- Do not introduce a custom moldable renderer protocol.
- Do not add graph nodes, graph persistence, launcher UX, app discovery, or
  persistent editor state.
- Do not change generic runtime-controller inspector/command facet semantics
  unless tests reveal a bug in the existing registry contract.

## Recommended approach

Introduce a small `app-host.workspace-inspector-snapshot` helper that reads the
current embedded host registries and returns plain data:

```fennel
{:inspectors [...]
 :commands [...]}
```

Then extend `app-host.workspace-panel` descriptors/sessions with read-only
snapshot access. This is deliberately smaller than building a full visual editor:
the first slice exposes the data contract that UI rendering and future editing
can build on, while preserving the existing HUD child lifecycle and tests.

This approach was chosen over two alternatives:

- Keeping the panel descriptor-only is too invisible now that hosted apps expose
  inspectors and commands.
- Building a full moldable editor protocol would overfit before we have enough
  concrete inspector/editor examples.

## Architecture

### Snapshot helper

`assets/lua/app-host/workspace-inspector-snapshot.fnl` should expose:

```fennel
{:read-host read-host}
```

`read-host(host)` requires:

- `host.inspectors:list()`;
- `host.commands:list()`.

It returns:

```fennel
{:inspectors [{:id id
               :title title
               :status :ok|:error|:unsupported
               :data plain-data-or-nil
               :error error-message-or-nil}]
 :commands [{:id id
             :title title
             :description description-or-nil
             :status :metadata}]}
```

Readable inspectors are facets with a `read` function. Their `read` result is
captured as `:data`. If `read` raises, the snapshot entry must contain
`:status :error` and a string `:error`. Inspectors without `read` are included as
`:status :unsupported` rather than omitted.

Commands are never executed. The snapshot records only metadata fields that are
already present on the command facet.

### Workspace panel integration

`WorkspacePanel.open(opts)` should still mount the app, add one HUD child, and
return a session with the existing control methods. The descriptor and session
should additionally provide snapshot access, for example through a function such
as `read-inspector-snapshot` that delegates to the snapshot helper using
`mount.host`.

The panel widget can remain visually minimal in this first slice, but the built
widget/descriptor must expose enough read-only data for tests and future UI work.
The integration must not mutate inspector data, execute commands, or alter
runtime controller registration behavior.

### Error handling

- Missing `host.inspectors:list` or `host.commands:list` fails loudly with an
  `app-host.workspace-inspector-snapshot` error.
- Inspector `read` failures are captured as explicit `:error` entries so one bad
  inspector does not hide the rest of the mounted app state.
- Workspace panel mount/HUD failure behavior remains unchanged: HUD add failure
  drops the mount; missing HUD fails before mounting.

## Testing strategy

Add focused snapshot tests for:

- successful readable inspector snapshots;
- unsupported inspectors without `read`;
- inspector read failures represented as error rows;
- command metadata snapshots without command execution;
- loud failures for malformed registries.

Extend workspace panel tests for:

- descriptor/session snapshot access;
- builder path retaining snapshot access;
- existing pause/resume/step/close behavior unchanged;
- close and HUD add failure teardown unchanged.

Validation should use Space-native Fennel commands:

1. touched-file `tools.fennel-check` or `make fennel-check`;
2. `make constraints`;
3. focused snapshot and workspace panel tests;
4. broader hosted runtime/workspace tests if panel integration affects mount
   behavior.

## Acceptance criteria

- Hosted workspace sessions expose read-only inspector snapshots from host
  registries.
- Plain-data inspector data is visible through a stable snapshot shape.
- Inspector read failures appear as explicit error entries.
- Command facets appear as metadata only and are not executed.
- Existing workspace panel session controls and teardown semantics remain intact.
- No new app entrypoint, app-specific inspector API, command execution, or editor
  mutation protocol is added.

## Follow-up

Future subprojects can turn these snapshots into richer visual widgets, command
execution surfaces, editable controls, graph-backed inspectors, persistent app
discovery, and app-specific moldable editors once the read-only contract has
proven useful.
