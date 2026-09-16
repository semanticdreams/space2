# Building space

## Install from Latest GitHub Release

Use prebuilt packages from the latest release:
[Latest release page](https://github.com/semanticdreams/space2/releases/latest)

Direct downloads:
- Windows installer (.exe): [space-windows-setup.exe](https://github.com/semanticdreams/space2/releases/latest/download/space-windows-setup.exe)
- Windows (.zip): [space-windows.zip](https://github.com/semanticdreams/space2/releases/latest/download/space-windows.zip)
- AppImage: [space-linux-x86_64.AppImage](https://github.com/semanticdreams/space2/releases/latest/download/space-linux-x86_64.AppImage)
- Debian/Ubuntu (.deb): [space-linux-amd64.deb](https://github.com/semanticdreams/space2/releases/latest/download/space-linux-amd64.deb)
- Fedora/openSUSE Tumbleweed (.rpm): [space-linux-x86_64.rpm](https://github.com/semanticdreams/space2/releases/latest/download/space-linux-x86_64.rpm)
- Tarball (.tar.gz): [space-linux-x86_64-bin.tar.gz](https://github.com/semanticdreams/space2/releases/latest/download/space-linux-x86_64-bin.tar.gz)
- Minimal AppImage: [space-minimal-linux-x86_64.AppImage](https://github.com/semanticdreams/space2/releases/latest/download/space-minimal-linux-x86_64.AppImage)
- Minimal Debian/Ubuntu (.deb): [space-minimal-linux-amd64.deb](https://github.com/semanticdreams/space2/releases/latest/download/space-minimal-linux-amd64.deb)
- Minimal Fedora/openSUSE Tumbleweed (.rpm): [space-minimal-linux-x86_64.rpm](https://github.com/semanticdreams/space2/releases/latest/download/space-minimal-linux-x86_64.rpm)
- Minimal Tarball (.tar.gz): [space-minimal-linux-x86_64-bin.tar.gz](https://github.com/semanticdreams/space2/releases/latest/download/space-minimal-linux-x86_64-bin.tar.gz)

Install guidance:
- Windows installer: run `space-windows-setup.exe` and follow the installer.
- Windows: extract `space-windows.zip` and run `space.exe`.
- AppImage: mark executable and run it (`chmod +x <file>.AppImage`, then `./<file>.AppImage`).
- Tarball: extract and run `./space`.
- Debian/Ubuntu: install the downloaded `.deb` with `sudo apt install ./space-*.deb` (or `sudo dpkg -i`).
- Fedora/openSUSE Tumbleweed: install the downloaded `.rpm` with `sudo dnf install ./space-*.rpm` (or `sudo rpm -i`). The RPM does not declare automatic dependencies; install the runtime libraries below first.
- RHEL/Rocky/openSUSE Leap: use the AppImage for now; full-feature RPMs need runtime libraries that are not available from their default repositories.

RPM runtime dependencies (install before running the RPM):

Fedora:
```bash
sudo dnf install bullet openal-soft libepoxy portaudio libvterm libnotify libcurl zeromq aubio xapian-core-libs rb_libtorrent ffmpeg-free libgccjit libsecret gdk-pixbuf2-modules
```

openSUSE Tumbleweed:
```bash
sudo zypper install libbullet3 libopenal1 libepoxy0 libportaudio2 libvterm0 libnotify4 libcurl4 libzmq5 libaubio5 libxapian30 libtorrent-rasterbar2_0 ffmpeg-7-libavcodec61 libgccjit0 libsecret-1-0 typelib-1_0-GdkPixbuf-2_0
```

## Build from source

Linux package names differ by distro. Use the dependency set that matches your system.

Ubuntu/Pop!_OS:

<!-- CI_DEPS_START -->
```bash
sudo apt install cmake libbullet-dev libglm-dev libopenal-dev libepoxy-dev portaudio19-dev libvterm-dev libnotify-dev libcurl4-openssl-dev libzmq3-dev python3 python3-pytest python3-pil python3-zmq cargo sccache libaubio-dev libboost-dev libxapian-dev libtorrent-rasterbar-dev ripgrep ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev libgccjit-11-dev libsecret-1-dev libfreetype-dev libwayland-dev libegl1-mesa-dev libxkbcommon-dev libxi-dev xvfb
```
<!-- CI_DEPS_END -->

Fedora:

```bash
sudo dnf install \
  cmake \
  bullet-devel \
  glm-devel \
  openal-soft-devel \
  libepoxy-devel \
  portaudio-devel \
  libvterm-devel \
  libnotify-devel \
  libcurl-devel \
  zeromq-devel \
  python3 \
  python3-pillow \
  python3-zmq \
  cargo \
  sccache \
  aubio-devel \
  boost-devel \
  xapian-core-devel \
  rb_libtorrent-devel \
  ripgrep \
  ffmpeg-free \
  ffmpeg-free-devel \
  libgccjit-devel \
  libsecret \
  libsecret-devel \
  libdecor-devel \
  wayland-devel \
  mesa-libEGL-devel \
  mesa-libGL-devel \
  libxkbcommon-devel \
  libXi-devel \
  libpng-devel
```

openSUSE Tumbleweed:

```bash
sudo zypper install \
  cmake \
  gcc-c++ \
  make \
  git \
  pkgconf \
  rpm-build \
  ccache \
  sccache \
  bzip2 \
  tar \
  libbullet-devel \
  glm-devel \
  openal-soft-devel \
  libepoxy-devel \
  portaudio-devel \
  libvterm-devel \
  libnotify-devel \
  libcurl-devel \
  zeromq-devel \
  python3 \
  python3-Pillow \
  python3-pyzmq \
  cargo \
  libaubio-devel \
  boost-devel \
  libxapian-devel \
  libtorrent-rasterbar-devel \
  ripgrep \
  ffmpeg-7-libavcodec-devel \
  ffmpeg-7-libavformat-devel \
  ffmpeg-7-libavutil-devel \
  ffmpeg-7-libswscale-devel \
  ffmpeg-7-libswresample-devel \
  libgccjit-devel \
  libsecret-devel \
  libdecor-devel \
  wayland-devel \
  Mesa-libEGL-devel \
  Mesa-libGL-devel \
  libxkbcommon-devel \
  libXi-devel \
  libpng16-devel
```

Build and run for normal local development:

```bash
make build
make run
```

`make build` is the quiet default local build. It prints the full build log path before configure/build work starts, writes the complete CMake and compiler transcript to `build/logs/build.log`, and prints a concise success or failure summary. On failure, the terminal includes a bounded tail from `build/logs/build.log`; inspect the full log file for the complete transcript.

The default local Makefile profile is minimal and CEF-off. `make build`, `make cmake`, and `make cmake-minimal` configure with `-DSPACE_BUILD_PROFILE=minimal -DSPACE_ENABLE_CEF=OFF`.

For browser-surface development, CEF integration work, or full local packaging checks, use the explicit full profile:

```bash
make build-full
make cmake-full
```

The full profile configures with `-DSPACE_BUILD_PROFILE=full -DSPACE_ENABLE_CEF=ON` and uses the same `build/logs/build.log` quiet build mechanism for `make build-full`.

To run the app directly, use `./build/space -m main`.
By default, `./build/space` also starts the main app; use `./build/space --repl` for the embedded Fennel REPL.

If you create fresh `git worktree`s for agent-driven development, you can
warm the build directory from a cached main-checkout build to skip the
initial full compile. See [OpenCode Agent Workflow](features/opencode-agent-workflow.md#optional-warm-new-worktrees-from-the-main-build)
for the setup script and caveats.

### Runtime asset discovery

Direct binary execution is supported from arbitrary working directories. After a normal build, assets are copied next to the executable at `build/assets`, so commands such as this work even outside the repository root:

```bash
tmp="$(mktemp -d)"
cd "$tmp"
SPACE_DISABLE_AUDIO=1 /path/to/space/build/space --no-dotenv -c '(print (+ 5 3))'
```

Asset roots are searched in this order:

1. `SPACE_ASSETS_PATH`, when non-empty.
2. User data assets: `get_user_data_dir("space") / "assets"`.
3. Developer/build sibling assets: `<exe_dir>/assets`.
4. Install or portable layout: `<exe_dir>/../share/space/assets`.
5. macOS-style bundle layout, if applicable: `<exe_dir>/../Resources/assets`.
6. Working-directory fallback: `<cwd>/assets`.
7. Legacy system fallback: `/usr/share/space/assets`.

`SPACE_ASSETS_PATH` is an explicit override for custom asset roots and remains the highest-priority lookup location. It is not required for normal build, installed, or portable runtime layouts.

### Runtime log location

Native logging is configured during C++ startup before any entry mode runs. By default, logs are written to `get_user_log_dir("space") / "space.log"`; on Linux this is `${XDG_CACHE_HOME:-~/.cache}/space/log/space.log`.

Set `SPACE_LOG_DIR` to a non-empty directory to override the log directory. The runtime writes `space.log` inside that directory. `LOGS_DIR` is not used by Space. Direct CLI modes such as `space --no-dotenv -c ...` do not write `gl.log` into the current working directory as part of normal startup.

Optional packaging dependencies (only needed for `make pack`):

Ubuntu/Pop!_OS:

```bash
sudo apt install dpkg-dev rpm
```

Fedora:

```bash
sudo dnf install dpkg-dev rpm-build
```

- `dpkg-dev` is needed for `.deb` dependency scanning (`dpkg-shlibdeps`).
- `rpm`/`rpm-build` is needed for `.rpm` output (`rpmbuild`).
- Use `make install-deb` to install a built `.deb` locally.
- Use `make install-rpm` to install a built `.rpm` locally.

Build an AppImage (portable Linux bundle) from the full CEF-enabled local profile:

```bash
make appimage
```

`make appimage` depends on `make build-full` so local AppImage checks include browser/CEF runtime files. `make pack` also depends on `make build-full` before running CPack. Minimal release artifacts remain available through `scripts/build-linux.sh --profile minimal`.

This writes `build/space-<version>-x86_64.AppImage`.

Build Linux release artifacts with selectable profiles:

```bash
# full profile (default)
scripts/build-linux.sh --profile full

# minimal profile (currently disables CEF; extend via SPACE_MINIMAL_DISABLED_OPTIONS)
scripts/build-linux.sh --profile minimal

# distro-specific DEB example
scripts/build-linux.sh --profile full --package-mode deb --deb-flavor ubuntu-24.04

# distro-specific RPM example
scripts/build-linux.sh --profile full --package-mode rpm --rpm-flavor fedora
```

Stable outputs are written as:
- Full default names: `build/space-linux-x86_64.AppImage`, `build/space-linux-amd64.deb`, `build/space-linux-x86_64.rpm`, `build/dist/space-linux-x86_64-bin.tar.gz`
- Minimal default names: `build/space-minimal-linux-x86_64.AppImage`, `build/space-minimal-linux-amd64.deb`, `build/space-minimal-linux-x86_64.rpm`, `build/dist/space-minimal-linux-x86_64-bin.tar.gz`
- Distro-flavored outputs use the selected flavor, such as `build/space-linux-ubuntu-24.04-amd64.deb` or `build/space-linux-fedora-x86_64.rpm`

Windows release builds currently publish:
- `space-windows-setup.exe`
- `space-windows.zip`

Both Windows release packages include two executables:

- `space.exe` is the desktop GUI launcher. Explorer, Start Menu entries, desktop shortcuts, and installer launch actions use this executable so normal launches do not open a terminal window. Alternate GUI shortcuts can still pass a module entry, such as `space.exe -m some.gui.entry:main`, without opening a terminal.
- `space-cli.exe` is the console launcher for PowerShell/cmd, scripts, CI, tests, and captured terminal output. Use it for command-line workflows such as `space-cli.exe --help`, `space-cli.exe -m tests.fast:main`, file execution, stdin, or `space-cli.exe -c "(print :ok)"`.

Linux and macOS release packages remain single-executable platforms.

The Matrix FFI library (`ffi/matrix`) is built by default and requires `cargo`. To skip it, configure
with `-DSPACE_BUILD_MATRIX=OFF` (e.g. `make cmake` then `cmake -DSPACE_BUILD_MATRIX=OFF ..`).
Matrix Rust artifacts are written to a shared Cargo target directory under the user cache by default
so new worktrees can reuse them. When `sccache` is installed, the build also enables it automatically
for Rust compilation.

Wallet-core integration is disabled by default. Enable it by configuring with `-DSPACE_ENABLE_WALLET_CORE=ON`
(e.g. `make cmake` then `cmake -DSPACE_ENABLE_WALLET_CORE=ON ..`).

CEF embedded browser integration is Linux-only right now. The normal local `make build` path is intentionally CEF-off for faster agent and developer feedback. Use the explicit full Makefile path when browser surfaces, CEF helper behavior, or CEF packaging contents are relevant:

```bash
make cmake-full
make build-full
```

If you need to override the pinned build, you can still pass:
`-DSPACE_CEF_VERSION=... -DSPACE_CEF_URL=... -DSPACE_CEF_SHA256=...`

CEF setup in `cmake/cef.cmake` is structured with a platform dispatcher (`space_setup_cef_for_target`) and Linux-specific implementation (`space_setup_cef_for_target_linux`) so Windows/macOS support can be added as separate platform handlers later.

At runtime, browser surfaces are created from Fennel via `app.engine.browser`:

```fennel
(app.engine.browser:create-surface {:id "cube-face-1"
                                    :url "https://example.com"
                                    :texture-name "browser/cube-face-1"
                                    :width 1024
                                    :height 1024
                                    :max-fps 30})
```

Bind `:texture-name` to any mesh/material texture slot to render web content on arbitrary geometry (planes, cube faces, UV-mapped meshes).
Use `app.engine.browser:send-mouse-move`, `:send-mouse-click`, `:send-mouse-wheel`, and `:set-focus` to route world-space hit input into the surface.

For an opt-in in-world cube demo (6 browser faces), run with:

```bash
SPACE_BROWSER_CUBE_DEMO=1 SPACE_ASSETS_PATH=$(pwd)/assets ./build/space -m main
```
