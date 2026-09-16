# Windows Desktop and CLI Launch

## Context

Windows builds currently produce `space.exe` as a console-subsystem executable.
That is convenient for terminal runs, CI smoke tests, and alternate entry points
such as `-m tests.fast:main`, but it also means a normal double-click or
installer shortcut opens a terminal window before the Space app appears. That
feels like a developer build rather than a polished desktop app.

The existing runtime already supports all entry forms in one C++ bootstrap path:
default `-m main`, `-m mod[:fn]`, files, stdin, and `-c`. Windows packages also
already include file logging under the user log directory, so GUI launches do not
need an attached terminal as the primary diagnostic channel.

## Goals

- Make the normal Windows app launch (`space.exe`) avoid opening a terminal when
  started from Explorer, installer shortcuts, or desktop shortcuts.
- Preserve reliable terminal, script, CI, and test usage on Windows.
- Keep one implementation of Space startup and entry-point parsing.
- Keep alternate GUI entry points such as `space.exe -m mod[:fn]` available for
  shortcuts, Explorer launches, and other user-facing launch mechanisms.
- Keep alternate CLI entry points such as `space-cli.exe -m mod[:fn]`, file
  execution, stdin, and `-c` available for Windows terminal workflows.
- Keep non-Windows executable names and behavior unchanged.
- Keep Windows installer and shortcut behavior user-facing and simple.

## Non-Goals

- Changing Fennel module loading or CLI parsing semantics.
- Adding Windows CEF support.
- Creating a shell wrapper, `.bat`, or `.cmd` as the primary Windows interface.
- Guaranteeing console-style stdout/stderr behavior when users explicitly run the
  GUI `space.exe` from an existing terminal.
- Renaming Linux or macOS binaries.

## Considered Approaches

### Keep a single console `space.exe`

This preserves current terminal behavior, but it does not solve the user-facing
problem: Windows will continue to create a terminal window on double-click. This
is not the right default for a desktop app.

### Make the single `space.exe` a GUI executable and attach to parent consoles

A GUI-subsystem executable can call Windows APIs such as
`AttachConsole(ATTACH_PARENT_PROCESS)` when launched from a terminal. That keeps
one file name, but terminal behavior is brittle: shells may not wait for the
process like they do for a console program, output capture and piping are less
predictable, and CI/Wine/script behavior becomes harder to reason about.

### Build separate desktop and console executables from the same source

The recommended design is to build two Windows executables from the same
`apps/space/main.cpp` entry implementation:

- `space.exe` — Windows GUI-subsystem desktop app for shortcuts and double-click
  launch. It does not create a terminal window, and it still accepts the same
  entry arguments, including `-m mod[:fn]`, for alternate GUI entry points.
- `space-cli.exe` — Windows console-subsystem app for terminals, scripts, tests,
  and entry points that need console stdout/stderr or shell-friendly process
  behavior.

This adds one packaged binary, but it matches common Windows app conventions and
keeps both launch modes reliable instead of forcing one executable to emulate two
different Windows process models.

## Design

On Windows only, CMake will create two executable targets from the same
`apps/space/main.cpp` source and link both to the existing runtime library. The
existing `${PROJECT_NAME}` target will become a `WIN32`/GUI-subsystem executable
and continue to output `space.exe`. A new console target will output
`space-cli.exe`.

Both executables must retain the full existing argument parser. The distinction
is not which entry points are allowed; it is which Windows subsystem owns process
presentation. User-facing GUI entry points should use `space.exe -m ...` so they
launch without a terminal. Terminal, CI, and script entry points should use
`space-cli.exe -m ...` when they need console output, stdin/stdout/stderr, shell
waiting, or predictable capture behavior.

Shared target setup such as linking, include directories, CEF compile definitions
when enabled, and platform-independent options should be factored so the two
targets cannot drift. Windows icon and version resources should remain attached
to the desktop `space.exe`; the console executable does not need desktop shell
metadata.

The GUI target should define a small compile-time marker so startup errors that
would otherwise only go to `stderr` can also be surfaced visibly, for example via
a Windows message box on explicit top-level startup/runtime failures. The console
target must not define that marker, preserving normal stderr behavior for
terminal workflows.

Packaging should include both executables in the Windows runtime directory.
Installer, Start Menu, desktop, and post-install launch actions should continue
to target `space.exe`. Windows test and smoke scripts should use `space-cli.exe`
for `--help`, `-m tests.fast:main`, and other terminal-style invocations.

## Expected Behavior

- Double-clicking packaged `space.exe` launches Space without opening a terminal
  window.
- Windows installer shortcuts launch `space.exe` and therefore do not show a
  terminal window.
- Windows GUI shortcuts can target alternate entries with arguments such as
  `space.exe -m some.gui.entry:main` without opening a terminal window.
- Running `space-cli.exe -m main` from PowerShell/cmd starts the same app through
  the same entry implementation, with normal console stdout/stderr semantics.
- Running `space-cli.exe -m tests.fast:main`, `space-cli.exe -c ...`, file
  entries, and stdin entries uses the same behavior currently provided by
  `space.exe`.
- Non-Windows builds continue to produce the existing `space` executable only.
- Windows packages include both `space.exe` and `space-cli.exe`.

## Testing

Validation should include a native configure/build to ensure non-Windows target
behavior remains intact, plus the normal test suite because the app target setup
and top-level startup error paths change. When the Windows cross-build toolchain
is available, build the Windows runtime and verify both executables exist.

The Windows PE subsystem should be checked directly: `space.exe` must report the
Windows GUI subsystem, and `space-cli.exe` must report the Windows CUI subsystem.
Wine or native Windows smoke tests should run terminal-style checks through
`space-cli.exe`, including an alternate module entry such as
`-m tests.fast:main`. Packaging validation should confirm both executables are
present and installer shortcuts still point at `space.exe`.

## Documentation

Update Windows build/release documentation to explain the split in user-facing
terms: launch `space.exe` from shortcuts or Explorer, use `space.exe -m ...` for
alternate GUI shortcuts, and use `space-cli.exe` for terminals, scripts, tests,
and console-oriented entry points.
