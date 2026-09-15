(local fs (require :fs))
(local BuiltinGraphTestHelpers (require :tests/graph-builtin-extension-helpers))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "graph-loaders"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "loaders-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn graph-has-register-key-loader []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (assert graph.register-key-loader "graph should have register-key-loader method")
  (graph:drop))

(fn graph-has-load-by-key []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (assert graph.load-by-key "graph should have load-by-key method")
  (graph:drop))

(fn register-key-loader-accepts-scheme-and-function []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (var called false)
  (graph:register-key-loader "test"
    (fn [key]
      (set called true)
      nil))
  (assert (= called false) "loader should not be called on registration")
  (graph:drop))

(fn load-by-key-returns-existing-node []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (local existing (Graph.GraphNode {:key "my-key"}))
  (graph:add-node existing {})
  (local result (graph:load-by-key "my-key"))
  (assert (= result existing) "load-by-key should return existing node")
  (graph:drop))

(fn load-by-key-returns-nil-for-unknown-scheme []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (local result (graph:load-by-key "unknown:123"))
  (assert (= result nil) "load-by-key should return nil for unknown scheme")
  (graph:drop))

(fn load-by-key-returns-nil-for-unknown-bare-scheme []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (local result (graph:load-by-key "unknown"))
  (assert (= result nil) "load-by-key should return nil for unknown bare scheme")
  (graph:drop))

(fn load-by-key-returns-nil-for-nil-key []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (local result (graph:load-by-key nil))
  (assert (= result nil) "load-by-key should return nil for nil key")
  (graph:drop))

(fn load-by-key-invokes-loader-for-matching-scheme []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (var loader-key nil)
  (graph:register-key-loader "test"
    (fn [key]
      (set loader-key key)
      (Graph.GraphNode {:key key})))
  (local result (graph:load-by-key "test:abc"))
  (assert (= loader-key "test:abc") "loader should receive the full key")
  (assert result "load-by-key should return the created node")
  (assert (= result.key "test:abc") "created node should have correct key")
  (graph:drop))

(fn load-by-key-adds-node-to-graph []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (graph:register-key-loader "test"
    (fn [key]
      (Graph.GraphNode {:key key})))
  (local result (graph:load-by-key "test:xyz"))
  (local lookup-result (graph:lookup "test:xyz"))
  (assert (= lookup-result result) "loaded node should be added to graph")
  (graph:drop))

(fn load-by-key-returns-nil-when-loader-returns-nil []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (graph:register-key-loader "maybe"
    (fn [key]
      nil))
  (local result (graph:load-by-key "maybe:missing"))
  (assert (= result nil) "load-by-key should return nil when loader returns nil")
  (graph:drop))

(fn make-completed-future [value]
  {:on-complete (fn [cb]
                  (cb true value nil :test)
                  value)
   :cancel (fn [] nil)})

(fn make-hackernews-client []
  {:fetch-topstories (fn [] (make-completed-future []))
   :fetch-newstories (fn [] (make-completed-future []))
   :fetch-beststories (fn [] (make-completed-future []))
   :fetch-item (fn [id]
                 (make-completed-future {:id id
                                         :by "dhouston"
                                         :title "demo"}))
   :fetch-user (fn [id]
                 (make-completed-future {:id id
                                         :created 0
                                         :karma 0
                                         :about ""}))})

(fn assert-graph-node-has-preview [node context]
  (assert node (.. "missing node for preview assertion: " context))
  (assert node.preview (.. context " should expose preview"))
  (assert (= (type node.preview) "function") (.. context " preview should be a function")))

(fn world-backed-loaders-return-nil-for-missing-objects []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (local world-manager {:get-world-entry (fn [_self _id] nil)
                        :list-tabs (fn [_self] [])})
  (local builtins (BuiltinGraphTestHelpers.install-builtins! graph {:world-manager world-manager}))
  (local keys ["world:missing"
               "activity-terrain:missing:sandbox:t1"
               "activity-terrain-editor:missing:sandbox:t1"
               "activity-terrain-tool:missing:sandbox:t1:resize-terrain"
               "activity-light-type:missing:sandbox:point"
               "activity-light:missing:sandbox:point:p1"
               "activity-scene-panel:missing:sandbox:1"
               "hud-panel:missing:tiles:1"])
  (each [_ key (ipairs keys)]
    (local (ok result) (pcall (fn [] (graph:create-node-by-key key))))
    (assert ok (.. "Missing world-backed key should not throw: " key))
    (assert (= result nil) (.. "Missing world-backed key should return nil: " key)))
  (builtins:drop)
  (graph:drop))

(fn multiple-loaders-match-by-scheme []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (var first-called false)
  (var second-called false)
  (graph:register-key-loader "first"
    (fn [key]
      (set first-called true)
      (Graph.GraphNode {:key key})))
  (graph:register-key-loader "second"
    (fn [key]
      (set second-called true)
      (Graph.GraphNode {:key key})))
  (graph:load-by-key "first:a")
  (assert first-called "first loader should be called")
  (assert (not second-called) "second loader should not be called")
  (set first-called false)
  (graph:load-by-key "second:b")
  (assert (not first-called) "first loader should not be called")
  (assert second-called "second loader should be called")
  (graph:drop))

(fn load-by-key-parses-scheme-before-first-colon []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (var matched nil)
  (graph:register-key-loader "fs"
    (fn [key]
      (set matched key)
      (Graph.GraphNode {:key key})))
  (local key "fs:/tmp/a:b:c")
  (graph:load-by-key key)
  (assert (= matched key) "scheme should be substring before first ':'")
  (graph:drop))

(fn load-by-key-uses-entire-key-as-scheme-when-missing-colon []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (graph:register-key-loader "no-colon"
    (fn [key]
      (Graph.GraphNode {:key key})))
  (local node (graph:load-by-key "no-colon"))
  (assert node "load-by-key should load using scheme == full key when no ':' present")
  (assert (= node.key "no-colon") "loaded node should have the exact bare key")
  (graph:drop))

(fn register-key-loader-rejects-scheme-with-colon []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (fn attempt []
    (graph:register-key-loader "bad:"
      (fn [key]
        (Graph.GraphNode {:key key}))))
  (local (ok err) (pcall attempt))
  (assert (not ok) "scheme containing ':' should error")
  (assert (string.find (tostring err) "must not include" 1 true)
          "error should mention ':' in scheme")
  (graph:drop))

(fn register-key-loader-rejects-duplicate-scheme []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (graph:register-key-loader "dup"
    (fn [key]
      (Graph.GraphNode {:key key})))
  (local (ok err)
    (pcall (fn []
             (graph:register-key-loader "dup"
               (fn [key]
                 (Graph.GraphNode {:key key}))))))
  (assert (not ok) "duplicate scheme registration should error")
  (assert (string.find (tostring err) "duplicate scheme" 1 true)
          "error should mention duplicate scheme")
  (graph:drop))

(fn load-by-key-rejects-mismatched-node-key []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (graph:register-key-loader "bad"
    (fn [_key]
      (Graph.GraphNode {:key "bad:other"})))
  (local (ok err) (pcall (fn [] (graph:load-by-key "bad:expected"))))
  (assert (not ok) "load-by-key should error when loader returns mismatched key")
  (assert (string.find (tostring err) "mismatched key" 1 true)
          "error should mention mismatched key")
  (graph:drop))

(fn string-entity-node-module-exports-register-loader []
  (local module (require :graph/nodes/string-entity))
  (assert module.register-loader "string-entity module should export register-loader")
  (assert (= (type module.register-loader) "function") "register-loader should be a function"))

(fn code-entity-node-module-exports-register-loader []
  (local module (require :graph/nodes/code-entity))
  (assert module.register-loader "code-entity module should export register-loader")
  (assert (= (type module.register-loader) "function") "register-loader should be a function"))

(fn list-entity-node-module-exports-register-loader []
  (local module (require :graph/nodes/list-entity))
  (assert module.register-loader "list-entity module should export register-loader")
  (assert (= (type module.register-loader) "function") "register-loader should be a function"))

(fn link-entity-node-module-exports-register-loader []
  (local module (require :graph/nodes/link-entity))
  (assert module.register-loader "link-entity module should export register-loader")
  (assert (= (type module.register-loader) "function") "register-loader should be a function"))

(fn notebook-node-module-exports-register-loader []
  (local module (require :graph/nodes/notebook))
  (assert module.register-loader "notebook module should export register-loader")
  (assert (= (type module.register-loader) "function") "register-loader should be a function"))

(fn identity-node-module-exports-register-loader []
  (local module (require :graph/nodes/identity))
  (assert module.register-loader "identity module should export register-loader")
  (assert (= (type module.register-loader) "function") "register-loader should be a function"))

(fn string-entity-loader-loads-existing-entity []
  (with-temp-dir
    (fn [dir]
      (local StringEntityStore (require :entities/string))
      (local store (StringEntityStore.StringEntityStore {:base-dir dir}))
      (local entity (store:create-entity {:value "test"}))
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local {:register-loader register-loader} (require :graph/nodes/string-entity))
      (register-loader graph {:store store})
      (local key (.. "string-entity:" entity.id))
      (local result (graph:load-by-key key))
      (assert result "loader should create node for existing entity")
      (assert (= result.key key) "node key should match")
      (assert (= result.entity-id entity.id) "node entity-id should match")
      (result:drop)
      (graph:drop))))

(fn string-entity-loader-returns-nil-for-missing-entity []
  (with-temp-dir
    (fn [dir]
      (local StringEntityStore (require :entities/string))
      (local store (StringEntityStore.StringEntityStore {:base-dir dir}))
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local {:register-loader register-loader} (require :graph/nodes/string-entity))
      (register-loader graph {:store store})
      (local result (graph:load-by-key "string-entity:nonexistent"))
      (assert (= result nil) "loader should return nil for missing entity")
      (graph:drop))))

(fn string-entity-loader-returns-nil-for-bare-scheme-key []
  (with-temp-dir
    (fn [dir]
      (local StringEntityStore (require :entities/string))
      (local store (StringEntityStore.StringEntityStore {:base-dir dir}))
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local {:register-loader register-loader} (require :graph/nodes/string-entity))
      (register-loader graph {:store store})
      (local result (graph:load-by-key "string-entity"))
      (assert (= result nil) "loader should return nil for bare scheme key")
      (graph:drop))))

(fn list-entity-loader-loads-existing-entity []
  (with-temp-dir
    (fn [dir]
      (local ListEntityStore (require :entities/list))
      (local store (ListEntityStore.ListEntityStore {:base-dir dir}))
      (local entity (store:create-entity {:name "test list"}))
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local {:register-loader register-loader} (require :graph/nodes/list-entity))
      (register-loader graph {:store store})
      (local key (.. "list-entity:" entity.id))
      (local result (graph:load-by-key key))
      (assert result "loader should create node for existing entity")
      (assert (= result.key key) "node key should match")
      (assert (= result.entity-id entity.id) "node entity-id should match")
      (result:drop)
      (graph:drop))))

(fn code-entity-loader-loads-existing-entity []
  (with-temp-dir
    (fn [dir]
      (local CodeEntityStore (require :entities/code))
      (local store (CodeEntityStore.CodeEntityStore {:base-dir dir}))
      (local entity (store:create-entity {:source "(+ 1 2)"}))
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local {:register-loader register-loader} (require :graph/nodes/code-entity))
      (register-loader graph {:store store})
      (local key (.. "code-entity:" entity.id))
      (local result (graph:load-by-key key))
      (assert result "loader should create node for existing entity")
      (assert (= result.key key) "node key should match")
      (assert (= result.entity-id entity.id) "node entity-id should match")
      (result:drop)
      (graph:drop))))

(fn link-entity-loader-loads-existing-entity []
  (with-temp-dir
    (fn [dir]
      (local LinkEntityStore (require :entities/link))
      (local store (LinkEntityStore.LinkEntityStore {:base-dir dir}))
      (local entity (store:create-entity {:source-key "a" :target-key "b"}))
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local {:register-loader register-loader} (require :graph/nodes/link-entity))
      (register-loader graph {:store store})
      (local key (.. "link-entity:" entity.id))
      (local result (graph:load-by-key key))
      (assert result "loader should create node for existing entity")
      (assert (= result.key key) "node key should match")
      (assert (= result.entity-id entity.id) "node entity-id should match")
      (result:drop)
      (graph:drop))))

(fn notebook-loader-loads-existing-notebook []
  (with-temp-dir
    (fn [dir]
      (local NotebookStore (require :notebooks/store))
      (local store (NotebookStore.NotebookStore {:base-dir dir}))
      (local notebook (store:create-notebook {:name "rounds notes"}))
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local {:register-loader register-loader} (require :graph/nodes/notebook))
      (register-loader graph {:store store})
      (local key (.. "notebook:" notebook.id))
      (local result (graph:load-by-key key))
      (assert result "loader should create node for existing notebook")
      (assert (= result.key key) "node key should match")
      (assert (= result.notebook-id notebook.id) "node notebook-id should match")
      (result:drop)
      (graph:drop))))

(fn identity-loader-loads-existing-identity []
  (with-temp-dir
    (fn [dir]
      (local IdentityStore (require :entities/identity))
      (local store (IdentityStore.IdentityStore {:base-dir dir}))
      (local entity (store:create-entity {:target-key "string-entity:abc"}))
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local {:register-loader register-loader} (require :graph/nodes/identity))
      (register-loader graph {:store store})
      (local key (.. "identity:" entity.id))
      (local result (graph:load-by-key key))
      (assert result "loader should create node for existing identity")
      (assert (= result.key key) "node key should match")
      (assert (= result.identity-id entity.id) "node identity-id should match")
      (assert (= result.identity-target-key "string-entity:abc")
              "node should expose identity target key")
      (result:drop)
      (graph:drop))))

(fn link-entity-integration-loads-endpoints-via-load-by-key []
  (with-temp-dir
    (fn [dir]
      (local StringEntityStore (require :entities/string))
      (local LinkEntityStore (require :entities/link))
      (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir (fs.join-path dir "link")}))
      (local left (string-store:create-entity {:value "left"}))
      (local right (string-store:create-entity {:value "right"}))
      (local left-key (.. "string-entity:" left.id))
      (local right-key (.. "string-entity:" right.id))
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false :link-store link-store}))
      (local {:register-loader string-register} (require :graph/nodes/string-entity))
      (string-register graph {:store string-store})
      (link-store:create-entity {:source-key left-key :target-key right-key})
      (assert (graph:lookup left-key) "link integration should load source node via load-by-key")
      (assert (graph:lookup right-key) "link integration should load target node via load-by-key")
      (assert (= (graph:edge-count) 1) "link integration should add edge after loading endpoints")
      (graph:drop))))

(fn link-entity-integration-readds-edge-after-node-removal []
  (with-temp-dir
    (fn [dir]
      (local StringEntityStore (require :entities/string))
      (local LinkEntityStore (require :entities/link))
      (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir (fs.join-path dir "link")}))
      (local left (string-store:create-entity {:value "left"}))
      (local right (string-store:create-entity {:value "right"}))
      (local left-key (.. "string-entity:" left.id))
      (local right-key (.. "string-entity:" right.id))
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false :link-store link-store}))
      (local {:register-loader string-register} (require :graph/nodes/string-entity))
      (string-register graph {:store string-store})
      (link-store:create-entity {:source-key left-key :target-key right-key})
      (local right-node (graph:lookup right-key))
      (assert right-node "right node should exist after link-driven loading")
      (assert (= (graph:edge-count) 1) "graph should have one edge before removal")
      (graph:remove-nodes [right-node])
      (assert (= (graph:edge-count) 0) "removing endpoint should remove link edge")
      (local reloaded (graph:load-by-key right-key))
      (assert reloaded "right node should reload after removal")
      (assert (= (graph:edge-count) 1)
              "link edge should be recreated after endpoint reload")
      (graph:drop))))

(fn list-entity-node-loads-items-via-load-by-key []
  (with-temp-dir
    (fn [dir]
      (local StringEntityStore (require :entities/string))
      (local ListEntityStore (require :entities/list))
      (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
      (local list-store (ListEntityStore.ListEntityStore {:base-dir (fs.join-path dir "list")}))
      (local string-entity (string-store:create-entity {:value "item"}))
      (local item-key (.. "string-entity:" string-entity.id))
      (local list-entity (list-store:create-entity {:name "test"
                                                    :items [item-key]}))
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local {:register-loader string-register} (require :graph/nodes/string-entity))
      (local {:register-loader list-register :ListEntityNode ListEntityNode} (require :graph/nodes/list-entity))
      (string-register graph {:store string-store})
      (list-register graph {:store list-store})
      (local list-node (ListEntityNode {:entity-id list-entity.id :store list-store}))
      (graph:add-node list-node {})
      ;; The string entity node should have been loaded via load-by-key
      (local loaded-string-node (graph:lookup item-key))
      (assert loaded-string-node "string entity node should be loaded via load-by-key")
      (assert (= loaded-string-node.entity-id string-entity.id) "loaded node should have correct entity-id")
      ;; There should be an edge from list node to string node
      (assert (= (graph:edge-count) 1) "should have edge from list to item")
      (list-node:drop)
      (loaded-string-node:drop)
      (graph:drop))))

(fn built-in-graph-extensions-register-and-load-nodes []
  (with-temp-dir
    (fn [dir]
      (local StringEntityStore (require :entities/string))
      (local ListEntityStore (require :entities/list))
      (local LinkEntityStore (require :entities/link))
      (local NotebookStore (require :notebooks/store))
      (local Kernels (require :kernels))
      (local LlmStore (require :llm/conversations/store))
      (local string-store (StringEntityStore.StringEntityStore {:base-dir (fs.join-path dir "string")}))
      (local list-store (ListEntityStore.ListEntityStore {:base-dir (fs.join-path dir "list")}))
      (local link-store (LinkEntityStore.LinkEntityStore {:base-dir (fs.join-path dir "link")}))
      (local notebook-store (NotebookStore.NotebookStore {:base-dir (fs.join-path dir "notebooks")}))
      (local kernels (Kernels.Kernels {:base-dir (fs.join-path dir "kernels")
                                       :defer-callbacks false}))
      (local llm-store (LlmStore.Store {:base-dir (fs.join-path dir "llm")}))
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false :link-store link-store}))

      (local builtins
        (BuiltinGraphTestHelpers.install-builtins! graph {:string-store string-store
                                                           :list-store list-store
                                                           :link-store link-store
                                                           :notebook-store notebook-store
                                                           :kernels kernels
                                                           :llm-store llm-store
                                                           :hackernews-ensure-client make-hackernews-client}))

      (local string-list (graph:load-by-key "string-entity-list"))
      (assert string-list "should load string-entity-list")
      (assert (= string-list.key "string-entity-list") "string list key should match")
      (assert (= string-list.store string-store) "string list should use provided store")
      (assert-graph-node-has-preview string-list "string-entity-list")

      (local notebook-record (notebook-store:create-notebook {:name "surgery prep"}))
      (local notebooks-node (graph:load-by-key "notebooks"))
      (assert notebooks-node "should load notebooks node")
      (assert (= notebooks-node.key "notebooks") "notebooks key should match")
      (assert (= notebooks-node.store notebook-store) "notebooks node should use provided store")
      (assert-graph-node-has-preview notebooks-node "notebooks")

      (local notebook-node (graph:load-by-key (.. "notebook:" notebook-record.id)))
      (assert notebook-node "should load notebook node")
      (assert (= notebook-node.key (.. "notebook:" notebook-record.id)) "notebook key should match")
      (assert (= notebook-node.notebook-id notebook-record.id) "notebook id should match")
      (assert-graph-node-has-preview notebook-node "notebook")

      (local kernels-node (graph:load-by-key "kernels"))
      (assert kernels-node "should load kernels node")
      (assert (= kernels-node.key "kernels") "kernels key should match")
      (assert-graph-node-has-preview kernels-node "kernels")

      (local created-kernel (kernels:create-kernel {:name "test-kernel"}))
      (local kernel-node (graph:load-by-key (.. "kernel:" (tostring created-kernel.id))))
      (assert kernel-node "should load kernel node")
      (assert (= kernel-node.key (.. "kernel:" (tostring created-kernel.id)))
              "kernel key should match")
      (assert-graph-node-has-preview kernel-node "kernel")

      (local node (graph:load-by-key "class:demo"))
      (assert node "should load class node")
      (assert (= node.key "class:demo") "class node key should match")
      (assert-graph-node-has-preview node "class")

      (local fs-node (graph:load-by-key "fs:/tmp"))
      (assert fs-node "should load fs node")
      (assert (= fs-node.key "fs:/tmp") "fs node key should match")
      (assert (= fs-node.path "/tmp") "fs node should use parsed path")
      (assert-graph-node-has-preview fs-node "fs")

      (local table-node (graph:load-by-key "table:_G"))
      (assert table-node "should load table:_G")
      (assert (= table-node.key "table:_G") "table node key should match")
      (assert (= table-node.table _G) "table node should resolve _G")
      (assert-graph-node-has-preview table-node "table")

      (local tool-node (graph:load-by-key "llm-tool:test-tool"))
      (assert tool-node "should load llm-tool node")
      (assert (= tool-node.key "llm-tool:test-tool") "llm-tool node key should match")
      (assert (= tool-node.name "test-tool") "llm-tool node should use parsed name")
      (assert-graph-node-has-preview tool-node "llm-tool")

      (llm-store:create-conversation {:name "demo"} "c1")
      (local convo-node (graph:load-by-key "llm-conversation:c1"))
      (assert convo-node "should load llm conversation")
      (assert (= convo-node.key "llm-conversation:c1") "llm conversation key should match")
      (assert-graph-node-has-preview convo-node "llm-conversation")

      (llm-store:create-item {:type "message" :content "hi"} "m1")
      (local msg-node (graph:load-by-key "llm-message:m1"))
      (assert msg-node "should load llm message")
      (assert (= msg-node.key "llm-message:m1") "llm message key should match")
      (assert-graph-node-has-preview msg-node "llm-message")

      (local hn-root (graph:load-by-key "hackernews-root"))
      (assert hn-root "should load hackernews root node")
      (assert (= hn-root.key "hackernews-root") "hackernews root key should match")
      (assert-graph-node-has-preview hn-root "hackernews-root")

      (local hn-list (graph:load-by-key "hackernews-story-list:topstories"))
      (assert hn-list "should load hackernews story list node")
      (assert (= hn-list.key "hackernews-story-list:topstories") "hackernews story list key should match")
      (assert-graph-node-has-preview hn-list "hackernews-story-list")

      (local hn-story (graph:load-by-key "hackernews-story:42"))
      (assert hn-story "should load hackernews story node")
      (assert (= hn-story.key "hackernews-story:42") "hackernews story key should match")
      (assert-graph-node-has-preview hn-story "hackernews-story")

      (local hn-user (graph:load-by-key "hackernews-user:jl"))
      (assert hn-user "should load hackernews user node")
      (assert (= hn-user.key "hackernews-user:jl") "hackernews user key should match")
      (assert-graph-node-has-preview hn-user "hackernews-user")

      (builtins:drop)
      (graph:drop)
      (kernels:drop))))

(fn fs-loader-returns-nil-for-missing-path []
  (with-temp-dir
    (fn [dir]
      (local Graph (require :graph/init))
      (local graph (Graph {:with-start false}))
      (local builtins (BuiltinGraphTestHelpers.install-builtins! graph {}))
      (local existing-key (.. "fs:" dir))
      (local existing-node (graph:load-by-key existing-key))
      (assert existing-node "fs loader should resolve an existing path")
      (local missing-key (.. "fs:" (fs.join-path dir "missing")))
      (local missing-node (graph:create-node-by-key missing-key))
      (assert (= missing-node nil)
              "fs loader should return nil for a missing path")
      (builtins:drop)
      (graph:drop))))

(fn hackernews-ensure-client-propagates-to-child-nodes []
  (local HackerNewsRootNode (require :graph/nodes/hackernews-root))
  (local ensure-client (fn [] {:fetch-topstories (fn [] nil)}))
  (local root (HackerNewsRootNode {:ensure-client ensure-client}))
  (local list-node (root:make-list-node "topstories" "Top stories"))
  (assert (= list-node.ensure-client ensure-client) "root should pass ensure-client to list node")
  (local story-node (list-node:make-story-node 42 {:id 42}))
  (assert (= story-node.ensure-client ensure-client) "list node should pass ensure-client to story node")
  (local edges [])
  (story-node:mount {:add-edge (fn [_self edge]
                                 (table.insert edges edge))})
  (story-node:add-user-node "dhouston")
  (assert (= (length edges) 1) "story node should add one edge for author user node")
  (local user-node (. (. edges 1) :target))
  (assert user-node "edge target should be user node")
  (assert (= user-node.ensure-client ensure-client) "story node should pass ensure-client to user node")
  (when list-node.drop (list-node:drop))
  (when root.drop (root:drop)))

(fn make-activity-world-manager []
  (local Signal (require :signal))
  (local scene-state {:panels [{:kind "alpha"}] :terrains [{:id "terrain-a" :kind "heightfield-terrain" :options {}}] :lights {:ambient {:id "ambient"} :directional [] :point [{:id "point-1"}] :spot []}
                      :skybox {:enabled? true :default {:name "lake" :brightness 0.1} :by-theme {}}
                      :background {:color [0.0 0.0 0.0]} :containment {:enabled? false}})
  (local entry {:id "test-world" :name "Test World" :world {:state {:scene {:panels [] :terrains []} :hud {:panels []}
                                                                   :activity {:active_id "sandbox" :sessions {:sandbox {:scene scene-state}}}}}})
  {:changed (Signal) :list-tabs (fn [_self] [{:index 1 :id "test-world" :name "Test World"}])
   :get-world-entry (fn [_self world-id] (if (= world-id "test-world") entry nil))})

(fn activity-hierarchy-loaders-resolve-existing-session []
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (local builtins (BuiltinGraphTestHelpers.install-builtins! graph {:world-manager (make-activity-world-manager) :asset-path-resolver (fn [_name] nil)}))
  (each [_ key (ipairs ["world-activities:test-world" "world-activity:test-world:sandbox" "activity-surfaces:test-world:sandbox" "activity-scene:test-world:sandbox" "activity-scene-panels:test-world:sandbox" "activity-terrains:test-world:sandbox" "activity-skybox:test-world:sandbox" "activity-background:test-world:sandbox" "activity-lights:test-world:sandbox" "activity-scene-panel:test-world:sandbox:1" "activity-terrain:test-world:sandbox:terrain-a" "activity-terrain-editor:test-world:sandbox:terrain-a" "activity-terrain-tool:test-world:sandbox:terrain-a:apply-perlin" "activity-light-type:test-world:sandbox:point" "activity-light:test-world:sandbox:point:point-1"])]
    (local node (graph:load-by-key key))
    (assert node (.. "loader should resolve " key))
    (assert (= node.key key) (.. "loader should preserve key " key)))
  (assert (= (graph:load-by-key "activity-hud:test-world:sandbox") nil) "activity-hud loader should return nil when session has no hud")
  (assert (= (graph:load-by-key "activity-canvas:test-world:sandbox") nil) "activity-canvas loader should return nil when session has no canvas")
  (each [_ key (ipairs ["scene-panels:test-world" "terrains:test-world" "skybox:test-world" "background:test-world" "lights:test-world"])]
    (assert (= (graph:load-by-key key) nil) (.. "legacy scene category loader should be absent: " key)))
  (builtins:drop)
  (graph:drop))

(fn legacy-scene-detail-loaders-are-absent-after-map-key-migration []
  "Legacy persisted detail keys migrate in GraphMapManager; loaders should not keep aliases."
  (local Graph (require :graph/init))
  (local graph (Graph {:with-start false}))
  (local builtins (BuiltinGraphTestHelpers.install-builtins! graph {:world-manager (make-activity-world-manager) :asset-path-resolver (fn [_name] nil)}))
  (each [_ key (ipairs ["scene-panel:test-world:1"
                        "terrain:test-world:terrain-a"
                        "terrain-editor:test-world:terrain-a"
                        "terrain-tool:test-world:terrain-a:apply-perlin"
                        "light-type:test-world:point"
                        "light:test-world:point:point-1"])]
    (assert (= (graph:load-by-key key) nil)
            (.. "legacy scene detail loader should be absent: " key)))
  (builtins:drop)
  (graph:drop))

(table.insert tests {:name "graph has register-key-loader"
                     :fn graph-has-register-key-loader})
(table.insert tests {:name "graph has load-by-key"
                     :fn graph-has-load-by-key})
(table.insert tests {:name "register-key-loader accepts scheme and function"
                     :fn register-key-loader-accepts-scheme-and-function})
(table.insert tests {:name "load-by-key returns existing node"
                     :fn load-by-key-returns-existing-node})
(table.insert tests {:name "load-by-key returns nil for unknown scheme"
                     :fn load-by-key-returns-nil-for-unknown-scheme})
(table.insert tests {:name "load-by-key returns nil for unknown bare scheme"
                     :fn load-by-key-returns-nil-for-unknown-bare-scheme})
(table.insert tests {:name "load-by-key returns nil for nil key"
                     :fn load-by-key-returns-nil-for-nil-key})
(table.insert tests {:name "load-by-key invokes loader for matching scheme"
                     :fn load-by-key-invokes-loader-for-matching-scheme})
(table.insert tests {:name "load-by-key adds node to graph"
                     :fn load-by-key-adds-node-to-graph})
(table.insert tests {:name "load-by-key returns nil when loader returns nil"
                     :fn load-by-key-returns-nil-when-loader-returns-nil})
(table.insert tests {:name "world-backed loaders return nil for missing objects"
                      :fn world-backed-loaders-return-nil-for-missing-objects})
(table.insert tests {:name "activity hierarchy loaders resolve existing session"
                      :fn activity-hierarchy-loaders-resolve-existing-session})
(table.insert tests {:name "legacy scene detail loaders are absent after map-key migration"
                     :fn legacy-scene-detail-loaders-are-absent-after-map-key-migration})
(table.insert tests {:name "multiple loaders match by scheme"
                      :fn multiple-loaders-match-by-scheme})
(table.insert tests {:name "load-by-key parses scheme before first colon"
                     :fn load-by-key-parses-scheme-before-first-colon})
(table.insert tests {:name "load-by-key uses entire key as scheme when missing colon"
                     :fn load-by-key-uses-entire-key-as-scheme-when-missing-colon})
(table.insert tests {:name "register-key-loader rejects scheme with colon"
                     :fn register-key-loader-rejects-scheme-with-colon})
(table.insert tests {:name "register-key-loader rejects duplicate scheme"
                     :fn register-key-loader-rejects-duplicate-scheme})
(table.insert tests {:name "load-by-key rejects mismatched node key"
                     :fn load-by-key-rejects-mismatched-node-key})
(table.insert tests {:name "string entity node module exports register-loader"
                     :fn string-entity-node-module-exports-register-loader})
(table.insert tests {:name "code entity node module exports register-loader"
                     :fn code-entity-node-module-exports-register-loader})
(table.insert tests {:name "list entity node module exports register-loader"
                     :fn list-entity-node-module-exports-register-loader})
(table.insert tests {:name "link entity node module exports register-loader"
                     :fn link-entity-node-module-exports-register-loader})
(table.insert tests {:name "notebook node module exports register-loader"
                     :fn notebook-node-module-exports-register-loader})
(table.insert tests {:name "identity node module exports register-loader"
                     :fn identity-node-module-exports-register-loader})
(table.insert tests {:name "string entity loader loads existing entity"
                     :fn string-entity-loader-loads-existing-entity})
(table.insert tests {:name "string entity loader returns nil for missing entity"
                     :fn string-entity-loader-returns-nil-for-missing-entity})
(table.insert tests {:name "string entity loader returns nil for bare scheme key"
                     :fn string-entity-loader-returns-nil-for-bare-scheme-key})
(table.insert tests {:name "list entity loader loads existing entity"
                     :fn list-entity-loader-loads-existing-entity})
(table.insert tests {:name "code entity loader loads existing entity"
                     :fn code-entity-loader-loads-existing-entity})
(table.insert tests {:name "link entity loader loads existing entity"
                     :fn link-entity-loader-loads-existing-entity})
(table.insert tests {:name "notebook loader loads existing notebook"
                     :fn notebook-loader-loads-existing-notebook})
(table.insert tests {:name "identity loader loads existing identity"
                     :fn identity-loader-loads-existing-identity})
(table.insert tests {:name "link entity integration loads endpoints via load-by-key"
                     :fn link-entity-integration-loads-endpoints-via-load-by-key})
(table.insert tests {:name "link entity integration readds edge after node removal"
                     :fn link-entity-integration-readds-edge-after-node-removal})
(table.insert tests {:name "list entity node loads items via load-by-key"
                     :fn list-entity-node-loads-items-via-load-by-key})
(table.insert tests {:name "built-in graph extensions register and load nodes"
                       :fn built-in-graph-extensions-register-and-load-nodes})
(table.insert tests {:name "fs loader returns nil for missing path"
                     :fn fs-loader-returns-nil-for-missing-path})
(table.insert tests {:name "hackernews ensure-client propagates to child nodes"
                       :fn hackernews-ensure-client-propagates-to-child-nodes})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-loaders"
                       :tests tests})))

{:name "graph-loaders"
 :tests tests
 :main main}
