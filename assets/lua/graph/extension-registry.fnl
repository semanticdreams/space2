(local M {})

(fn non-empty-string? [value]
  (and (= (type value) "string") (> (string.len value) 0)))

(fn sequential-non-empty-strings? [items]
  (and (= (type items) "table")
       (> (length items) 0)
       (do
         (var ok? true)
         (for [i 1 (length items)]
           (when (not (non-empty-string? (. items i)))
             (set ok? false)))
         ok?)))

(fn copy-sequential [items]
  (icollect [_ item (ipairs items)] item))

(fn validate-descriptor [descriptor]
  (assert (= (type descriptor) "table") "graph extension descriptor must be a table")
  (assert (non-empty-string? descriptor.id) "graph extension descriptor requires non-empty id")
  (assert (non-empty-string? descriptor.unit-id) "graph extension descriptor requires non-empty unit-id")
  (assert (sequential-non-empty-strings? descriptor.schemes)
          "graph extension descriptor requires non-empty sequential schemes")
  (assert (= (type descriptor.install-loaders) "function")
          "graph extension descriptor requires install-loaders function")
  (when descriptor.install-morphs
    (assert (= (type descriptor.install-morphs) "function")
            "graph extension descriptor install-morphs must be a function"))
  (when descriptor.refresh-schemes
    (assert (sequential-non-empty-strings? descriptor.refresh-schemes)
            "graph extension descriptor refresh-schemes must be non-empty sequential strings"))
  descriptor)

(fn unregister-handles [handles]
  (for [i (length handles) 1 -1]
    (local handle (. handles i))
    (when handle
      (assert (= (type handle.unregister) "function")
              "graph extension install returned handle without unregister")
      (handle:unregister))))

(fn append-handles [target returned context]
  (assert (= (type returned) "table")
          (.. context " must return a table of registration handles"))
  (each [_ handle (ipairs returned)]
    (assert (= (type handle) "table") (.. context " returned non-table handle"))
    (assert (= (type handle.unregister) "function")
            (.. context " returned handle without unregister"))
    (table.insert target handle))
  target)

(fn sorted-extension-ids [extensions]
  (local ids [])
  (each [id _extension (pairs extensions)]
    (table.insert ids id))
  (table.sort ids)
  ids)

(fn runtime-context [descriptor app]
  {:owner-id descriptor.unit-id
   :unit-id descriptor.unit-id
   :extension-id descriptor.id
   :app app})

(fn install-extension-into-runtime [descriptor runtime app]
  (assert (= (type runtime) "table") "graph extension runtime must be a table")
  (local graph (assert runtime.graph "graph extension runtime requires :graph"))
  (assert graph.register-key-loader "graph extension runtime graph requires register-key-loader")
  (local ctx (runtime-context descriptor app))
  (local handles [])
  (local (ok result)
    (pcall
      (fn []
        (append-handles handles (descriptor.install-loaders graph ctx) "install-loaders")
        (when descriptor.install-morphs
          (local morphs (assert graph.morphs "graph extension runtime graph requires morphs for install-morphs"))
          (append-handles handles (descriptor.install-morphs morphs ctx) "install-morphs"))
        handles)))
  (if ok
      result
      (do
        (unregister-handles handles)
        (error result))))

(fn refresh-runtime-extension [runtime descriptor]
  (local manager (assert runtime.graph-map-manager
                         "graph extension runtime requires :graph-map-manager for refresh"))
  (assert manager.get-active-map
          "graph extension runtime graph-map-manager requires get-active-map")
  (local graph-map (assert (manager:get-active-map)
                           "graph extension runtime requires active graph map for refresh"))
  (assert graph-map.refresh-adapters-by-scheme
          "graph extension active graph map requires refresh-adapters-by-scheme")
  (local schemes (or descriptor.refresh-schemes descriptor.schemes))
  (local results [])
  (each [_ scheme (ipairs schemes)]
    (table.insert results (graph-map:refresh-adapters-by-scheme scheme)))
  {:runtime runtime
   :extension-id descriptor.id
   :results results})

(fn find-runtime-index [runtimes runtime]
  (var found nil)
  (for [i 1 (length runtimes)]
    (when (= (. runtimes i) runtime)
      (set found i)))
  found)

(fn runtime-state [data runtime]
  (var state (. data.runtime-states runtime))
  (when (not state)
    (set state {:runtime runtime :handles {}})
    (set (. data.runtime-states runtime) state)
    (table.insert data.runtimes runtime))
  state)

(fn remove-runtime [data runtime]
  (local index (find-runtime-index data.runtimes runtime))
  (when index
    (table.remove data.runtimes index))
  (set (. data.runtime-states runtime) nil))

(fn uninstall-extension-from-state [state extension-id]
  (local handles (. state.handles extension-id))
  (when handles
    (unregister-handles handles)
    (set (. state.handles extension-id) nil))
  true)

(fn install-extension-into-state [data state descriptor]
  (assert (not (. state.handles descriptor.id))
          (.. "graph extension already installed in runtime: " descriptor.id))
  (local handles (install-extension-into-runtime descriptor state.runtime data.app))
  (set (. state.handles descriptor.id) handles)
  true)

(fn rollback-state-extensions [state extension-ids]
  (for [i (length extension-ids) 1 -1]
    (uninstall-extension-from-state state (. extension-ids i))))

(fn rollback-installed-states [states extension-id]
  (for [i (length states) 1 -1]
    (uninstall-extension-from-state (. states i) extension-id)))

(fn install-descriptor-into-existing-runtimes [data descriptor installed-states]
  (each [_ runtime (ipairs data.runtimes)]
    (local state (assert (. data.runtime-states runtime)
                         "graph extension registry missing runtime state"))
    (install-extension-into-state data state descriptor)
    (table.insert installed-states state))
  true)

(fn make-stored-extension [data descriptor]
  (set data.extension-registration-seq (+ data.extension-registration-seq 1))
  {:id descriptor.id
   :unit-id descriptor.unit-id
   :schemes (copy-sequential descriptor.schemes)
   :refresh-schemes (and descriptor.refresh-schemes
                         (copy-sequential descriptor.refresh-schemes))
   :descriptor descriptor
   :registration-id data.extension-registration-seq})

(var registry-unregister-extension nil)

(fn make-register-handle [data stored]
  {:id stored.id
   :unit-id stored.unit-id
   :registration-id stored.registration-id
   :active? true
   :unregister (fn [handle-self]
                 (registry-unregister-extension data handle-self))})

(fn registry-register-extension [data descriptor]
  (validate-descriptor descriptor)
  (assert (not (. data.extensions descriptor.id))
          (.. "duplicate graph extension: " descriptor.id))
  (local installed-states [])
  (local (ok result)
    (pcall install-descriptor-into-existing-runtimes data descriptor installed-states))
  (if ok
      (do
        (local stored (make-stored-extension data descriptor))
        (set (. data.extensions descriptor.id) stored)
        (local handle (make-register-handle data stored))
        (set stored.handle handle)
        handle)
      (do
        (rollback-installed-states installed-states descriptor.id)
        (error result))))

(set registry-unregister-extension
     (fn [data handle-or-id]
       (assert handle-or-id "unregister-extension requires handle or id")
       (local extension-id (if (= (type handle-or-id) "table") handle-or-id.id handle-or-id))
       (assert (non-empty-string? extension-id) "unregister-extension requires extension id")
       (local extension (. data.extensions extension-id))
       (if (not extension)
           (if (and (= (type handle-or-id) "table") (not handle-or-id.active?))
               true
               false)
           (do
             (when (= (type handle-or-id) "table")
               (when (or (not (= handle-or-id.registration-id extension.registration-id))
                         (not (= handle-or-id extension.handle)))
                 (error (.. "graph extension " extension-id " belongs to another registration"))))
             (each [_ runtime (ipairs data.runtimes)]
               (local state (. data.runtime-states runtime))
               (when state
                 (uninstall-extension-from-state state extension-id)))
             (set (. data.extensions extension-id) nil)
             (when (= (type handle-or-id) "table")
               (set handle-or-id.active? false))
             true))))

(fn install-existing-extensions-into-runtime [data state installed-extension-ids]
  (each [_ extension-id (ipairs (sorted-extension-ids data.extensions))]
    (local extension (. data.extensions extension-id))
    (install-extension-into-state data state extension.descriptor)
    (table.insert installed-extension-ids extension-id))
  true)

(fn registry-install-runtime [data runtime]
  (assert runtime "install-runtime requires runtime")
  (assert (not (. data.runtime-states runtime)) "graph extension runtime already installed")
  (local state (runtime-state data runtime))
  (local installed-extension-ids [])
  (local (ok result)
    (pcall install-existing-extensions-into-runtime data state installed-extension-ids))
  (if ok
      true
      (do
        (rollback-state-extensions state installed-extension-ids)
        (remove-runtime data runtime)
        (error result))))

(fn registry-uninstall-runtime [data runtime]
  (assert runtime "uninstall-runtime requires runtime")
  (local state (. data.runtime-states runtime))
  (if (not state)
      false
      (do
        (each [extension-id _handles (pairs state.handles)]
          (uninstall-extension-from-state state extension-id))
        (remove-runtime data runtime)
        true)))

(fn registry-refresh-extension [data extension-id]
  (assert (non-empty-string? extension-id) "refresh-extension requires extension id")
  (local extension (assert (. data.extensions extension-id)
                           (.. "unknown graph extension: " extension-id)))
  (local results [])
  (each [_ runtime (ipairs data.runtimes)]
    (table.insert results (refresh-runtime-extension runtime extension.descriptor)))
  results)

(fn registry-refresh-unit [data unit-id]
  (assert (non-empty-string? unit-id) "refresh-unit requires unit id")
  (local results [])
  (each [_ extension-id (ipairs (sorted-extension-ids data.extensions))]
    (local extension (. data.extensions extension-id))
    (when (= extension.unit-id unit-id)
      (table.insert results {:extension-id extension-id
                             :results (registry-refresh-extension data extension-id)})))
  results)

(fn registry-debug-state [data]
  (local extension-summaries [])
  (each [_ extension-id (ipairs (sorted-extension-ids data.extensions))]
    (local extension (. data.extensions extension-id))
    (table.insert extension-summaries
                  {:id extension.id
                   :unit-id extension.unit-id
                   :schemes (copy-sequential extension.schemes)
                   :refresh-schemes (and extension.refresh-schemes
                                         (copy-sequential extension.refresh-schemes))}))
  {:runtime-count (length data.runtimes)
   :extensions extension-summaries})

(fn GraphExtensionRegistry [opts]
  (local options (if opts opts {}))
  (local data {:app options.app
               :extensions {}
               :runtimes []
               :runtime-states {}
               :extension-registration-seq 0})
  {:register-extension (fn [_self descriptor]
                         (registry-register-extension data descriptor))
   :unregister-extension (fn [_self handle-or-id]
                           (registry-unregister-extension data handle-or-id))
   :install-runtime (fn [_self runtime]
                      (registry-install-runtime data runtime))
   :uninstall-runtime (fn [_self runtime]
                        (registry-uninstall-runtime data runtime))
   :refresh-extension (fn [_self extension-id]
                        (registry-refresh-extension data extension-id))
   :refresh-unit (fn [_self unit-id]
                   (registry-refresh-unit data unit-id))
   :debug-state (fn [_self]
                  (registry-debug-state data))})

(set M.GraphExtensionRegistry GraphExtensionRegistry)

M
