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
  (local lifecycle (or options.lifecycle application.reference-lifecycle))
  (assert (or (not options.lifecycle) (not application.reference-lifecycle)
              (= options.lifecycle application.reference-lifecycle)) "built-in reference lifecycle conflict")
  (local identity-store (or options.identity-store application.identity-store
                            (IdentityStore.get-default {:base-dir data-dir})))
  (local composed {:entity-type-catalog catalog :lifecycle lifecycle
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
                    (ListEntityStore.get-default {:base-dir data-dir :identity-store identity-store}))
   :dict-store (or options.dict-store application.dict-store
                    ((. (require :entities/dict) :get-default) {:base-dir data-dir :identity-store identity-store}))
   :link-store (or options.link-store application.link-store
                    (LinkEntityStore.get-default {:base-dir data-dir :identity-store identity-store}))
   :identity-store identity-store
   :notebook-store (or options.notebook-store application.notebook-store
                        (NotebookStore.get-default {:base-dir data-dir :identity-store identity-store}))
   :llm-store (or options.llm-store application.llm-store
                  (LlmStore.get-default {:base-dir data-dir}))
   :kernels (or options.kernels application.kernels (KernelsStore.get-default))
   :hackernews-ensure-client (or options.hackernews-ensure-client
                                  application.hackernews-ensure-client)})
  (when lifecycle
    (each [_ row (ipairs [["string-entity" :string-store] ["code-entity" :code-store]
                          ["list-entity" :list-store] ["dict-entity" :dict-store] ["link-entity" :link-store]
                          ["identity" :identity-store] ["notebook" :notebook-store] ["workflow-step" :workflow-store]])]
      (assert (lifecycle:owns-store? (. row 1) (. composed (. row 2))) "built-in reference lifecycle store ownership mismatch")))
  composed)

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

(fn init-reference-stores! [application]
  (local fs (require :fs))
  (local root (fs.absolute application.user-data-dir))
  (local identity-store ((. (require :entities/identity) :get-default) {:base-dir root}))
  (local options {:base-dir root :identity-store identity-store})
  (local stores {:base-dir root :identity-store identity-store
                 :string-store ((. (require :entities/string) :get-default) options)
                 :code-store ((. (require :entities/code) :get-default) options)
                 :list-store ((. (require :entities/list) :get-default) options)
                 :dict-store ((. (require :entities/dict) :get-default) options)
                 :link-store ((. (require :entities/link) :get-default) options)
                 :notebook-store ((. (require :notebooks/store) :get-default) options)
                 :workflow-store ((. (require :workflows/store) :get-default) options)})
  (each [field store (pairs stores)]
    (when (not (= field :base-dir))
      (assert (= (fs.absolute store.base-dir) root) (.. "canonical " field " base-dir mismatch"))
      (tset application field store)))
  stores)

(fn start-reference-lifecycle! [application stores]
  (local options {:stores stores :world-manager application.world-manager})
  (local owners [((require :reference-lifecycle/entities-owner) stores)
                ((require :reference-lifecycle/identities-owner) stores)
                ((require :reference-lifecycle/workflows-owner) stores)
                ((require :reference-lifecycle/world-owner) options)
                ((require :reference-lifecycle/runtime-owner) options)])
  (local lifecycle ((require :reference-lifecycle) {:stores stores :owners owners}))
  (set application.reference-lifecycle lifecycle)
  (lifecycle:start!))

(fn clear-reference-composition! [application]
  (when application.reference-lifecycle
    (application.reference-lifecycle.committed:clear))
  (set application.reference-lifecycle nil)
  (each [_ field (ipairs [:string-store :code-store :identity-store :list-store
                          :dict-store :link-store :notebook-store :workflow-store])]
    (tset application field nil))
  nil)

{:ensure! ensure! :init-reference-stores! init-reference-stores!
 :start-reference-lifecycle! start-reference-lifecycle! :clear-reference-composition! clear-reference-composition!}
