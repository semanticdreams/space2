# webbrowser

## Canonical Import

```fennel
(local webbrowser (require :webbrowser))
```

## Source Files

- `src/lua_webbrowser.cpp`
- `src/lua_runtime.cpp`

## What It Provides

`webbrowser` asks the platform to open URLs or file targets in a browser.

## API Summary

- `open(target [mode] [autoraise?])` opens a non-empty target. Modes are `same-window`/`same`, `new-window`/`window`, or `new-tab`/`tab`; `autoraise?` defaults to true.
- `open_new(target)` opens in a new window.
- `open_new_tab(target)` opens in a new tab.

## Examples

```fennel
(local webbrowser (require :webbrowser))

(when (not (webbrowser.open "https://example.com" "new-tab" true))
  (print "browser open failed"))
```

## Errors and Platform Notes

Empty targets and invalid modes raise Lua errors. Return values indicate whether the platform browser request succeeded; actual browser behavior depends on the OS and default browser.

## Related Modules

- [`process`](/sdk/modules/process) for direct process launching when browser integration is insufficient.
- [`shell`](/sdk/modules/shell) for shell-based platform tooling on supported hosts.

## Aliases and Search Terms

Search terms: browser, URL opener, open URL, web browser.
