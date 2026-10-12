---
type: dev-note
tags:
  - note
---

Layered Points In Graph View (Status)
=====================================

Goal
----
- Add a reusable raw LayeredPoint renderer that renders multiple point layers (stacked radii) for
  selection/focus outlines, plus measured layout wrappers where those points need to participate in widget layout.
- Update graph node points to use layered borders:
  - Selection border: 0.2 units (theme color).
  - Focus border: 0.1 units (theme input focus outline).
  - When both, focus border sits outside the selection border.
- Make node points focusable (via focus manager) and still double-clickable.
- Add tests (unit + e2e), run tests, verify a pleasant snapshot.

What Was Implemented
--------------------
1) New raw LayeredPoint renderer
   - File: assets/lua/layered-point.fnl
   - Behavior:
     - Accepts a list of layers `{ :size :color :z-offset }`.
     - Creates a point per layer via ctx.points.
     - Uses a base layer index for `:size`, `:color`, `:position`, and `:intersect`.
     - Supports `set-position`, `set-position-values`, `set-color`, `set-size`,
       `set-layer`, `set-layer-size`, `set-layer-color`.
     - Uses depth-offset indexes per layer for ordering (no z offsets).
   - Notes:
     - Works with `Points` buffer (8 floats per point) and uses standard point shader.
     - Does not own widget `Layout` or reserve measured space; spatial graph views use
       raw layered points directly so large graph maps do not allocate a layout node per point.

1a) Measured LayeredPointBox wrapper
   - File: assets/lua/layered-point-box.fnl
   - Behavior:
     - Owns a raw `LayeredPoint` and a fixed measured footprint for widget/layout contexts.
     - Keeps the raw point centered within the reserved box and exposes the point for
       compact graph projection records that need to register interactions against it.
   - Notes:
     - Outline rows use `LayeredPointBox` for compact markers so focus and selection rings
       can grow visually without changing row measurement or descendant point positions.
     - Interaction ownership stays with graph compact projection records; the box is a
       measured marker wrapper, not a graph interaction owner.

2) GraphView updated to use LayeredPoint and focus handling
   - File: assets/lua/graph/view/init.fnl
   - Changes:
     - Requires `:layered-point` and uses it instead of `ctx.points:create-point`.
     - Adds focus manager integration:
       - Requires `ctx.focus`.
       - Creates a FocusNode per graph node (`focus:create-node`).
       - On click, requests focus; on double click, opens node view.
       - Click-driven auto-focus: widgets like `button.fnl` call
         `focus-manager:arm-auto-focus` on pointer events, and
         `focus.fnl` will auto-focus the next attached focus node in
         `attach-node-at` (used by `focus:create-node` via `build-context`).
         This is why a newly added graph node can be focused by default
         after a click, without the graph code explicitly requesting focus.
     - Maintains `selected-set`, `focused-node` and updates border sizes.
     - Tracks focus change via `focus.manager.focus-focus` and `focus.manager.focus-blur`.
     - Adds theme-required graph selection border color and input focus outline.
     - Registers clickables for left click and double click; unregisters on removal/drop.
     - Cleans up focus nodes on node removal/drop and clears maps.
   - Layer order:
     - Layer 1: focus border (outermost).
     - Layer 2: selection border.
     - Layer 3: base point.

3) Theme additions
   - Files:
     - assets/lua/dark-theme.fnl
     - assets/lua/light-theme.fnl
   - Added `:graph.selection-border-color` in both themes.
   - Uses existing `theme.input.focus-outline` for focus border.

4) Unit tests
   - New file: assets/lua/tests/test-layered-point.fnl
     - Verifies layer sizes, z-offsets, and position updates.
   - Added to test suite: assets/lua/tests/fast.fnl
   - GraphView tests updated:
     - assets/lua/tests/test-graph-view.fnl
       - BuildContext now includes FocusManager + stub theme.
       - New test verifies selection + focus borders sizes.
     - assets/lua/tests/test-selection.fnl
       - BuildContext now includes FocusManager + stub theme (for GraphView in selection tests).

5) E2E harness support for focus
   - File: assets/lua/tests/e2e/harness.fnl
   - Added `:focus-manager`/`:focus-scope` support in make-screen-target and make-scene-target.
   - Stores focus manager on target for cleanup.

6) E2E graph node points test (currently not working visually)
   - File: assets/lua/tests/e2e/test-graph-node-points.fnl
   - Builds a GraphView in a screen target, selects two nodes, focuses one.
   - Asserts point buffer length > 0.
   - Uses a minimal layout for draw.
   - Snapshot name: `graph-node-points`.
   - Problem: snapshot output is blank (uniform background).

Tests Run
---------
1) Full Lua fast test suite (outside sandbox)
   - Command:
     SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
       SPACE_ASSETS_PATH=$(pwd)/assets make test
   - Result: PASS

2) E2E snapshot for graph-node-points (outside sandbox)
   - Command:
     SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
       SPACE_ASSETS_PATH=$(pwd)/assets SPACE_SNAPSHOT_UPDATE=graph-node-points \
       FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
       FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" \
       xvfb-run -a -s "-screen 0 1280x720x24" \
       ./build/space -m tests.e2e.test-graph-node-points:main
   - Result: snapshot updated, but image is uniform background.

What Still Needs To Be Done
---------------------------
1) Fix the E2E snapshot to actually render the graph node points.
   - Current `graph-node-points.png` is uniform (single color).
   - Pixel check (PIL):
     - Image size 640x360.
     - Unique pixels = 1.
   - The test currently:
     - Uses `make-screen-target`.
     - Builds GraphView points and asserts point vector length > 0.
     - Uses a minimal layout (size 0, no children) to allow draw pass.
   - Hypotheses to check:
     - Points are created in the scene BuildContext but not drawn because
       the target isn't getting a proper projection/view for points.
     - Points are created but culled/clipped.
     - Points are off-screen due to coordinate system mismatch for screen targets.
     - The point renderer works, but the test target isn't contributing geometry to the final draw.
     - The snapshot uses a render path that doesn't include target geometry (likely not,
       since other screen targets draw correctly).
   - Debug steps to run:
     - Log or inspect `target.get-point-vector():length` before capture.
     - Verify `app.renderers:draw-target` is invoked and uses `target.projection` and `target.get-view-matrix`.
     - Temporarily add a known visible primitive (rectangle or button) to same target
       to confirm draw path is working.
     - Try rendering the graph points in a HUD target instead of screen target (if appropriate),
       or use a dedicated scene target with a known orthographic projection.
     - Confirm point shader is drawing by disabling clipping or setting a known large size.
     - Confirm point positions are within expected bounds of screen target coordinates.

2) Ensure the E2E snapshot is visually pleasant
   - Need to view the final `graph-node-points.png` once the points render.
   - Tweak sizes/positions and theme colors if borders are too subtle.

3) Decide if the label text in the E2E test is needed
   - A temporary label was added to prove rendering; it should be removed
     once points render correctly. (Currently removed in latest version; no label.)

4) Re-run E2E snapshot after fixing rendering
   - Use the same snapshot update command.
   - View the image and confirm that selected/focused borders are visible and nice.

Files Modified / Added
----------------------
- Added: assets/lua/layered-point.fnl
- Updated: assets/lua/graph/view/init.fnl
- Updated: assets/lua/dark-theme.fnl
- Updated: assets/lua/light-theme.fnl
- Added: assets/lua/tests/test-layered-point.fnl
- Updated: assets/lua/tests/fast.fnl
- Updated: assets/lua/tests/test-graph-view.fnl
- Updated: assets/lua/tests/test-selection.fnl
- Updated: assets/lua/tests/e2e/harness.fnl
- Added: assets/lua/tests/e2e/test-graph-node-points.fnl
- Updated: assets/lua/tests/e2e.fnl

Notes / Observations
--------------------
- GraphView now asserts presence of theme colors for selection and focus outline.
  Tests supply stub themes in contexts to satisfy this.
- GraphView focus integration:
  - Click sets focus (via focus node), double click opens node view.
  - Focus nodes are cleaned up on node removal and view drop.
- LayeredPoint uses depth-offset indexes per layer; GraphView assigns base 0 with step 1.
- E2E snapshot for graph-node-points currently renders uniform background only.
  The point buffer is non-empty (asserted), but draw output appears empty.

Next Steps Suggested
--------------------
1) Make a minimal e2e test that draws a single raw `Points:create-point` in a screen target
   to validate point rendering in this path. If that fails, the issue is target/projection.
2) If a raw point renders, then isolate GraphView contribution:
   - Ensure GraphView point positions are in the same coordinate system as the target.
3) Adjust graph node positions, sizes, and screen target world-units-per-pixel
   until they are visible.
4) Only after rendering works, refine snapshot aesthetics and update golden.


## See also

- [Graph Foundation](/dev/features/graph-foundation)
