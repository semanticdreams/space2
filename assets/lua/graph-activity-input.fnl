(global app (or app {}))

(local InputModifiers (require :input-modifiers))

(local KEY_A (string.byte "a"))

(fn active-input [ctx]
  (and ctx (. ctx :active-input) ((. ctx :active-input))))

(fn active-graph-view []
  (local world-runtime app.active-world-runtime)
  (if (and world-runtime world-runtime.graph-view)
      world-runtime.graph-view
      app.graph-view))

(fn select-all-visible-nodes []
  (local graph-view (active-graph-view))
  (if (and graph-view graph-view.select-all-visible-nodes)
      (graph-view:select-all-visible-nodes)
      false))

(fn key-down [ctx payload]
  (if (and (not (active-input ctx))
           (= app.canvas-interactive? true)
           (= (and payload payload.key) KEY_A)
           (InputModifiers.ctrl-held? (and payload payload.mod)))
      (select-all-visible-nodes)
      false))

{:key-down key-down
 :handlers {:key-down key-down}}
