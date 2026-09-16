# Runtime Asset Overlays

Space resolves assets through ordered roots. Earlier roots shadow later roots, so projects can override built-in runtime assets by mirroring the same relative path under `assets/`.

Search order:

1. Each non-empty `SPACE_ASSETS_PATH` entry, in order.
2. `<cwd>/assets`.
3. User data assets: `get_user_data_dir("space") / "assets"`.
4. `<exe_dir>/assets`.
5. `<exe_dir>/../share/space/assets`.
6. `<exe_dir>/../Resources/assets`.
7. `/usr/share/space/assets`.

`SPACE_ASSETS_PATH` entries are asset roots, not project roots. On Unix-like systems the separator is `:`:

```bash
SPACE_ASSETS_PATH=/game/assets:/shared/assets space -m main
```

Requested asset paths remain relative to roots. Absolute paths and traversal that escapes a root are rejected loudly. Missing assets report the requested relative path and the candidate paths searched.

Normal project launch uses:

```text
project/
  assets/
    lua/main.fnl
```

Running `space --no-dotenv -m main` from `project/` loads `project/assets/lua/main.fnl` before built-in modules. Lua and Fennel module search paths include every asset root in overlay order, so project modules can override built-ins while dependencies not present in the project still fall back to packaged runtime assets.
