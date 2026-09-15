(local Registry (require :graph/extension-registry))
(local BuiltInGraphExtensions (require :graph/extensions/builtins))
(local fs (require :fs))

(var temp-counter 0)

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path "/tmp/space/tests" (.. "graph-builtins-" (os.time) "-" temp-counter)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn make-default-kernels []
  (local Signal (require :signal))
  {:kernels-changed (Signal)
   :instances-changed (Signal)
   :list-kernels (fn [_self] [])
   :list-instances (fn [_self _opts] [])
   :kernel-label (fn [_self kernel] (if kernel.name kernel.name kernel.id))
   :get-kernel (fn [_self _id] nil)
   :get-instance (fn [_self _id] nil)
   :drop (fn [_self] true)})

(fn make-default-world-manager []
  (local Signal (require :signal))
  {:changed (Signal)
   :list-tabs (fn [_self] [])
   :get-world-entry (fn [_self _id] nil)})

(fn make-default-options [dir opts]
  (local StringEntityStore (require :entities/string))
  (local CodeEntityStore (require :entities/code))
  (local ListEntityStore (require :entities/list))
  (local LinkEntityStore (require :entities/link))
  (local IdentityStore (require :entities/identity))
  (local NotebookStore (require :notebooks/store))
  (local LlmStore (require :llm/conversations/store))
  (local WorkflowStore (require :workflows/store))
  (local options
    {:string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")})
     :code-store (CodeEntityStore.CodeEntityStore {:base-dir (fs.join-path dir "code")})
     :list-store (ListEntityStore.ListEntityStore {:base-dir (fs.join-path dir "list")})
     :link-store (LinkEntityStore.LinkEntityStore {:base-dir (fs.join-path dir "link")})
     :identity-store (IdentityStore.IdentityStore {:base-dir (fs.join-path dir "identity")})
     :notebook-store (NotebookStore.NotebookStore {:base-dir (fs.join-path dir "notebooks")})
     :llm-store (LlmStore.Store {:base-dir (fs.join-path dir "llm")})
     :workflow-store (WorkflowStore.WorkflowStore {:base-dir (fs.join-path dir "workflow")})
     :kernels (make-default-kernels)
     :world-manager (make-default-world-manager)
     :asset-path-resolver (fn [path] path)})
  (each [key value (pairs (if opts opts {}))]
    (set (. options key) value))
  options)

(fn unregister-handles [handles]
  (for [i (length handles) 1 -1]
    (local handle (. handles i))
    (when (and handle handle.unregister handle.active?)
      (handle:unregister))))

(fn install-builtins! [graph opts]
  (assert graph "install-builtins! requires graph")
  (local dir (make-temp-dir))
  (local options (make-default-options dir opts))
  (local registry (Registry.GraphExtensionRegistry {:app options.app}))
  (local runtime {:graph graph :graph-map-manager options.graph-map-manager})
  (local handles (BuiltInGraphExtensions.register! registry options))
  (registry:install-runtime runtime)
  {:registry registry
   :runtime runtime
   :handles handles
   :opts options
   :drop (fn [_self]
           (registry:uninstall-runtime runtime)
           (unregister-handles handles)
           (when (fs.exists dir)
             (fs.remove-all dir)))})

{:install-builtins! install-builtins!}
