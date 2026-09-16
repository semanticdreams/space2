# Release Artifact Naming Design

## Context

Release artifact names are currently split across the Linux packaging script, the
Windows build workflow, the Windows installer helper, and user/developer docs.
The current names are inconsistent in three ways:

- Windows release artifacts omit the architecture: `space-windows.zip` and
  `space-windows-setup.exe`.
- Linux binary tarballs include a redundant `-bin` marker:
  `space-linux-x86_64-bin.tar.gz`.
- The `minimal` variant appears before the platform, for example
  `space-minimal-linux-x86_64.AppImage`, which prevents stable grouping by
  operating system and architecture.

The next release does not need backward-compatible aliases for the old names.

## Goals

- Add the architecture token to Windows release artifact names.
- Drop `-bin` from binary tarball names.
- Standardize optional variants such as `minimal` at the end of the artifact
  grammar.
- Keep ecosystem-specific architecture spelling where it matters, especially
  Debian's `amd64` token for `.deb` artifacts.
- Update workflow checks and documentation so every release-facing reference uses
  the new names.

## Non-goals

- Do not publish duplicate compatibility artifacts with the old names.
- Do not change package contents, installation behavior, signing behavior, or
  version calculation.
- Do not rename internal CI-only artifact names unless they are release-facing or
  required by the packaging data flow.

## Considered approaches

### Minimal-change grammar

`space[-minimal]-<os>-<arch>[-<role>].<ext>` would add `x86_64` to Windows and
drop `-bin`, but it would preserve the existing placement of `minimal` before
the platform. This has the least churn but leaves poor artifact grouping.

### Stable hierarchy grammar

`space-<os>-<arch>[-<role>][-<variant>].<ext>` places the stable dimensions
first: project, operating system, architecture, optional role, then optional
variant. This renames all minimal release artifacts, but it gives the cleanest
long-term hierarchy and makes future variants predictable.

### Fully explicit artifact-kind grammar

`space-<os>-<arch>-<kind>[-<variant>].<ext>` would name runtime archives as
`space-linux-x86_64-runtime.tar.gz` or `space-windows-x86_64-runtime.zip`. This
is explicit, but it is noisy and redundant with extensions such as `.AppImage`,
`.deb`, `.rpm`, and `.zip`.

## Decision

Use the stable hierarchy grammar:

```text
space-<os>-<arch>[-<role>][-<variant>].<ext>
```

The full profile omits a variant token. The minimal profile appends `-minimal`
after any role token and before the extension. Role tokens describe artifact
purpose when the extension is not enough; the Windows installer keeps `setup` as
its role token.

Release-facing names become:

| Artifact type | Full profile | Minimal profile |
| --- | --- | --- |
| Linux tarball | `space-linux-x86_64.tar.gz` | `space-linux-x86_64-minimal.tar.gz` |
| Linux AppImage | `space-linux-x86_64.AppImage` | `space-linux-x86_64-minimal.AppImage` |
| Debian package | `space-linux-amd64.deb` | `space-linux-amd64-minimal.deb` |
| RPM package | `space-linux-x86_64.rpm` | `space-linux-x86_64-minimal.rpm` |
| Windows ZIP | `space-windows-x86_64.zip` | not currently produced |
| Windows installer | `space-windows-x86_64-setup.exe` | not currently produced |

If Windows minimal artifacts are introduced later, they should use
`space-windows-x86_64-minimal.zip` and
`space-windows-x86_64-setup-minimal.exe`.

## Architecture and components

- `scripts/build-linux.sh` remains the authority for stable Linux output names
  and the release-artifact manifest. It should construct full and minimal names
  from the same grammar rather than preserving the old `space-minimal-*` prefix.
- `.github/workflows/build.yml` remains the release workflow authority for
  Windows ZIP names and smoke checks for Linux artifacts.
- `scripts/build-windows-installer.py` remains responsible for the default
  installer basename when the workflow does not override it.
- `docs/dev/building.md` and `docs/user/quick-start.md` should be updated with
  the new download names and examples.

## Data flow

1. Linux packaging builds versioned intermediate artifacts as it does today.
2. `scripts/build-linux.sh` copies those intermediates to stable release names
   using the new grammar.
3. `scripts/build-linux.sh` writes `build/release-artifacts-<profile>.txt` with
   the new stable paths.
4. The GitHub release workflow reads the manifest and uploads exactly those
   paths.
5. Windows packaging stages `build/dist/windows`, creates
   `space-windows-x86_64.zip`, creates `space-windows-x86_64-setup.exe`, and
   uploads those release artifacts.

## Error handling

Missing or stale artifact names should continue to fail loudly in workflow smoke
checks and upload steps. The implementation should update expected paths rather
than relaxing checks or adding fallback uploads. If a generated package cannot be
found, the existing packaging scripts should keep failing with an explicit error.

## Testing and validation

- Run the existing script/workflow tests that cover packaging workflow structure,
  especially `python3 -m pytest scripts/tests/test_makefile_build_workflow.py`.
- Inspect the workflow and script diffs for every old release-facing name:
  `space-minimal-linux`, `-bin.tar.gz`, `space-windows.zip`, and
  `space-windows-setup.exe`.
- When full packaging validation is justified, run the Linux packaging script for
  both profiles and verify the manifest contains the new names.
- Documentation validation is diff/search based: user-facing download examples
  should contain only the new grammar.
