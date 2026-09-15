(local tests [])

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

(table.insert tests {:name "built-in descriptors have required shape"
                     :fn builtin-descriptors-have-required-shape})
(table.insert tests {:name "built-in descriptors expose exact scheme coverage"
                     :fn builtin-descriptors-expose-exact-scheme-coverage})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "test-builtin-graph-extensions"
                       :tests tests})))

{:tests tests
 :main main}
