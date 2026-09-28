# temporal

## Canonical Import

```fennel
(local temporal (require :temporal))
```

## Source Files

- `assets/lua/temporal.fnl`
- `assets/lua/temporal/standard.fnl`
- `assets/lua/temporal/period.fnl`
- `assets/lua/temporal/interval.fnl`
- `assets/lua/temporal/repeating-interval.fnl`
- `assets/lua/temporal/pattern.fnl`
- `assets/lua/temporal/recurrence.fnl`
- `assets/lua/temporal/expression.fnl`
- `assets/lua/temporal/natural.fnl`
- `src/lua_temporal_core.cpp`

## What It Provides

`temporal` is the high-level Fennel date/time toolkit. It wraps [`temporal-core`](/sdk/modules/temporal-core) with helpers for ISO parsing and formatting, calendar periods, intervals, repeating intervals, patterns, recurrence rules, simple natural-language expressions, and expression resolution.

## API Summary

- Core groups forwarded from `temporal-core`: `duration`, `instant`, `plain-date-time`, `zoned-date-time`, `clock`, and `tzdb`.
- `standard`: `parse-instant(text)`, `format-instant(instant)`, `parse-plain-date-time(text)`, `format-plain-date-time(plain)`, `parse-zoned-date-time(text)`, `format-zoned-date-time(zdt)`.
- `period`: `from(parts)`, `parse(text)`, `format(period)`, `negate(period)`, `add-to-plain-date-time(plain period)`, `subtract-from-plain-date-time(plain period)`.
- `interval`: `from(options)`, `parse(text options)`, `format(interval)`, `duration(interval)`, `contains(interval value)`, `shift(interval duration)`.
- `repeating-interval`: `from(options)`, `parse(text options)`, `format(repeating)`, `occurrences(repeating options)`.
- `pattern`: `compile(pattern-text)`, `parse(compiled text opts)`, `format(compiled value)`.
- `recurrence`: `from(options)`, `parse-rrule(text)`, `to-rrule(rule)`, `occurrences(rule dtstart options)`.
- `natural`: `parse(input)` for supported phrases such as `today`, `tomorrow`, relative day/week forms, `next <weekday>`, and `every <weekday>`.
- `expression`: `context(options)` and `resolve(expr ctx)` for resolving natural expression results against a reference time.

## Examples

```fennel
(local temporal (require :temporal))

(local start (temporal.standard.parse-plain-date-time "2026-09-28T09:00:00"))
(local period (temporal.period.parse "P1W"))
(local end (temporal.period.add-to-plain-date-time start period))
(local meeting (temporal.interval.from {:type :plain-date-time
                                        :start start
                                        :end end}))

(print (temporal.interval.format meeting))
(print (temporal.period.format period))
```

```fennel
(local temporal (require :temporal))

(local rule (temporal.recurrence.from {:freq :weekly :count 3 :by-day [:mo]}))
(each [_ occurrence (ipairs (temporal.recurrence.occurrences rule
                                                             (temporal.standard.parse-plain-date-time "2026-09-28T09:00:00")
                                                             {}))]
  (print (occurrence:to-string)))
```

## Errors and Platform Notes

Validation failures raise Lua errors with `temporal`-specific messages. Calendar period fields must be finite safe integers and may not mix positive and negative signs. Interval parsing requires an explicit `:type` option (`:instant` or `:plain-date-time`), and repeating intervals require either a finite count or an expansion limit. Time-zone behavior depends on the native tzdb available through `temporal-core`.

## Related Modules

- [`temporal-core`](/sdk/modules/temporal-core) for native temporal objects and clocks.
- [`json`](/sdk/modules/json) and [`json-utils`](/sdk/modules/json-utils) for serializing temporal strings in persisted data.

## Aliases and Search Terms

Search terms: date, time, datetime, duration, instant, time zone, tzdb, period, interval, recurrence, RRULE, natural date, calendar.
