# SDK Module Reference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-center `docs/sdk/` around comprehensive per-module Space ecosystem references with API details, canonical imports, aliases, and code examples.

**Architecture:** Add a flat `docs/sdk/modules/` reference catalog with one canonical page per module and category grouping in indexes/sidebar. Preserve existing SDK tutorials, guides, examples, and app/host contract reference pages, but make module reference the primary SDK navigation path. Document aliases such as `physics`, `graphics`, `sqlite`, `yojimbo`, and `treesitter` as search terms rather than fake import names.

**Tech Stack:** VitePress Markdown, `docs/.vitepress/config.mts`, Space native Lua/Fennel binding sources in `src/lua_*.cpp`, public Fennel modules in `assets/lua/**/*.fnl`, docs validation with `cd docs && npm run docs:build`.

## Global Constraints

- Re-center `docs/sdk/` around comprehensive per-module reference documentation for the libraries and modules provided by the Space ecosystem.
- The SDK section should primarily answer: “What modules are available, how do I import them, what functions/types do they expose, what errors or platform constraints should I expect, and what does real usage look like?”
- Provide complete per-module reference pages for Space ecosystem modules.
- Include practical code examples on every module page.
- Use canonical import names and document aliases/search terms separately.
- Group modules into understandable categories without making URLs depend on categories.
- Preserve existing SDK tutorials/guides/examples/app-contract pages as secondary content.
- Link to developer docs for implementation details, but keep SDK module pages consumer-facing.
- Avoid inventing APIs, compatibility aliases, or stability guarantees.
- No runtime, C++, Fennel, Lua, binding, or packaging behavior changes.
- No new module aliases or compatibility shims.
- No formal SDK stability/versioning policy.
- No invented XML reference page unless a canonical XML module/source is identified.
- No movement or deletion of existing `docs/dev/**` content.
- Use flat canonical pages under `docs/sdk/modules/`, grouped by category in `docs/sdk/modules/index.md` and the VitePress sidebar.
- Use canonical import names in page titles, filenames, examples, and sidebar entries.
- Put non-canonical names in `docs/sdk/modules/aliases.md` and in the module page's “Aliases and Search Terms” section.
- `assets/python/` is historical prototype material and must not define SDK module contracts.

---

## File Structure

- `docs/dev/notes/sdk-docs.md` — maintainer policy for SDK module docs, source-of-truth rules, alias rules, and shared page template.
- `docs/dev/notes/index.md` — link to SDK docs policy note.
- `docs/sdk/index.md` — SDK landing page, updated so module reference is the first path.
- `docs/sdk/concepts.md` — explain modules versus app/host contracts.
- `docs/sdk/reference/index.md` — clarify app/host contracts versus module references.
- `docs/sdk/modules/index.md` — categorized module catalog.
- `docs/sdk/modules/aliases.md` — non-canonical search terms and canonical destinations.
- `docs/sdk/modules/*.md` — one module reference page per canonical module.
- `docs/.vitepress/config.mts` — SDK sidebar with module reference groups.

## Shared Module Page Requirements

Every `docs/sdk/modules/*.md` page except `index.md` and `aliases.md` must include these sections:

- `# <canonical import>`
- `## Canonical Import`
- `## Source Files`
- `## What It Provides`
- `## API Summary`
- `## Examples`
- `## Errors and Platform Notes`
- `## Related Modules`
- `## Aliases and Search Terms`

Every module page must include at least one fenced `fennel` example using the canonical import name unless the page is explicitly documenting a submodule family such as `aubio`, where examples may show canonical submodule imports.

## Source-of-Truth Rules

- Native modules: inspect the matching `src/lua_*.cpp` file and runtime registration in `src/lua_runtime.cpp` or `src/lua_engine.cpp`.
- Fennel modules: inspect `assets/lua/**/*.fnl` and tests/examples for usage.
- Existing `docs/dev/**` pages may provide implementation links but must not be copied wholesale.
- If a requested name is not canonical, document it in `aliases.md` and on the related canonical page, not as a fake module page.

---

### Task 1: SDK Module Docs Policy and Navigation Re-centering

**Files:**
- Create: `docs/dev/notes/sdk-docs.md`
- Modify: `docs/dev/notes/index.md`
- Modify: `docs/sdk/index.md`
- Modify: `docs/sdk/reference/index.md`
- Modify: `docs/sdk/concepts.md`
- Modify: `docs/.vitepress/config.mts`

**Interfaces:**
- Consumes: design spec `docs/specs/2026-09-28-sdk-module-reference-design.md` and existing SDK pages.
- Produces: policy/template for later module pages and navigation entry points for `/sdk/modules/`.

- [ ] **Step 1: Create `docs/dev/notes/sdk-docs.md`**
  Include sections for purpose, selected IA, rejected IA alternatives, source-of-truth policy, alias policy, XML/no-canonical-module policy, and the shared module page template exactly matching this plan's Shared Module Page Requirements.

- [ ] **Step 2: Link policy note from `docs/dev/notes/index.md`**
  Add `- [SDK Docs](./sdk-docs)` near the other `S...` entries.

- [ ] **Step 3: Update `docs/sdk/index.md`**
  State that SDK docs are primarily module references. Make the first Start Here link `[Module Reference](/sdk/modules/)`. Keep Tutorials, Guides, App/Host Reference, Examples, Developer Docs, and the Stability Note reachable.

- [ ] **Step 4: Update `docs/sdk/reference/index.md`**
  Add a short paragraph explaining that `/sdk/reference/` covers app/host contracts, while `/sdk/modules/` covers reusable ecosystem modules.

- [ ] **Step 5: Update `docs/sdk/concepts.md`**
  Add a `## Modules vs. App Contracts` section linking to `/sdk/modules/` and `/sdk/reference/`.

- [ ] **Step 6: Update the SDK sidebar shell**
  In `docs/.vitepress/config.mts`, add a `Modules` group under the `/sdk/` sidebar before Tutorials with links to `/sdk/modules/` and `/sdk/modules/aliases`.

- [ ] **Step 7: Validate and commit**
  Run:
  ```bash
  git diff --check
  rg -n "/sdk/modules|SDK Docs" docs/sdk docs/dev/notes/index.md docs/.vitepress/config.mts
  rg -n "TO""DO|TB""D|coming soon" docs/dev/notes/sdk-docs.md docs/sdk/index.md docs/sdk/reference/index.md docs/sdk/concepts.md
  ```
  Commit:
  ```bash
  git add docs/dev/notes/sdk-docs.md docs/dev/notes/index.md docs/sdk/index.md docs/sdk/reference/index.md docs/sdk/concepts.md docs/.vitepress/config.mts
  git commit -m "docs(sdk): center SDK docs on module references"
  ```

---

### Task 2: Module Catalog and Alias Index

**Files:**
- Create: `docs/sdk/modules/index.md`
- Create: `docs/sdk/modules/aliases.md`
- Modify: `docs/.vitepress/config.mts`

**Interfaces:**
- Consumes: sidebar shell from Task 1.
- Produces: canonical module catalog and alias/search-term mapping used by all later module pages.

- [ ] **Step 1: Create `docs/sdk/modules/index.md`**
  Add H1 `# Module Reference`. Include category sections: Runtime and platform; Data, storage, and parsing; Rendering, media, and graphics; Audio; Physics and world systems; Networking and services; Wallet and identity; Advanced/native tooling. Under each category, add explicit links for every module page planned in Tasks 3–6.

- [ ] **Step 2: Create `docs/sdk/modules/aliases.md`**
  Add H1 `# Module Aliases and Search Terms`. Include exact mappings: `physics` → `bt`; `graphics` and `rendering` → `gl`, `shaders`, `textures`, `vector-buffer`, `image-io`, `glm`, `colors`, `cgltf`; `treesitter` → `tree-sitter`; `yojimbo` → `realtime`; `sqlite` → `lsqlite3` and `sql-builder`; `jpeg` and `jpg` → `image-io` and `textures`; `xml` → no canonical SDK module found.

- [ ] **Step 3: Expand sidebar Modules group**
  In `docs/.vitepress/config.mts`, add categorized module sidebar entries for all planned module pages. Keep categories collapsible if the surrounding config style supports it.

- [ ] **Step 4: Validate and commit**
  Run:
  ```bash
  git diff --check
  rg -n "physics|graphics|treesitter|yojimbo|sqlite|jpeg|xml" docs/sdk/modules/aliases.md
  rg -n "/sdk/modules/(appdirs|temporal|http|bt|wallet|gccjit)" docs/sdk/modules/index.md docs/.vitepress/config.mts
  ```
  Commit:
  ```bash
  git add docs/sdk/modules/index.md docs/sdk/modules/aliases.md docs/.vitepress/config.mts
  git commit -m "docs(sdk): add module catalog and aliases"
  ```

---

### Task 3: Runtime and Platform Module Pages

**Files:**
- Create: `docs/sdk/modules/appdirs.md`
- Create: `docs/sdk/modules/engine.md`
- Create: `docs/sdk/modules/runtime.md`
- Create: `docs/sdk/modules/cli-args.md`
- Create: `docs/sdk/modules/fs.md`
- Create: `docs/sdk/modules/logging.md`
- Create: `docs/sdk/modules/error-reporting.md`
- Create: `docs/sdk/modules/callbacks.md`
- Create: `docs/sdk/modules/jobs.md`
- Create: `docs/sdk/modules/keyring.md`
- Create: `docs/sdk/modules/process.md`
- Create: `docs/sdk/modules/shell.md`
- Create: `docs/sdk/modules/file-watch.md`
- Create: `docs/sdk/modules/notify.md`
- Create: `docs/sdk/modules/tray.md`
- Create: `docs/sdk/modules/terminal.md`
- Create: `docs/sdk/modules/sysinfo.md`
- Create: `docs/sdk/modules/uuid.md`
- Create: `docs/sdk/modules/random.md`
- Create: `docs/sdk/modules/input-state.md`
- Create: `docs/sdk/modules/dial-type.md`
- Create: `docs/sdk/modules/webbrowser.md`

**Interfaces:**
- Consumes: template and catalog from Tasks 1–2.
- Produces: complete runtime/platform module references.

- [ ] **Step 1: Inspect source files**
  Inspect relevant sources before writing pages: `src/lua_appdirs.cpp`, `src/lua_engine.cpp`, `src/lua_runtime.cpp`, `assets/lua/cli-args.fnl`, and the matching `src/lua_*.cpp` files for each native module in this task.

- [ ] **Step 2: Create all pages with the shared template**
  Every page must include canonical import, source files, what it provides, API summary, examples, errors/platform notes, related modules, aliases/search terms.

- [ ] **Step 3: Include examples**
  Include at least one `fennel` example per page using canonical imports, such as `(local appdirs (require :appdirs))`, `(local logging (require :logging))`, and `(local cli-args (require :cli-args))`.

- [ ] **Step 4: Validate and commit**
  Run:
  ```bash
  git diff --check
  rg -n "## Canonical Import|## API Summary|## Examples|## Errors and Platform Notes" docs/sdk/modules/appdirs.md docs/sdk/modules/engine.md docs/sdk/modules/logging.md docs/sdk/modules/cli-args.md
  rg -n "require :appdirs|require :engine|require :logging|require :cli-args" docs/sdk/modules
  ```
  Commit:
  ```bash
  git add docs/sdk/modules/appdirs.md docs/sdk/modules/engine.md docs/sdk/modules/runtime.md docs/sdk/modules/cli-args.md docs/sdk/modules/fs.md docs/sdk/modules/logging.md docs/sdk/modules/error-reporting.md docs/sdk/modules/callbacks.md docs/sdk/modules/jobs.md docs/sdk/modules/keyring.md docs/sdk/modules/process.md docs/sdk/modules/shell.md docs/sdk/modules/file-watch.md docs/sdk/modules/notify.md docs/sdk/modules/tray.md docs/sdk/modules/terminal.md docs/sdk/modules/sysinfo.md docs/sdk/modules/uuid.md docs/sdk/modules/random.md docs/sdk/modules/input-state.md docs/sdk/modules/dial-type.md docs/sdk/modules/webbrowser.md
  git commit -m "docs(sdk): add runtime module references"
  ```

---

### Task 4: Data, Storage, and Parsing Module Pages

**Files:**
- Create: `docs/sdk/modules/temporal.md`
- Create: `docs/sdk/modules/temporal-core.md`
- Create: `docs/sdk/modules/json.md`
- Create: `docs/sdk/modules/json-utils.md`
- Create: `docs/sdk/modules/toml.md`
- Create: `docs/sdk/modules/lsqlite3.md`
- Create: `docs/sdk/modules/sql-builder.md`
- Create: `docs/sdk/modules/tree-sitter.md`

**Interfaces:**
- Consumes: catalog, aliases, and page template from Tasks 1–2.
- Produces: complete data/storage/parsing references.

- [ ] **Step 1: Inspect source files**
  Inspect `assets/lua/temporal.fnl`, `assets/lua/temporal/**/*.fnl`, `src/lua_temporal_core.cpp`, `src/lua_json.cpp`, `assets/lua/json-utils.fnl`, `src/lua_toml.cpp`, runtime `lsqlite3` registration in `src/lua_runtime.cpp`, `assets/lua/sql-builder*.fnl`, and `src/lua_tree_sitter.cpp`.

- [ ] **Step 2: Create module pages**
  Follow the shared template. `temporal.md` must mention the temporal submodules. `lsqlite3.md` must document the SQLite binding and point to upstream API limits where appropriate. `sql-builder.md` must document the Fennel query builder. `tree-sitter.md` must list `treesitter` as search alias only.

- [ ] **Step 3: Include examples**
  Include at least one `fennel` example per page using canonical imports, such as `(local temporal (require :temporal))`, `(local json (require :json))`, `(local toml (require :toml))`, and `(local tree-sitter (require :tree-sitter))`.

- [ ] **Step 4: Validate and commit**
  Run:
  ```bash
  git diff --check
  rg -n "temporal-core|json-utils|lsqlite3|sql-builder|tree-sitter|treesitter" docs/sdk/modules
  rg -n "require :temporal|require :json|require :toml|require :tree-sitter" docs/sdk/modules
  ```
  Commit:
  ```bash
  git add docs/sdk/modules/temporal.md docs/sdk/modules/temporal-core.md docs/sdk/modules/json.md docs/sdk/modules/json-utils.md docs/sdk/modules/toml.md docs/sdk/modules/lsqlite3.md docs/sdk/modules/sql-builder.md docs/sdk/modules/tree-sitter.md
  git commit -m "docs(sdk): add data module references"
  ```

---

### Task 5: Rendering, Media, Audio, Physics, and World Module Pages

**Files:**
- Create: `docs/sdk/modules/gl.md`
- Create: `docs/sdk/modules/shaders.md`
- Create: `docs/sdk/modules/textures.md`
- Create: `docs/sdk/modules/vector-buffer.md`
- Create: `docs/sdk/modules/image-io.md`
- Create: `docs/sdk/modules/glm.md`
- Create: `docs/sdk/modules/colors.md`
- Create: `docs/sdk/modules/cgltf.md`
- Create: `docs/sdk/modules/ray-box.md`
- Create: `docs/sdk/modules/graph-edge-batch.md`
- Create: `docs/sdk/modules/force-layout.md`
- Create: `docs/sdk/modules/msdf-atlas-gen.md`
- Create: `docs/sdk/modules/video.md`
- Create: `docs/sdk/modules/audio.md`
- Create: `docs/sdk/modules/audio-input.md`
- Create: `docs/sdk/modules/aubio.md`
- Create: `docs/sdk/modules/bt.md`
- Create: `docs/sdk/modules/perlin-terrain-native.md`

**Interfaces:**
- Consumes: alias policy and catalog from Tasks 1–2.
- Produces: rendering/media/audio/physics/world references.

- [ ] **Step 1: Inspect source files**
  Inspect corresponding `src/lua_*.cpp` files, `src/lua_aubio.cpp`, `src/lua_physics.cpp`, `src/lua_image_io.cpp`, `src/lua_textures.cpp`, and related tests/examples such as JPEG texture decode and aubio tests.

- [ ] **Step 2: Create module pages**
  Follow the shared template. `image-io.md` and `textures.md` must mention `jpeg`/`jpg` as aliases/search terms, not canonical modules. `aubio.md` must list `aubio/vec`, `aubio/spectral`, `aubio/temporal`, `aubio/io`, `aubio/synth`, and `aubio/utils`. `bt.md` must state that `physics` is a search alias for the Bullet-backed `bt` module.

- [ ] **Step 3: Include examples**
  Include at least one `fennel` example per page using canonical imports, such as `(local gl (require :gl))`, `(local textures (require :textures))`, `(local audio (require :audio))`, and `(local bt (require :bt))`.

- [ ] **Step 4: Validate and commit**
  Run:
  ```bash
  git diff --check
  rg -n "jpeg|jpg|physics|aubio/temporal|require :bt|require :audio" docs/sdk/modules
  rg -n "## Canonical Import|## Examples" docs/sdk/modules/gl.md docs/sdk/modules/audio.md docs/sdk/modules/bt.md docs/sdk/modules/image-io.md
  ```
  Commit:
  ```bash
  git add docs/sdk/modules/gl.md docs/sdk/modules/shaders.md docs/sdk/modules/textures.md docs/sdk/modules/vector-buffer.md docs/sdk/modules/image-io.md docs/sdk/modules/glm.md docs/sdk/modules/colors.md docs/sdk/modules/cgltf.md docs/sdk/modules/ray-box.md docs/sdk/modules/graph-edge-batch.md docs/sdk/modules/force-layout.md docs/sdk/modules/msdf-atlas-gen.md docs/sdk/modules/video.md docs/sdk/modules/audio.md docs/sdk/modules/audio-input.md docs/sdk/modules/aubio.md docs/sdk/modules/bt.md docs/sdk/modules/perlin-terrain-native.md
  git commit -m "docs(sdk): add media and physics module references"
  ```

---

### Task 6: Networking, Wallet, Search, and Native Tooling Module Pages

**Files:**
- Create: `docs/sdk/modules/http.md`
- Create: `docs/sdk/modules/http-server.md`
- Create: `docs/sdk/modules/zmq.md`
- Create: `docs/sdk/modules/realtime.md`
- Create: `docs/sdk/modules/libtorrent.md`
- Create: `docs/sdk/modules/matrix.md`
- Create: `docs/sdk/modules/xapian.md`
- Create: `docs/sdk/modules/wallet.md`
- Create: `docs/sdk/modules/wallet-core.md`
- Create: `docs/sdk/modules/gccjit.md`

**Interfaces:**
- Consumes: canonical naming and alias policy from Tasks 1–2.
- Produces: networking/service/wallet/tooling references.

- [ ] **Step 1: Inspect source files**
  Inspect `src/lua_http.cpp`, `src/lua_http_server.cpp`, `src/lua_zmq.cpp`, `src/lua_realtime.cpp`, `src/lua_libtorrent.cpp`, `src/lua_matrix.cpp`, `src/lua_xapian.cpp`, `assets/lua/tests/test-matrix.fnl`, `assets/lua/tests/test-xapian.fnl`, `assets/lua/wallet.fnl`, `src/lua_wallet_core.cpp`, and `src/lua_gccjit.cpp`.

- [ ] **Step 2: Create module pages**
  Follow the shared template. `http-server.md` must document canonical import `http_server`. `realtime.md` must list `yojimbo` as an implementation/search alias, not an import. `wallet.md` documents the higher-level Fennel facade; `wallet-core.md` documents the native core binding.

- [ ] **Step 3: Include examples**
  Include at least one `fennel` example per page using canonical imports, such as `(local http (require :http))`, `(local zmq (require :zmq))`, `(local realtime (require :realtime))`, and `(local wallet (require :wallet))`.

- [ ] **Step 4: Validate and commit**
  Run:
  ```bash
  git diff --check
  rg -n "http_server|yojimbo|wallet-core|gccjit|require :http|require :zmq|require :realtime|require :wallet" docs/sdk/modules
  ```
  Commit:
  ```bash
  git add docs/sdk/modules/http.md docs/sdk/modules/http-server.md docs/sdk/modules/zmq.md docs/sdk/modules/realtime.md docs/sdk/modules/libtorrent.md docs/sdk/modules/matrix.md docs/sdk/modules/xapian.md docs/sdk/modules/wallet.md docs/sdk/modules/wallet-core.md docs/sdk/modules/gccjit.md
  git commit -m "docs(sdk): add service module references"
  ```

---

### Task 7: Module Reference Link Audit and Docs Build

**Files:**
- Modify: `docs/sdk/modules/index.md`
- Modify: `docs/sdk/modules/aliases.md`
- Modify: `docs/.vitepress/config.mts`
- Test: `docs/sdk/modules/`
- Test: `docs/`

**Interfaces:**
- Consumes: all module pages from Tasks 3–6.
- Produces: validated module reference section ready for final review.

- [ ] **Step 1: Verify every module page is linked**
  Run:
  ```bash
  python3 - <<'PY'
  from pathlib import Path

  files = sorted(
      path for path in Path("docs/sdk/modules").glob("*.md")
      if path.name not in {"index.md", "aliases.md"}
  )
  index_text = Path("docs/sdk/modules/index.md").read_text()
  sidebar_text = Path("docs/.vitepress/config.mts").read_text()
  missing = []
  for path in files:
      link = f"/sdk/modules/{path.stem}"
      if link not in index_text and link not in sidebar_text:
          missing.append(link)

  if missing:
      raise SystemExit("Missing module links:\n" + "\n".join(missing))

  print(f"checked {len(files)} module pages")
  PY
  ```
  Expected: prints the number of module pages and no missing links.

- [ ] **Step 2: Verify no fake canonical alias pages are linked**
  Run:
  ```bash
  rg -n "/sdk/modules/(physics|graphics|treesitter|yojimbo|sqlite|jpeg|xml)" docs/sdk docs/.vitepress/config.mts
  ```
  Expected: no matches.

- [ ] **Step 3: Verify page-template coverage**
  Run:
  ```bash
  python3 - <<'PY'
  from pathlib import Path

  required = [
      "## Canonical Import",
      "## Source Files",
      "## What It Provides",
      "## API Summary",
      "## Examples",
      "## Errors and Platform Notes",
      "## Related Modules",
      "## Aliases and Search Terms",
  ]
  failures = []
  for path in sorted(Path("docs/sdk/modules").glob("*.md")):
      if path.name in {"index.md", "aliases.md"}:
          continue
      text = path.read_text()
      for heading in required:
          if heading not in text:
              failures.append(f"{path}: missing {heading}")
      if "```fennel" not in text:
          failures.append(f"{path}: missing fenced fennel example")

  if failures:
      raise SystemExit("Module template failures:\n" + "\n".join(failures))

  print("all module pages contain required template sections and examples")
  PY
  ```
  Expected: prints `all module pages contain required template sections and examples`.

- [ ] **Step 4: Search for placeholders and unsupported stability promises**
  Run:
  ```bash
  rg -n "TO""DO|TB""D|coming soon|stable public API guarantee|stable API guarantee" docs/sdk docs/dev/notes/sdk-docs.md
  ```
  Expected: no matches except intentional wording that says no formal stability policy exists without promising stability.

- [ ] **Step 5: Run docs build**
  Run:
  ```bash
  cd docs && npm run docs:build
  ```
  Expected: VitePress build completes successfully.

- [ ] **Step 6: Commit fixes only if validation changed files**
  If link/sidebar/content fixes were required, commit them:
  ```bash
  git add docs/sdk/modules docs/.vitepress/config.mts
  git commit -m "docs(sdk): fix module reference validation issues"
  ```
  If validation did not change files, skip this step.

- [ ] **Step 7: Record final status**
  Run:
  ```bash
  git status --porcelain
  ```
  Expected: clean tree.
