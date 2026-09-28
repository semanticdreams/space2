---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: "space"
  text: "Free Your System"
  tagline: space is a programmable, shared, user-owned computing environment for code, knowledge, games, art, and collaboration.
  image:
    src: /space.png
    alt: space logo
  actions:
    - theme: brand
      text: Quick Start
      link: /user/quick-start
    - theme: alt
      text: User Docs
      link: /user/
    - theme: alt
      text: SDK Docs
      link: /sdk/
    - theme: alt
      text: Developer Docs
      link: /dev/

features:
  - title: Spatial Computing
    details: 3D spaces with in-world media, embedded surfaces, spatial widgets, and interactive visualization.
  - title: Live Programming
    details: Code you can inspect, modify, and reload in place while the world is running.
  - title: Shared Worlds
    details: Persistent multi-user spaces for collaboration, communication, and social interaction.
  - title: User-Owned Infrastructure
    details: Self-hosted and federated services for sync, communication, identity, and software distribution.
  - title: Games, Art, and Simulation
    details: Games, visual art, simulation, and artificial life built inside interactive worlds.
  - title: Connected Workflows
    details: Code, data, notes, tools, media, and world state linked together for knowledge work and creation.
---

## What Is space?

- 3D Emacs: a programmable environment where code, notes, tools, and media can be inspected and reshaped in place.
- Operating system interface: a spatial shell for files, apps, services, and world objects.
- Federated metaverse: persistent virtual worlds built on user-owned infrastructure.
- Collaborative workspace and social medium: shared spaces for communication, editing, coordination, and presence.
- Gaming and simulation platform: editable worlds for games, experiments, toys, and interactive systems.
- Live development environment: code and runtime state can be changed while the system is running.
- Information management system: graph-oriented notes, tasks, files, conversations, and code linked together.
- Digital arts and visualization tool: a place for visual art, spatial interfaces, interactive media, and data visualization.

## Demo Gallery

This section will eventually show short demos. The current planned gallery labels are:

- Graph workspace
- Live programming
- Terrain and world editing
- Gameplay and simulation sandbox
- Drawing canvas
- Browser, terminal, and media surfaces
- Linked conversations, notes, and code

## Project State

- [x] 3D runtime with scene rendering, physics, spatial widgets, and embedded surfaces
- [x] Fennel + C++ runtime with the current layout and widget system
- [x] Entity and graph model for state, linked objects, and views exposed through the graph
- [x] Core UI primitives and interactions: text, buttons, inputs, lists, focus, and selection
- [x] Engine and app integrations: terminal, video playback, browser embedding, search, LLM client work, and remote-control debugging
- [x] Interactive world-editing work: terrain, lighting, scene objects, and drawing/canvas workflows
- [x] Technical groundwork for game-like worlds: physics, scene objects, world state, and live editing tools
- [ ] Graph browsing, editing, filtering, and navigation as a coherent primary workflow
- [ ] Integrated graph/terminal/search/file editing workflow
- [ ] In-place widget and code editing with defined reload units, history, and rollback
- [ ] Gameplay systems such as avatars, vehicles, and reusable world mechanics
- [ ] Shared-world state and realtime sync with permissions and provenance
- [ ] Matrix-based social and contribution views around code, assets, and worlds
- [ ] Concrete pod, asset distribution, and service-management workflows
