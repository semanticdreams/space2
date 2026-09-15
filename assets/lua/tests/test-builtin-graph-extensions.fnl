(local tests [])

(local Main (require :main))
(local fs (require :fs))
(local Graph (require :graph/init))
(local GraphExtensionRegistry (require :graph/extension-registry))
(local Signal (require :signal))
(local tempfile (require :tempfile))

(local expected-schemes
  ["activity-background" "activity-canvas" "activity-hud" "activity-lights"
   "activity-light" "activity-light-type" "activity-scene" "activity-scene-panel"
   "activity-scene-panels" "activity-skybox" "activity-surface" "activity-surfaces"
   "activity-terrain" "activity-terrain-editor" "activity-terrain-tool" "activity-terrains"
   "agent-session" "class" "code-dir" "code-entity" "cpp-module" "entities"
   "fnl-module" "fs" "fs-file-viewer" "hackernews-root" "hackernews-story"
   "hackernews-story-list" "hackernews-user" "hud-panel" "hud-panels" "identity"
   "kernel" "kernel-instance" "kernels" "link-entity" "link-entity-list" "list-entity"
   "list-entity-list" "llm" "llm-conversation" "llm-conversations" "llm-message"
   "llm-model" "llm-provider" "llm-tool" "llm-tool-call" "llm-tool-result"
   "llm-tools" "notebook" "notebooks" "quit" "start" "string-entity"
   "string-entity-list" "table" "text-module" "workflow-definition" "workflow-run"
   "workflow-run-event" "workflow-run-explorer" "workflow-run-step" "workflow-run-timeline"
   "workflow-step" "workflow-step-explorer" "workflows" "world" "world-activities"
   "world-activity" "worlds"])

(fn non-empty-string? [value]
  (and (= (type value) "string") (> (string.len value) 0)))

(fn collect-descriptor-schemes [descriptors]
  (local schemes [])
  (each [_ descriptor (ipairs descriptors)]
    (each [_ scheme (ipairs descriptor.schemes)]
      (table.insert schemes scheme)))
  (table.sort schemes)
  schemes)

(fn assert-same-schemes [actual expected]
  (assert (= (length actual) (length expected))
          (.. "expected " (length expected) " schemes, got " (length actual)))
  (for [i 1 (length expected)]
    (assert (= (. actual i) (. expected i))
            (.. "scheme mismatch at " i ": expected " (tostring (. expected i))
                ", got " (tostring (. actual i))))))

(fn builtin-descriptors-have-required-shape []
  (local BuiltInGraphExtensions (require :graph/extensions/builtins))
  (local descriptors (BuiltInGraphExtensions.descriptors {}))
  (assert (> (length descriptors) 0) "built-in descriptors should not be empty")
  (each [_ descriptor (ipairs descriptors)]
    (assert (non-empty-string? descriptor.id) "descriptor should have non-empty id")
    (assert (non-empty-string? descriptor.unit-id) "descriptor should have non-empty unit-id")
    (assert (> (length descriptor.schemes) 0) "descriptor should have non-empty schemes")
    (each [_ scheme (ipairs descriptor.schemes)]
      (assert (non-empty-string? scheme) "descriptor scheme should be non-empty string"))
    (assert (= (type descriptor.install-loaders) "function")
            "descriptor should have install-loaders function")))

(fn builtin-descriptors-expose-exact-scheme-coverage []
  (local BuiltInGraphExtensions (require :graph/extensions/builtins))
  (local actual (collect-descriptor-schemes (BuiltInGraphExtensions.descriptors {})))
  (local expected (icollect [_ scheme (ipairs expected-schemes)] scheme))
  (table.sort expected)
  (assert-same-schemes actual expected))

(fn workflow-descriptor [opts]
  (local Workflows (require :graph/extensions/builtins/workflows))
  (. (Workflows.descriptors opts) 1))

(fn unregister-test-handle [_handle]
  true)

(fn make-recording-graph []
  (local registrations [])
  (fn register-key-loader [_self scheme loader-fn opts]
    (assert (= (type loader-fn) "function") "test graph expected loader function")
    (table.insert registrations {:scheme scheme :opts opts})
    {:scheme scheme
     :unregister unregister-test-handle})
  {:registrations registrations
   :register-key-loader register-key-loader})

(fn registered-schemes [graph]
  (icollect [_ registration (ipairs graph.registrations)] registration.scheme))

(fn assert-registered-schemes [graph expected]
  (local actual (registered-schemes graph))
  (assert-same-schemes actual expected))

(fn assert-owner-registration [graph]
  (each [_ registration (ipairs graph.registrations)]
    (assert (= registration.opts.owner-id "builtin-graph-workflows")
            "workflow loader should use descriptor owner id")
    (assert (= registration.opts.extension-id "builtin-graph-workflows")
            "workflow loader should use descriptor extension id")))

(fn workflow-descriptor-registers-store-only-schemes-without-runner []
  (local graph (make-recording-graph))
  (local descriptor (workflow-descriptor {:workflow-store {}}))
  (local handles (descriptor.install-loaders graph
                   {:owner-id descriptor.unit-id :extension-id descriptor.id}))
  (assert (= (length handles) 8) "workflow store without runner should install eight handles")
  (assert-registered-schemes graph ["workflows" "workflow-step" "workflow-step-explorer"
                                    "workflow-run-explorer" "workflow-run-step"
                                    "workflow-run-event" "workflow-run-timeline" "agent-session"])
  (assert-owner-registration graph))

(fn workflow-descriptor-registers-runner-schemes-when-runner-present []
  (local graph (make-recording-graph))
  (local descriptor (workflow-descriptor {:workflow-store {} :workflow-runner {}}))
  (local handles (descriptor.install-loaders graph
                   {:owner-id descriptor.unit-id :extension-id descriptor.id}))
  (assert (= (length handles) 10) "workflow store with runner should install ten handles")
  (assert-registered-schemes graph ["workflows" "workflow-definition" "workflow-run"
                                    "workflow-step" "workflow-step-explorer"
                                    "workflow-run-explorer" "workflow-run-step"
                                    "workflow-run-event" "workflow-run-timeline" "agent-session"])
  (assert-owner-registration graph))

(fn workflow-descriptor-requires-workflow-store-explicitly []
  (local graph (make-recording-graph))
  (local descriptor (workflow-descriptor {}))
  (local (ok err) (pcall descriptor.install-loaders graph
                   {:owner-id descriptor.unit-id :extension-id descriptor.id}))
  (assert (not ok) "workflow descriptor should reject missing workflow-store")
  (assert (string.find (tostring err) "builtin-graph-workflows requires :workflow-store" 1 true)
          (.. "missing workflow-store error should be explicit, got: " (tostring err))))

(fn create-test-built-in-options [base-dir]
  (assert base-dir "test built-in options require base-dir")
  (local StringEntityStore (require :entities/string))
  (local CodeEntityStore (require :entities/code))
  (local ListEntityStore (require :entities/list))
  (local LinkEntityStore (require :entities/link))
  (local IdentityStore (require :entities/identity))
  (local NotebookStore (require :notebooks/store))
  (local LlmStore (require :llm/conversations/store))
  (local WorkflowStore (require :workflows/store))
  {:string-store (StringEntityStore.StringEntityStore {:base-dir base-dir})
   :code-store (CodeEntityStore.CodeEntityStore {:base-dir base-dir})
   :list-store (ListEntityStore.ListEntityStore {:base-dir base-dir})
   :link-store (LinkEntityStore.LinkEntityStore {:base-dir base-dir})
   :identity-store (IdentityStore.IdentityStore {:base-dir base-dir})
   :notebook-store (NotebookStore.NotebookStore {:base-dir base-dir})
   :llm-store (LlmStore.Store {:base-dir base-dir})
   :workflow-store (WorkflowStore.get-default {:base-dir base-dir})
   :kernels {:kernels-changed (Signal)
             :instances-changed (Signal)
             :list-kernels (fn [_self] [])
             :list-instances (fn [_self _opts] [])
             :kernel-label (fn [_self kernel] (if kernel.name kernel.name kernel.id))
             :get-kernel (fn [_self _id] nil)
             :get-instance (fn [_self _id] nil)}
   :world-manager {:changed (Signal)
                   :list-tabs (fn [_self]
                                [{:id "world-a" :name "home" :active? true}])}
   :asset-path-resolver (fn [path] path)})

(fn assert-loads [graph key]
  (assert (graph:load-by-key key)
          (.. "expected built-in registry loader to load " key)))

(fn built-in-registration-through-registry-loads-representative-families []
  (assert (= (type Main.ensure-built-in-graph-extensions!) "function")
          "Main should expose ensure-built-in-graph-extensions!")
  (local saved-registry app.graph-extension-registry)
  (local saved-handles app.builtin-graph-extension-handles)
  (local temp-dir (tempfile.TemporaryDirectory {:prefix "builtin-graph-registry-"}))
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {:app app}))
  (local graph (Graph {:with-start false :entity-events? false}))
  (local runtime {:graph graph})
  (set app.graph-extension-registry registry)
  (set app.builtin-graph-extension-handles nil)
  (local options (create-test-built-in-options temp-dir.path))
  (Main.ensure-built-in-graph-extensions! options)
  (registry:install-runtime runtime)
  (assert-loads graph "start")
  (assert-loads graph "string-entity-list")
  (assert-loads graph (.. "fs:" temp-dir.path))
  (assert-loads graph "llm")
  (assert-loads graph "kernels")
  (assert-loads graph "worlds")
  (registry:uninstall-runtime runtime)
  (graph:drop)
  (temp-dir:drop)
  (set app.graph-extension-registry saved-registry)
  (set app.builtin-graph-extension-handles saved-handles)
  true)

(fn graph-key-loaders-module-is-not-present []
  (local (ok _module) (pcall require :graph/key-loaders))
  (assert (not ok) "graph/key-loaders module should not be present"))

(table.insert tests {:name "built-in descriptors have required shape"
                     :fn builtin-descriptors-have-required-shape})
(table.insert tests {:name "built-in descriptors expose exact scheme coverage"
                     :fn builtin-descriptors-expose-exact-scheme-coverage})
(table.insert tests {:name "workflow descriptor registers store-only schemes without runner"
                     :fn workflow-descriptor-registers-store-only-schemes-without-runner})
(table.insert tests {:name "workflow descriptor registers runner schemes when runner present"
                     :fn workflow-descriptor-registers-runner-schemes-when-runner-present})
(table.insert tests {:name "workflow descriptor requires workflow-store explicitly"
                      :fn workflow-descriptor-requires-workflow-store-explicitly})
(table.insert tests {:name "built-in-registration-through-registry-loads-representative-families"
                      :fn built-in-registration-through-registry-loads-representative-families})
(table.insert tests {:name "graph-key-loaders-module-is-not-present"
                     :fn graph-key-loaders-module-is-not-present})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "test-builtin-graph-extensions"
                       :tests tests})))

{:tests tests
 :main main}
