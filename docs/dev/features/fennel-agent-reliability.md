# Fennel Agent Reliability

This page documents the project-native validation path for Space Fennel work.
Agents should use these commands and tools instead of system Fennel or Lua
installations so diagnostics match the runtime that ships with Space.

## Validation Ladder

For changes that touch `assets/lua/**/*.fnl`, Fennel tests, Fennel constraints,
or Fennel validation tooling, validate in this order:

1. **Compile check first** — run the fast syntax oracle for touched files when
   the task is narrow, or the repository target when broad:
   ```bash
   ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/foo.fnl
   make fennel-check
   ```
2. **Constraints second** — run structural constraints after the compile gate:
   ```bash
   make constraints
   ```
3. **Focused tests third** — run the smallest relevant Fennel test command with
   the normal Space runtime environment.
4. **Broader suite fourth** — finish with the broader relevant suite; use the
   standard `make test` command when final whole-project validation is required.

Reports and handoffs should include compile-check, constraints, and focused-test
evidence in that order. A reported `make test` includes the compile and
constraints gates transitively, but focused Fennel work should still use the
earlier stages for faster diagnosis when feasible.

## Commands

- `make fennel-check` runs the repository compile gate through
  `./build/space -m tools.fennel-check:main -- --target repo` with the same
  canonical runtime environment used by constraints and tests.
- `./build/space -m tools.fennel-check:main -- --target files --file <path>`
  checks explicit `.fnl` files only and rejects non-`.fnl` targets.
- `make constraints` depends on `make fennel-check`, so structural constraints
  run only after the compile oracle succeeds.
- `make fennel-check` and `make constraints` use concise summary output by
  default. Add `VERBOSE=1` to either Make command when debugging needs the raw
  JSON result.
- Direct `./build/space -m tools.fennel-check:main -- ...` and
  `./build/space -m constraints.runner:main -- ...` commands remain JSON by
  default for tooling compatibility; pass `--output summary` for concise direct
  CLI output.

Do not use system `fennel`, system `lua`, `fennel-ls`, `fnlfmt`,
`./build/space --compile`, or `./build/space -e` as validation oracles for
Space Fennel work.

## MCP Tools

The MCP bridge exposes exactly five read-only, filesystem-read-risk Fennel tools
that wrap the same project-native validation service:

- `space_fennel_check_file` — compile-check one `.fnl` file and return
  structured diagnostics.
- `space_constraints_check_files` — run constraints over explicit files and
  return runner status, counts, and diagnostics.
- `space_fennel_parse_tree` — return a bounded tree-sitter parse summary.
- `space_fennel_enclosing_form` — return the smallest enclosing form around a
  line and column.
- `space_fennel_structure_metrics` — return nesting, function, and module
  metrics.

These MCP tools are for inspection and validation only. They must not edit files
or duplicate compiler/parser logic outside the project service.

The Fennel validation MCP bridge uses the shared OpenCode bridge mechanism in
`llm/opencode-mcp/bridge.fnl`, while remaining read-only and preserving this
validation-only tool list.

## Repair Workflow

When Fennel reports a delimiter or confusing parse error, start with the compile
diagnostic and inspect the nearest enclosing form before editing. Use
`space_fennel_enclosing_form` or the equivalent service call around the reported
line and column, then repair the smallest malformed enclosing form. Prefer
simplifying nested code into helper functions when delimiter balance remains
unclear.

After a repair, rerun the compile check first, then constraints, then the
focused test that covers the touched behavior.

## Deferred Integrations

The reliability path deliberately defers `fennel-ls`, `fnlfmt`, write-capable
MCP tools, and automatic AST rewriting. Those integrations are not validation
oracles for this workflow and should not be introduced as substitutes for the
compile → constraints → focused tests → broader suite ladder.
