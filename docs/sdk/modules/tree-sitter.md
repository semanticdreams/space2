# tree-sitter

## Canonical Import

```fennel
(local tree-sitter (require :tree-sitter))
```

## Source Files

- `src/lua_tree_sitter.cpp`

## What It Provides

`tree-sitter` parses source text with the bundled Tree-sitter grammars and exposes lightweight tree and node wrappers to Lua/Fennel.

## API Summary

- `parse(code [opts])` returns a `TSTree`. `opts.language` may be `"cpp"`, `:cpp`, `"fennel"`, or `:fennel`; the default language is C++.
- `TSTree:root()` returns the root `TSNode`.
- `TSNode:type()` returns the node type string.
- `TSNode:child-count()` returns the number of children.
- `TSNode:child(index)` returns a child node by Tree-sitter child index.
- `TSNode:start-byte()` / `TSNode:end-byte()` return byte offsets.
- `TSNode:start-point()` / `TSNode:end-point()` return tables with `row` and `column` fields.
- `TSNode:is-null()` reports whether a node is null.
- `TSNode:sexpr()` returns Tree-sitter's S-expression representation for the node.

## Examples

```fennel
(local tree-sitter (require :tree-sitter))

(local tree (tree-sitter.parse "(fn hello [] 42)" {:language :fennel}))
(local root (tree:root))

(print (root:type))
(print (root:sexpr))
```

## Errors and Platform Notes

Unsupported `opts.language` values raise `tree-sitter.parse unsupported language: <value>`. Only the bundled C++ and Fennel grammars are exposed by this module. Byte offsets are byte-based rather than Unicode codepoint offsets. Tree-sitter child indexes follow the native binding; inspect `:child-count()` before indexing children.

## Related Modules

- [`fs`](/sdk/modules/fs) for reading source files before parsing.

## Aliases and Search Terms

Search terms: treesitter, Tree-sitter, parser, syntax tree, AST, C++, Fennel. `treesitter` is a search alias only; use `tree-sitter` as the import name.
