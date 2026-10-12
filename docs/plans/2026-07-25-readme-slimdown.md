# README Slimdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `README.md` from a 396-line developer-heavy document into a ~50-line friendly landing page, moving detailed content into `docs/`.

**Architecture:** README becomes a front door for "everyone" — badges, tagline, quick links, brief "What is space?" section, getting started pointers, contribute, and license. Build/setup details move to `docs/dev/building.md`; user install guidance moves to `docs/user/quick-start.md`; debugging/testing/profiling each get their own dev doc pages. CI workflows updated to parse deps from the new location.

**Tech Stack:** Markdown, VitePress (docs site), GitHub Actions YAML.

## Global Constraints

- README target length is approximately ~50 lines.
- README audience is "everyone": users, evaluators, and contributors.
- README tagline must include "Free Your System".
- README quick links must include Quick Start, User Docs, Developer Docs, and Latest Release.
- README license section must state GPL v3.
- Do not duplicate detailed video docs; link to existing `docs/dev/video-playback.md`.
- Preserve CI dependency extraction markers (`CI_DEPS_START` / `CI_DEPS_END`); relocate them — do not delete.
- `docs/user/quick-start.md` must not point users back to README for setup after README is slimmed.
- Out of scope: changing build commands, package names, release artifact names, runtime behavior, or feature APIs.
- All new docs pages must be added to VitePress sidebar config and dev index page.

---

### Task 1: README Landing Page

**Files:**
- Modify: `README.md`

**Interfaces:**
- Produces: A short README landing page with no detailed developer procedures. Links to: `https://github.com/semanticdreams/spacecore/releases/latest`, `docs/user/quick-start.md`, `docs/user/index.md`, `docs/dev/index.md`, `docs/dev/building.md`.

- [ ] **Step 1: Replace entire README.md content with the slim version**

Write the following content to `README.md`:

```markdown
# space

[![.github/workflows/test.yml](https://github.com/semanticdreams/spacecore/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/semanticdreams/spacecore/actions/workflows/test.yml)
[![.github/workflows/build.yml](https://github.com/semanticdreams/spacecore/actions/workflows/build.yml/badge.svg?branch=)](https://github.com/semanticdreams/spacecore/actions/workflows/build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://opensource.org/license/gpl-3-0)

> **Free Your System** — a programmable, shared, user-owned computing environment for code, knowledge, games, art, and collaboration.

[Quick Start](https://spaceui.org/user/quick-start) · [User Docs](https://spaceui.org/user/) · [Developer Docs](https://spaceui.org/dev/) · [Latest Release](https://github.com/semanticdreams/spacecore/releases/latest)

## What is space?

space is a 3D spatial computing platform and live programming environment — a programmable world where code, data, tools, notes, and media are projected into one unified graph. Built in C++ with Fennel (Lisp) scripting, it runs as a single binary with a built-in runtime.

- **Spatial Computing** — 3D spaces with in-world media, embedded surfaces, spatial widgets, and interactive visualization.
- **Live Programming** — Code you can inspect, modify, and reload in place while the world is running.
- **Shared Worlds** — Persistent multi-user spaces for collaboration, communication, and social interaction.
- **User-Owned Infrastructure** — Self-hosted and federated services for sync, communication, identity, and software distribution.

## Getting Started

**Prebuilt packages:** [Download the latest release](https://github.com/semanticdreams/spacecore/releases/latest) — AppImage, .deb, .rpm, .exe, and .zip available.

**Build from source:** See [Building space](/dev/building) for per-distro dependencies and build instructions.

## Contribute

[Discussions](https://github.com/semanticdreams/spacecore/discussions) · [Matrix](https://matrix.to/#/#spaceui.org:matrix.org)

## License

[GNU General Public License v3](https://opensource.org/license/gpl-3-0)
```

- [ ] **Step 2: Verify no detailed content remains**

Run: `grep -n -i "sudo apt install\|CI_DEPS_START\|Remote Control\|E2E Snapshot\|In-World Video\|video-widget\|prof-scene\|profiling the fennel\|SPACE_TERMINAL_PROGRAM\|CEF embedded\|Matrix FFI\|Wallet-core\|AppImage\|build-linux.sh\|dpkg-dev\|rpm-build" README.md`

Expected: No matches found (or at most a single `build-linux.sh` reference if contained in a link — ok if none).

- [ ] **Step 3: Commit**

```
git add README.md
git commit -m "docs(readme): slim to landing page, move details to docs/"
```

---

### Task 2: New Developer Building Page

**Files:**
- Create: `docs/dev/building.md`
- Modify: `.github/workflows/test.yml:53`
- Modify: `.github/workflows/build.yml:57`
- Modify: `docs/dev/index.md`
- Modify: `docs/.vitepress/config.mts`

**Interfaces:**
- Consumes: Build-from-source, per-distro dependency lists, packaging, AppImage, release-script documentation currently in original `README.md`.
- Produces: `docs/dev/building.md` with CI dependency markers preserved; updated workflows that extract from the new path.

- [ ] **Step 1: Create `docs/dev/building.md` with full build content**

Write to `docs/dev/building.md` the install-from-latest-release section AND the build-from-source section from the current README. Include everything from the "Install from latest GitHub release" heading through the CEF/Matrix/Wallet-core paragraphs and build-script examples (approximately lines 9-249 of the current README). The Ubuntu dependency block must preserve the `<!-- CI_DEPS_START -->` and `<!-- CI_DEPS_END -->` markers exactly as they are.

Start the file with:
```markdown
# Building space

## Install from Latest GitHub Release
```

- [ ] **Step 2: Update `.github/workflows/test.yml` dependency extraction**

Change line 53 from:
```yaml
          deps=$(awk '/CI_DEPS_START/{flag=1;next}/CI_DEPS_END/{flag=0}flag' README.md | sed -n 's/^sudo apt install //p')
```
to:
```yaml
          deps=$(awk '/CI_DEPS_START/{flag=1;next}/CI_DEPS_END/{flag=0}flag' docs/dev/building.md | sed -n 's/^sudo apt install //p')
```

- [ ] **Step 3: Update `.github/workflows/build.yml` dependency extraction**

Change line 57 from:
```yaml
          deps=$(awk '/CI_DEPS_START/{flag=1;next}/CI_DEPS_END/{flag=0}flag' README.md | sed -n 's/^sudo apt install //p')
```
to:
```yaml
          deps=$(awk '/CI_DEPS_START/{flag=1;next}/CI_DEPS_END/{flag=0}flag' docs/dev/building.md | sed -n 's/^sudo apt install //p')
```

- [ ] **Step 4: Verify CI extraction still works**

Run: `awk '/CI_DEPS_START/{flag=1;next}/CI_DEPS_END/{flag=0}flag' docs/dev/building.md | sed -n 's/^sudo apt install //p'`

Expected: The command prints a space-separated list of Ubuntu package names (same output as when run against the current README).

- [ ] **Step 5: Add "Building" link to `docs/dev/index.md`**

Add to the Core Docs section (alphabetically, after "Agent Preset Control Panel"):
```markdown
- [Building](/dev/building)
```

- [ ] **Step 6: Add "Building" to VitePress sidebar in `docs/.vitepress/config.mts`**

In the "Internals" sidebar section (the last one), add before "Reloadable Units":
```typescript
            { text: 'Building', link: '/dev/building' },
```

- [ ] **Step 7: Commit**

```
git add docs/dev/building.md .github/workflows/test.yml .github/workflows/build.yml docs/dev/index.md docs/.vitepress/config.mts
git commit -m "docs(dev): add building page with per-distro deps and packaging docs"
```

---

### Task 3: User Quick Start Page

**Files:**
- Modify: `docs/user/quick-start.md`
- Modify: `docs/user/index.md`

**Interfaces:**
- Consumes: Install-from-release information from the original README.
- Produces: Self-sufficient quick-start page that doesn't point users back to README.

- [ ] **Step 1: Rewrite `docs/user/quick-start.md`**

Replace the entire file with a self-sufficient quick-start page. Include the release artifact list and install guidance that was in the original README (lines 9-47 — everything from "Install from latest GitHub release" through the RPM runtime dependencies for openSUSE). Do NOT include build-from-source dependency lists. End with a link to `/dev/building` for source builds.

Start with:
```markdown
# Quick Start

## Install from Latest GitHub Release

[Latest release page](https://github.com/semanticdreams/spacecore/releases/latest)
```

Then include the direct download links and install guidance from the original README. Include the RPM runtime dependency sections for Fedora and openSUSE Tumbleweed.

After the install guidance, add:
```markdown
## Build from Source

See [Building space](/dev/building) for per-distro build dependencies and instructions.
```

- [ ] **Step 2: Update `docs/user/index.md`**

Change the current content:
```markdown
# User Docs

This section is for running and using `space`.

- Start with [Quick Start](/user/quick-start)
```

to clearly direct users to the Quick Start page without implying README is the source. Keep the existing structure but ensure the language is self-contained.

- [ ] **Step 3: Commit**

```
git add docs/user/quick-start.md docs/user/index.md
git commit -m "docs(user): make quick-start self-sufficient with install guidance"
```

---

### Task 4: Developer Operational Pages

**Files:**
- Create: `docs/dev/remote-control.md`
- Create: `docs/dev/terminal.md`
- Create: `docs/dev/e2e-testing.md`
- Create: `docs/dev/profiling.md`
- Modify: `docs/dev/index.md`
- Modify: `docs/.vitepress/config.mts`

**Interfaces:**
- Consumes: Remote Control, Terminal widget, E2E Snapshot Tests, and Profiling sections from the original README.
- Produces: Four new developer documentation pages linked from dev index and sidebar.

**Remote Control content** (from original README lines 251-290): Create `docs/dev/remote-control.md` with heading "Remote Control (Debugging)". Include all content: the ZeroMQ endpoint setup, client invocation, async result API example, heavy test script reference, and the security warning.

**Terminal widget content** (from original README lines 292-295): Create `docs/dev/terminal.md` with heading "Terminal Widget". Include both bullet points about `SPACE_TERMINAL_PROGRAM` and sandbox fallback behavior.

**E2E Snapshot Tests content** (from original README lines 297-302): Create `docs/dev/e2e-testing.md` with heading "E2E Snapshot Tests". Include all four bullet points.

**Profiling content** (from original README lines 385-391): Create `docs/dev/profiling.md` with heading "Profiling the Fennel Runtime". Include both bullet points about `SPACE_FENNEL_PROFILE` and the `prof-scene` module.

- [ ] **Step 1: Create all four developer docs pages**

Create each file with the content specified above.

- [ ] **Step 2: Link all four pages from `docs/dev/index.md`**

Add these links to the Core Docs section (alphabetically):
```markdown
- [E2E Snapshot Tests](/dev/e2e-testing)
- [Profiling](/dev/profiling)
- [Remote Control (Debugging)](/dev/remote-control)
- [Terminal Widget](/dev/terminal)
```

- [ ] **Step 3: Add all four pages to VitePress sidebar in `docs/.vitepress/config.mts`**

In the "Internals" sidebar section, add after the newly added "Building" entry:
```typescript
            { text: 'E2E Snapshot Tests', link: '/dev/e2e-testing' },
            { text: 'Profiling', link: '/dev/profiling' },
            { text: 'Remote Control', link: '/dev/remote-control' },
            { text: 'Terminal Widget', link: '/dev/terminal' },
```

- [ ] **Step 4: Commit**

```
git add docs/dev/remote-control.md docs/dev/terminal.md docs/dev/e2e-testing.md docs/dev/profiling.md docs/dev/index.md docs/.vitepress/config.mts
git commit -m "docs(dev): add remote-control, terminal, e2e-testing, and profiling pages"
```

---

### Task 5: Fix Cross-References to README in Docs

**Files:**
- Modify: `docs/dev/features/cef-in-world-browser.md:44`
- Modify: `docs/dev/features/development-tooling.md:36`
- Modify: `docs/dev/features/ffmpeg-video-playback.md:45`

**Interfaces:**
- Consumes: Current README references in feature docs.
- Produces: Updated links pointing to the new canonical doc pages.

- [ ] **Step 1: Fix CEF browser doc reference**

In `docs/dev/features/cef-in-world-browser.md`, change line 44 from:
```markdown
- See: [README](https://github.com/semanticdreams/spacecore) (CEF build setup)
```
to:
```markdown
- See: [Building space](/dev/building) (CEF build setup)
```

- [ ] **Step 2: Fix development tooling doc reference**

In `docs/dev/features/development-tooling.md`, change the line containing the README link from:
```markdown
See [README](https://github.com/semanticdreams/spacecore) — build/install section.
```
to:
```markdown
See [Building space](/dev/building).
```

- [ ] **Step 3: Fix FFmpeg video playback doc reference**

In `docs/dev/features/ffmpeg-video-playback.md`, change the line containing the README link from:
```markdown
- See: [README](https://github.com/semanticdreams/spacecore) (in-world video section)
```
to:
```markdown
- See: [Video Playback (FFmpeg)](/dev/video-playback)
```

- [ ] **Step 4: Verify no remaining README references in docs**

Run: `grep -rn "README" docs/dev/ docs/ --include="*.md" | grep -v ".vitepress\|specs\|plans\|node_modules"`

Expected: No matches.

- [ ] **Step 5: Commit**

```
git add docs/dev/features/cef-in-world-browser.md docs/dev/features/development-tooling.md docs/dev/features/ffmpeg-video-playback.md
git commit -m "docs: fix cross-references from README to new canonical pages"
```

---

### Task 6: Validation

**Files:**
- Validate: `README.md`
- Validate: `docs/dev/building.md`
- Validate: `.github/workflows/test.yml`
- Validate: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: All previous documentation/navigation/workflow changes.
- Produces: Verified docs structure and preserved CI dependency behavior.

- [ ] **Step 1: Verify README is appropriately slim**

Run: `wc -l README.md`

Expected: < 70 lines.

- [ ] **Step 2: Verify CI dependency extraction still works from new location**

Run: `awk '/CI_DEPS_START/{flag=1;next}/CI_DEPS_END/{flag=0}flag' docs/dev/building.md | sed -n 's/^sudo apt install //p'`

Expected: Prints a space-separated package list.

- [ ] **Step 3: Build the VitePress docs site**

Run in `docs/`:
```
npm install && npm run docs:build
```

Expected: Build succeeds without errors.

- [ ] **Step 4: Verify no orphaned README references**

Run in repo root:
```
grep -rn "README" docs/ --include="*.md" | grep -v ".vitepress\|specs\|plans\|node_modules"
```

Expected: No matches.

- [ ] **Step 5: Run the full test suite to ensure nothing broke**

```
SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
```

Expected: All tests pass.

- [ ] **Step 6: Commit if any fixes were needed**

Only needed if validation uncovered issues. Otherwise this is a no-op commit.
