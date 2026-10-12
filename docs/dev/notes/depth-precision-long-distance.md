---
type: dev-note
tags:
  - note
---

# Depth Precision For Long-Distance Rendering

## Current State

The current scene projection is defined in [assets/lua/app-projection.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/app-projection.fnl):

- perspective projection via `glm.perspective`
- vertical FOV: `0.7853982` radians, about `45` degrees
- near plane: `1.0`
- far plane: `10000.0`

The current renderer is still using a conventional forward-Z depth setup:

- depth comparison: `GL_LESS` in [assets/lua/renderers.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/renderers.fnl)
- normal depth clears with `GL_DEPTH_BUFFER_BIT`
- no `glClipControl`
- no logarithmic depth write in shaders

So the engine today is the standard case:

- near maps to depth values close to `0`
- far maps to depth values close to `1`
- precision is concentrated near the camera
- pushing the far plane out hurts, but pushing the near plane inward hurts much more

This note covers the long-term options for improving long-distance visibility without introducing unacceptable z-fighting or precision loss.

## Why Precision Gets Bad

Perspective depth is not linear in view-space distance. The depth buffer allocates much more precision to geometry close to the camera than geometry far away.

That means:

- halving the near plane is usually much more damaging than doubling the far plane
- very large world ranges with a tiny near plane produce z-fighting, terrain shimmer, and unstable ordering
- the problem is not specific to our terrain tools; it affects all scene geometry using the same depth buffer

For our current style of app, the likely long-range pressure points are:

- terrain and sky-scale world views
- large scenes with distant props
- wanting both close interaction and long visibility in the same camera mode

## Option 1: Standard Perspective With Better Near/Far Choices

This is what we are doing now.

### What it is

Keep the existing projection and depth pipeline, but choose better clip planes.

### Pros

- simplest
- no renderer architecture change
- no shader change
- no compatibility issues with current materials or passes

### Cons

- only delays the problem
- still fundamentally limited for very large ranges
- can force an uncomfortable compromise between close-up interaction and distant visibility

### Best use

- short-term tuning
- projects that do not need true massive-scale draw distances
- separate camera modes where different near/far pairs are acceptable

### Notes for this repo

This is fully compatible with the current system because it is the current system.

## Option 2: Reversed-Z

This is usually the best long-term default for large 3D scenes if the renderer can support it cleanly.

### What it is

Reverse the depth mapping so:

- near corresponds to depth values near `1`
- far corresponds to depth values near `0`
- depth test becomes `GL_GREATER` or `GL_GEQUAL`
- depth clear becomes `0` instead of `1`

The reason this helps is that floating-point depth values have denser representation near `0`, so reversed-Z moves the precision where far geometry needs it.

### Pros

- large precision improvement, especially at distance
- preserves a normal perspective camera model
- usually better than trying to fight precision with clip-plane tuning alone
- pairs very well with floating-point depth buffers

### Cons

- not just a parameter tweak
- affects projection conventions, clear values, and depth test state
- every depth-aware render pass must be audited
- some custom shaders or post-processing that assume forward-Z may break

### What changes

At minimum:

- projection generation
- depth clear value
- depth comparison function
- any code reconstructing view-space depth from depth textures
- any pass that samples depth and assumes near=`0`, far=`1`
- skybox and special-case depth handling

Depending on API choices, reversed-Z may also use `glClipControl` to move to a zero-to-one clip-space convention instead of OpenGL's default minus-one-to-one NDC.

### Can it be combined with our current system?

It does not replace the idea of perspective projection or the depth buffer. It replaces the current depth convention.

So:

- it is compatible with the current renderer architecture in principle
- it is not a bolt-on side feature
- it becomes the new depth convention across the scene pipeline

### Best use

- general-purpose long-distance rendering
- terrain-heavy scenes
- engines that want one robust default path

### Recommendation level

High. If we want a durable fix without going exotic, reversed-Z is the strongest candidate.

## Option 3: Floating-Point Depth Buffer

This usually means using a depth attachment with higher precision than the common fixed-point depth formats.

### What it is

Use a floating-point depth buffer, often `32F` or a depth format with stronger precision behavior than the current default.

### Pros

- increases available precision
- especially effective when paired with reversed-Z
- relatively contained compared to logarithmic depth

### Cons

- by itself, it is not as transformational as reversed-Z
- can increase memory bandwidth or storage cost
- may require care in framebuffer setup and platform compatibility

### Can it be combined with our current system?

Yes.

It can be combined with:

- the current forward-Z pipeline
- reversed-Z

In practice:

- forward-Z + floating depth: helpful
- reversed-Z + floating depth: usually excellent

### Best use

- as an upgrade to another strategy
- especially as part of a reversed-Z migration

### Recommendation level

Medium by itself, high in combination with reversed-Z.

## Option 4: Logarithmic Depth

This is the most aggressive single-camera-range option, but also the highest-friction one.

### What it is

Instead of using the standard projection-produced depth value, shaders write a logarithmic depth representation so precision stays more usable across extreme distance ranges.

### Pros

- can support extremely large visible ranges
- attractive for planet-scale or astronomical scenes
- less dependent on near/far tuning than standard depth

### Cons

- shader-heavy solution
- touches material/shader infrastructure broadly
- can interfere with early-Z optimizations
- can complicate depth-based effects, shadowing, and post-processing
- more fragile across render paths than reversed-Z

### Can it be combined with our current system?

Only in a much more invasive way.

It does not naturally sit on top of the current renderer without replacing how many shaders produce depth. It is more of an alternate depth strategy than a small upgrade.

It can sometimes be combined with reversed-Z in advanced engines, but that is usually not the first thing to do. Most engines choose one primary direction:

- standard/reversed depth pipeline
- or logarithmic depth pipeline

### Best use

- truly enormous scale ranges
- specialized engines
- cases where even reversed-Z is not enough

### Recommendation level

Low for this repo unless the project is moving toward extremely large-world rendering.

## Option 5: Multi-Range Or Camera-Mode Solutions

These do not directly improve one depth buffer. They reduce the problem by splitting it.

Examples:

- separate near and far render passes
- multiple frusta
- camera-mode-dependent near/far settings
- origin rebasing for large world coordinates

### Pros

- can solve practical problems without a full renderer rewrite
- useful when different content layers have different distance requirements

### Cons

- more complexity in culling, pass composition, and depth integration
- can create stitching or transition problems
- still may need better depth conventions underneath

### Can it be combined with our current system?

Yes. These are architectural additions on top of the renderer.

### Best use

- sky or distant terrain layers
- different interaction vs overview camera modes
- very large scenes with distinct render bands

## Comparison Summary

### Standard Perspective Tuning

- Lowest cost
- Lowest risk
- Lowest upside
- Already in use

### Reversed-Z

- Moderate implementation cost
- High practical upside
- Good general solution
- Likely best next major step

### Floating-Point Depth

- Moderate cost
- Medium upside alone
- Very good complement to reversed-Z

### Logarithmic Depth

- High cost
- High upside for extreme scales
- Highest shader and pipeline disruption

### Multi-Range Techniques

- Cost varies
- Useful complement, not necessarily a substitute
- Good when scene requirements are heterogeneous

## Recommended Path For This Repo

If the goal is "see much farther without depth precision becoming fragile", the pragmatic order is:

1. Keep improving near/far defaults where camera behavior allows it.
2. Move the renderer to reversed-Z.
3. If needed, pair reversed-Z with a floating-point depth attachment.
4. Only consider logarithmic depth if the project starts targeting truly massive scales where reversed-Z still is not enough.

This recommendation fits the current codebase because:

- the engine is still using a conventional OpenGL depth path
- the current scene/renderer organization can absorb a depth-convention migration
- most of the risk is in auditing passes, not in redesigning scene logic

## Migration Notes For Reversed-Z

If we choose reversed-Z later, the migration checklist should include at least:

- [assets/lua/app-projection.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/app-projection.fnl)
- [assets/lua/renderers.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/renderers.fnl)
- [assets/lua/sub-app.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/sub-app.fnl)
- [assets/lua/next-app/sub-app.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/next-app/sub-app.fnl)
- [assets/lua/skybox-renderer.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/skybox-renderer.fnl)
- depth-reconstructing shaders or Lua-side math that samples depth textures
- snapshot tests and any scene tests that assume old depth ordering

The most important point is consistency: once the renderer switches to reversed-Z, all passes need to agree on the same convention.

## Bottom Line

- Reversed-Z is the best long-term general solution.
- Floating-point depth is a strong companion, not a competing idea.
- Logarithmic depth is a specialized alternative for very large scales, not the first step.
- These options do not all "replace rendering", but they do replace or augment the current depth convention.
- For this repo, reversed-Z plus floating-point depth is the most credible long-term path if the standard projection tuning stops being enough.


## See also

- [Rendering](/dev/subsystems/rendering)
