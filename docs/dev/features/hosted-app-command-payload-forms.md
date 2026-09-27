# Hosted App Command Payload Forms

Hosted app command facets may declare an optional `:payload-schema` so workspace
panels can render simple payload forms before calling `run-command` or
`run-command-async`.

## Schema shape

```fennel
{:payload-schema
 {:fields [{:id :title :type :string :label "Title" :default "draft"}
           {:id :count :type :number :label "Count" :default 2}
           {:id :enabled :type :boolean :label "Enabled" :default false}
           {:id :mode :type :select :label "Mode"
            :options [{:value :fast :label "Fast"}
                      {:value :safe :label "Safe"}]}]}}
```

## Field types

- `:string`: classic text input; payload value is text.
- `:number`: classic text input; payload value is `tonumber` output and invalid text fails before command execution.
- `:boolean`: button-backed toggle; payload value is boolean.
- `:select`: button-backed option cycler; payload value is the selected option value.

## Execution

Commands without `:payload-schema` still run with nil payload from visual
controls. Commands with schemas build flat payload tables keyed by field id and
execute through `descriptor/session:run-command(command-id, payload)` for
synchronous-only descriptors or
`descriptor/session:run-command-async(command-id, payload, callbacks)` when async
dispatch is available.

## Inline confirmations

When a command has required `:confirmation` metadata, the first click only arms
the inline confirmation state and does not build payloads. Payload construction
and payload validation happen only on the actual execution click. Invalid
payloads fail before command execution, so the command handler is not run.
Confirmations do not add permissions, authorization, modal dialogs, persistent
approvals, or “always allow” behavior.

## Errors

Malformed schemas fail loudly with `[app-host.command-payload-schema]` during snapshot reads, widget builds, and command runner dispatch. Command handler exceptions still use the existing command-runner error result envelope.

## Out of scope

Nested objects, arrays, validation DSLs, permissions/auth policy, persistent form
state, app-specific controls, command queues, polling APIs, persistent/background
jobs, and dropdown framework work are future slices.
