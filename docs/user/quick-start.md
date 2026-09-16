# Quick Start

## Install from Latest GitHub Release

[Latest release page](https://github.com/semanticdreams/space2/releases/latest)

Use prebuilt packages from the latest release.

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

Windows users should normally run `space.exe` from the installer, Start Menu, desktop shortcut, Explorer, or the extracted ZIP. Terminal and script users should use `space-cli.exe` for console behavior. GUI shortcuts can still launch alternate entries with `space.exe -m some.gui.entry:main` without opening a terminal window.

RPM runtime dependencies (install before running the RPM):

Fedora:
```bash
sudo dnf install bullet openal-soft libepoxy portaudio libvterm libnotify libcurl zeromq aubio xapian-core-libs rb_libtorrent ffmpeg-free libgccjit libsecret gdk-pixbuf2-modules
```

openSUSE Tumbleweed:
```bash
sudo zypper install libbullet3 libopenal1 libepoxy0 libportaudio2 libvterm0 libnotify4 libcurl4 libzmq5 libaubio5 libxapian30 libtorrent-rasterbar2_0 ffmpeg-7-libavcodec61 libgccjit0 libsecret-1-0 typelib-1_0-GdkPixbuf-2_0
```

## Build from Source

See [Building space](/dev/building) for per-distro build dependencies and instructions.
