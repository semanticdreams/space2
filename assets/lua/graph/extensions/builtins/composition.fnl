(fn built-in-options [application options catalog]
  (local appdirs (require :appdirs))
  (local StringEntityStore (require :entities/string))
  (local CodeEntityStore (require :entities/code))
  (local ListEntityStore (require :entities/list))
  (local LinkEntityStore (require :entities/link))
  (local IdentityStore (require :entities/identity))
  (local NotebookStore (require :notebooks/store))
  (local LlmStore (require :llm/conversations/store))
  (local WorkflowStore (require :workflows/store))
  (local KernelsStore (require :kernels))
  (local data-dir (or application.user-data-dir (appdirs.user-data-dir "space")))
  (assert data-dir "built-in graph extensions require app user data dir")
  {:entity-type-catalog catalog
   :world-manager (or options.world-manager application.world-manager)
   :asset-path-resolver (or options.asset-path-resolver
                            (and application.engine application.engine.get-asset-path))
   :code-store (or options.code-store application.code-store
                   (CodeEntityStore.get-default {:base-dir data-dir}))
   :workflow-store (or options.workflow-store application.workflow-store
                       (WorkflowStore.get-default {:base-dir data-dir}))
   :workflow-runner (or options.workflow-runner application.workflow-runner)
   :string-store (or options.string-store application.string-store
                     (StringEntityStore.get-default {:base-dir data-dir}))
   :list-store (or options.list-store application.list-store
                   (ListEntityStore.get-default {:base-dir data-dir}))
   :dict-store (or options.dict-store application.dict-store
                   ((. (require :entities/dict) :get-default) {:base-dir data-dir}))
   :link-store (or options.link-store application.link-store
                   (LinkEntityStore.get-default {:base-dir data-dir}))
   :identity-store (or options.identity-store application.identity-store
                       (IdentityStore.get-default {:base-dir data-dir}))
   :notebook-store (or options.notebook-store application.notebook-store
                       (NotebookStore.get-default {:base-dir data-dir}))
   :llm-store (or options.llm-store application.llm-store
                  (LlmStore.get-default {:base-dir data-dir}))
   :kernels (or options.kernels application.kernels (KernelsStore.get-default))
   :hackernews-ensure-client (or options.hackernews-ensure-client
                                 application.hackernews-ensure-client)})

(fn validate-catalog [catalog]
  (assert (and (= (type catalog) "table")
               (= (type catalog.list-types) "function")
               (= (type catalog.get-type) "function"))
          "entity-type-catalog requires list-types and get-type methods")
  catalog)

(fn ensure! [application opts ensure-registry!]
  (local options (or opts {}))
  (if application.builtin-graph-extension-handles
      (do
        (validate-catalog application.entity-type-catalog)
        (assert (or (= options.entity-type-catalog nil)
                    (= options.entity-type-catalog application.entity-type-catalog))
                "conflicting :entity-type-catalog while built-in graph extensions are installed")
        application.builtin-graph-extension-handles)
      (do
        (local Builtins (require :graph/extensions/builtins))
        (local {:EntityTypeCatalog EntityTypeCatalog} (require :entities/type-catalog))
        (local catalog (validate-catalog
                         (if (not= options.entity-type-catalog nil) options.entity-type-catalog
                             application.entity-type-catalog application.entity-type-catalog
                             (EntityTypeCatalog {:types (Builtins.entity-types)}))))
        (local registry (ensure-registry!))
        (local handles (Builtins.register! registry (built-in-options application options catalog)))
        (set application.entity-type-catalog catalog)
        (set application.builtin-graph-extension-handles handles)
        handles)))

{:ensure! ensure!}
