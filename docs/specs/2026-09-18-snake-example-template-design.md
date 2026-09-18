# Snake Example Template Design

## Context

Space now has reusable app-distribution tooling for independent Fennel desktop
applications. The repository does not yet contain a concrete example directory
that a new app/game repository can copy as a starting point. The app-distribution
docs describe the target layout as an app-owned `assets/` tree with Fennel under
`assets/lua/`, plus a small caller workflow that uses
`semanticdreams/space2/.github/workflows/bundle.yml`.

Runtime lookup already supports this shape: when Space is launched from an app
repository, `<cwd>/assets` is part of the asset search path. Running
`space -m main` requires `assets/lua/main.fnl`, but it does not call an exported
`:main` function. Running `space -m main:main` does call that function. A good
template should support the documented default command without making tests or
alternate entrypoints double-start the game.

## Goals

- Add `examples/snake/` as a copyable independent Space app template.
- Make the example a small playable Snake game, not just a compile fixture.
- Keep the example independent from Space's default `assets/lua/main.fnl`, HUD,
  graph, LLM, wallet, and other default-app modules.
- Demonstrate the app repository layout expected by the reusable bundle workflow.
- Include documentation for local development, copying the template into a new
  repository, and publishing releases through Space's reusable workflow.
- Validate the example with Space-native Fennel checks, constraints, and a focused
  logic test.

## Non-goals

- Do not redesign Space runtime asset lookup, CLI entrypoint behavior, or the
  app-distribution workflow.
- Do not move the existing default `main` app out of Space.
- Do not add packaging functionality beyond showing the caller workflow a copied
  app would use.
- Do not introduce heavy UI/game abstractions for this one example.
- Do not depend on system `fennel`, system `lua`, `fnlfmt`, or `fennel-ls` for
  validation.

## Considered approaches

### Approach A: top-level start only

`assets/lua/main.fnl` could start the game unconditionally when the module is
required. This makes `space -m main` work, but it makes `require :main` unsafe for
tests and tools because loading the module immediately starts the application.

### Approach B: exported function only

The example could export `{:main main}` and document `space -m main:main`. This
matches the existing tiny `mygame` fixture, but it conflicts with the default
app-distribution docs and workflow default of `entrypoint: main`.

### Approach C: AppConfig-gated dual mode

`main.fnl` defines `main`, exports `{:main main}`, and calls `main` at module load
only when `app-config.run-main` is true. This follows Space's existing entrypoint
semantics: `space -m main` runs the app, while `space -m main:main` and tests can
call the function deliberately.

## Decision

Use Approach C. The template should be runnable from `examples/snake/` with:

```sh
space -m main
```

and from the repository root during local development with explicit asset roots:

```sh
SPACE_ASSETS_PATH="$(pwd)/examples/snake/assets:$(pwd)/assets" ./build/space -m main
```

The example should also keep the game logic testable separately from runtime boot
code.

## File layout

```text
examples/
└── snake/
    ├── README.md
    ├── .github/
    │   └── workflows/
    │       └── release.yml
    └── assets/
        └── lua/
            ├── main.fnl
            ├── snake/
            │   ├── game.fnl
            │   └── app.fnl
            └── tests/
                └── test-snake-game.fnl
```

- `README.md` explains how to run the example locally, how to copy it into a new
  repository, and how the included release workflow calls Space's reusable bundle
  workflow.
- `.github/workflows/release.yml` is an illustrative caller workflow for copied
  repositories. It should use `semanticdreams/space2/.github/workflows/bundle.yml`
  and pinned placeholders that a new repository updates.
- `main.fnl` is the entrypoint bridge. It should require `app-config`, require the
  snake app module, define `main`, call it when `run-main` is true, and export
  `{:main main}`.
- `snake/game.fnl` is pure Snake game state and rules: grid size, snake body,
  direction changes, food placement, growth, collision, scoring, game-over, and
  restart. It should not require engine or default-app modules.
- `snake/app.fnl` is the minimal runtime shell that owns engine startup, input,
  update ticks, and presentation. It should depend only on low-level reusable
  Space runtime modules as needed.
- `tests/test-snake-game.fnl` covers deterministic game logic such as movement,
  rejecting direct reversal, eating food, growth, and wall/self collision.

## Runtime behavior

The game should be intentionally simple so it works as a template:

- Arrow keys or WASD change direction.
- The snake moves on a fixed-size grid at a fixed tick rate.
- Eating food grows the snake and increments the score.
- Hitting a wall or the snake's body ends the round.
- Space or Enter restarts after game over.
- Escape or Q quits.

Rendering can be minimal. The template should prioritize understandable code and
clear separation between game rules and runtime glue over visual polish. If the
smallest robust runtime shell cannot render a board without pulling in default-app
infrastructure, the example should still keep the game logic and entrypoint
correct and document the rendering boundary explicitly in the README.

## Error handling

- The entrypoint should fail loudly if required modules are missing; no silent
  no-op boot paths.
- Game logic should validate or normalize invalid direction changes rather than
  entering impossible state.
- Restart should create fresh game state rather than mutating stale state in
  surprising ways.

## Testing and validation

Implementation should use Space-native Fennel validation:

1. Build first if `./build/space` is missing or stale.
2. Compile check touched example files with `tools.fennel-check`.
3. Run constraints for touched Fennel files or the normal constraints gate.
4. Run the focused game-logic test module through `./build/space` with
   `SPACE_ASSETS_PATH` including `examples/snake/assets` before repository
   `assets`.
5. Run packaging metadata normalization against `examples/snake` to prove the
   template layout is accepted by the app-distribution scripts.
6. Run broader validation only if final finishing or reviewers require it.

## Acceptance criteria

- `examples/snake/` exists with README, assets, Fennel source, focused Fennel
  logic test, and sample release workflow.
- The example is structured like an independent repository and can be copied out
  without depending on files outside its own app assets except the installed Space
  runtime and Space-owned runtime assets.
- `space -m main` from the example root is the documented local run command.
- The example does not import Space's default `assets/lua/main.fnl` app or its
  default-app-only modules.
- Space-native compile, constraints, focused test, and metadata-normalization
  validation pass.
