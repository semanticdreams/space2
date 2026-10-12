---
type: dev-note
tags:
  - note
---

# Test Harness Cleanup Notes

This note documents the recent cleanup of the Lua/Fennel test harness around shared fixtures,
temporary app-state replacement, and terrain-heavy integration tests.

The main goal was not adding new product behavior. It was making the tests:

- less duplicated
- less machine-specific
- less dependent on implicit global app state
- more trustworthy under full-suite execution instead of only isolated runs

## Problems We Hit

Several test failures and maintenance smells turned out to be harness problems rather than product
bugs.

### 1. Fixture Paths Were Reimplemented Incorrectly

Some tests were resolving fixture paths ad hoc, including direct user-home paths and incorrect use
of `app.engine.get-asset-path(...)`.

Problems:

- machine-specific paths made tests non-hermetic
- repeated path code invited drift
- a few helpers were simply wrong

This affected:

- [test-demo-browser.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-demo-browser.fnl)
- [test-heightfield-terrain.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-heightfield-terrain.fnl)
- [find-heightfield-support-mismatch.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/find-heightfield-support-mismatch.fnl)
- [test-heightfield-physics-support-grid.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/e2e/test-heightfield-physics-support-grid.fnl)

### 2. Tests Mutated `app.states` Without Suspending The Current State

Many tests replaced `app.states` directly with a fresh `States` instance.

That was often good enough in isolated runs, but it was not clean:

- the previously active state could remain connected to engine signals
- full-suite ordering could expose leaks that narrowed runs did not
- restoring `app.states` alone did not restore the previous state lifecycle correctly

This was especially visible in terrain pick / terrain paint tests spread across:

- [test-demo-browser.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-demo-browser.fnl)
- [test-states.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-states.fnl)
- [test-graph-view.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-graph-view.fnl)
- [test-world-nodes.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-world-nodes.fnl)

### 3. One Test Was Over-Specifying Global Input Plumbing

One terrain-rect-pick test asserted that clickables counters stayed at zero.

That was brittle because it tested too much of the surrounding global routing instead of the actual
behavior the test owned:

- engine events reach the active terrain-rect-pick session
- the session completes
- state is restored

The counter assertion was removed because it made refactors harder without increasing confidence in
the picker logic itself.

### 4. Full-Suite Execution Exposed Stale State Teardown

After extracting shared suspend/resume helpers, the full suite exposed a real harness issue:

- some previously active states were already effectively detached
- calling `on-leave` again caused `Signal handler not connected`

That did not show up in the smaller targeted runs, which is exactly why the full-suite rerun
mattered.

## Final Improvements

### Shared Test Helper Module

The shared helper now lives in:

- [test-support.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-support.fnl)

It currently owns:

- `fixture-path`
- `suspend-active-state`
- `resume-active-state`

This gives the touched tests one place for:

- repo-local fixture resolution
- temporary active-state suspension before swapping `app.states`
- resuming the previous state after restoration

### Repo-Local Fixtures

The terrain-heavy tests now use committed fixtures under `assets/lua/tests/data/` instead of user
home paths.

This makes the tests:

- portable
- reproducible
- safe to run outside the original development machine

### Safer App-State Swaps

The touched suites now suspend the currently active state before replacing `app.states`, then
restore `app.states`, then resume the suspended state.

This is better than the old pattern because it makes state lifecycle explicit instead of relying on
the old state silently staying valid in the background.

### Better Aggregate Verification

The cleanup was not accepted based only on targeted suites. It was verified against:

- `tests.test-states:main`
- `tests.test-graph-view:main`
- `tests.test-world-nodes:main`
- `tests.fast:main`
- `make test`

The important lesson here is that harness cleanup must be verified in the full aggregate shape,
because state leaks are often invisible in isolated test runs.

## Trade-Offs

The current result is good, but not perfect.

### 1. `test-support` Still Knows About A Specific Error String

`suspend-active-state` currently treats `"Signal handler not connected"` as a stale-state case and
returns `nil` instead of failing.

That is acceptable for test glue because:

- the failure was real under aggregate runs
- the helper is intentionally defensive around global mutable app state

But it is still a compromise. String matching is not a clean systems boundary.

### 2. The Deeper Problem Is Still Global App State

The helper improves the situation, but it does not remove the architectural reason these tests are
fragile:

- many tests still mutate global `app` fields
- the harness still depends on lifecycle discipline rather than hard isolation

So the helper is a practical containment layer, not a fundamental redesign.

## What To Watch Out For

When writing or refactoring tests in this codebase:

- do not hardcode user-home fixture paths
- prefer [test-support.fnl](https://github.com/semanticdreams/spacecore/blob/main/assets/lua/tests/test-support.fnl) for fixture lookup
- if a test replaces `app.states`, suspend the current active state first and resume it after restore
- verify state-heavy cleanup with `tests.fast` or `make test`, not only a narrow module run
- avoid asserting incidental global plumbing when the test can assert the owned behavior directly

## Future Improvements

The next worthwhile improvements are structural, not urgent.

### 1. Make State Teardown Idempotent At The Source

The best long-term fix is not better string matching in test glue.
It is making state/signal teardown safe to call repeatedly.

If `on-leave` and signal disconnect paths become idempotent, `test-support` can be simplified
substantially.

### 2. Broaden Shared App-Fixture Helpers

`test-support` currently focuses on:

- fixture paths
- active-state suspension/resume

It could grow carefully into a shared helper for other common global test setup patterns, for
example:

- temporary HUD replacement
- temporary clickables / hoverables setup
- temporary world-manager setup

That should be done incrementally, not by building a giant generic harness abstraction up front.

### 3. Reduce Direct Global Mutation In Tests

Longer term, the cleanest direction is to reduce how many tests need to patch global `app` fields at
all.

That would likely require more explicit app-fixture construction helpers or narrower module
boundaries.

## Summary

The practical improvements were:

- centralize fixture lookup
- centralize active-state suspend/resume
- remove brittle over-specified assertions
- verify under the full suite

The remaining known compromise is:

- `test-support` still contains a stale-state string match because state teardown is not yet
  idempotent at the source

That is acceptable for now, but it is the first place to revisit if this harness area gets touched
again.


## See also

- [Development Tooling](/dev/features/development-tooling)
