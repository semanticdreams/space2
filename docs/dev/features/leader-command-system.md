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

Graph preview commands operate on the current graph selection:

| Binding | Action |
| --- | --- |
| `SPC g p e` | expand selected node previews. |
| `SPC g p c` | collapse selected node previews. |
| `SPC g p t` | toggle selected node previews. |

Graph selection commands operate on the currently focused graph node, not the hovered node or pointer position:

| Binding | Action |
| --- | --- |
| `SPC g s s` | select focused graph node only. |
| `SPC g s a` | add focused graph node to selection. |
| `SPC g s r` | remove/deselect focused graph node from selection. |
| `SPC g s t` | toggle focused graph node in selection. |
| `SPC g s c` | clear graph selection. |

Focused graph node commands operate on the current focused graph node:

| Binding | Action |
| --- | --- |
| `SPC g n o` | open the focused node view/panel. |
| `SPC g n m` | open the focused node context menu. |
| `SPC g n t` | toggle the focused node preview. |
| `SPC g n y` | copy the focused node key. |
| `SPC g n r` | remove the focused node from the active graph map without deleting the backing object. |
| `SPC g n 1` ... `SPC g n 9` | run focused-node action slots 1 through 9. |

Focused-node action slots use the same action list as the focused node context menu. A slot is available only when that numbered menu action exists for the focused node.

Graph view commands operate on the active graph view:

| Binding | Action |
| --- | --- |
| `SPC g v c` | center/reveal the focused node in the graph view. |
| `SPC g v l` | start graph layout. |
| `SPC g v s` | ensure the `start` node is in the active map, then select, focus, and center it in the graph view. |

Graph map commands operate on the active graph map and map manager:

| Binding | Action |
| --- | --- |
| `SPC g m a` | add the `start` node to the active map. |
| `SPC g m n` | create and switch to a new empty map. |
| `SPC g m s` | create and switch to a new map from the current selection. |
| `SPC g m c` | clear the active map's map-local topology and interaction state. |

Future systems with native selection behavior should reuse the terminal verbs `s`, `a`, `r`, `t`, and `c` under their own command namespace, backed by their native selection controller. This convention is not a generic selection framework.
