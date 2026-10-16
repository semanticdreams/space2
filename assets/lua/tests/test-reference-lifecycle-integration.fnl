(local H (require :tests/test-reference-lifecycle-helpers))
(local fs (require :fs))
(local json (require :json))
(local J (require :json-utils))
(local R (require :reference-lifecycle/record-utils))
(local HomeWorld (require :home-world))
(local tests [])
(local source-key "string-entity:s")
(local source-text " \n(+ 1 2)\n ")

(fn same [actual expected]
  (assert (= (J.stable-json actual) (J.stable-json expected))
          (.. "values differ: " (J.stable-json actual) " != " (J.stable-json expected))))
(fn pending [s] ((require :reference-lifecycle/pending) s.base-dir))
(fn metadata-path [s id]
  (fs.join-path s.base-dir "worlds" id "graph" "maps" "reserve" "metadata.json"))
(fn board-state []
  {:items [{:id "subject" :type "string-entity" :subject-key source-key
            :position [11 12 0] :rotation [1 0 0 0] :size [33 17 0] :state {:marker "authored"}}
           {:id "survivor" :type "string-entity" :subject-key "string-entity:a"
            :position [70 12 0] :size [30 20 0] :state {:marker "independent"}}]
   :connectors [{:id "connector" :source-item-id "subject" :target-item-id "survivor"
                 :kind "visual" :state {:marker "authored connector"}}]})
(fn map-state [id]
  {:id id :name id :nodes [source-key "string-entity:a"]
   :edges [{:source source-key :target "string-entity:a" :label "authored" :weight 7}]
   :selected_node_keys [source-key] :focused_node_key source-key :view_mode "outline"
   :outline_root_keys [source-key]
   :islands [{:id "island" :kind "ordered-list" :members [source-key "string-entity:a"]
              :state {:list-key source-key :position [9 8 0] :spacing 4}}]})
(fn write-world [s id]
  (local dir (fs.join-path s.base-dir "worlds" id))
  (fs.create-dirs dir)
  (local world (HomeWorld {:id id :dir dir}))
  (set world.state.board (board-state))
  (set world.state.activity.sessions.board {:board-state (board-state)})
  (set world.state.graph {:active_map_id "main" :next_map_id 3
                         :maps [(map-state "main") (map-state "reserve")]})
  (world:save-state)
  (local path (metadata-path s id))
  (fs.create-dirs (fs.parent path))
  (J.write-json! path
    {:positions {source-key [11 12 0]} :sizes {source-key [33 17]}
     :presentations {source-key "expanded"} :camera {:position [4 5 100]}
     :panels [{:kind "graph-node-view" :graph-map-id "reserve" :node-key source-key
               :target-kind "canvas" :panel {:node-key source-key :opaque false}}]
     :extra_panels [{:kind "graph-node-view" :graph-map-id "reserve" :node-key source-key
                     :target-kind "hud" :panel {:node-key source-key :opaque "keep"}}]
     :provenance {:text source-key}}))
(fn seed [s]
  (s.string-store:create-entity {:id "s" :value source-text})
  (s.string-store:create-entity {:id "a" :value "independent"})
  (s.list-store:create-entity {:id "unopened" :items [source-key "string-entity:a"]})
  (write-world s "loaded")
  (write-world s "unopened")
  (J.write-json! (fs.join-path s.base-dir "worlds" "index.json")
    {:worlds [{:id "loaded" :type "home" :name "Loaded"} {:id "unopened" :type "home" :name "Unopened"}]}))
(fn add [name f]
  (fn rooted [root]
    (local s (H.stores root)) (seed s)
    (H.with-native-world s "loaded" f))
  (table.insert tests {:name (.. "reference lifecycle integration " name) :fn #(H.with-root rooted)}))
(fn active [fixture] (fixture.maps:get-active-map))
(fn morph! [fixture]
  (local morphs ((. (require :morphs/init) :Morphs) {}))
  ((require :morphs/string-entity-to-code-entity) morphs)
  (local node (assert (: (active fixture) :load-by-key source-key)))
  (morphs:apply node "code-entity" {:lifecycle fixture.service}))
(fn browser-child [fixture browser-key record key]
  (local graph-map (active fixture))
  (local browser (assert (graph-map:load-by-key browser-key)))
  (local ctx ((require :build-context) {:clickables app.clickables :hoverables app.hoverables
                                       :icons ((require :icons))}))
  (local view ((browser.view browser {}) ctx))
  (local (ok result) (pcall (fn submit []
    (view.search.submitted:emit [record record.id])
    (local child (assert (graph-map:lookup key)))
    (assert (= (child:resolve-reference-lifecycle!) fixture.service))
    child)))
  (view:drop)
  (if ok result (error result)))
(fn assert-map-key [record key]
  (same record.nodes [key "string-entity:a"])
  (same record.selected_node_keys [key]) (assert (= record.focused_node_key key))
  (same record.outline_root_keys [key])
  (same (. record.islands 1 :members) [key "string-entity:a"])
  (assert (= (. record.islands 1 :state :list-key) key))
  (assert (= (. record.edges 1 :source) key))
  (assert (= (. record.edges 1 :label) "authored")))
(fn assert-world-key [s id key]
  (local world (HomeWorld {:id id :dir (fs.join-path s.base-dir "worlds" id)}))
  (world:init {})
  (each [_ record (ipairs world.state.graph.maps)] (assert-map-key record key))
  (local item (. world.state.board.items 1))
  (assert (= item.id "subject")) (assert (= item.type "code-entity"))
  (H.assert-reference s.identity-store item.subject-key key)
  (each [_ field (ipairs [:position :rotation :size :state])]
    (same (. item field) (. (board-state) :items 1 field)))
  (same world.state.board.connectors (. (board-state) :connectors))
  (local metadata (json.loads (fs.read-file (metadata-path s id))))
  (same (. metadata.positions key) [11 12 0])
  (assert (= (. metadata.positions source-key) nil))
  (each [_ field (ipairs [:panels :extra_panels])]
    (assert (= (. metadata field 1 :node-key) key))
    (assert (= (. metadata field 1 :panel :node-key) key)))
  (assert (= metadata.provenance.text source-key)))
(fn cold-start [s]
  (local fresh (H.stores s.base-dir))
  (local composition (H.cold-lifecycle fresh))
  (composition.service:start!)
  (assert (= (composition.manager:active-world-id) nil))
  (each [_ entry (ipairs (composition.manager:list-reference-worlds))] (assert (= entry.world nil)))
  (values fresh composition))

;; Root actions intentionally use the actual canonical lazy stores, not patched
;; get-default functions. Package cache scoping is the established fixture idiom.
(fn selected-command [graph-map selected name]
  (local actions ((. (require :graph-activity-actions) :graph-root-actions)
                  {:graph {:graph-map graph-map :selected-nodes selected}}))
  (var chosen nil)
  (each [_ action (ipairs actions)] (when (= action.name name) (set chosen action)))
  ((. (assert chosen) :fn) nil nil))
(fn author-and-morph [fixture]
  (local s fixture.stores)
  (fixture.service:start!)
  (local graph-map (active fixture))
  (local a (assert (graph-map:lookup source-key)))
  (local b (assert (graph-map:lookup "string-entity:a")))
  (fn author []
    (selected-command graph-map [a b a] "Create List Entity")
    (selected-command graph-map [a b] "Create Link Entity")
    (selected-command graph-map [b a] "Create Link Entity"))
  (H.with-fields app {:graph-map graph-map :active-world-runtime fixture.world.runtime} author)
  (local authored (icollect [_ record (ipairs (s.list-store:list-entities))]
                    (when (not (= record.id "unopened")) record)))
  (local list-record (assert (. authored 1)))
  (assert (= (# list-record.items) 2))
  (local list-node (assert (graph-map:lookup (.. "list-entity:" list-record.id))))
  (list-node:add-item source-key)
  (assert (= (# list-record.items) 2) "selected raw plus node add must not duplicate")
  (s.identity-store:create-entity {:id "alias" :target-key source-key})
  (s.identity-store:create-entity {:id "upstream" :target-key "identity:alias"})
  (s.notebook-store:create-notebook {:id "cold-notebook" :items ["identity:upstream"]})
  (local result (morph! fixture))
  (assert (= result.code-entity (s.code-store:get-entity result.code-entity.id)))
  (assert (= result.code-entity.source source-text))
  (H.assert-reference s.identity-store (. list-record.items 1) result.code-key)
  (assert (= (s.identity-store:resolve-key "identity:upstream") result.code-key))
  (assert (= (. (s.identity-store:get-entity "upstream") :target-key) "identity:alias"))
  (assert (not (fixture.maps:get-instantiated-map "reserve")))
  (assert-map-key (. (fixture.maps:snapshot-reference-state) :maps 2) result.code-key)
  (local board (fixture.board:capture-state))
  (same (. board.items 1 :position) [11 12 0])
  (same board.connectors (. (board-state) :connectors))
  (assert (= (# (s.link-store:list-entities)) 2))
  (each [_ link (ipairs (s.link-store:list-entities))]
    (local endpoints [(s.identity-store:resolve-key link.source-key) (s.identity-store:resolve-key link.target-key)])
    (assert (or (= (. endpoints 1) result.code-key) (= (. endpoints 2) result.code-key))))
  (fixture.world:save-state)
  (local (fresh _cold) (cold-start s))
  (assert-world-key fresh "unopened" result.code-key)
  (fixture.maps:switch-map! "reserve")
  (assert (: (active fixture) :lookup result.code-key))
  (fixture.maps:switch-map! "main")
  (local node (assert (: (active fixture) :lookup result.code-key)))
  (node:delete-entity)
  (assert (= (# (s.link-store:list-entities)) 0))
  (assert (= (# (. (s.notebook-store:get-notebook "cold-notebook") :items)) 0))
  (assert (= (# list-record.items) 1))
  (assert (s.string-store:get-entity "a")))
(fn selected-authoring []
  (fn canonical [s] (seed s) (H.with-native-world s "loaded" author-and-morph))
  (fn rooted [root] (H.with-canonical-stores root canonical))
  (H.with-root rooted))
(table.insert tests {:name "reference lifecycle integration selected authoring morph delete retained and cold owners"
                     :fn selected-authoring})

(fn workflow-fixture [s]
  (s.code-store:create-entity {:id "retired" :source "retired"})
  (s.code-store:create-entity {:id "independent" :source "keep"})
  (each [_ id (ipairs ["one" "two"])]
    (s.workflow-store:create-definition
      {:id id :steps [{:id "a" :code-entity-id "retired"} {:id "b" :code-entity-id "retired"}
                      {:id "keep" :code-entity-id "independent"} {:id "other" :code-entity-id "independent"}]
       :edges [{:id "ab" :source-step-id "a" :target-step-id "b"}
               {:id "bk" :source-step-id "b" :target-step-id "keep"}
               {:id "keep" :source-step-id "keep" :target-step-id "other"}]}))
  (local run (s.workflow-store:create-run "one" {} {:snapshot {:key "code-entity:retired"}}))
  (s.workflow-store:upsert-run-step run.id "a" {:status :succeeded :result {:key "code-entity:retired"}})
  (s.workflow-store:append-event run.id {:kind :step-succeeded :step-id "a" :data {:key "code-entity:retired"}})
  (local second-run (s.workflow-store:create-run "two" {} {:snapshot {:key "code-entity:retired"}}))
  (s.workflow-store:upsert-run-step second-run.id "b" {:status :succeeded})
  (s.workflow-store:append-event second-run.id {:kind :step-succeeded :step-id "b"})
  (s.workflow-store:create-definition
    {:id "untouched" :steps [{:id "left" :code-entity-id "independent"} {:id "right" :code-entity-id "independent"}]
     :edges [{:id "untouched" :source-step-id "left" :target-step-id "right"}]})
  (s.list-store:create-entity {:id "steps" :items ["workflow-step:one:a" "workflow-step:two:b"]})
  {:run-path (fs.join-path s.workflow-store.runs-dir (.. run.id ".json"))
   :second-run-path (fs.join-path s.workflow-store.runs-dir (.. second-run.id ".json"))
   :untouched-path (. (s.workflow-store:snapshot-definition "untouched") :path)
   :code-path (. (s.code-store:snapshot-entity "independent") :path)})
(fn assert-workflows [s evidence]
  (assert (= (s.code-store:get-entity "retired") nil))
  (assert (= (fs.read-file evidence.run-path) evidence.run-bytes))
  (assert (= (fs.read-file evidence.code-path) evidence.code-bytes))
  (assert (= (fs.read-file evidence.second-run-path) evidence.second-run-bytes))
  (assert (= (fs.read-file evidence.untouched-path) evidence.untouched-bytes))
  (each [_ id (ipairs ["one" "two"])]
    (local definition (s.workflow-store:get-definition id))
    (same (icollect [_ step (ipairs definition.steps)] step.id) ["keep" "other"])
    (same (icollect [_ edge (ipairs definition.edges)] edge.id) ["keep"]))
  (assert (= (# (. (s.list-store:get-entity "steps") :items)) 0)))
(fn freeze-workflow [s]
  (local evidence (workflow-fixture s))
  (set evidence.run-bytes (fs.read-file evidence.run-path))
  (set evidence.code-bytes (fs.read-file evidence.code-path))
  (set evidence.second-run-bytes (fs.read-file evidence.second-run-path))
  (set evidence.untouched-bytes (fs.read-file evidence.untouched-path))
  evidence)
(add "code browser cascades definitions preserving history bytes" (fn workflow [fixture]
  (local s fixture.stores)
  (local evidence (freeze-workflow s))
  (fixture.service:start!)
  (local node (browser-child fixture "code-entity-list" (s.code-store:get-entity "retired") "code-entity:retired"))
  (node:delete-entity)
  (assert-workflows s evidence)
  (local (fresh _cold) (cold-start s))
  (assert-workflows fresh evidence)))

(add "container and identity browser actions preserve independent targets" (fn independent [fixture]
  (local s fixture.stores)
  (local bytes (. (s.string-store:snapshot-entity "a") :bytes))
  (local record (s.list-store:create-entity {:id "container" :items ["string-entity:a"]}))
  (s.notebook-store:create-notebook {:id "container-holder" :items ["list-entity:container"]})
  (s.identity-store:create-entity {:id "explicit" :target-key "string-entity:a"})
  (s.identity-store:create-entity {:id "up" :target-key "identity:explicit"})
  (s.dict-store:create-entity {:id "aliases" :items {:slot "identity:up"}})
  (fixture.service:start!)
  (: (browser-child fixture "list-entity-list" record "list-entity:container") :delete-entity)
  (assert (= (# (. (s.notebook-store:get-notebook "container-holder") :items)) 0))
  (local node (assert (: (active fixture) :load-by-key "identity:explicit")))
  (node:delete-entity)
  (assert (= (s.identity-store:get-entity "up") nil))
  (assert (= (next (. (s.dict-store:get-entity "aliases") :items)) nil))
  (assert (= (. (s.string-store:snapshot-entity "a") :bytes) bytes))
  (local (fresh _cold) (cold-start s))
  (assert (= (. (fresh.string-store:snapshot-entity "a") :bytes) bytes))))

;; The child has a fixed three-assertion roster and actually reopens native files
;; and adapters. A new object in the parent is not fresh-process evidence.
(fn reopen-main []
  (local root (assert (os.getenv "SPACE_REFERENCE_REOPEN_ROOT")))
  (local key (assert (os.getenv "SPACE_REFERENCE_REOPEN_KEY")))
  (local s (H.stores root))
  (local cold (H.cold-lifecycle s))
  (cold.service:start!)
  (assert (= (: (pending s) :read) nil))
  (assert (= (s.string-store:get-entity "s") nil))
  (assert (= (# (s.code-store:list-entities)) 1))
  (print "[CHILD PASS] pending replay and unique replacement")
  (assert-world-key s "unopened" key)
  (print "[CHILD PASS] unopened board map metadata after images")
  (fn activate [fixture]
    (fixture.service:start!)
    (assert (: (active fixture) :lookup key))
    (assert (not (: (active fixture) :lookup source-key)))
    (assert (= (. (fixture.board:capture-state) :items 1 :type) "code-entity")))
  (H.with-native-world s "loaded" activate)
  (print "[CHILD PASS] normal native activation without resurrected source")
  (print "[CHILD SUMMARY] 3/3"))
(fn reopen-process [s key]
  (local assets (assert (os.getenv "SPACE_ASSETS_PATH")))
  (local paths (.. assets "/lua/?.fnl;" assets "/lua/?/init.fnl"))
  (local executable ((. (require :tests.runtime-bin) :resolve)))
  (local result ((. (require :process) :run)
    {:args [executable "--no-dotenv" "-m" "tests.test-reference-lifecycle-integration:reopen-main"]
     :env {:SPACE_ASSETS_PATH assets :FENNEL_PATH paths :FENNEL_MACRO_PATH paths
           :SPACE_DISABLE_AUDIO "1" :SKIP_KEYRING_TESTS "1" :XDG_DATA_HOME (assert (os.getenv "XDG_DATA_HOME"))
           :SPACE_REFERENCE_REOPEN_ROOT s.base-dir :SPACE_REFERENCE_REOPEN_KEY key}
     :timeout 90}))
  (print (.. "[NATIVE REOPEN STATUS] " (tostring result.exit-code)))
  (assert (= result.exit-code 0) (.. "native reopen exit " (tostring result.exit-code) "\n"
                                   (or result.stdout "") (or result.stderr "")))
  (local roster ["pending replay and unique replacement" "unopened board map metadata after images"
                 "normal native activation without resurrected source"])
  (each [_ name (ipairs roster)]
    (assert (string.find result.stdout (.. "[CHILD PASS] " name) 1 true)))
  (assert (string.find result.stdout "[CHILD SUMMARY] 3/3" 1 true))
  (print result.stdout))
(add "metadata collision resumes in fresh native process" (fn collision [fixture]
  (local s fixture.stores)
  (fixture.service:start!)
  (local path (metadata-path s "unopened"))
  (local collision (.. path ".tmp"))
  (fs.create-dirs collision)
  (H.assert-error path #(morph! fixture))
  (local intent (assert (: (pending s) :read)))
  (assert (s.string-store:get-entity "s") "incoming failure must precede requested retirement")
  (assert (= (# (s.code-store:list-entities)) 1))
  (local unique {})
  (each [_ change (ipairs intent.changes)]
    (assert (not (. unique change.path))) (tset unique change.path true)
    (when (= change.owner "worlds")
      (assert (= change.after-check (R.check-bytes change.after-bytes change.format)))))
  (assert (> (# intent.runtime-state) 0))
  (each [_ capture (ipairs intent.runtime-state)] (assert (= capture.owner "runtime")))
  (fs.remove-all collision)
  (reopen-process s intent.operation.target-key)))

(add "source retirement restart preserves aggregated workflow ISO bytes" (fn retirement [fixture]
  (local s fixture.stores)
  (local evidence (freeze-workflow s))
  (fixture.service:start!)
  (local node (browser-child fixture "code-entity-list" (s.code-store:get-entity "retired") "code-entity:retired"))
  (local path (. (s.code-store:snapshot-entity "retired") :path))
  (H.with-fs-failure :remove path #(H.assert-error path #(node:delete-entity)))
  (local intent (assert (: (pending s) :read)))
  (local after {})
  (each [_ change (ipairs intent.changes)]
    (when (= change.owner "workflows")
      (local serialized (json.loads change.after-bytes))
      (assert (= (type serialized.updated-at) :string))
      (assert (string.find serialized.updated-at "T" 1 true))
      (assert (= (. (s.workflow-store:snapshot-definition serialized.id) :check) change.after-check))
      (tset after serialized.id {:bytes (fs.read-file change.path) :path change.path :check change.after-check})))
  (assert (= (# (. (s.list-store:get-entity "steps") :items)) 0))
  (local (fresh _cold) (cold-start s))
  (assert-workflows fresh evidence)
  (each [id record (pairs after)]
    (assert (= (fs.read-file record.path) record.bytes))
    (assert (= (. (fresh.workflow-store:snapshot-definition id) :check) record.check)))
  (assert (= (: (pending fresh) :read) nil))))

(fn conflict-diagnostics [message intent path]
  ;; The record path contains /worlds/: that spelling is not owner attribution.
  ;; Remove the exact known path without prescribing diagnostic punctuation.
  (local escaped-path (string.gsub path "(%W)" "%%%1"))
  (local without-path (string.gsub message escaped-path "<record-path>"))
  (fn operation-check []
    (assert (or (string.find message intent.operation-id 1 true)
                (and (string.find message intent.operation.kind 1 true)
                     (string.find message intent.operation.source-key 1 true)))
            "startup conflict must diagnose the pending operation, not only its path"))
  (fn owner-check []
    (assert (string.find without-path "worlds" 1 true)
            "startup conflict must diagnose the fixed owning domain outside the record path"))
  (local (operation-ok operation-error) (pcall operation-check))
  (local (owner-ok owner-error) (pcall owner-check))
  (print (.. "[CONFLICT DIAGNOSTIC] " (J.stable-json
    {:message message :message-without-record-path without-path
     :operation-id intent.operation-id :kind intent.operation.kind
     :source-key intent.operation.source-key :owner "worlds" :path path
     :operation-check {:passed operation-ok :failure (when (not operation-ok) (tostring operation-error))}
     :owner-check {:passed owner-ok :failure (when (not owner-ok) (tostring owner-error))}})))
  (assert operation-ok operation-error)
  (assert owner-ok owner-error))

(fn startup-read-failure [s cold intent path fail-at]
  (local tree (H.snapshot-tree s.base-dir))
  (local original fs.read-file)
  (var reads 0)
  (fn read [candidate ...]
    (when (= (fs.absolute candidate) (fs.absolute path))
      (set reads (+ reads 1))
      (when (= reads fail-at)
        (error (.. "injected permission denied: read-file " path))))
    (original candidate ...))
  (fn fail-read []
    (local message (H.assert-error "injected permission denied: read-file"
                     #(cold.service:start!)))
    (assert (string.find message path 1 true) "read failure must retain its original path")
    (when (= fail-at 2) (conflict-diagnostics message intent path)))
  ;; Count only start! reads, after setup/snapshots. The first is preflight;
  ;; the second is admitted pending validation. Never infer pending before read.
  (H.with-fields fs {:read-file read} fail-read)
  (assert (= reads fail-at) "startup fault must hit exactly its declared read boundary")
  (same tree (H.snapshot-tree s.base-dir))
  (same (: (pending s) :read) intent)
  (assert (= (cold.manager:active-world-id) nil))
  (assert (s.string-store:get-entity "s")))

(add "external metadata conflict blocks cold startup" (fn conflict [fixture]
  (local s fixture.stores)
  (fixture.service:start!)
  (local path (metadata-path s "unopened"))
  (H.with-fs-failure :write-file (.. path ".tmp") #(H.assert-error path #(morph! fixture)))
  (local intent (assert (: (pending s) :read)))
  (local before (fs.read-file path))
  (local edited (json.loads before)) (set edited.positions {:external:changed [9 9 9]})
  (J.write-json! path edited)
  (local tree (H.snapshot-tree s.base-dir))
  (local fresh (H.stores s.base-dir))
  (local cold (H.cold-lifecycle fresh))
  (startup-read-failure fresh cold intent path 1)
  (startup-read-failure fresh cold intent path 2)
  (local message (H.assert-error path #(cold.service:start!)))
  (assert (string.find message "pending conflict" 1 true))
  (assert (string.find message "world-metadata:unopened:reserve" 1 true))
  (conflict-diagnostics message intent path)
  (same tree (H.snapshot-tree s.base-dir))
  (assert (= (cold.manager:active-world-id) nil))
  (same (: (pending fresh) :read) intent)
  (fs.write-file path before)
  (cold.service:start!)
  (assert-world-key fresh "unopened" intent.operation.target-key)))

(add "runtime failure replays frozen namespaced captures" (fn runtime-replay [fixture]
  (local s fixture.stores)
  (fixture.service:start!)
  (fixture.graph:load-by-key source-key)
  (fn reject [event]
    (when (= (string.sub event.node.key 1 12) "code-entity:") (error "native runtime publication rejected")))
  (local handler (fixture.graph.node-added:connect reject))
  (local (ok failure) (pcall H.assert-error "native runtime publication rejected" #(morph! fixture)))
  (fixture.graph.node-added:disconnect handler true)
  (if (not ok) (error failure))
  (local intent (assert (: (pending s) :read)))
  (local frozen (J.stable-json intent.runtime-state))
  (local ids {})
  (each [_ capture (ipairs intent.runtime-state)]
    (assert (= capture.owner "runtime"))
    (local id (.. capture.owner "/" capture.world-id "/" (tostring capture.map-id)))
    (assert (not (. ids id))) (tset ids id true))
  (local preparation (fixture.runtime-owner:prepare (fixture.runtime-owner:inventory) intent.operation))
  (assert (= (# preparation.changes) 0))
  (assert (s.string-store:get-entity "s"))
  ;; Unsaved runtime changes after preparation cannot alter the frozen after-image.
  (fixture.board:update-item-subject "subject" "string-entity:a" "string-entity")
  (local result (morph! fixture))
  (assert (= result.code-key intent.operation.target-key))
  (assert (= (. (fixture.board:capture-state) :items 1 :state :marker) "authored"))
  (H.assert-reference s.identity-store (. (fixture.board:capture-state) :items 1 :subject-key) result.code-key)
  (assert (= (J.stable-json intent.runtime-state) frozen))
  (assert (= (# (s.code-store:list-entities)) 1))
  (assert (= (: (pending s) :read) nil))))

(add "empty roots drafts malformed records and real collisions" (fn invalid [fixture]
  (local s fixture.stores)
  (fixture.service:start!)
  (s.link-store:create-entity {:id "draft"})
  (local before (H.snapshot-tree s.base-dir))
  (H.assert-error "unsupported lifecycle target" #(fixture.service:delete! "fs:/tmp/not-owned"))
  (same before (H.snapshot-tree s.base-dir))
  (fixture.service:delete! "string-entity:missing")
  (assert (= (. (s.link-store:get-entity "draft") :source-key) ""))
  (local path (metadata-path s "unopened"))
  (local original (fs.read-file path))
  (fs.write-file path "{malformed")
  (H.assert-error path #(fixture.service:delete! source-key))
  (assert (s.string-store:get-entity "s"))
  (assert (= (: (pending s) :read) nil))
  (fs.write-file path original)
  (local collision (fs.join-path s.base-dir "reference-lifecycle" "pending.json.tmp"))
  (fs.create-dirs collision)
  (H.assert-error "pending.json" #(fixture.service:delete! source-key))
  (assert (s.string-store:get-entity "s"))
  (fs.remove-all collision)
  (fixture.service:delete! source-key)
  (fn empty [root]
    (local blank (H.stores root))
    (local cold (H.cold-lifecycle blank))
    (cold.service:start!)
    (local tree (H.snapshot-tree root))
    (cold.service:start!) (same tree (H.snapshot-tree root)))
  (H.with-root empty)))

(add "ordinary map remove and clear preserve authored domain bytes" (fn presentation [fixture]
  (local s fixture.stores)
  (freeze-workflow s)
  (s.dict-store:create-entity {:id "dict" :items {:slot source-key}})
  (s.notebook-store:create-notebook {:id "notebook" :items [source-key]})
  (s.link-store:create-entity {:id "link" :source-key source-key :target-key "string-entity:a"})
  (fixture.service:start!)
  (local graph-map (active fixture))
  (each [_ key (ipairs ["list-entity:unopened" "dict-entity:dict" "notebook:notebook"])]
    (graph-map:load-by-key key))
  (local tree (H.snapshot-tree s.base-dir))
  (graph-map:remove-nodes [(assert (graph-map:lookup source-key))])
  (same tree (H.snapshot-tree s.base-dir))
  (graph-map:clear!)
  (same tree (H.snapshot-tree s.base-dir))
  (local (fresh _cold) (cold-start s))
  (assert (fresh.string-store:get-entity "s"))
  (assert (= (# (. (fresh.list-store:get-entity "unopened") :items)) 2))))

{:tests tests :reopen-main reopen-main}
