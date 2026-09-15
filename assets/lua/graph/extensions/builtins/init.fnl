(local Entities (require :graph/extensions/builtins/entities))
(local Filesystem (require :graph/extensions/builtins/filesystem))
(local Llm (require :graph/extensions/builtins/llm))
(local HackerNews (require :graph/extensions/builtins/hackernews))
(local Kernels (require :graph/extensions/builtins/kernels))
(local Workflows (require :graph/extensions/builtins/workflows))
(local Worlds (require :graph/extensions/builtins/worlds))

(local family-modules [Entities Workflows Filesystem Llm HackerNews Kernels Worlds])

(fn descriptors [opts]
  (local all [])
  (each [_ family (ipairs family-modules)]
    (each [_ descriptor (ipairs (family.descriptors opts))]
      (table.insert all descriptor)))
  all)

(fn unregister-handles-reverse [handles]
  (for [i (length handles) 1 -1]
    (local handle (. handles i))
    (when (and handle handle.unregister)
      (handle:unregister))))

(fn register! [registry opts]
  (assert registry "BuiltInGraphExtensions.register! requires registry")
  (assert registry.register-extension "BuiltInGraphExtensions.register! requires registry.register-extension")
  (local handles [])
  (local (ok result)
    (pcall
      (fn []
        (each [_ descriptor (ipairs (descriptors opts))]
          (table.insert handles (registry:register-extension descriptor)))
        handles)))
  (if ok
      result
      (do
        (unregister-handles-reverse handles)
        (error result))))

{:descriptors descriptors
 :register! register!}
