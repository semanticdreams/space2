# Commands

Commands are host-presented actions exposed by an app runtime. They should provide enough metadata for a host to validate, display, confirm, and execute the action.

## Synchronous Commands

A synchronous command includes:

- `:id` — command identifier within the app.
- `:title` — user-facing label.
- `:description` — short explanation of what the command does.
- `:danger-level` — one of `:normal`, `:warning`, or `:danger`.
- `:confirmation` — optional confirmation metadata.
- `:run` — handler invoked by the command runner.

## Asynchronous Commands

Asynchronous commands use the same metadata shape but provide canonical `:run-async` instead of `:run`. The async handler should report completion or failure through the command runner contract instead of blocking host presentation.

## Confirmations

Confirmation metadata can include:

- `:message` — text shown before running the command.
- `:required?` — whether the user must explicitly confirm before execution.

## Payload Schemas

Command payload schemas can use these field types:

- `:string`
- `:number`
- `:boolean`
- `:select`

Malformed command metadata fails with command metadata errors. Malformed payload schemas fail with command payload schema errors. Handler exceptions become command-runner error envelopes so hosts and automation receive structured failure information instead of raw crashes or silent no-ops.

See [Hosted Runtime Apps](/dev/features/hosted-runtime-apps) and [Hosted App Command Payload Forms](/dev/features/hosted-app-command-payload-forms) for deeper implementation details.
