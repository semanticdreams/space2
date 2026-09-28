# sql-builder

## Canonical Import

```fennel
(local sql-builder (require :sql-builder))
```

## Source Files

- `assets/lua/sql-builder.fnl`
- `assets/lua/sql-builder-methods.fnl`
- `assets/lua/sql-builder-functions.fnl`
- `assets/lua/sql-builder-exports.fnl`

## What It Provides

`sql-builder` is a Fennel query builder for SQLite-oriented SQL. It builds immutable-ish query/expression tables and compiles them into SQL text plus positional or named parameter collections.

## API Summary

- Table/schema helpers: `table(name [alias])`, `Table(name)`, `Tables(...)`, `field(table name [alias])`, `star([table])`, `Schema(name)`, `Database(name)`.
- Value/expression helpers: `raw(sql)`, `literal(value)`, `param(value [name])`, `parameter(placeholder)`, `qmark-parameter()`, `numeric-parameter(placeholder)`, `named-parameter(placeholder)`, `format-parameter()`, `pyformat-parameter(placeholder)`.
- Query factories: `select(...)`, `from(source)`, `with(name subquery)`, `with-recursive(name subquery)`, `insert-into(target)`, `into(target)`, `update(target)`, `delete-from(target)`, `create-table(target)`, `create-index(name)`, `create-view(name)`, `drop-table(target opts)`, `drop-view(target opts)`, `drop-index(target opts)`.
- Expression helpers include `as`, `eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `like`, `not-like`, `glob`, `regexp`, `bitwiseand`, `lshift`, `rshift`, `in_`, `not-in`, `between`, `is-null`, `is-not-null`, `not_`, `neg`, `and_`, `or_`, arithmetic helpers, `exists`, `excluded`, `tuple`, `case`, `when_`, and window-frame helpers.
- Function catalogs: `Functions` dynamically creates SQL function calls, and `Analytics` provides common analytic/window function helpers.
- Compile helpers: `compile(query [options])`, `to-sql(query [options])`, and `to-sql-string(query [options])`. Query objects also support `:compile`, `:to-sql`, and `:to-sql-string`.

## Examples

```fennel
(local sql-builder (require :sql-builder))

(local notes (sql-builder.table "notes"))
(local query
  (-> (notes:select notes.id notes.body)
      (:where (notes.body:like (sql-builder.param "%space%")))
      (:order-by notes.id)
      (:limit 10)))

(local compiled (query:compile))
(print compiled.sql)   ; SELECT "notes"."id", "notes"."body" FROM "notes" WHERE ...
(print (. compiled.params 1))
```

```fennel
(local sql-builder (require :sql-builder))

(local users (sql-builder.table "users"))
(local insert
  (-> (sql-builder.insert-into users)
      (:columns "id" "name")
      (:values [1 "Ada"])
      (:on-conflict "id")
      (:do-update)
      (:set "name" (sql-builder.excluded "name"))))

(print (insert:to-sql-string))
```

## Errors and Platform Notes

The builder targets SQLite and explicitly errors for unsupported helpers such as `ilike`, `regex`, `rlike`, `prewhere`, `for-update`, `use-index`, `force-index`, `with-totals`, `rollup`, some temporal table helpers, and unsupported drop operations. Identifiers are double-quoted and parameters default to `?`; pass `{:param-style :named}` to `compile` for named parameters. The generated SQL should still be validated against the SQLite version and features available through [`lsqlite3`](/sdk/modules/lsqlite3).

## Related Modules

- [`lsqlite3`](/sdk/modules/lsqlite3) for executing generated SQL against SQLite.

## Aliases and Search Terms

Search terms: sqlite, SQL builder, query builder, select, insert, update, delete, DDL, parameters.
