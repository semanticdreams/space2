(local tests [])

(local Main (require :main))
(local fs (require :fs))
(local Graph (require :graph/init))
(local GraphExtensionRegistry (require :graph/extension-registry))
(local Signal (require :signal))
(local tempfile (require :tempfile))
(local Builtins (require :graph/extensions/builtins))
(local {:EntityTypeCatalog EntityTypeCatalog} (require :entities/type-catalog))

(local expected-schemes
  ["activity-background" "activity-canvas" "activity-hud" "activity-lights"
   "activity-light" "activity-light-type" "activity-scene" "activity-scene-panel"
   "activity-scene-panels" "activity-skybox" "activity-surface" "activity-surfaces"
   "activity-terrain" "activity-terrain-editor" "activity-terrain-tool" "activity-terrains"
   "agent-session" "class" "code-dir" "code-entity" "code-entity-list" "cpp-module" "entities"
   "fnl-module" "fs" "fs-file-viewer" "hackernews-root" "hackernews-story"
   "hackernews-story-list" "hackernews-user" "hud-panel" "hud-panels" "identity"
   "hosted-app-launcher"
    "kernel" "kernel-instance" "kernels" "link-entity" "link-entity-list" "list-entity" "dict-entity"
    "list-entity-list" "dict-entity-list" "llm" "llm-conversation" "llm-conversations" "llm-message"
   "llm-model" "llm-provider" "llm-tool" "llm-tool-call" "llm-tool-result"
   "llm-tools" "notebook" "notebooks" "quit" "start" "string-entity"
    "string-entity-list" "string-entity-search" "table" "text-module" "workflow-definition" "workflow-run"
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
  (local DictEntityStore (require :entities/dict))
  (local LinkEntityStore (require :entities/link))
  (local IdentityStore (require :entities/identity))
  (local NotebookStore (require :notebooks/store))
  (local LlmStore (require :llm/conversations/store))
  (local WorkflowStore (require :workflows/store))
  {:entity-type-catalog (EntityTypeCatalog {:types (Builtins.entity-types)})
   :string-store (StringEntityStore.StringEntityStore {:base-dir base-dir})
    :code-store (CodeEntityStore.CodeEntityStore {:base-dir base-dir})
    :list-store (ListEntityStore.ListEntityStore {:base-dir base-dir})
    :dict-store (DictEntityStore.DictEntityStore {:base-dir base-dir})
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
  (local saved-catalog app.entity-type-catalog)
  (local temp-dir (tempfile.TemporaryDirectory {:prefix "builtin-graph-registry-"}))
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {:app app}))
  (local graph (Graph {:with-start false :entity-events? false}))
  (local runtime {:graph graph})
  (set app.graph-extension-registry registry)
  (set app.builtin-graph-extension-handles nil)
  (set app.entity-type-catalog nil)
  (local options (create-test-built-in-options temp-dir.path))
  (local (ok result)
    (pcall
      (fn exercise-loaders []
        (Main.ensure-built-in-graph-extensions! options)
        (registry:install-runtime runtime)
        (assert-loads graph "start")
        (assert-loads graph "string-entity-list")
        (assert-loads graph "string-entity-search")
        (assert-loads graph "dict-entity-list")
        (local code-browser (assert-loads graph "code-entity-list"))
        (assert (= code-browser.store options.code-store)
                "code browser loader should capture the supplied code store")
        (assert (= (graph:load-by-key "code-entity-list:unexpected") nil)
                "code browser loader should reject non-exact keys")
        (assert-loads graph (.. "fs:" temp-dir.path))
        (assert-loads graph "llm")
        (assert-loads graph "hosted-app-launcher:workspace")
        (assert-loads graph "kernels")
        (assert-loads graph "worlds"))))
  (registry:uninstall-runtime runtime)
  (graph:drop)
  (each [_ handle (ipairs (or app.builtin-graph-extension-handles []))] (handle:unregister))
  (temp-dir:drop)
  (set app.graph-extension-registry saved-registry)
  (set app.builtin-graph-extension-handles saved-handles)
  (set app.entity-type-catalog saved-catalog)
  (if ok result (error result)))

(fn graph-key-loaders-module-is-not-present []
  (local (ok _module) (pcall require :graph/key-loaders))
  (assert (not ok) "graph/key-loaders module should not be present"))

(fn assert-error [f text]
  (local (ok err) (pcall f))
  (assert (not ok) (.. "expected error: " text))
  (assert (string.find (tostring err) text 1 true) (tostring err)))

(fn default-catalog [] (EntityTypeCatalog {:types (Builtins.entity-types)}))

(fn with-isolated-app-composition [f]
  (local saved-registry app.graph-extension-registry)
  (local saved-handles app.builtin-graph-extension-handles)
  (local saved-catalog app.entity-type-catalog)
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {:app app}))
  (set app.graph-extension-registry registry)
  (set app.builtin-graph-extension-handles nil)
  (set app.entity-type-catalog nil)
  (local (ok result) (pcall f registry))
  (each [_ handle (ipairs (or app.builtin-graph-extension-handles []))]
    (handle:unregister))
  (set app.graph-extension-registry saved-registry)
  (set app.builtin-graph-extension-handles saved-handles)
  (set app.entity-type-catalog saved-catalog)
  (when (not ok) (error result)))

(fn app-catalog-registration-is-atomic []
  (each [_ prior (ipairs [false (default-catalog)])]
    (with-isolated-app-composition
      (fn exercise [registry]
        (local previous (if prior prior nil))
        (local candidate (default-catalog))
        (set app.entity-type-catalog previous)
        (local register registry.register-extension)
        (var registrations 0)
        (var first-handle nil)
        (set registry.register-extension
             (fn fail-second [self descriptor]
               (assert (= app.entity-type-catalog previous) "candidate must not be published during registration")
               (assert (= app.builtin-graph-extension-handles nil))
               (set registrations (+ registrations 1))
               (when (= registrations 2) (error "intentional second registration failure"))
               (set first-handle (register self descriptor))
               first-handle))
        (assert-error (fn initialize []
                        (Main.ensure-built-in-graph-extensions! {:entity-type-catalog candidate}))
                      "intentional second registration failure")
        (assert (= registrations 2))
        (assert (= first-handle.active? false) "earlier registration must be rolled back")
        (assert (= (length (. (registry:debug-state) :extensions)) 0))
        (assert (= app.entity-type-catalog previous))
        (assert (= app.builtin-graph-extension-handles nil))
        (set registry.register-extension register)
        (local handles (Main.ensure-built-in-graph-extensions! {:entity-type-catalog candidate}))
        (assert (= app.entity-type-catalog candidate))
        (assert (= app.builtin-graph-extension-handles handles))))))

(fn app-catalog-default-reuse-and-conflict []
  (with-isolated-app-composition
    (fn exercise [registry]
      (local handles (Main.ensure-built-in-graph-extensions!))
      (local catalog (assert app.entity-type-catalog "app must publish a default catalog"))
      (assert (= (length (catalog:list-types)) 5))
      (assert (= handles (Main.ensure-built-in-graph-extensions!)))
      (assert (= handles (Main.ensure-built-in-graph-extensions! {:entity-type-catalog catalog})))
      (local register registry.register-extension)
      (set registry.register-extension (fn unexpected-registration [_self _descriptor] (error "must reject before registration")))
      (assert-error (fn replace-catalog []
                      (Main.ensure-built-in-graph-extensions! {:entity-type-catalog (default-catalog)}))
                    "conflicting :entity-type-catalog")
      (set registry.register-extension register)
      (assert (= app.entity-type-catalog catalog))
      (assert (= app.builtin-graph-extension-handles handles)))))

(fn app-catalog-reuses-existing-reference []
  (with-isolated-app-composition
    (fn exercise [_registry]
      (local catalog (default-catalog))
      (set app.entity-type-catalog catalog)
      (Main.ensure-built-in-graph-extensions!)
      (assert (= app.entity-type-catalog catalog)))))

(fn app-catalog-validates-before-registration []
  (with-isolated-app-composition
    (fn exercise [registry]
      (set registry.register-extension (fn unexpected-registration [_self _descriptor] (error "must validate before registration")))
      (each [_ invalid (ipairs [false {} {:list-types (fn list-no-types [_self] [])}])]
        (assert-error (fn initialize []
                        (Main.ensure-built-in-graph-extensions! {:entity-type-catalog invalid}))
                      "entity-type-catalog"))
      (assert (= app.entity-type-catalog nil))
      (assert (= app.builtin-graph-extension-handles nil)))))

(fn assert-runtime-catalog [registry runtime catalog]
  (registry:install-runtime runtime)
  (assert (= app.entity-type-catalog catalog))
  (local entities (runtime.graph:load-by-key "entities"))
  (assert (= entities.entity-type-catalog catalog))
  (registry:uninstall-runtime runtime)
  (assert (= app.entity-type-catalog catalog)))

(fn runtime-installation-retains-app-catalog []
  (with-isolated-app-composition
    (fn exercise [registry]
      (local temp-dir (tempfile.TemporaryDirectory {:prefix "builtin-catalog-runtime-"}))
      (local options (create-test-built-in-options temp-dir.path))
      (local catalog (default-catalog))
      (set options.entity-type-catalog catalog)
      (Main.ensure-built-in-graph-extensions! options)
      (local graph (Graph {:with-start false :entity-events? false}))
      (local runtime {:graph graph})
      (local (ok result) (pcall assert-runtime-catalog registry runtime catalog))
      (registry:uninstall-runtime runtime)
      (graph:drop)
      (temp-dir:drop)
      (when (not ok) (error result)))))

(fn composition-validates-before-registry-or-store-work []
  (local Composition (require :graph/extensions/builtins/composition))
  (var registry-calls 0)
  (fn unexpected-registry [] (set registry-calls (+ registry-calls 1)) (error "unexpected registry creation"))
  (fn unexpected-dependency [_self key]
    (when (not (= key :builtin-graph-extension-handles))
      (error (.. "unexpected dependency lookup: " key))))
  (local application (setmetatable {} {:__index unexpected-dependency}))
  (each [_ invalid (ipairs [false {} {:list-types (fn list-no-types [_self] [])}])]
    (assert-error (fn initialize-invalid []
                    (Composition.ensure! application {:entity-type-catalog invalid} unexpected-registry))
                  "entity-type-catalog"))
  (assert (= registry-calls 0))
  (assert (= (rawget application :entity-type-catalog) nil))
  (assert (= (rawget application :builtin-graph-extension-handles) nil)))

(fn composition-reuse-is-lazy []
  (local Composition (require :graph/extensions/builtins/composition))
  (local catalog (default-catalog))
  (local handles [])
  (fn unexpected-registry [] (error "unexpected registry creation"))
  (fn unexpected-dependency [_self key] (error (.. "unexpected dependency lookup: " key)))
  (local application (setmetatable {:entity-type-catalog catalog :builtin-graph-extension-handles handles}
                                   {:__index unexpected-dependency}))
  (assert (= (Composition.ensure! application nil unexpected-registry) handles))
  (assert (= (Composition.ensure! application {:entity-type-catalog catalog} unexpected-registry) handles))
  (assert-error (fn conflicting []
                  (Composition.ensure! application {:entity-type-catalog (default-catalog)} unexpected-registry))
                "conflicting :entity-type-catalog"))

(fn composition-uses-explicit-app-stores []
  (local Composition (require :graph/extensions/builtins/composition))
  (local dir (tempfile.TemporaryDirectory {:prefix "builtin-explicit-app-"}))
  (local application (create-test-built-in-options dir.path))
  (local registry (GraphExtensionRegistry.GraphExtensionRegistry {:app application}))
  (local graph (Graph {:with-start false :entity-events? false}))
  (local runtime {:graph graph})
  (var registry-calls 0)
  (fn resolve-registry [] (set registry-calls (+ registry-calls 1)) registry)
  (local (ok result)
    (pcall
      (fn exercise-app-injection []
        (Composition.ensure! application {:asset-path-resolver application.asset-path-resolver} resolve-registry)
        (registry:install-runtime runtime)
        (assert (= (. (graph:load-by-key "code-entity-list") :store) application.code-store))
        (assert (= (. (graph:load-by-key "entities") :entity-type-catalog) application.entity-type-catalog))
        (assert (= registry-calls 1)))))
  (registry:uninstall-runtime runtime)
  (graph:drop)
  (each [_ handle (ipairs (or application.builtin-graph-extension-handles []))] (handle:unregister))
  (dir:drop)
  (when (not ok) (error result)))

(fn documented-startup-code []
  (local assets (assert (os.getenv "SPACE_ASSETS_PATH") "startup documentation test requires asset path"))
  (local text (fs.read-file (fs.join-path assets "../docs/dev/features/entity-type-catalog.md")))
  (assert (string.match text "```fennel\n(.-)\n```") "startup example must contain a Fennel block"))

(fn assert-startup-browser [registry runtime catalog early-store]
  (registry:install-runtime runtime)
  (local browser (runtime.graph:load-by-key "code-entity-list"))
  (assert (= browser.store app.code-store) "documented startup must capture the initialized app.code-store")
  (assert (not (= browser.store early-store)))
  (assert (= (. (runtime.graph:load-by-key "entities") :entity-type-catalog) catalog))
  (local seen [])
  (browser.items-changed:connect (fn observe-items [items] (table.insert seen items)))
  (app.code-store:create-entity {:id "startup" :name "Before"})
  (app.code-store:update-entity "startup" {:name "After"})
  (assert (= (length seen) 2))
  (assert (= (. (. (. seen 1) 1) 2) "Before"))
  (assert (= (. (. (. seen 2) 1) 2) "After")))

(fn exercise-documented-startup [registry options early-store]
  (local CodeStore (require :entities/code))
  (local code (documented-startup-code))
  (local ensure-position (string.find code "(Main.ensure-built-in-graph-extensions!" 1 true))
  (local init-position (string.find code "(Main.init)" 1 true))
  (local catalog (default-catalog))
  ;; Follow the documented phase order. The real store constructor is the same
  ;; store-init seam used by Main.init; no renderer/world startup is required.
  (if (and ensure-position (or (not init-position) (< ensure-position init-position)))
      (do
        (set options.entity-type-catalog catalog)
        (Main.ensure-built-in-graph-extensions! options))
      (do
        (local precompose-position (string.find code "(set app.entity-type-catalog catalog)" 1 true))
        (assert (and precompose-position init-position (< precompose-position init-position))
                "documented startup must precompose metadata before Main.init")
        (set app.entity-type-catalog catalog)))
  (set app.code-store (CodeStore.CodeEntityStore {:base-dir early-store.base-dir}))
  (Main.ensure-built-in-graph-extensions! options)
  (local graph (Graph {:with-start false :entity-events? false
                       :link-store options.link-store :identity-store options.identity-store
                       :string-store options.string-store}))
  (local runtime {:graph graph})
  (local (ok result) (pcall assert-startup-browser registry runtime catalog early-store))
  (registry:uninstall-runtime runtime)
  (graph:drop)
  (when (not ok) (error result)))

(fn documented-startup-uses-initialized-app-store []
  (local CodeStore (require :entities/code))
  (local dir (tempfile.TemporaryDirectory {:prefix "catalog-startup-phases-"}))
  (local options (create-test-built-in-options dir.path))
  (local early-store options.code-store)
  (set options.code-store nil)
  (set options.entity-type-catalog nil)
  (local saved-code-store app.code-store)
  (local get-default CodeStore.get-default)
  (set app.code-store nil)
  ;; An early ensure must resolve only this test-local stand-in, never real data.
  (set CodeStore.get-default (fn early-default [_opts] early-store))
  (local (ok result)
    (pcall with-isolated-app-composition
      (fn exercise-startup [registry] (exercise-documented-startup registry options early-store))))
  (set app.code-store saved-code-store)
  (set CodeStore.get-default get-default)
  (dir:drop)
  (when (not ok) (error result)))

(table.insert tests {:name "app catalog registration failure is atomic and retryable" :fn app-catalog-registration-is-atomic})
(table.insert tests {:name "app catalog default reuse and explicit conflict" :fn app-catalog-default-reuse-and-conflict})
(table.insert tests {:name "app catalog reuses precomposed reference" :fn app-catalog-reuses-existing-reference})
(table.insert tests {:name "app catalog validates before registration" :fn app-catalog-validates-before-registration})
(table.insert tests {:name "runtime install uninstall retains app catalog identity" :fn runtime-installation-retains-app-catalog})
(table.insert tests {:name "composition validates before registry or store dependencies" :fn composition-validates-before-registry-or-store-work})
(table.insert tests {:name "composition reuse avoids registry and store dependencies" :fn composition-reuse-is-lazy})
(table.insert tests {:name "composition uses explicitly supplied app stores" :fn composition-uses-explicit-app-stores})
(table.insert tests {:name "documented startup captures initialized app store and refresh signals" :fn documented-startup-uses-initialized-app-store})

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
