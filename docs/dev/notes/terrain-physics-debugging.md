---
type: dev-note
tags:
  - note
---

# Terrain Physics Debugging Notes

This note documents the recent `heightfield-terrain` physics debugging arc in detail.

The main value of this document is not the final code diff. It is the sequence of wrong
assumptions, misleading symptoms, dead-end fixes, and the architectural lessons that came out
of them.

The core bug was real:

- the rendered terrain and scene query terrain could live under a transformed layout tree
- the Bullet terrain body did not follow that runtime layout transform
- so visible/query terrain and Bullet terrain could disagree about where the terrain actually was

Several secondary bugs and misleading tests made that harder to see than it should have been.

## Final Root Cause

The main architecture bug was:

- render/query terrain used runtime layout transforms
- Bullet terrain used only persisted record `position` / `rotation`

For `heightfield-terrain`, the terrain mesh is not positioned directly at `record.options.position`.
The runtime layout position also includes the terrain mesh `origin-offset` derived from sample bounds.
That means the Bullet body cannot be created once from raw record data and then left alone.

The correct model is:

- build the Bullet heightfield shape from canonical terrain sample data
- keep the Bullet body transform synchronized to the terrain runtime layout transform
- compute the body world transform from:
  - runtime layout position
  - runtime layout rotation
  - Bullet heightfield `center-offset`

This is now implemented by:

- [heightfield-terrain-physics.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/heightfield-terrain-physics.fnl)
- [heightfield-terrain.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/heightfield-terrain.fnl)

The important detail is:

- the terrain layout position already corresponds to the mesh origin including `origin-offset`
- Bullet `btHeightfieldTerrainShape` is centered on its local AABB
- therefore the Bullet world origin must be:
  - `layout-position + rotation * center-offset`

Not:

- raw record position
- raw record position plus some unrelated scene-root offset guessed elsewhere

## Why The Bug Was Hard To See

The symptoms were noisy and easy to misread:

- objects visibly fell through elevated terrain
- some base terrain support still seemed to work
- some tests passed on synthetic terrains
- some probes hit terrain in scene query but still failed in physics
- some debug experiments changed the terrain transform seen by query, making logs contradictory

There were also multiple independent problems discovered during the same period:

1. terrain picker bugs
2. remote-control servicing bug
3. terrain selection harness bugs
4. a real fast-raycast bug unrelated to the terrain-physics transform bug

That made it very easy to overfit the latest symptom.

## Problems Encountered

### 1. Misattributing The Bug To Picking And Query

Early on, the terrain selection problems looked like they might be raycast issues.
That led to debugging effort on:

- fast DDA terrain raycasting
- exact triangle raycasting
- selection overlay fallback behavior
- drag-preview and commit state

Some of that work was valid because there really were selection-flow bugs.
But it was not the root cause of the terrain physics issue.

Important lesson:

- if render/query and Bullet disagree, improving raycast precision does not solve the transform mismatch

### 2. Using Exact Raycast As A General-Purpose Escape Hatch

An exact triangle raycast path was introduced again during debugging.
This was a mistake.

Problems:

- it made the picker slower
- it did not address the actual physics bug
- it encouraged treating “more exact geometry testing” as a substitute for understanding the state flow

That exact path was later removed completely.

Important lesson:

- do not add an expensive “oracle” implementation to fix a symptom unless the symptom is proven to be in the queried geometry path

### 3. Overlay And Preview Logic Masked Real Selection Failures

The old selection overlay could fall back from transient preview to previous committed selection.
That produced a misleading visual symptom:

- when preview became invalid, the overlay appeared to “jump back” to the previous selection

That made it look like the selection target was unstable in arbitrary ways.

The later simplification was better:

- one selection target
- drag begin clears selection
- valid drag sets selection
- invalid drag clears selection
- cancel leaves nothing selected

That did not fix terrain physics, but it removed a large amount of interaction noise.

Important lesson:

- debug the interaction system with the smallest possible state model

### 4. A Real Raycast Bug That Was Not The Physics Bug

There was a real bug in the fast heightfield raycast:

- a cell’s two triangle hits were stored as `[tri0 tri1]`
- the code iterated them with `ipairs`
- if `tri0=nil` and `tri1` hit, `ipairs` stopped early and the hit was lost

That caused periodic picker failures at cell diagonals.

This was fixed correctly, and the regression test was good.
But it was still not the root cause of the terrain physics mismatch.

Important lesson:

- real bugs found during a debugging arc are not automatically the user’s main bug

### 5. Query Diagnostics Were Initially Untrustworthy

Even after the Bullet transform sync fix, some tests still failed.
At that point it looked like Bullet might still be wrong.

But the actual remaining issue was that some tests were bad:

- they probed cells with only one elevated corner
- they treated any cell with a high corner as “elevated support”
- they sometimes derived world probe points before the terrain layout had settled after `build-default`

This produced misleading failures where:

- the query itself said the chosen point was on the low triangle
- or the probe was computed from a pre-settle transform

Those tests were fixed by:

- probing broad elevated cells only
- letting the scene layout settle before deriving runtime world probe points

Important lesson:

- when testing terrain support, probe semantics matter as much as physics semantics

### 6. Excessive Runtime Logging Became Its Own Problem

During debugging, always-on logs were added to:

- terrain creation
- terrain query probes
- ball creation
- body creation

This was useful while diagnosing the live issue, but it left the code noisy and more complex.
Those logs were removed after the core issue was understood.

Important lesson:

- temporary deep logging is fine
- shipping it as permanent runtime behavior is usually not

## Debugging Strategies That Helped

### 1. Compare Three Domains Explicitly

The useful mental model was:

1. rendered terrain
2. scene query terrain
3. Bullet terrain

The debugging improved as soon as each symptom was framed in those three domains instead of saying
“terrain is wrong”.

The real question each time was:

- does render agree with query?
- does query agree with Bullet?
- if not, which transform or representation differs?

### 2. Use Real Saved Worlds, Not Only Synthetic Fixtures

Synthetic terrains were useful, but they often passed.
The first real proof came from:

- using the terrain from the user’s first home world
- dropping many balls above it at a uniform spawn height
- letting physics settle
- then comparing final body positions to terrain support

That exposed a failure synthetic tests did not reliably reproduce.

Important lesson:

- add at least one regression using real persisted terrain data when debugging world-space bugs

### 3. Snapshot + Data Report Was Better Than Either Alone

The most convincing evidence came from pairing:

- a rendered snapshot
- a JSON report counting objects below terrain

The snapshot showed the visual failure.
The report quantified it.

Either alone would have been weaker:

- image only: can be misread
- numbers only: can hide whether the scene setup was wrong

### 4. Narrow The Failing Probe Set

The broadest tests initially mixed too many terrain situations:

- broad plateaus
- narrow ridges
- mixed-height cells
- one-corner spikes

The tests became much more meaningful once probes were split into:

- broad elevated support
- central plateau support
- transformed-terrain support
- query stability across updates

Important lesson:

- one terrain-support test should correspond to one terrain-support claim

### 5. Instrument Until The Question Becomes Mechanical

The useful logs were not “everything everywhere”.
The useful logs answered specific questions:

- what is the runtime terrain layout transform?
- what is the query-record transform?
- what local point does this world point map to?
- what terrain cell and heights are under this body center?

Once those logs existed, the transform mismatch became much more obvious.

## Attempted Fixes That Were Wrong Or Incomplete

These are worth documenting because they are tempting future mistakes.

### 1. Exact Raycast For Physics Symptoms

Wrong because:

- query precision was not the root cause
- the disagreement was transform/domain related

### 2. Teleport Refresh / Broadphase Sync As Primary Fix

There were experiments around:

- refreshing body AABBs
- removing and re-adding bodies
- forcing Bullet sync after teleports

Those addressed overlap recovery semantics, not the terrain transform mismatch.

They were not the correct architectural fix.

### 3. Guessing Query Transform Composition In `scene`

There were attempts to “fix” `terrain-query-record` by composing transforms differently in `scene`.
Those attempts broke more tests because they were modifying query semantics without first isolating
the runtime layout contract.

The actual durable fix was not “more composition in scene”.
It was:

- make Bullet follow the runtime terrain layout
- make tests derive probe points from settled runtime layout

### 4. Treating Mixed-Height Cells As Guaranteed Elevated Support

This produced false failures and should not be repeated.

A cell like:

- `(0, 0, 0, 130)`

is not a plateau.
It is a single elevated corner with one elevated triangle region.

Any test that claims “this is elevated support” must specify:

- the exact probe point
- and ideally whether it expects broad support or just a corner rise

## Final Solutions

### 1. Bullet Heightfield Uses Runtime Layout Transform

Implemented by:

- [heightfield-terrain-physics.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/heightfield-terrain-physics.fnl)
- [heightfield-terrain.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/heightfield-terrain.fnl)

Key behavior:

- create shape from canonical terrain data
- keep rigid body transform synchronized to terrain layout
- update body only when layout position/rotation changes

### 2. Terrain Physics Construction Was Factored Out

The Bullet-specific logic was moved out of `heightfield-terrain.fnl` into its own helper module.

That improved separation of concerns:

- `heightfield-terrain.fnl`
  - terrain widget/runtime
  - render mesh
  - layout
  - overlay
- `heightfield-terrain-physics.fnl`
  - Bullet heightfield shape data
  - rigid body creation
  - runtime transform sync

### 3. Tests Now Use Production Terrain Query Logic

The demo-browser terrain support tests no longer reimplement terrain interpolation in ad hoc ways.

Instead they use:

- [terrain-query.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/terrain-query.fnl)
- specifically `surface-info-at-local-point`

This reduces drift risk between:

- production terrain interpretation
- test terrain interpretation

### 4. Elevated Support Tests Now Probe Broad Elevated Cells

The support tests were rewritten to:

- collect cells whose minimum corner height is already above a threshold
- probe broad elevated support areas
- settle the scene before deriving runtime-layout-based world points

This makes the tests match the actual claim:

- “broad elevated support works”

instead of:

- “some cell with one high corner counts as broad elevated support”

## What To Watch Out For In The Future

### 1. Runtime Layout Is The Source Of Truth For World Transform

If a terrain lives in the scene graph, the runtime layout transform is the real world transform.

Do not assume:

- persisted record transform
- parent transform
- query transform

are interchangeable without checking how the runtime layout is built.

### 2. `origin-offset` And `center-offset` Are Different

This was an important source of confusion.

- `origin-offset`:
  - mesh/layout rebase offset from sample bounds
- `center-offset`:
  - Bullet heightfield center relative to mesh origin

Using one where the other is required will produce visually plausible but wrong transforms.

### 3. Avoid Reimplementing Terrain Interpolation Outside Query Code

If code needs to know the surface height at a point, prefer:

- `TerrainQuery.surface-info-at-local-point`
- `TerrainQuery.surface-info-at-world-point`

Do not copy the interpolation logic into multiple places unless there is a strong reason.

### 4. Broad Plateau Support And Mixed-Cell Support Are Different Tests

Keep those test categories separate.

Suggested categories:

- transformed broad support
- central plateau support
- mixed-cell / diagonal-triangle support
- overlap recovery after teleport

They answer different questions.

### 5. Remove Investigation Logging After The Fix Lands

This debugging arc accumulated a lot of logging.
That is acceptable temporarily.
It is not good final architecture.

Future rule:

- add deep logs freely while isolating a bug
- remove or gate them once the fix and regression tests are in place

### 6. Be Careful About Scene Stabilization In Tests

For layout-dependent runtime objects, tests may need a short stabilization step after build:

- `scene:update` for a small number of ticks

This is not a substitute for correct architecture.
It is a way to avoid deriving probe points from pre-settle runtime layout.

## Possible Remaining Risk Areas

The main bug is fixed, but these areas remain plausible future risk points:

### 1. Terrain Replacement While Bodies Already Rest On Terrain

Terrain replacement and body support are covered better now, but replacing a terrain under already
resting bodies is still a delicate case.

Watch for:

- stale overlap state
- bodies resting on a terrain that changes height underneath them

### 2. Complex Parented Layout Chains

The fixed bug involved a scene-root transform.
If terrain later lives under deeper or more dynamic parent layout chains, the same class of bug could
reappear if any subsystem bypasses runtime layout and uses persisted transform directly.

### 3. Non-Yaw Or More Complex Rotations

The reproductions involved terrain rotations that were easy to visualize.
If more arbitrary rotations become common, keep explicit regression coverage around:

- runtime query transform
- runtime Bullet transform
- persisted record transform

### 4. Heightfield Shape Conventions

The current code uses `btHeightfieldTerrainShape` with:

- `up-axis = 1`
- `flip-quad-edges = false`

If Bullet settings are changed later, re-check:

- render/query triangle interpretation
- support on mixed-height cells

especially because those failures are easy to misread as transform bugs.

## Recommended Rules Going Forward

1. If a subsystem needs world-space terrain behavior, derive it from runtime layout, not raw record transform.
2. Keep terrain query logic canonical and reuse it from tests.
3. Separate broad-support tests from mixed-cell tests.
4. Do not use exact raycast or extra geometry paths as a substitute for understanding transform/state ownership.
5. Remove debug logging once the bug is understood and covered by tests.
6. When debugging terrain/world mismatches, always compare render, query, and Bullet as separate domains.

## Current State

The current state after the cleanup is:

- Bullet terrain follows runtime terrain layout
- scene terrain support queries are stable across updates
- transformed broad elevated terrain support is covered by tests
- real saved-world terrain support is covered by tests
- the temporary runtime logging used during debugging has been removed
- Bullet-specific heightfield code is factored into its own module

Relevant files:

- [heightfield-terrain-physics.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/heightfield-terrain-physics.fnl)
- [heightfield-terrain.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/heightfield-terrain.fnl)
- [terrain-query.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/terrain-query.fnl)
- [scene.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/scene.fnl)
- [test-demo-browser.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-demo-browser.fnl)
- [test-heightfield-terrain.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-heightfield-terrain.fnl)


## See also

- [World Building](/dev/features/world-building), [Terrain Heightfield System](/dev/features/terrain-heightfield-system)
