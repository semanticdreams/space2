(fn snapshot-error [message]
  (error (.. "[app-host.workspace-inspector-snapshot] " message)))

(fn require-list [host registry-name]
  (local registry (. host registry-name))
  (when (not (= (type registry) :table))
    (snapshot-error (.. (tostring registry-name) " registry is required")))
  (local list-fn registry.list)
  (when (not (= (type list-fn) :function))
    (snapshot-error (.. (tostring registry-name) " registry requires list")))
  (list-fn registry))

(fn inspector-entry [facet]
  (if (= (type facet.read) :function)
      (do
        (local (ok result) (pcall facet.read facet))
        (if ok
            {:id facet.id :title facet.title :status :ok :data result}
            {:id facet.id :title facet.title :status :error :error (tostring result)}))
      {:id facet.id :title facet.title :status :unsupported}))

(fn command-entry [facet]
  {:id facet.id
   :title facet.title
   :description facet.description
   :status :metadata})

(fn read-host [host]
  (when (not (= (type host) :table))
    (snapshot-error "read-host requires host table"))
  (local inspector-facets (require-list host :inspectors))
  (local command-facets (require-list host :commands))
  (local inspectors [])
  (each [_ facet (ipairs inspector-facets)]
    (table.insert inspectors (inspector-entry facet)))
  (local commands [])
  (each [_ facet (ipairs command-facets)]
    (table.insert commands (command-entry facet)))
  {:inspectors inspectors :commands commands})

{:read-host read-host}
