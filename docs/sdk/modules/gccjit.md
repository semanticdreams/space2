# gccjit

## Canonical Import

```fennel
(local gccjit (require :gccjit))
```

## Source Files

- `src/lua_gccjit.cpp`

## What It Provides

`gccjit` exposes Linux libgccjit APIs for constructing native code at runtime: contexts, types, functions, blocks, values, globals, structs, extended asm, timers, compilation results, direct call helpers, and libgccjit constant tables.

## API Summary

- `Context()` acquires a `ContextRef`; `Timer()` creates a `TimerRef`.
- Version helpers: `version-major()`, `version-minor()`, and `version-patchlevel()`.
- `ContextRef` configures options/logging/dumps/timers, creates locations/types/fields/structs/functions/globals/rvalues/calls/casts/cases/child contexts, emits top-level asm, compiles to a `ResultRef`, or compiles to files.
- `ResultRef` methods include `get-code-address`, `get-global-address`, `call-i32`, `call-i64`, `call-double`, `call-void`, `call-word`, `call-pointer`, `call-void-word`, `release`, and `drop`.
- Object wrapper types expose conversion and builder methods: `Object`, `Location`, `Type`, `Field`, `Struct`, `Param`, `Function`, `Block`, `LValue`, `RValue`, `Case`, and `ExtendedAsm`.
- Constant tables include `StrOption`, `IntOption`, `BoolOption`, `OutputKind`, `Types`, `FunctionKind`, `GlobalKind`, `UnaryOp`, `BinaryOp`, and `Comparison`.

## Examples

```fennel
(local gccjit (require :gccjit))

(local ctx (gccjit.Context))
(local int-type (ctx:get-type (. gccjit.Types :int)))
(local fn (ctx:new-function nil (. gccjit.FunctionKind :exported) int-type "answer" [] false))
(local block (fn:new-block "entry"))
(block:end-with-return nil (ctx:new-rvalue-from-int int-type 42))

(local result (ctx:compile))
(print (result:call-i32 "answer" []))
(result:drop)
(ctx:drop)
```

## Errors and Platform Notes

On non-Linux builds the module reports `available false`, `missing-reason`, and throws `gccjit unavailable: <key>` for other API access. Live references validate native pointers and raise when contexts, results, or timers have been released. Compile failures surface libgccjit's first/last context error. Direct call helpers support only the argument counts documented in their error messages, and callers are responsible for matching generated function signatures.

## Related Modules

- [`process`](/sdk/modules/process) for invoking external toolchains when runtime JIT is not desired.
- [`fs`](/sdk/modules/fs) for reading/writing generated files, dumps, and timer output paths.

## Aliases and Search Terms

Search terms: gccjit, libgccjit, JIT, compiler, native tooling, generated code, runtime compilation.
