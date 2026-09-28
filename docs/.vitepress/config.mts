import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: "space",
  description: "space documentation",
  srcExclude: [
    'dev/openai/**',
    'dev/zai/**',
    'dev/fennel/**'
  ],
  head: [
    ['link', { rel: 'icon', href: '/space.png' }]
  ],
  themeConfig: {
    search: {
      provider: 'local'
    },
    logo: '/space.png',
    // https://vitepress.dev/reference/default-theme-config
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Quick Start', link: '/user/quick-start' },
      { text: 'User', link: '/user/' },
      { text: 'SDK', link: '/sdk/' },
      { text: 'Developer', link: '/dev/' }
    ],

    sidebar: {
      '/sdk/': [
        {
          text: 'Overview',
          items: [
            { text: 'SDK Docs', link: '/sdk/' },
            { text: 'Getting Started', link: '/sdk/getting-started' },
            { text: 'Concepts', link: '/sdk/concepts' }
          ]
        },
        {
          text: 'Modules',
          items: [
            { text: 'Module Reference', link: '/sdk/modules/' },
            { text: 'Aliases and Search Terms', link: '/sdk/modules/aliases' },
            {
              text: 'Runtime and platform',
              collapsed: true,
              items: [
                { text: 'appdirs', link: '/sdk/modules/appdirs' },
                { text: 'engine', link: '/sdk/modules/engine' },
                { text: 'runtime', link: '/sdk/modules/runtime' },
                { text: 'cli-args', link: '/sdk/modules/cli-args' },
                { text: 'fs', link: '/sdk/modules/fs' },
                { text: 'logging', link: '/sdk/modules/logging' },
                { text: 'error-reporting', link: '/sdk/modules/error-reporting' },
                { text: 'callbacks', link: '/sdk/modules/callbacks' },
                { text: 'jobs', link: '/sdk/modules/jobs' },
                { text: 'keyring', link: '/sdk/modules/keyring' },
                { text: 'process', link: '/sdk/modules/process' },
                { text: 'shell', link: '/sdk/modules/shell' },
                { text: 'file-watch', link: '/sdk/modules/file-watch' },
                { text: 'notify', link: '/sdk/modules/notify' },
                { text: 'tray', link: '/sdk/modules/tray' },
                { text: 'terminal', link: '/sdk/modules/terminal' },
                { text: 'sysinfo', link: '/sdk/modules/sysinfo' },
                { text: 'uuid', link: '/sdk/modules/uuid' },
                { text: 'random', link: '/sdk/modules/random' },
                { text: 'input-state', link: '/sdk/modules/input-state' },
                { text: 'dial-type', link: '/sdk/modules/dial-type' },
                { text: 'webbrowser', link: '/sdk/modules/webbrowser' }
              ]
            },
            {
              text: 'Data, storage, and parsing',
              collapsed: true,
              items: [
                { text: 'temporal', link: '/sdk/modules/temporal' },
                { text: 'temporal-core', link: '/sdk/modules/temporal-core' },
                { text: 'json', link: '/sdk/modules/json' },
                { text: 'json-utils', link: '/sdk/modules/json-utils' },
                { text: 'toml', link: '/sdk/modules/toml' },
                { text: 'lsqlite3', link: '/sdk/modules/lsqlite3' },
                { text: 'sql-builder', link: '/sdk/modules/sql-builder' },
                { text: 'tree-sitter', link: '/sdk/modules/tree-sitter' }
              ]
            },
            {
              text: 'Rendering, media, and graphics',
              collapsed: true,
              items: [
                { text: 'gl', link: '/sdk/modules/gl' },
                { text: 'shaders', link: '/sdk/modules/shaders' },
                { text: 'textures', link: '/sdk/modules/textures' },
                { text: 'vector-buffer', link: '/sdk/modules/vector-buffer' },
                { text: 'image-io', link: '/sdk/modules/image-io' },
                { text: 'glm', link: '/sdk/modules/glm' },
                { text: 'colors', link: '/sdk/modules/colors' },
                { text: 'cgltf', link: '/sdk/modules/cgltf' },
                { text: 'ray-box', link: '/sdk/modules/ray-box' },
                { text: 'graph-edge-batch', link: '/sdk/modules/graph-edge-batch' },
                { text: 'force-layout', link: '/sdk/modules/force-layout' },
                { text: 'msdf-atlas-gen', link: '/sdk/modules/msdf-atlas-gen' },
                { text: 'video', link: '/sdk/modules/video' }
              ]
            },
            {
              text: 'Audio',
              collapsed: true,
              items: [
                { text: 'audio', link: '/sdk/modules/audio' },
                { text: 'audio-input', link: '/sdk/modules/audio-input' },
                { text: 'aubio', link: '/sdk/modules/aubio' }
              ]
            },
            {
              text: 'Physics and world systems',
              collapsed: true,
              items: [
                { text: 'bt', link: '/sdk/modules/bt' },
                { text: 'perlin-terrain-native', link: '/sdk/modules/perlin-terrain-native' }
              ]
            },
            {
              text: 'Networking and services',
              collapsed: true,
              items: [
                { text: 'http', link: '/sdk/modules/http' },
                { text: 'http-server', link: '/sdk/modules/http-server' },
                { text: 'zmq', link: '/sdk/modules/zmq' },
                { text: 'realtime', link: '/sdk/modules/realtime' },
                { text: 'libtorrent', link: '/sdk/modules/libtorrent' },
                { text: 'matrix', link: '/sdk/modules/matrix' },
                { text: 'xapian', link: '/sdk/modules/xapian' }
              ]
            },
            {
              text: 'Wallet and identity',
              collapsed: true,
              items: [
                { text: 'wallet', link: '/sdk/modules/wallet' },
                { text: 'wallet-core', link: '/sdk/modules/wallet-core' }
              ]
            },
            {
              text: 'Advanced/native tooling',
              collapsed: true,
              items: [
                { text: 'gccjit', link: '/sdk/modules/gccjit' }
              ]
            }
          ]
        },
        {
          text: 'Tutorials',
          items: [
            { text: 'Tutorials Overview', link: '/sdk/tutorials/' },
            { text: 'Your First Space App', link: '/sdk/tutorials/your-first-space-app' },
            { text: 'Add a Command', link: '/sdk/tutorials/add-a-command' },
            { text: 'Publish an App', link: '/sdk/tutorials/publish-an-app' }
          ]
        },
        {
          text: 'Guides',
          items: [
            { text: 'Guides Overview', link: '/sdk/guides/' },
            { text: 'App Layout', link: '/sdk/guides/app-layout' },
            { text: 'Hostable Runtime Apps', link: '/sdk/guides/hostable-runtime-apps' },
            { text: 'Embedded Workspace Hosting', link: '/sdk/guides/embedded-workspace-hosting' },
            { text: 'Graph Extension Units', link: '/sdk/guides/graph-extension-units' },
            { text: 'UI Surfaces', link: '/sdk/guides/ui-surfaces' }
          ]
        },
        {
          text: 'Reference',
          items: [
            { text: 'Reference Overview', link: '/sdk/reference/' },
            { text: 'App Module Contract', link: '/sdk/reference/app-module-contract' },
            { text: 'Host Capabilities', link: '/sdk/reference/host-capabilities' },
            { text: 'Runtime Facets', link: '/sdk/reference/runtime-facets' },
            { text: 'Commands', link: '/sdk/reference/commands' },
            { text: 'Scene Capability', link: '/sdk/reference/scene-capability' },
            { text: 'Packaging Workflow', link: '/sdk/reference/packaging-workflow' },
            { text: 'Graph Extension Descriptors', link: '/sdk/reference/graph-extension-descriptors' }
          ]
        },
        {
          text: 'Examples',
          items: [
            { text: 'Examples Overview', link: '/sdk/examples/' }
          ]
        }
      ],
      '/user/': [
        {
          text: 'User',
          items: [
            { text: 'Overview', link: '/user/' },
            { text: 'Quick Start', link: '/user/quick-start' }
          ]
        }
      ],
      '/dev/': [
        {
          text: 'Overview',
          items: [
            { text: 'Developer Docs', link: '/dev/' },
            { text: 'Concepts', link: '/dev/concepts' },
            { text: 'Devlog', link: '/dev/devlog' }
          ]
        },
        {
          text: 'Project',
          items: [
            { text: 'Goals', link: '/dev/project/goals' },
            { text: 'Features', link: '/dev/project/features' },
            { text: 'Ideas', link: '/dev/project/ideas' },
            { text: 'Research', link: '/dev/project/research' },
            { text: 'Milestones', link: '/dev/project/milestones/' },
            { text: 'Project History', link: '/dev/project/history' },
            { text: 'Bugs', link: '/dev/project/bugs/' },
            { text: 'Technical Debt', link: '/dev/project/tech-debt/' }
          ]
        },
        {
          text: 'Architecture',
          items: [
            { text: 'Lifecycle Invariants', link: '/dev/lifecycle-invariants' },
            { text: 'Lifecycle Centralization', link: '/dev/lifecycle-centralization' },
            { text: 'Lifecycle Hardening Plan', link: '/dev/lifecycle-hardening-plan' },
            { text: 'Widget Ownership & Teardown', link: '/dev/widget-ownership-and-teardown' },
            { text: 'ADRs', link: '/dev/adrs/' },
            { text: 'Subsystems', link: '/dev/subsystems/' }
          ]
        },
        {
          text: 'Features',
          items: [
            { text: 'Agent Runner System', link: '/dev/features/agent-runner-system' },
            { text: 'Agent Tools', link: '/dev/features/agent-tools' },
            { text: 'Board Canvas Mode', link: '/dev/features/board-canvas-mode' },
            { text: 'Canvas Mode System', link: '/dev/features/canvas-mode-system' },
            { text: 'CEF In-World Browser', link: '/dev/features/cef-in-world-browser' },
            { text: 'Core Platform', link: '/dev/features/core-platform' },
            { text: 'Development Tooling', link: '/dev/features/development-tooling' },
            { text: 'FFmpeg Video Playback', link: '/dev/features/ffmpeg-video-playback' },
            { text: 'Graph Browsing', link: '/dev/features/graph-browsing' },
            { text: 'Graph Foundation', link: '/dev/features/graph-foundation' },
            { text: 'Graph Notebooks', link: '/dev/features/graph-notebooks' },
            { text: 'Hot Reload Units', link: '/dev/features/hot-reload-units' },
            { text: 'Kernel System', link: '/dev/features/kernel-system' },
            { text: 'Layout Widget Engine', link: '/dev/features/layout-widget-engine' },
            { text: 'Opencode Agent Workflow', link: '/dev/features/opencode-agent-workflow' },
            { text: 'Panel Transfer System', link: '/dev/features/panel-transfer-system' },
            { text: 'Stylus Drawing Input', link: '/dev/features/stylus-drawing-input' },
            { text: 'Terrain Heightfield System', link: '/dev/features/terrain-heightfield-system' },
            { text: 'Wallet System', link: '/dev/features/wallet-system' },
            { text: 'World Building', link: '/dev/features/world-building' }
          ]
        },
        {
          text: 'Notes',
          collapsed: true,
          items: [
            { text: 'Notes Index', link: '/dev/notes/' }
          ]
        },
        {
          text: 'Journal',
          collapsed: true,
          items: [
            { text: 'Journal Index', link: '/dev/journal/' },
            { text: 'Devlog', link: '/dev/devlog' }
          ]
        },
        {
          text: 'Internals',
          items: [
            { text: 'Building', link: '/dev/building' },
            { text: 'E2E Snapshot Tests', link: '/dev/e2e-testing' },
            { text: 'Profiling', link: '/dev/profiling' },
            { text: 'Remote Control', link: '/dev/remote-control' },
            { text: 'Terminal Widget', link: '/dev/terminal' },
            { text: 'Reloadable Units', link: '/dev/reloadable-units' },
            { text: 'Repository Workbench', link: '/dev/repository-workbench' },
            { text: 'Runtime Performance', link: '/dev/runtime-performance' },
            { text: 'Agent Preset Control Panel', link: '/dev/agent-preset-control-panel' },
            { text: 'Video Playback', link: '/dev/video-playback' },
            { text: 'SQL Builder', link: '/dev/sql-builder' }
          ]
        }
      ]
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/semanticdreams/space2' },
      {
        icon: {
          // Source: docs/node_modules/@iconify-json/simple-icons/icons.json
          svg: `<svg width="32" height="32" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path fill="currentColor" d="M20.317 4.37a19.8 19.8 0 0 0-4.885-1.515a.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.3 18.3 0 0 0-5.487 0a13 13 0 0 0-.617-1.25a.08.08 0 0 0-.079-.037A19.7 19.7 0 0 0 3.677 4.37a.1.1 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.08.08 0 0 0 .031.057a19.9 19.9 0 0 0 5.993 3.03a.08.08 0 0 0 .084-.028a14 14 0 0 0 1.226-1.994a.076.076 0 0 0-.041-.106a13 13 0 0 1-1.872-.892a.077.077 0 0 1-.008-.128a10 10 0 0 0 .372-.292a.07.07 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.07.07 0 0 1 .078.01q.181.149.373.292a.077.077 0 0 1-.006.127a12.3 12.3 0 0 1-1.873.892a.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.08.08 0 0 0 .084.028a19.8 19.8 0 0 0 6.002-3.03a.08.08 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.06.06 0 0 0-.031-.03M8.02 15.33c-1.182 0-2.157-1.085-2.157-2.419c0-1.333.956-2.419 2.157-2.419c1.21 0 2.176 1.096 2.157 2.42c0 1.333-.956 2.418-2.157 2.418m7.975 0c-1.183 0-2.157-1.085-2.157-2.419c0-1.333.955-2.419 2.157-2.419c1.21 0 2.176 1.096 2.157 2.42c0 1.333-.946 2.418-2.157 2.418"/>
</svg>`
        },
        link: 'https://discord.gg/EP3vBaQA',
        ariaLabel: 'discord'
      },
      {
        icon: {
          svg: `<svg width="32" height="32" viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
   <path fill="currentColor" d="M 30,2.0000001 V 30 h -1 -2 v 2 h 5 V -3.3333334e-8 L 27,0 v 2 z"/>
   <path fill="currentColor" d="M 9.9515939,10.594002 V 12.138 h 0.043994 c 0.3845141,-0.563728 0.8932271,-1.031728 1.4869981,-1.368 0.580003,-0.322998 1.244999,-0.485 1.993002,-0.485 0.72,0 1.376999,0.139993 1.971998,0.42 0.595,0.279004 1.047001,0.771001 1.355002,1.477001 0.338003,-0.500001 0.795999,-0.941 1.376999,-1.323001 0.579999,-0.382998 1.265998,-0.574 2.059998,-0.574 0.602003,0 1.160002,0.074 1.674002,0.220006 0.514,0.148006 0.953998,0.382998 1.321999,0.706998 0.36601,0.322999 0.653001,0.746 0.859,1.268002 0.205001,0.521998 0.307994,1.15 0.307994,1.887001 v 7.632997 h -3.127 v -6.463997 c 0,-0.383002 -0.01512,-0.743002 -0.04399,-1.082003 -0.02079,-0.3072 -0.103219,-0.607113 -0.242003,-0.881998 -0.133153,-0.25081 -0.335962,-0.457777 -0.584001,-0.596002 -0.257008,-0.146003 -0.605998,-0.220006 -1.046997,-0.220006 -0.440002,0 -0.796003,0.085 -1.068,0.253002 -0.272013,0.170003 -0.485001,0.390002 -0.639001,0.662003 -0.159119,0.287282 -0.263585,0.601602 -0.307994,0.926997 -0.05197,0.346923 -0.07801,0.697217 -0.07801,1.048002 v 6.353999 h -3.128005 v -6.398 c 0,-0.338003 -0.0072,-0.673001 -0.02116,-1.004001 -0.01134,-0.313663 -0.07487,-0.623229 -0.187994,-0.915999 -0.107943,-0.276623 -0.300435,-0.512126 -0.550001,-0.673001 -0.25799,-0.168 -0.636,-0.253002 -1.134999,-0.253002 -0.198123,0.0083 -0.394383,0.04195 -0.584002,0.100006 -0.258368,0.07446 -0.498455,0.201827 -0.704999,0.373985 -0.227981,0.183987 -0.421999,0.449 -0.583997,0.794003 -0.161008,0.345978 -0.242003,0.797998 -0.242003,1.356998 v 6.618999 H 6.99942 V 10.590001 Z"/>
   <path fill="currentColor" d="M 2,2.0000001 V 30 h 3 v 2 H 0 V 9.2650922e-8 L 5,0 v 2 z"/>
</svg>`
        },
        link: 'https://matrix.to/#/#spaceui.org:matrix.org',
        ariaLabel: 'matrix'
      }
    ],

    footer: {
      message: "Join the community on <a href='https://matrix.to/#/#spaceui.org:matrix.org' target='_blank'>Matrix</a> or <a href='https://discord.gg/EP3vBaQA' target='_blank'>Discord</a>."
    }
  }
})
