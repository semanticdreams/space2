# Temporal Provider Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Temporal.providers`, a deterministic local Fennel provider registry for future temporal parsing/localization/calendar tracks.

**Architecture:** Implement a pure Fennel factory module that owns private provider state and exposes a small API through the existing `assets/lua/temporal.fnl` facade. Tests use the existing temporal test style and register in the fast suite. No native code, runtime plugin loading, network behavior, or temporal semantic providers are introduced in this slice.

**Tech Stack:** Fennel modules under `assets/lua/temporal/`, Space Fennel test runner, `tools.fennel-check`, `make constraints`, `tests.fast`.

## Global Constraints

- Export `Temporal.providers` from `(require :temporal)`.
- Public API: `register`, `unregister`, `list`, `all`, and `parse`.
- Provider manifest keys are canonical: `:id`, `:version`, `:capabilities`, `:priority`, `:parse`, `:format`, `:calendar`, `:business-calendar`.
- Unknown top-level provider keys are rejected loudly.
- At least one operational field among `:parse`, `:format`, `:calendar`, or `:business-calendar` is required.
- `:id` and `:version` are non-empty strings.
- `:capabilities` is a non-empty sequential array of keyword values with no duplicates.
- `:priority` is optional and defaults to `100`; when present it must be a number.
- Provider ordering is deterministic: lower priority first, then lexicographic id.
- `list` and `all` return defensive provider summaries containing only `:id`, `:version`, `:capabilities`, and `:priority`; mutating summaries must not mutate registry state.
- Handles returned by `register` are opaque. Reusing a valid inactive handle with `unregister` returns `false`; invalid handle shape throws.
- `parse` dispatches only providers with capability `:natural` and a `:parse` function.
- `parse` returns an empty array when there are no matching providers or when providers return no candidates.
- `parse` prefixes provider failures with `temporal provider <id> parse failed:`.
- `parse` annotates each candidate with `:provider-id` when absent and preserves an existing `:provider-id` when present.
- Do not load provider files from disk, add native plugin ABI/sandboxing, add remote/network providers, modify dependency packaging, expand natural-language grammar, implement localization/calendar/business-calendar behavior, or persist providers.
- Fennel validation order: touched-file `tools.fennel-check`, then `make constraints`, then focused provider registry test, then `tests.fast:main`.

---

## File Structure

- Create `assets/lua/temporal/provider-registry.fnl`: pure Fennel factory returning the provider registry API.
- Modify `assets/lua/temporal.fnl`: require the factory, instantiate it, and export as `:providers`.
- Create `assets/lua/tests/test-temporal-provider-registry.fnl`: focused unit tests for manifest validation, ordering, unregister behavior, defensive summaries, and parse dispatch.
- Modify `assets/lua/tests/fast.fnl`: register the focused provider registry test module near other temporal tests.
- Modify `docs/dev/features/temporal-complete-acceptance.md`: mark provider registry evidence as now covered by the focused test and fast-suite registration.
- Modify `docs/dev/features/temporal-complete-library.md`: mention that the local provider registry track establishes `Temporal.providers` while later tracks add concrete providers.

---

### Task 1: Provider Registry Implementation and Tests

**Files:**
- Create: `assets/lua/temporal/provider-registry.fnl`
- Modify: `assets/lua/temporal.fnl`
- Create: `assets/lua/tests/test-temporal-provider-registry.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Produces:
  - `Temporal.providers.register(provider-table) -> handle`
  - `Temporal.providers.unregister(handle) -> boolean`
  - `Temporal.providers.list(capability-key) -> provider-summary[]`
  - `Temporal.providers.all() -> provider-summary[]`
  - `Temporal.providers.parse(text, context) -> candidate[]`

- [ ] **Step 1: Add failing focused test file**

Create `assets/lua/tests/test-temporal-provider-registry.fnl` using the existing test-module pattern. Include tests with these names and behaviors:

```fennel
(local Temporal (require :temporal))
(local create-provider-registry (require :temporal/provider-registry))

(local tests [])

(fn assert= [actual expected message]
  (when (not (= actual expected))
    (error (or message (.. "expected " (tostring expected) ", got " (tostring actual))))))

(fn assert-error [f expected]
  (local (ok err) (pcall f))
  (when ok
    (error (.. "expected error containing: " expected)))
  (when (not (string.find (tostring err) expected 1 true))
    (error (.. "expected error containing " expected ", got " (tostring err)))))

(fn sample-provider [id priority]
  {:id id
   :version "1.0"
   :priority priority
   :capabilities [:natural]
   :parse (fn [text _context]
            [{:kind :sample :text text}] )})

(table.insert tests
  {:name "orders providers by priority then id"
   :fn (fn []
         (local registry (create-provider-registry {}))
         (registry.register (sample-provider "later" 20))
         (registry.register (sample-provider "alpha" 10))
         (registry.register (sample-provider "beta" 10))
         (local listed (registry.list :natural))
         (assert= (. listed 1 :id) "alpha")
         (assert= (. listed 2 :id) "beta")
         (assert= (. listed 3 :id) "later"))})
```

Use `(create-provider-registry {})` when tests need an isolated registry. Also add tests in the same file for:

- duplicate `:id` rejection with error containing `duplicate temporal provider id`;
- invalid manifests: non-table provider, empty id, empty version, empty capabilities, non-keyword capability, duplicate capability, unknown key, no operational field;
- unregister behavior: active handle returns `true`, second unregister returns `false`, invalid handle throws `invalid temporal provider handle`;
- defensive summaries: mutating returned summary capabilities does not affect a later `list` call;
- no matching parse providers returns `[]`;
- parse composition uses deterministic order and annotates `:provider-id`;
- provider parse error is prefixed with `temporal provider bad parse failed:`.

The module must return `{:name "temporal-provider-registry" :tests tests :main main}` and define `main` consistently with other temporal test files.

- [ ] **Step 2: Register focused test in fast suite**

In `assets/lua/tests/fast.fnl`, add:

```fennel
:tests.test-temporal-provider-registry
```

near the existing temporal test modules.

- [ ] **Step 3: Run RED validation**

Run:

```bash
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-provider-registry:main
```

Expected: fails because `Temporal.providers` or `temporal/provider-registry` is missing.

- [ ] **Step 4: Implement provider registry module**

Create `assets/lua/temporal/provider-registry.fnl` with:

```fennel
(local allowed-keys
  {:id true :version true :capabilities true :priority true
   :parse true :format true :calendar true :business-calendar true})

(fn sequential-length [values]
  (var count 0)
  (each [index _value (ipairs values)]
    (set count index))
  count)

(fn copy-array [values]
  (local out [])
  (each [_ value (ipairs values)]
    (table.insert out value))
  out)

(fn has-operational-field? [provider]
  (or (= (type provider.parse) :function)
      (= (type provider.format) :function)
      (= (type provider.calendar) :function)
      (= (type provider.calendar) :table)
      (= (type provider.business-calendar) :function)
      (= (type provider.business-calendar) :table)))

(fn validate-capabilities [provider]
  (assert (= (type provider.capabilities) :table) "temporal provider capabilities must be an array")
  (assert (> (sequential-length provider.capabilities) 0) "temporal provider capabilities must not be empty")
  (local seen {})
  (each [_ capability (ipairs provider.capabilities)]
    (assert (= (type capability) :string) "temporal provider capability must be a keyword")
    (assert (not (. seen capability)) "duplicate temporal provider capability")
    (tset seen capability true)))

(fn validate-provider [provider]
  (assert (= (type provider) :table) "temporal provider must be a table")
  (each [key _value (pairs provider)]
    (assert (. allowed-keys key) (.. "invalid temporal provider key: " (tostring key))))
  (assert (and (= (type provider.id) :string) (> (length provider.id) 0)) "temporal provider id must be a non-empty string")
  (assert (and (= (type provider.version) :string) (> (length provider.version) 0)) "temporal provider version must be a non-empty string")
  (validate-capabilities provider)
  (when (not (= provider.priority nil))
    (assert (= (type provider.priority) :number) "temporal provider priority must be a number"))
  (assert (has-operational-field? provider) "temporal provider requires an operational field"))

(fn capability-present? [provider capability]
  (var present false)
  (each [_ current (ipairs provider.capabilities)]
    (when (= current capability)
      (set present true)))
  present)

(fn provider-priority [provider]
  (if (= provider.priority nil) 100 provider.priority))

(fn provider-summary [provider]
  {:id provider.id
   :version provider.version
   :priority (provider-priority provider)
   :capabilities (copy-array provider.capabilities)})

(fn sort-providers! [providers]
  (table.sort providers
    (fn [a b]
      (if (not (= (provider-priority a) (provider-priority b)))
          (< (provider-priority a) (provider-priority b))
          (< a.id b.id)))))

(fn create-registry []
  (local state {:providers [] :by-id {}})

  (fn ordered-providers []
    (local providers [])
    (each [_ provider (ipairs state.providers)]
      (table.insert providers provider))
    (sort-providers! providers)
    providers)

  (fn register [provider]
    (validate-provider provider)
    (assert (= (. state.by-id provider.id) nil) (.. "duplicate temporal provider id: " provider.id))
    (local stored {:id provider.id
                   :version provider.version
                   :priority (provider-priority provider)
                   :capabilities (copy-array provider.capabilities)
                   :parse provider.parse
                   :format provider.format
                   :calendar provider.calendar
                   :business-calendar provider.business-calendar})
    (table.insert state.providers stored)
    (tset state.by-id stored.id stored)
    {:kind :temporal-provider-handle :id stored.id :active? true :registry state})

  (fn unregister [handle]
    (assert (and (= (type handle) :table)
                 (= handle.kind :temporal-provider-handle)
                 (= handle.registry state)
                 (= (type handle.id) :string))
            "invalid temporal provider handle")
    (if (not handle.active?)
        false
        (do
          (set handle.active? false)
          (tset state.by-id handle.id nil)
          (local kept [])
          (each [_ provider (ipairs state.providers)]
            (when (not (= provider.id handle.id))
              (table.insert kept provider)))
          (set state.providers kept)
          true)))

  (fn list [capability]
    (assert (= (type capability) :string) "temporal provider capability must be a keyword")
    (local out [])
    (each [_ provider (ipairs (ordered-providers))]
      (when (capability-present? provider capability)
        (table.insert out (provider-summary provider))))
    out)

  (fn all []
    (local out [])
    (each [_ provider (ipairs (ordered-providers))]
      (table.insert out (provider-summary provider)))
    out)

  (fn append-candidates [out provider candidates]
    (when (not (= candidates nil))
      (assert (= (type candidates) :table) "temporal provider parse result must be an array")
      (each [_ candidate (ipairs candidates)]
        (assert (= (type candidate) :table) "temporal provider candidate must be a table")
        (local copied {})
        (each [key value (pairs candidate)]
          (tset copied key value))
        (when (= copied.provider-id nil)
          (tset copied :provider-id provider.id))
        (table.insert out copied))))

  (fn parse [text context]
    (assert (= (type text) :string) "temporal provider parse text must be a string")
    (local ctx (if (= context nil) {} context))
    (assert (= (type ctx) :table) "temporal provider parse context must be a table")
    (local out [])
    (each [_ provider (ipairs (ordered-providers))]
      (when (and (= (type provider.parse) :function) (capability-present? provider :natural))
        (local (ok result) (pcall provider.parse text ctx))
        (if ok
            (append-candidates out provider result)
            (error (.. "temporal provider " provider.id " parse failed: " (tostring result))))))
    out)

  {:register register
   :unregister unregister
   :list list
   :all all
   :parse parse})

(fn create [_deps]
  (local registry (create-registry))
  {:register registry.register
   :unregister registry.unregister
   :list registry.list
   :all registry.all
   :parse registry.parse})

create
```

If compile/constraints reject syntax or style, preserve the same semantics while adjusting to project idioms.

- [ ] **Step 5: Export from temporal facade**

In `assets/lua/temporal.fnl`, add:

```fennel
(local create-provider-registry (require :temporal/provider-registry))
```

near the other `require` forms, instantiate:

```fennel
(local providers (create-provider-registry {}))
```

and export:

```fennel
:providers providers
```

inside the returned table.

- [ ] **Step 6: Run Fennel validation ladder**

Run touched-file compile check:

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/provider-registry.fnl --file assets/lua/temporal.fnl --file assets/lua/tests/test-temporal-provider-registry.fnl --file assets/lua/tests/fast.fnl
```

Then run:

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-provider-registry:main
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
```

Expected: compile check passes, constraints pass, focused test passes, fast suite passes.

- [ ] **Step 7: Commit Task 1**

Commit only Task 1 files:

```bash
git add assets/lua/temporal/provider-registry.fnl assets/lua/temporal.fnl assets/lua/tests/test-temporal-provider-registry.fnl assets/lua/tests/fast.fnl
git commit -m "feat(temporal): add provider registry"
```

---

### Task 2: Provider Registry Documentation and Final Validation

**Files:**
- Modify: `docs/dev/features/temporal-complete-library.md`
- Modify: `docs/dev/features/temporal-complete-acceptance.md`

**Interfaces:**
- Consumes: `Temporal.providers` from Task 1.
- Produces: docs marking the provider registry track as established while concrete provider families remain later tracks.

- [ ] **Step 1: Update roadmap docs**

In `docs/dev/features/temporal-complete-library.md`, add a short subsection after `## Architecture boundaries`:

```markdown
## Provider registry status

`Temporal.providers` is the local deterministic provider registry used by later temporal tracks. It validates in-process provider manifests, orders providers by priority and id, exposes defensive summaries, and provides natural-parse candidate dispatch. Concrete localization, calendar, business-calendar, and natural-language providers are added by later tracks.
```

- [ ] **Step 2: Update acceptance matrix**

In `docs/dev/features/temporal-complete-acceptance.md`, update the `Provider registry` row evidence to include:

```markdown
manifest validation tests, deterministic ordering tests, no-network invariant docs, fast-suite registration
```

- [ ] **Step 3: Run final validation**

Run the same validation ladder as Task 1:

```bash
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/temporal/provider-registry.fnl --file assets/lua/temporal.fnl --file assets/lua/tests/test-temporal-provider-registry.fnl --file assets/lua/tests/fast.fnl
SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets make constraints
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-temporal-provider-registry:main
SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 SPACE_DISABLE_AUDIO=1 SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.fast:main
rg "Temporal.providers|Provider registry status|fast-suite registration" docs/dev/features/temporal-complete-library.md docs/dev/features/temporal-complete-acceptance.md
git diff --check
```

Expected: all commands pass.

- [ ] **Step 4: Commit Task 2**

Commit only Task 2 files:

```bash
git add docs/dev/features/temporal-complete-library.md docs/dev/features/temporal-complete-acceptance.md
git commit -m "docs(temporal): document provider registry status"
```
