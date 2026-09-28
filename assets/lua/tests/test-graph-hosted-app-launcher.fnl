(local Runner (require :tests/runner))
(local Graph (require :graph/init))
(local BuiltInGraphExtensions (require :graph/extensions/builtins))
(local Signal (require :signal))

(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn assert-equals [actual expected message]
  (local prefix (if message message "values should match"))
  (assert (= actual expected)
          (.. prefix
              ": expected " (tostring expected)
              ", got " (tostring actual))))

(var last-launched-source nil)

(fn empty-lookup [_self _key]
  nil)

(fn default-open-source [_source _opts]
  {:session true})

(fn record-open-source [source _opts]
  (set last-launched-source source)
  {:session true})

(fn failing-open-source [_source _opts]
  (error "boom"))

(fn recording-resolve-selection [map keys]
  (set map.resolve-calls (+ map.resolve-calls 1))
  (set map.resolved-selected-keys keys)
  map.resolver-result)

(fn descriptor-for-scheme [scheme]
  (var found nil)
  (each [_ descriptor (ipairs (BuiltInGraphExtensions.descriptors {})) &until found]
    (each [_ candidate (ipairs descriptor.schemes) &until found]
      (when (= candidate scheme)
        (set found descriptor))))
  found)

(fn make-recording-map [selected-keys resolver-result]
  {:selected_node_keys (if selected-keys selected-keys [])
   :selection-changed (Signal)
   :resolver-result resolver-result
   :resolve-calls 0
   :resolved-selected-keys nil
   :lookup empty-lookup})

(fn make-node [selected-keys resolver-result launcher-fn]
  (local HostedAppLauncherNode (require :graph/nodes/hosted-app-launcher))
  (local graph-map (make-recording-map selected-keys resolver-result))
  (local open-source (if launcher-fn launcher-fn default-open-source))
  (local node
    (HostedAppLauncherNode
      {:source-resolver
       {:resolve-selection recording-resolve-selection}
       :source-launcher
       {:open-source open-source}}))
  (node:mount graph-map)
  {:node node :graph-map graph-map})

(fn fail-result [reason message]
  {:ok? false :reason reason :message message})

(fn success-result [source]
  (local value (if source source {:lua-root "/tmp/app" :module-name "main" :label "main.fnl"}))
  (set value.ok? true)
  value)

(fn assert-status [node expected-status expected-message]
  (local status (node:current-status))
  (assert-equals status.status expected-status "status should match")
  (when expected-message
    (assert (string.find status.message expected-message 1 true)
            (.. "message should include " expected-message ", got " (tostring status.message))))
  status)

(fn builtin-descriptors-include-hosted-app-launcher-scheme []
  (local descriptor (descriptor-for-scheme "hosted-app-launcher"))
  (assert descriptor "built-in descriptors should include hosted-app-launcher scheme"))

(fn loading-hosted-app-launcher-key-returns-labeled-node []
  (local descriptor (descriptor-for-scheme "hosted-app-launcher"))
  (assert descriptor "hosted-app-launcher descriptor should exist")
  (local graph (Graph {:with-start false :entity-events? false}))
  (descriptor.install-loaders graph {:owner-id descriptor.unit-id :extension-id descriptor.id})
  (local node (graph:create-node-by-key "hosted-app-launcher:workspace"))
  (assert node "hosted app launcher key should load")
  (assert-equals node.label "Hosted App Launcher" "launcher node label should match")
  (graph:drop))

(fn start-node-collect-targets-includes-hosted-app-launcher []
  (local StartNode (require :graph/nodes/start))
  (local start (StartNode))
  (local targets (start:collect-targets))
  (var found nil)
  (each [_ target (ipairs targets) &until found]
    (when (= (. target 2) "Hosted App Launcher")
      (set found (. target 1))))
  (assert found "start node targets should include Hosted App Launcher")
  (assert-equals found.key "hosted-app-launcher:workspace" "start target key should match"))

(fn refresh-status-for-no-selection []
  (local ctx (make-node [] (fail-result :no-selection "select one filesystem app source")))
  (ctx.node:refresh-selection)
  (assert-status ctx.node :disabled "select one filesystem app source"))

(fn refresh-status-for-multiple-selection []
  (local ctx (make-node ["fs:/a" "fs:/b"] (fail-result :multiple-selection "select only one filesystem app source")))
  (ctx.node:refresh-selection)
  (assert-status ctx.node :disabled "select only one filesystem app source"))

(fn refresh-status-for-non-fs-selection []
  (local ctx (make-node ["start"] (fail-result :unsupported-selection "selected graph key is not an fs: source")))
  (ctx.node:refresh-selection)
  (assert-status ctx.node :disabled "selected graph key is not an fs: source"))

(fn refresh-status-for-unresolved-filesystem-source []
  (local ctx (make-node ["fs:/missing"] (fail-result :missing-path "selected filesystem path does not exist")))
  (ctx.node:refresh-selection)
  (assert-status ctx.node :disabled "selected filesystem path does not exist"))

(fn refresh-status-for-resolvable-source []
  (local source (success-result))
  (local ctx (make-node ["fs:/tmp/app/main.fnl"] source))
  (local status (ctx.node:refresh-selection))
  (assert-equals status.status :ready "resolvable source should be ready")
  (assert-equals status.source source "ready status should store source"))

(fn open-selected-resolves-current-selection []
  (local ctx (make-node ["fs:/tmp/app/main.fnl"] (success-result)))
  (ctx.node:open-selected {})
  (assert-equals ctx.graph-map.resolve-calls 1 "open-selected should resolve selection")
  (assert-equals (. ctx.graph-map.resolved-selected-keys 1) "fs:/tmp/app/main.fnl" "open-selected should pass selected keys"))

(fn open-selected-calls-launcher-on-valid-source []
  (local source (success-result {:lua-root "/tmp/app" :module-name "main" :label "main.fnl"}))
  (set last-launched-source nil)
  (local ctx (make-node ["fs:/tmp/app/main.fnl"] source
                        record-open-source))
  (local session (ctx.node:open-selected {}))
  (assert-equals last-launched-source source "launcher should receive resolved source")
  (assert-equals session.session true "open-selected should return launcher session"))

(fn open-selected-updates-status-to-launched []
  (local ctx (make-node ["fs:/tmp/app/main.fnl"] (success-result)))
  (ctx.node:open-selected {})
  (assert-status ctx.node :launched "Hosted app launched"))

(fn open-selected-captures-launch-failure []
  (local ctx (make-node ["fs:/tmp/app/main.fnl"] (success-result)
                        failing-open-source))
  (local session (ctx.node:open-selected {}))
  (assert-equals session nil "failed launch should return nil")
  (assert-status ctx.node :error "boom"))

(add-test "built-in descriptors include hosted app launcher scheme" builtin-descriptors-include-hosted-app-launcher-scheme)
(add-test "loading hosted app launcher key returns labeled node" loading-hosted-app-launcher-key-returns-labeled-node)
(add-test "start node targets include hosted app launcher" start-node-collect-targets-includes-hosted-app-launcher)
(add-test "refresh status for no selection" refresh-status-for-no-selection)
(add-test "refresh status for multiple selection" refresh-status-for-multiple-selection)
(add-test "refresh status for non-fs selection" refresh-status-for-non-fs-selection)
(add-test "refresh status for unresolved filesystem source" refresh-status-for-unresolved-filesystem-source)
(add-test "refresh status for resolvable source" refresh-status-for-resolvable-source)
(add-test "open-selected resolves current selection" open-selected-resolves-current-selection)
(add-test "open-selected calls launcher on valid source" open-selected-calls-launcher-on-valid-source)
(add-test "open-selected updates status to launched" open-selected-updates-status-to-launched)
(add-test "open-selected captures launch failure" open-selected-captures-launch-failure)

(fn main []
  (Runner.run-tests {:name "graph-hosted-app-launcher" :tests tests}))

{:name "graph-hosted-app-launcher"
 :tests tests
 :main main}
