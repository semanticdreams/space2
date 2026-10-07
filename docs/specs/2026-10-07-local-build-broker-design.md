# Local Build Broker Design

## Status

Design only. This document records the intended architecture for a future local
build broker. It does not approve or begin implementation.

## Problem

Space development commonly uses fresh git worktrees. Each new worktree starts
with an empty `build/` directory, so `make build` pays a full native configure
and compile cost even when the worktree only changes Fennel, docs, prompts, or
other non-native files. Existing incremental builds are already good once a
worktree has a populated build directory; the bottleneck is cold worktree
bootstrap.

The desired experience is unchanged developer ergonomics:

- developers continue using `make build`, `make test`, and `make run`;
- `make build` becomes faster for worktrees whose native inputs match a
  previously built state;
- when native C++/CMake/Rust inputs do change, the system uses normal
  incremental CMake builds rather than starting from an empty worktree build;
- uncommitted native changes are supported;
- different branches with identical native inputs can share build results even
  when their git commits differ.

## Existing Context

- The normal local `make build` path configures the minimal Release profile with
  `-DSPACE_BUILD_PROFILE=minimal -DSPACE_ENABLE_CEF=OFF` and writes logs through
  `scripts/build-log-runner.sh` to `build/logs/build.log`.
- `make build-full` exists for full CEF-enabled work and should remain a later
  integration target, not part of the first wiring.
- CMake enables `ccache` automatically when available. CI also restores ccache
  and sccache directories, but those caches do not create a ready worktree
  `build/` directory.
- Matrix Rust artifacts already use a shared Cargo target directory by default,
  but CMake/native build trees still remain per worktree.
- Existing documentation includes a warm-worktree script that copies and repaths
  a build directory. That confirms the problem shape, but the intended broker is
  more explicit: content-keyed, local-cache-backed, and transparent behind
  `make build`.

## Goals

1. Provide a local-only build broker that can reuse native build results across
   Space worktrees.
2. Keep the public workflow transparent: `make build`, `make test`, and
   `make run` remain the commands developers use.
3. Key build results by native/config/toolchain state, not by git SHA.
4. Support uncommitted native changes by hashing and syncing file contents.
5. Materialize an ordinary per-worktree `./build` directory, not a symlink to a
   mutable shared cache slot.
6. Preserve normal CMake/ccache incremental behavior inside service-owned build
   slots.
7. Design the configuration model so `make build-full` can be wired later with
   the same broker shape.

## Non-Goals for the First Version

- Long-running daemon, socket protocol, background service lifecycle, or
  network/shared builders.
- Windows, macOS, cross-builds, AppImage, package targets, or install targets.
- Initial integration with `make build-full` or CEF-enabled builds.
- Replacing CMake, replacing ccache, or introducing Bazel/Nix-style hermetic
  builds.
- Sharing mutable `build/` directories directly between worktrees.
- Caching Fennel/assets as native build inputs, except where a file is actually
  consumed by CMake/native configure or build steps.

## Chosen Direction

The broker should start as a one-shot Python CLI invoked by `make build`, not a
resident daemon. It should behave like a local build service but run as a normal
command:

1. compute a configuration key and a native input hash from the requesting
   worktree;
2. check a local user-cache store for an exact compatible result;
3. on a hit, materialize a normal `./build` directory into the worktree;
4. on a miss, lock a compatible service-owned slot, sync a native source
   snapshot into that slot, run the normal CMake configure/build incrementally
   there, publish the successful result atomically, then materialize `./build`
   into the requesting worktree;
5. exit with the underlying build status and write useful diagnostics to the
   usual build log.

The cache should live under a user-private cache root such as:

```text
${XDG_CACHE_HOME:-~/.cache}/space/build-service/
```

The broker should create cache directories with user-only permissions because
the cache may contain source snapshots and build outputs from active worktrees.

## Key Model

Git commit SHA is not build identity. The broker may record branch/commit data
as metadata for diagnostics, but correctness should come from content and
configuration.

### Native Input Hash

The native input hash identifies source/build files that can affect the local
native build. The first version should include at least:

- root `CMakeLists.txt`;
- `cmake/**`;
- `Makefile` portions that affect broker/direct minimal build behavior;
- `scripts/build-log-runner.sh` and the broker script itself;
- `src/**/*.cpp`, `src/**/*.c`, `src/**/*.h`, and related native headers;
- `apps/space/**` native entry files and Windows resource templates only when
  the selected build configuration can consume them;
- native C++ tests if CTest registration or target construction includes them;
- `ffi/matrix/Cargo.toml`, `ffi/matrix/Cargo.lock`, and `ffi/matrix/src/**`;
- vendored/native build metadata under `external/**` that CMake adds or
  configures for the selected profile.

The hash must reflect file additions/removals as well as content changes. This
matters because the current CMake uses globbed native sources, so adding or
removing `src/*.cpp` can change the build even if no existing file changed.

The hash should intentionally exclude Fennel, docs, prompts, and runtime assets
unless a specific file is part of CMake/native configuration for the selected
profile.

### Configuration and Toolchain Key

The compatibility key should include build state that can change generated
objects or link outputs, including:

- target platform and architecture;
- CMake version and generator;
- compiler path and compiler version;
- selected build type, initially Release;
- selected Space build profile, initially minimal;
- major build options such as `SPACE_ENABLE_CEF`, `SPACE_BUILD_MATRIX`,
  `SPACE_ENABLE_LIBTORRENT`, `SPACE_ENABLE_FFMPEG`, and `SPACE_ENABLE_SSH`;
- relevant environment variables such as `CC`, `CXX`, `CFLAGS`, `CXXFLAGS`,
  `LDFLAGS`, `PKG_CONFIG_PATH`, `CMAKE_PREFIX_PATH`, `RUST_TARGET`,
  `RUSTC_WRAPPER`, and `CARGO_TARGET_DIR`;
- normalized dependency discovery results where practical, especially pkg-config
  decisions for optional libraries.

The first implementation may start conservative: include more compatibility
inputs rather than fewer, even if that reduces sharing. Incorrect sharing is
worse than a missed cache hit.

### SPACE_VERSION Concern

Current CMake derives `SPACE_VERSION` from git when no explicit override is
provided. That creates a design tension: two branches can have identical native
source but different git-derived versions. The broker design should resolve this
before implementation by choosing one of these policies:

1. include the effective git-derived version in the key, preserving current local
   version semantics but reducing cross-branch sharing; or
2. pass a deterministic local broker version such as `-DSPACE_VERSION=...` for
   brokered local builds, increasing sharing but changing local version strings.

Until this is decided, version semantics are a known open design decision, not
an implementation detail.

## Cache and Slot Model

The broker should distinguish exact results from mutable internal build slots.

### Exact Result

An exact result corresponds to:

```text
configuration/toolchain key + native input hash
```

If the exact result has already been successfully built and published, a new
worktree with the same key should not rebuild native code. It should simply
materialize a usable `./build` directory.

### Mutable Build Slot

A mutable slot is a service-owned canonical source/build pair compatible with a
broader configuration/toolchain key. The slot is allowed to move from one native
snapshot to another:

```text
slot at native hash A -> sync to native hash B -> cmake/build incrementally
```

This is what makes small native changes efficient. The broker does not require a
preexisting internal build directory for every exact hash. It can reuse a nearby
compatible slot and incrementally advance it to the requested native state.

Slots should be locked during mutation. Parallel requests for the same exact
key should coalesce or wait on the same key lock. Parallel requests for different
keys may use different compatible slots if available; otherwise they should
serialize rather than corrupt cache state.

## Source Snapshot Sync

The broker should not build directly in arbitrary worktree paths. Instead, it
should maintain service-owned canonical source snapshots for slots. On a miss,
it syncs the requesting worktree's native inputs into the selected slot source
tree, deleting stale native files that are no longer present.

This source snapshot approach supports uncommitted changes because file content,
not commit identity, is authoritative. It also avoids constantly re-rooting the
internal CMake build slot itself.

The sync must be strict enough that stale files in the service slot cannot
silently affect a build.

## Materialization Model

The requesting worktree should receive an ordinary `./build` directory. It
should not be a symlink to a mutable broker slot. This avoids cross-worktree test
interference and preserves the mental model that each worktree owns its build
directory.

Materialization may copy a ready result from the broker cache, but it must not
blindly expose cache-root paths where worktree-root paths are required. CMake
build directories are not generally relocatable. Known path-sensitive areas
include:

- `CMakeCache.txt` source/build paths;
- generated CTest files and test working directories;
- paths to runtime assets or helper scripts;
- compile commands used by tools;
- RPATH or runtime references to service-owned build outputs;
- Matrix/Rust dynamic library paths.

Therefore the materializer must either:

1. rewrite/re-root the copied build tree safely; or
2. copy artifacts and then run a local CMake configure step in the worktree to
   regenerate pathful metadata; or
3. use another verified strategy that leaves `make test` and direct
   `./build/space` execution operating against the active worktree.

The design preference is correctness over maximal hit speed. If copied metadata
cannot be proven safe, re-running local CMake configure after materialization is
acceptable. The expensive native compile/link work should still be avoided on
exact hits.

Materialization should be atomic from the worktree's perspective: failed or
interrupted materialization must not leave a half-valid `build/` that future
commands mistake for a good build.

## Makefile Integration

The first integration target is the normal local Linux minimal `make build`.
`make build` should continue to use `scripts/build-log-runner.sh`, preserve the
current log path, and preserve the existing build label.

The direct CMake path should remain available through an explicit escape hatch,
for example:

```bash
SPACE_BUILD_BROKER=0 make build
```

Unsupported targets should remain unchanged initially:

- `make build-full`;
- `make pack`;
- `make appimage`;
- `make debug`;
- Windows and cross-build scripts.

The broker interface should still be generic enough to accept profile/options so
that a future `make build-full` wiring can reuse the same architecture.

## Failure and Error Handling

- Cache hits are valid only after successful atomic publication.
- Failed canonical builds must never become reusable results.
- Interrupted builds should leave diagnostic logs but no hit-eligible metadata.
- Lock acquisition should avoid corrupting cache state under concurrent agents.
- The broker should fail closed when it cannot compute a trustworthy key,
  cannot verify materialization safety, or detects incompatible cache metadata.
- The escape hatch should make it easy to bypass the broker if the cache is
  suspected to be stale or broken.

## Acceptance Criteria for a Future Implementation

The future implementation should be considered correct only if these behaviors
hold:

1. A fresh worktree with empty `build/` can run `make build` and receive a usable
   `./build/space`.
2. A second worktree with identical native inputs can run `make build` without
   recompiling native code.
3. Fennel/docs-only changes do not change the native input hash.
4. Uncommitted native source changes do change the native input hash.
5. Adding or removing a native source file changes the native input hash.
6. Toolchain/configuration changes change the compatibility key.
7. `make test` after a cache hit runs against the active worktree's assets,
   scripts, and CTest metadata rather than the broker cache slot.
8. Materialized `build/` is a real per-worktree directory, not a symlink to a
   mutable service slot.
9. Concurrent broker invocations do not corrupt internal slots or published
   results.
10. Failed builds exit nonzero, preserve useful diagnostics in the normal build
    log, and do not publish a reusable result.
11. `SPACE_BUILD_BROKER=0 make build` preserves the pre-broker direct CMake
    behavior.

## Validation Ideas for a Future Implementation

- Unit-test native key computation with synthetic repositories:
  - identical native content in different paths produces the same key;
  - docs/Fennel changes do not change the key;
  - native content/add/remove changes do change the key;
  - relevant environment/config changes do change the key.
- Unit-test cache publication and locking behavior.
- Unit-test materialization into a temporary worktree and assert generated files
  do not contain the service cache source path where the active worktree path is
  required.
- Run `make -n build` and `SPACE_BUILD_BROKER=0 make -n build` to verify Makefile
  wiring and escape hatch behavior.
- Run `make build` in two fresh worktrees with identical native inputs and
  inspect the second run for a cache hit/no native compile.
- Run focused Fennel checks and then `make test` after a cache-hit
  materialization because this changes build/test plumbing.

## Open Decisions Before Implementation

1. **SPACE_VERSION policy:** preserve git-derived versions in the key or use a
   deterministic broker-local version override for local brokered builds.
2. **Cache retention policy:** manual cleanup only for the first version, or an
   explicit size/age garbage collector.
3. **Materialization strategy:** path rewrite, local reconfigure after copy, or a
   hybrid artifact-copy approach. This must be proven safe before enabling the
   broker by default.
4. **`make run` behavior:** current `make run` assumes a build already exists;
   decide whether future broker work should keep that behavior or make `run`
   depend on `build`.

## Rationale Against Alternatives

### Raw Worktree Build Copy

Turning the existing warm-worktree snippet into a script would be faster to ship,
but it remains checkout-oriented and path-rewrite-heavy. It does not provide a
clear content key, cache slot model, or support for identical native inputs
across different branches/commits.

### Symlinked Shared Build Directory

Symlinking `./build` to a service-owned mutable build slot would make
materialization fast but creates cross-worktree interference risks. Tests,
temporary files, and concurrent builds could mutate shared state unexpectedly.
The copied per-worktree build directory is intentionally less clever and safer.

### Long-Running Daemon

A daemon could eventually provide better queueing, status, and background
prewarming, but it adds lifecycle, socket, protocol, and stale-process
complexity. The first version should be a one-shot CLI broker with service-like
internal boundaries so a daemon can wrap the same logic later if needed.

### Bazel or a Full Build-System Migration

Bazel-like systems solve this class of problem more fundamentally with
content-addressed build actions. Migrating Space from CMake to Bazel would be a
large independent project involving third-party dependencies, CEF, Rust, tests,
and packaging. The local broker is a narrower solution for the current
worktree-bootstrap pain while preserving the existing CMake build.
