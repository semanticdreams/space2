(local Runner (require :tests/runner))
(local Graph (require :graph/init))
(local BuiltInGraphExtensions (require :graph/extensions/builtins))
(local Signal (require :signal))
(local glm (require :glm))

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

(fn buffer-allocate [_self _count]
  1)

(fn ignore-two [_self _value]
  nil)

(fn ignore-four [_self _handle _offset _value]
  nil)

(fn ignore-three [_self _key _opts]
  nil)

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate buffer-allocate)
  (set buffer.delete ignore-two)
  (set buffer.set-glm-vec3 ignore-four)
  (set buffer.set-glm-vec4 ignore-four)
  (set buffer.set-glm-vec2 ignore-four)
  (set buffer.set-float ignore-four)
  buffer)

(fn make-text-ssbo-batcher []
  {:upsert-text ignore-three
   :update-text-transform ignore-three
   :remove-text ignore-two})

(fn make-clickables-stub []
  {:register ignore-two
   :unregister ignore-two
   :register-right-click ignore-two
   :unregister-right-click ignore-two
   :register-double-click ignore-two
   :unregister-double-click ignore-two})

(fn make-hoverables-stub []
  {:register ignore-two
   :unregister ignore-two})

(fn make-icons-stub []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :bottom 0 :top 1}
                :atlasBounds {:left 0 :right 1 :bottom 0 :top 1}})
  (local font {:metadata {:metrics {:ascender 1 :descender -1 :lineHeight 1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}})
  (local stub {:font font :codepoints {:rocket_launch 4242}})
  (set stub.get (fn [self name]
                  (local value (. self.codepoints name))
                  (assert value (.. "Missing icon " name))
                  value))
  (set stub.resolve (fn [self name]
                      {:type :font
                       :codepoint (self:get name)
                       :font self.font}))
  stub)

(fn make-ui-ctx []
  (local triangle (make-vector-buffer))
  (local text-batcher (make-text-ssbo-batcher))
  (local ctx {:triangle-vector triangle
              :clickables (make-clickables-stub)
              :hoverables (make-hoverables-stub)
              :system-cursors {:set-cursor ignore-two}
              :icons (make-icons-stub)
              :theme {:text {:foreground (glm.vec4 1 1 1 1)
                             :dim-foreground (glm.vec4 0.6 0.6 0.6 1)}}})
  (set ctx.get-text-ssbo-batcher (fn [_self] text-batcher))
  ctx)

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
  (local status (assert-status ctx.node :ready "Ready to launch"))
  (assert status.latest-launch "successful launch should keep latest launch status")
  (assert-equals status.latest-launch.status :launched "latest launch status should be launched")
  (assert (string.find status.latest-launch.message "Hosted app launched" 1 true)
          "latest launch should report success"))

(fn open-selected-captures-launch-failure []
  (local ctx (make-node ["fs:/tmp/app/main.fnl"] (success-result)
                        failing-open-source))
  (local session (ctx.node:open-selected {}))
  (assert-equals session nil "failed launch should return nil")
  (local status (assert-status ctx.node :ready "Ready to launch"))
  (assert status.latest-launch "failed launch should keep latest launch status")
  (assert-equals status.latest-launch.status :error "latest launch status should be error")
  (assert (string.find status.latest-launch.message "boom" 1 true)
          "latest launch should report error"))

(fn node-exposes-hosted-launcher-view-constructor []
  (local ctx (make-node [] (fail-result :no-selection "select one filesystem app source")))
  (local HostedAppLauncherView (require :graph/view/views/hosted-app-launcher))
  (assert-equals ctx.node.view HostedAppLauncherView "launcher node view should use hosted launcher view"))

(fn built-view-renders-disabled-status-for-invalid-selection []
  (local ctx (make-node [] (fail-result :no-selection "select one filesystem app source")))
  (local builder (ctx.node.view ctx.node))
  (local view (builder (make-ui-ctx)))
  (assert-equals ctx.graph-map.resolve-calls 1 "view build should refresh selection")
  (assert-equals view.status-kind :disabled "view should expose disabled status")
  (assert (string.find view.status-message "select one filesystem app source" 1 true)
          "view should render disabled status text")
  (view:drop))

(fn launch-button-disabled-unless-ready []
  (local disabled-ctx (make-node [] (fail-result :no-selection "select one filesystem app source")))
  (local disabled-view ((disabled-ctx.node.view disabled-ctx.node) (make-ui-ctx)))
  (assert-equals disabled-view.launch-button.enabled? false "launch button should be disabled for invalid status")
  (disabled-view:drop)
  (local ready-ctx (make-node ["fs:/tmp/app/main.fnl"] (success-result)))
  (local ready-view ((ready-ctx.node.view ready-ctx.node) (make-ui-ctx)))
  (assert-equals ready-view.status-kind :ready "ready view should expose ready status")
  (assert-equals ready-view.launch-button.enabled? true "launch button should be enabled for ready status")
  (assert-equals ready-view.launch-button.icon "rocket_launch" "launch button should use rocket_launch icon")
  (ready-view:drop))

(fn clicking-enabled-button-opens-selection-and-refreshes-status []
  (local source (success-result {:lua-root "/tmp/app" :module-name "main" :label "main.fnl"}))
  (set last-launched-source nil)
  (local ctx (make-node ["fs:/tmp/app/main.fnl"] source record-open-source))
  (local view ((ctx.node.view ctx.node) (make-ui-ctx)))
  (assert-equals view.launch-button.enabled? true "ready launch button should start enabled")
  (view.launch-button:on-click {:button 1})
  (assert-equals last-launched-source source "click should open selected source")
  (assert-equals view.status-kind :ready "click should preserve visible selection readiness")
  (assert (string.find view.launch-message "Hosted app launched" 1 true)
          "view should render latest launched status text")
  (assert-equals view.launch-button.enabled? true "launch button should remain enabled while selection is ready")
  (view:drop))

(fn failed-launch-keeps-button-enabled-for-ready-selection []
  (local ctx (make-node ["fs:/tmp/app/main.fnl"] (success-result)
                        failing-open-source))
  (local view ((ctx.node.view ctx.node) (make-ui-ctx)))
  (assert-equals view.launch-button.enabled? true "ready launch button should start enabled")
  (local session (ctx.node:open-selected {}))
  (assert-equals session nil "failed launch should return nil")
  (assert-equals view.status-kind :ready "failed launch should preserve visible selection readiness")
  (assert (string.find view.launch-message "boom" 1 true)
          "view should render latest launch error")
  (assert-equals view.launch-button.enabled? true "launch button should remain enabled so user can retry")
  (view:drop))

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
(add-test "node exposes hosted launcher view constructor" node-exposes-hosted-launcher-view-constructor)
(add-test "built view renders disabled status for invalid selection" built-view-renders-disabled-status-for-invalid-selection)
(add-test "launch button disabled unless ready" launch-button-disabled-unless-ready)
(add-test "clicking enabled button opens selection and refreshes status" clicking-enabled-button-opens-selection-and-refreshes-status)
(add-test "failed launch keeps button enabled for ready selection" failed-launch-keeps-button-enabled-for-ready-selection)

(fn main []
  (Runner.run-tests {:name "graph-hosted-app-launcher" :tests tests}))

{:name "graph-hosted-app-launcher"
 :tests tests
 :main main}
