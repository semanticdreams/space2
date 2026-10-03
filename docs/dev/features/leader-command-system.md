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

Graph selection commands operate on the currently focused graph node, not the hovered node or pointer position:

| Binding | Action |
| --- | --- |
| `SPC g s s` | select focused graph node only. |
| `SPC g s a` | add focused graph node to selection. |
| `SPC g s r` | remove/deselect focused graph node from selection. |
| `SPC g s t` | toggle focused graph node in selection. |
| `SPC g s c` | clear graph selection. |

Future systems with native selection behavior should reuse the terminal verbs `s`, `a`, `r`, `t`, and `c` under their own command namespace, backed by their native selection controller. This convention is not a generic selection framework.
