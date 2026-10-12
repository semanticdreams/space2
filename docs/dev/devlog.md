# Devlog

## 2026-08-07
Space's graph workspace became easier to recover, search, and trust in motion: the [Graph Sidebar Node Finder](/specs/2026-08-06-graph-sidebar-node-finder-design) added Add Start recovery and Find Node rows that reveal or open graph-addressable objects through activity callbacks while keeping GraphMap as the interaction-context owner, and [Graph UX Polish](/specs/2026-08-07-graph-ux-polish-design) stabilized sidebar width, restored-map identity, truncation, and theme-resolved graph/chrome backgrounds so the graph view can stay a visual navigation surface instead of absorbing domain ownership. In parallel, weekly-agent workflow hardening tightened OpenCode capability boundaries and PR-protection polling, making the scheduled-agent path safer as graph work accelerates.

## 2026-08-05
The HUD chrome work moved from broad visual alignment into sharper layout contracts: real Material icon metrics now shape the chrome instead of idealized icon boxes, toolbar and rail rows share natural height, [HUD-scoped control and world-selector spacing](/specs/2026-08-04-hud-control-button-spacing-design) removes stray gaps without changing global widget defaults, and the [right rail now reserves only rail width](/specs/2026-08-04-hud-right-rail-transparent-strip-design) while projecting terminal/chat panels below the toolbar reserve so expanded side panels no longer steal transparent render space. Together these refinements keep Space's HUD polish tied to measurable widget behavior, making future layout changes easier to validate instead of hand-tune.

## 2026-08-04
Yesterday's HUD chrome pass turned scattered top/bottom/side/toolbar surfaces into a unified, naturally measured widget system: [shared HUD chrome metrics](/specs/2026-08-03-hud-chrome-visual-uniformity-design) made side rails the visual source of truth, the Sandbox toolbar gained real chrome inside a Card/Padding shell, and focused tests captured equal natural sizing and consistent behavior across the HUD boundary. A second pass [corrected single-row HUD icon scale](/plans/2026-08-03-hud-chrome-visual-uniformity) to keep icon rows at their natural chrome height, then a [follow-up refinement](/specs/2026-08-03-hud-chrome-button-owned-padding-design) moved control-panel and Sandbox toolbar height into button-owned padding with zero shell padding—preserving Card backgrounds and status-panel sizing while making the visual match architectural instead of fixed-size. This supports Space's UI/layout engine goals by making chrome composition easier to reason about and validate as future activities grow.

## 2026-08-03
Agent workflow reliability pushed through the finish line late on August 2 as five more PRs connected the remaining guardrails into one coherent loop: [targeted local validation](/plans/2026-08-02-targeted-agent-validation) replaced unconditional full-suite runs with narrowest-meaningful checks across every agent role, the [daily devlog automation](/dev/notes/daily-devlog-automation) added a locked-dependency preflight so fresh checkouts never fail on a missing VitePress, [workflow-debug landing](/plans/2026-08-02-workflow-debug-pr-landing) now routes final branches through `origin/main`-based PRs instead of local `main`, a [worktree build-warm recipe](/dev/features/opencode-agent-workflow) with exact-HEAD safety checks lets fresh Orca checkouts clone the build cache without stale-artifact risk, and the [merge queue agent workflow](/plans/2026-08-02-merge-queue-agent-workflow)—paired with [until-merged polling](/plans/2026-08-02-until-merged-merge-queue)—completed the repository migration to `semanticdreams/spacecore`, tying the `merge_group` CI trigger and auto-merge into one closed loop that owns every PR through to merge.

## 2026-08-02
Agent-driven development tightened its grip on reliability across the board: a [canonical Orca/OpenCode workflow page](/dev/features/opencode-agent-workflow) now gives collaborators a single setup entry point with supported remote-SSH and remote-VM patterns minus personal-machine noise, a dedicated web-researcher subagent isolates untrusted web evidence from the mutation-capable supervisor, and every workflow surface—from implementation to daily and weekly automation—shares a validation-continuation contract that reroutes required-test failures through systematic debugging and current-`origin/main` freshness checks instead of stopping dead at red. The [daily devlog automation](/dev/notes/daily-devlog-automation) hardened its own guardrails by verifying GitHub-ruleset branch protection before auto-merge and pinning landing-date attribution to `origin/main` merges so stale commit-author timestamps cannot skip or backdate landed work. Local builds got quieter and faster: the [default `make build` profile](/dev/building) is now minimal and CEF-off with summary-only output and a complete log file, reserving `make build-full` for browser-surface iteration. On the [Windows side](/plans/2026-08-01-windows-artifact-fast-suite), backslash normalization, `SPACE_ASSETS_PATH` fixture resolution, and POSIX-symlink skips brought the artifact fast-suite to green—together making the agent loop and cross-platform tooling faster and harder to trip over.

## 2026-08-01
Fennel constraints graduated from experimental to stable infrastructure, with validation output now summarized by default while preserving full detail behind a verbose flag for debugging, and agent workflows tightened in parallel through skill routing, MCP-accessible lint and repair tools, and hardened enclosing-form lookup — together sharpening the compile-check-and-iterate loop so constraint-aware development stays fast and reliable as the project scales.

## 2026-07-31
Runtime portability tightened with asset discovery that resolves from the executable through a deduplicated search order while preserving explicit overrides, and native logging now settles in a deliberate user log directory after dotenv has a chance to provide `SPACE_LOG_DIR`, keeping CLI, REPL, module, developer, installed, and portable runs predictable instead of scattering assets or `gl.log` around arbitrary launch directories.

## 2026-07-30
Late July added grounded camera controls and physics anchor dragging through a new sandbox interaction toolbar, migrated the presentation layer from app-global assumptions to activity-owned delegates, shipped external-unit MCP tooling for loader-neutral user code, and matured the daily devlog automation with a retrospective journal backfill — giving the project a durable narrative record as it builds toward the next graph and world-editing milestones.

## 2026-07-14
By mid-July, the project consolidated its operating loop around panel transfer, the repository workbench, conversation-first supervision, and the new VitePress knowledge base, turning months of scattered architecture notes into a navigable map for future graph, world-building, and live-development milestones.

## 2026-06-15
June pushed Space toward portability and broader authoring workflows, pairing Windows cross-compilation and packaging smoke-test work with board canvas mode, semantic connectors, item selection, and hot-reload cache cleanup so the workspace could travel beyond the original Linux development loop.

## 2026-05-08
May shifted the project toward live agent-assisted development: the agent runner, presets, MCP transport, OpenCode streaming, reloadable units, user-code scanning, and Lua-owned HTTP pieces started turning Space into an environment that can inspect and reshape itself while it runs.

## 2026-04-16
April was a stabilization pass for the growing world-building system, tightening lifecycle ownership, signal cleanup, composable state handling, stylus drawing, Yojimbo experiments, and canvas modes so interactive surfaces could grow without silent callbacks or tangled mode logic.

## 2026-03-18
March turned the newly merged Lua/Fennel stack into a world-building platform: terrain heightfields, graph editing, exposed world entities, lighting, and containment work converged so scenes were no longer just rendered surfaces but editable environments connected through the graph.

## 2026-02-16
Restructured docs: combined public docs with dev docs in a new VitePress project, deployed via GitHub Pages to spaceui.org.
A recent attempt at creating a new instanced quad based rectangle and text rendering system stalled, see code in next-app. Live development is needed to understand the system and harmonize layout and rendering designs.

## 2026-02-09
Added Xapian bindings for in-app search. Fixed input text alignment for inputs with extra space. Main challenge is how to structure the graph system to support specific features such as agentic coding, live state exploration, visual programming, knowledge management, etc. while remaining generic and convenient. A possible next step is to add notebooks with notebook pages (or nested notebooks) inspired by gtoolkit in order to provide a structure for the implementation of new features and to keep track of the alignment of development efforts with project goals.

## 2026-02-08
Status: Most features from the Python prototype have been recreated in the new Fennel/C++ implementation over the last few months.

## 2025-10-01
By October, Space's Python prototype had become a staging ground for a deeper Lua/Fennel migration: the long-lived branch carried the engine toward a scriptable UI and graph-centered runtime, keeping the momentum from the September Fennel rendering experiments while avoiding noisy mainline churn until the new architecture could land as a coherent replacement.

## 2025-09-24
Changed to load classes in Python prototype directly from z folder rather than through DB-based entities
to avoid a strange system-dependent problem.
As a result, editing class entities from within the prototype world will no longer work.
Prototype is reaching its end of life so this is ok.

Fixed fbo update issue by updating Lua's fbo handle on viewport change.

## 2025-09-17
Fennel implementation has basic triangle renderering and initial UI code (rectangles, layout, widget).
Output is rendered to a framebuffer displayed on a texture within the scene created by the prototype.
Entities will be file-based.

## 2025-09-16
In the process of replacing Python prototype with C++/Fennel implementation.
Prototype has skybox, line, triangle, text (msdf), image, point, mesh and sub-world **renderers**.
**UI layout system** has measure pass and layout pass. Layout nodes have to be assembled manually,
no uniform widget system. Since there is no widget hierarchy, every object stores
references to anything it creates, to be able to drop it when it's dropped.
**Entities** (base units of knowledge management in space), stored in sqlite, subclasses of `Entity`.
Each entity class defines view, preview, color, load & dump methods plus custom behavior. Entity
superclass tracks type, id, color and changed signal, has base get, create, save, delete methods.
Class entities are used for most of the prototype code. Jump to internal entities was problematic 
due to lacking internal development tools. Currently, 2-way sync between file system based classes
and class entities enables working from both external and internal environments.
**Space graph**, called dynamic graph in the prototype, implemented in classes `DynamicGraph`
and `DynamicGraphChild`. Nodes positioned using force layout, multiple LOD levels and full view added to HUD on selection.
Root graph entity (ID 18) is mounted into dynamic graph.

![Space Prototype Screenshot](./space-prototype-screenshot1.png)
