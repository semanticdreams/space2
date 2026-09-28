# cli-args

## Canonical Import

```fennel
(local cli-args (require :cli-args))
```

## Source Files

- `assets/lua/cli-args.fnl`

## What It Provides

`cli-args` is a small Fennel command-line parser with option, positional, help, version, usage, type conversion, and validation support.

## API Summary

- `parser(spec)` returns a parser instance with `parse`, `usage`, `options`, and `positionals`.
- `parse(spec argv)` builds a parser and parses `argv` in one call.
- `build-usage(spec options positionals)` formats a usage/help string.
- Option specs support `key`, `short`, `long`, `help`, `default`, `required?`, `repeatable?`, `count?`, `takes-value?`/`value?`, `type`, `choices`, `parse`, `is-help?`, and `is-version?`.
- Positional specs support `key`, `help`, `required?`, `repeatable?`, `default`, `type`, `choices`, and `parse`.

## Examples

```fennel
(local cli-args (require :cli-args))

(local result
  (cli-args.parse
    {:name "demo"
     :options [{:key "verbose" :short "v" :long "verbose"}
               {:key "count" :long "count" :takes-value? true :type "int"}]}
    ["--count" "3" "-v"]))

(when result.ok
  (print result.values.count result.values.verbose))
```

## Errors and Platform Notes

Parsing returns result tables rather than throwing for normal CLI errors. Returned failures include `:ok false`, `:error` or help/version flags, and `:usage`. Custom `parse` functions are called with `pcall`; their errors become parse errors.

## Related Modules

- [`process`](/sdk/modules/process) for invoking command-line tools.
- [`runtime`](/sdk/modules/runtime) for runtime context.

## Aliases and Search Terms

Search terms: argv, CLI parser, command-line options, usage, help.
