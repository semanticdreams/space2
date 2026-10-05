---
type: index
aliases:
  - Subsystems
tags:
  - index
  - subsystems
  - architecture
---

# Subsystems

Space is organized into these major subsystems. Detailed subsystem pages: [Rendering](/dev/subsystems/rendering), [Input](/dev/subsystems/input), [Audio](/dev/subsystems/audio), [Networking](/dev/subsystems/networking), [SSH](/dev/subsystems/ssh), [Build](/dev/subsystems/build), [Process](/dev/subsystems/process), [Cross Platform](/dev/subsystems/cross-platform).

See [Concepts](/dev/concepts) for the VitePress concept docs, and [Dev Notes](/dev/notes/) for detailed architecture notes.

## Engine (C++)

- **Rendering** — OpenGL-based renderer, batched triangles/quads, model transforms, clips, FXAA. SSBO-backed instanced quad pipeline for UI. See [Rendering](/dev/subsystems/rendering)
- **Physics** — Bullet integration for rigid-body and world simulation
- **Audio** — OpenAL/PortAudio-based positional audio with microphone input. See [Audio](/dev/subsystems/audio)
- **Audio Analysis** — aubio bindings: FFT, pitch/onset/tempo/notes detection, MFCC, spectral descriptors, phase vocoder, wavetable synthesis. See [Audio](/dev/subsystems/audio)
- **Graph** — Exposure layer for app state, knowledge objects, and linked views. See [Graph Identity](/dev/notes/graph-identity) and [Graph Llm](/dev/notes/graph-llm)
- **Video** — FFmpeg-based in-world video playback with A/V sync telemetry. See [Video Playback](/dev/video-playback)
- **Browser** — CEF-based embedded browser surfaces rendered onto 3D geometry
- **Terminal** — PTY-based terminal widget via libvterm
- **Search** — Xapian full-text search
- **Wallet** — wallet-core based crypto wallet
- **Torrent** — libtorrent binding for asset distribution
- **Matrix** — Matrix bridge foundation for federation/chat
- **Realtime Networking** — yojimbo-based client/server with feature protocol, auth ticketing, reliable/unreliable messaging. See [Networking](/dev/subsystems/networking)
- **HTTP** — Multi-threaded libcurl HTTP client and embedded HTTP server
- **SSH** — Space-owned async SSH client transport with optional `libssh` backend, known-host policy, SFTP, shell, and tunnel primitives. See [SSH](/dev/subsystems/ssh)
- **Color Science** — Comprehensive color library: 15+ color spaces, Delta-E (1976/1994/2000/CMC), CIECAM02, CVD simulation. See [Cross Platform](/dev/subsystems/cross-platform)
- **Force Layout** — Physics-based graph layout algorithm (spring/repulsion, pinning, stabilization). See [Force Layout Barnes Hut](/dev/notes/force-layout-barnes-hut)
- **Job System** — Thread pool for async work (texture/audio loading, glTF parsing). See [Process](/dev/subsystems/process)
- **Keyring & System Tools** — OS credential storage, system tray, desktop notifications, process management, shell execution, sysinfo. See [Process](/dev/subsystems/process)
- **File Watch** — efsw-based filesystem change notifications for live reload
- **Tree-Sitter** — Incremental syntax parsing for code analysis
- **GCC JIT** — libgccjit bindings for runtime C code generation and compilation. See [Build](/dev/subsystems/build)
- **MSDF Atlas** — Multi-channel signed distance field generation for high-quality font rendering
- **Dial Input** — Gamepad analog-stick dial input for text entry on controllers

## Widget System (Fennel)

- **Layout** — Constraint-based layout engine (flex, stack, grid, padding, sized, aligned, positioned, radial). See [Layout Widget Engine](/dev/features/layout-widget-engine)
- **Primitives** — Rectangle, text span, image, button, input, combo box, label, icon, disclosure row, scroll area, tab view, list view
- **Composition** — Higher-order widgets composed from primitives (cards, containers, status badges, search views)
- **Raw renderers** — Rectangle, gradient triangle, image, polyhedron, sphere primitives
- **Canvas** — Virtual canvas for in-world panels and retained activity slots
- **Graph views** — View layer for graph nodes, decoupled from node state. See [Graph View As Widget](/dev/notes/graph-view-as-widget)
- **Drawing** — Vector drawing with stylus/pressure input, history/undo, raster layer. See [Stylus Drawing Input](/dev/features/stylus-drawing-input), [Drawing Architecture](/dev/notes/drawing-architecture)
- **Board** — Structured board activity with connectors, selection, resizable items. See [Activities Architecture](/dev/features/activities); legacy notes: [Board Canvas Mode](/dev/features/board-canvas-mode)
- **Terrain** — Heightfield terrain with physics, painting, selection tools. See [Terrain Heightfield System](/dev/features/terrain-heightfield-system)
- **HUD** — Heads-up display with control panel, status panel, command hints, panel persistence
- **Theming** — Dark/light theme system with widget-level utilities. See [Light Theme Layering](/dev/notes/light-theme-layering)

## Application Model (Fennel)

- **Lifecycle** — `app.init/update/drop` with signal-driven events. See [Lifecycle Invariants](/dev/lifecycle-invariants)
- **Signals** — Event system for decoupled communication across all subsystems
- **Reloadable units** — Hot-reload architecture with load/unload/snapshot/restore and efsw file watching. See [Hot Reload Units](/dev/features/hot-reload-units), [Reloadable Units](/dev/reloadable-units)
- **Remote control** — ZeroMQ-based live debugging with async result polling.
- **State management** — Composable state machines with route wrappers, enter/leave hooks, and pluggable input-state handlers (focus, hover, camera, gamepad, touch, pen)
- **Fennel caching** — Compiled Fennel → Lua bytecode cache for fast startup. See [Fennel Cache](/dev/project/tech-debt/tech-debt-fennel-cache)

## Application Features (Fennel)

- **LLM & Conversations** — JSON-persisted conversation store with OpenAI/Opencode/Codex/ZAI providers. See [Agent Layer Design](/dev/notes/agent-layer-design), [Graph Llm](/dev/notes/graph-llm)
- **Agent System** — Autonomous agent runner with sessions, turns, tool execution, approval gating, and MCP synchronization. See [Agent Runner System](/dev/features/agent-runner-system), [Agent Presets](/dev/notes/agent-presets)
- **MCP Server** — Model Context Protocol server (JSON-RPC 2.0, tool registry, HTTP transport) for exposing tools to external AI clients. See [Remote Mcp](/dev/notes/remote-mcp)
- **Kernel System** — Interactive computational kernel manager: Fennel REPL, shell execution, stdin/stdout, ZeroMQ communication. See [Kernels](/dev/notes/kernels)
- **Entity Store** — Persistence layer for string, code, link, list, and identity entities with CRUD, search, and signals
- **Repository Workbench** — Git repo management: clone, branch, commit, diff, workspace operations. See [Repository Workbench](/dev/repository-workbench)
- **Wallet** — Crypto wallet with mnemonic generation, signing, Arbitrum Nova transfers, encrypted persistence
- **Node Morphing** — Graph node type conversion system (e.g., string-entity → code-entity). See [Morphs](/dev/notes/morphs)
- **Ripgrep** — Programmatic ripgrep integration for file search with result parsing. See [Ripgrep](/dev/notes/ripgrep)
- **SQL Builder** — 1300+ line SQL query builder. See [SQL Builder](/dev/sql-builder)
- **External Editor** — Launch external editor with content, wait for result
- **Fennel Interpreter** — Interactive Fennel REPL UI widget
- **Launchables** — Applet system: discoverable Fennel modules providing name + run entry points
- **QR Code** — QR code generation and rendering
- **XDG Icons** — Icon theming integration
- **System Cursors** — OS cursor management
- **Volume Control** — Audio volume and device management
- **Tetris** — Tetris mini-game as a launchable

## Tooling

- **Development tooling** — Profiling, testing, render capture, remote control, and CLI tools. See [Development Tooling](/dev/features/development-tooling)
- **Tests** — CTest for C++, Fennel test harness for 170+ unit tests and 55 E2E snapshot tests. See [Concepts](/dev/concepts)
- **Profiling** — Flamegraph profilers with stack sampling and frame profiling. See [Prof Graph Layout](/dev/notes/prof-graph-layout), [Prof Scroll](/dev/notes/prof-scroll), [Prof Terminal](/dev/notes/prof-terminal)
- **E2E snapshots** — Visual regression testing with golden PNG images
- **Render capture** — `glReadPixels` + PNG output for frame capture. See [Render Capture](/dev/notes/render-capture)
- **CLI tools** — Remote control client, MCP remote server, torrent download/upload
