# Leader Command System

Space leader commands are contributed by contextual command providers. A provider supplies command descriptors and declarative key bindings. Leader state composes active providers, resolves nested `SPC ...` sequences, executes available commands, and derives command hints from the same data.

Providers should be reusable. Graph commands, for example, are created with a graph-view resolver so graph activity and future embedded graph views can install the same commands in their own context.

Graph namespace conventions:

- `SPC g p ...` graph preview / presentation commands.
- `SPC g s ...` graph selection editing.
- `SPC g n ...` focused graph node actions.
- `SPC g v ...` graph view, camera, and layout.
- `SPC g m ...` graph map and topology.

These namespaces are conventions for predictable command placement. They are not a generic target-scope type system. Each command owns its own availability and target resolution rules.
