(local fs (require :fs))
(local BuildContext (require :build-context))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "string-entity-search"))

(fn make-icons-stub []
  {:resolve (fn [_self _name]
              nil)})

(fn make-ctx []
  (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                 :hoverables (assert app.hoverables "test requires app.hoverables")
                 :icons (make-icons-stub)}))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "search-" (os.time) "-" temp-counter)))

(fn with-temp-store [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local StringEntityStore (require :entities/string))
  (local store (StringEntityStore.StringEntityStore {:base-dir dir}))
  (local (ok result) (pcall f store dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn fake-ripgrep [matches]
  (local state {:calls []})
  (fn cancel-token [_self _opts]
    (set state.cancelled true))
  (fn search-async [opts callback]
    (table.insert state.calls opts)
    (callback {:ok true :query opts.query :matches matches :stderr ""})
    {:cancel cancel-token})
  (set state.search-async
       search-async)
  state)

(fn capture-payload [seen payload]
  (table.insert seen payload))

(fn fake-token-cancel [token _opts]
  (set token.owner.cancelled true))

(fn fake-backend-search-text [self query callback]
  (table.insert self.calls query)
  (callback {:ok true
             :query query
             :results [{:entity-id "alpha"
                        :entity {:id "alpha" :value "Alpha"}
                        :matches []
                        :match-count 0}]})
  {:owner self :cancel fake-token-cancel})

(fn fake-backend []
  {:calls []
   :search-text fake-backend-search-text})

(fn controllable-token-cancel [self _opts]
  (set self.cancelled true))

(fn controllable-backend-search-text [self query callback]
  (table.insert self.callbacks {:query query :callback callback})
  (local token {:cancelled false
                :cancel controllable-token-cancel})
  (table.insert self.tokens token)
  token)

(fn controllable-backend []
  {:callbacks []
   :tokens []
   :search-text controllable-backend-search-text})

(fn nil-get-entity [] nil)

(fn fake-node-store []
  {:entities-dir "/tmp/entities" :get-entity nil-get-entity})

(fn capture-emitted-results [holder results]
  (set holder.results results))

(fn fake-search-node-for-view []
  (local Signal (require :signal))
  {:results []
   :status "Ready"
   :results-changed (Signal)
   :status-changed (Signal)
   :searched []
   :opened []
   :search-text (fn [self query] (table.insert self.searched query))
   :open-result (fn [self result]
                  (table.insert self.opened result)
                  {:key (.. "string-entity:" result.entity-id)})})

(fn state-contains-string? [value needle seen]
  (if (= (type value) :string)
      (not (= (string.find value needle 1 true) nil))
      (= (type value) :table)
      (if (rawget seen value)
          false
          (do
            (tset seen value true)
            (var found false)
            (each [k v (pairs value) &until found]
              (when (if (state-contains-string? k needle seen)
                        true
                        (state-contains-string? v needle seen))
                (set found true)))
            found))
      false))

(fn assert-state-omits-string [state needle]
  (assert (= (state-contains-string? state needle {}) false)))

(fn fake-load-by-key [self key]
  (table.insert self.loaded key)
  {:key key})

(fn exercise-backend-passes-ripgrep-options [store _root]
  (local entity (store:create-entity {:id "alpha" :value "Needle text"}))
  (local path (fs.join-path store.entities-dir (.. entity.id ".md")))
  (local rg (fake-ripgrep [{:path path :line 5 :column 1 :text "Needle text"}]))
  (local Search (require :entities/string-search))
  (local backend (Search.RipgrepStringEntitySearchBackend {:store store :ripgrep rg}))
  (local seen [])
  (backend:search-text "Needle" (fn [payload] (capture-payload seen payload)))
  (local opts (. rg.calls 1))
  (assert opts "ripgrep should be invoked")
  (assert (= opts.query "Needle"))
  (assert (= opts.literal true))
  (assert (= opts.case :ignore))
  (assert (= (. opts.paths 1) store.entities-dir))
  (assert (= (. opts.globs 1) "*.md"))
  (assert (= (length (. (. seen 1) :results)) 1)))

(fn backend-passes-ripgrep-options []
  (with-temp-store exercise-backend-passes-ripgrep-options))

(fn exercise-backend-blank-query-does-not-invoke-ripgrep [store _root]
  (local rg (fake-ripgrep []))
  (local Search (require :entities/string-search))
  (local backend (Search.RipgrepStringEntitySearchBackend {:store store :ripgrep rg}))
  (local seen [])
  (local token (backend:search-text "  " (fn [payload] (capture-payload seen payload))))
  (local payload (. seen 1))
  (assert (= token nil))
  (assert (= (length rg.calls) 0))
  (assert payload)
  (assert (= payload.ok true))
  (assert (= (length payload.results) 0)))

(fn backend-blank-query-does-not-invoke-ripgrep []
  (with-temp-store exercise-backend-blank-query-does-not-invoke-ripgrep))

(fn exercise-backend-dedupes-multiple-matches-per-entity [store _root]
  (local entity (store:create-entity {:id "dupe" :value "needle\nneedle"}))
  (local path (fs.join-path store.entities-dir (.. entity.id ".md")))
  (local rg (fake-ripgrep [{:path path :line 5 :column 1 :text "needle"}
                           {:path path :line 6 :column 1 :text "needle again"}]))
  (local Search (require :entities/string-search))
  (local backend (Search.RipgrepStringEntitySearchBackend {:store store :ripgrep rg}))
  (local seen [])
  (backend:search-text "needle" (fn [payload] (capture-payload seen payload)))
  (local payload (. seen 1))
  (assert (= (length payload.results) 1))
  (assert (= (. (. payload.results 1) :entity-id) "dupe"))
  (assert (= (. (. payload.results 1) :match-count) 2)))

(fn backend-dedupes-multiple-matches-per-entity []
  (with-temp-store exercise-backend-dedupes-multiple-matches-per-entity))

(fn exercise-backend-ignores-non-entity-matches [store root]
  (store:create-entity {:id "kept" :value "needle"})
  (local kept-path (fs.join-path store.entities-dir "kept.md"))
  (local other-path (fs.join-path root "outside.md"))
  (local txt-path (fs.join-path store.entities-dir "note.txt"))
  (local missing-path (fs.join-path store.entities-dir "missing.md"))
  (local rg (fake-ripgrep [{:path kept-path :line 5 :column 1 :text "needle"}
                           {:path other-path :line 1 :column 1 :text "needle"}
                           {:path txt-path :line 1 :column 1 :text "needle"}
                           {:path missing-path :line 1 :column 1 :text "needle"}]))
  (local Search (require :entities/string-search))
  (local backend (Search.RipgrepStringEntitySearchBackend {:store store :ripgrep rg}))
  (local seen [])
  (backend:search-text "needle" (fn [payload] (capture-payload seen payload)))
  (local payload (. seen 1))
  (assert (= (length payload.results) 1))
  (assert (= (. (. payload.results 1) :entity-id) "kept")))

(fn backend-ignores-non-entity-matches []
  (with-temp-store exercise-backend-ignores-non-entity-matches))

(fn search-node-creates-with-exact-key []
  (local {:StringEntitySearchNode StringEntitySearchNode} (require :graph/nodes/string-entity-search))
  (local node (StringEntitySearchNode {:store (fake-node-store)
                                       :backend (fake-backend)}))
  (assert (= node.key "string-entity-search"))
  (assert (= node.label "string entity text search"))
  (assert (= (type node.view) "function"))
  (assert node.results-changed)
  (assert node.status-changed)
  (node:drop))

(fn search-node-delegates-and-emits-results []
  (local {:StringEntitySearchNode StringEntitySearchNode} (require :graph/nodes/string-entity-search))
  (local backend (fake-backend))
  (local node (StringEntitySearchNode {:store (fake-node-store)
                                       :backend backend}))
  (local emitted {:results nil})
  (node.results-changed:connect (fn [results] (capture-emitted-results emitted results)))
  (node:search-text "Alpha")
  (assert (= (. backend.calls 1) "Alpha"))
  (assert (= node.status "Found 1 result"))
  (assert (= (length emitted.results) 1))
  (node:drop))

(fn search-node-cancels-previous-token []
  (local {:StringEntitySearchNode StringEntitySearchNode} (require :graph/nodes/string-entity-search))
  (local backend (controllable-backend))
  (local node (StringEntitySearchNode {:store (fake-node-store)
                                       :backend backend}))
  (node:search-text "one")
  (node:search-text "two")
  (assert (= (. (. backend.tokens 1) :cancelled) true))
  (node:drop))

(fn search-node-ignores-stale-callbacks []
  (local {:StringEntitySearchNode StringEntitySearchNode} (require :graph/nodes/string-entity-search))
  (local backend (controllable-backend))
  (local node (StringEntitySearchNode {:store (fake-node-store)
                                       :backend backend}))
  (node:search-text "old")
  (node:search-text "new")
  ((. (. backend.callbacks 1) :callback) {:ok true :query "old" :results [{:entity-id "old"}]})
  ((. (. backend.callbacks 2) :callback) {:ok true :query "new" :results [{:entity-id "new"}]})
  (assert (= (. (. node.results 1) :entity-id) "new"))
  (node:drop))

(fn search-node-clear-results-ignores-pending-callback []
  (local {:StringEntitySearchNode StringEntitySearchNode} (require :graph/nodes/string-entity-search))
  (local backend (controllable-backend))
  (local node (StringEntitySearchNode {:store (fake-node-store)
                                       :backend backend}))
  (node:search-text "before clear")
  (node:clear-results)
  ((. (. backend.callbacks 1) :callback) {:ok true
                                          :query "before clear"
                                          :results [{:entity-id "stale-after-clear"}]})
  (assert (= (length node.results) 0))
  (assert (= node.status "Enter text to search string entities"))
  (assert (= (. (. backend.tokens 1) :cancelled) true))
  (node:drop))

(fn search-node-open-result-loads-string-entity-key []
  (local {:StringEntitySearchNode StringEntitySearchNode} (require :graph/nodes/string-entity-search))
  (local loaded [])
  (local graph-map {:loaded loaded :load-by-key fake-load-by-key})
  (local node (StringEntitySearchNode {:store (fake-node-store)
                                       :backend (fake-backend)}))
  (set node.graph graph-map)
  (local result (node:open-result {:entity-id "abc"}))
  (assert (= result.key "string-entity:abc"))
  (assert (= (. loaded 1) "string-entity:abc"))
  (node:drop))

(fn search-node-capture-state-omits-query-text []
  (local Graph (require :graph/core))
  (local {:GraphMap GraphMap} (require :graph/map))
  (local {:StringEntitySearchNode StringEntitySearchNode :register-loader register-loader} (require :graph/nodes/string-entity-search))
  (local graph (Graph {}))
  (register-loader graph {:store (fake-node-store)})
  (local graph-map (GraphMap {:id "test-map" :name "test" :graph graph}))
  (local node (StringEntitySearchNode {:store (fake-node-store)
                                       :backend (controllable-backend)}))
  (graph-map:add-node node)
  (node:search-text "secret query")
  ((. (. node.backend.callbacks 1) :callback) {:ok true
                                               :query "secret query"
                                               :results [{:entity-id "runtime-only-result"
                                                          :entity {:id "runtime-only-result"
                                                                   :value "distinct persisted leak"}}]})
  (local state (graph-map:capture-state))
  (assert-state-omits-string state "secret query")
  (assert-state-omits-string state "runtime-only-result")
  (assert-state-omits-string state "distinct persisted leak")
  (graph-map:drop))

(fn search-node-view-click-search-submits-input []
  (local View (require :graph/view/views/string-entity-search))
  (local node (fake-search-node-for-view))
  (local view ((View node) (make-ctx)))
  (view.input:set-text "needle")
  (view.search-button:on-click {:button 1})
  (assert (= (. node.searched 1) "needle"))
  (view:drop))

(fn search-node-view-refreshes-results-and-opens-row []
  (local View (require :graph/view/views/string-entity-search))
  (local node (fake-search-node-for-view))
  (local view ((View node) (make-ctx)))
  (local result {:entity-id "abc" :entity {:value "Alpha body"} :matches [{:text "Alpha body"}] :match-count 1})
  (node.results-changed:emit [result])
  (assert (= (length view.results-list.items) 1))
  (local row-builder view.results-list.builder)
  (local row (row-builder [result "Alpha body"] (make-ctx)))
  (row:on-click {:button 1})
  (assert (= (. (. node.opened 1) :entity-id) "abc"))
  (row:drop)
  (view:drop))

(table.insert tests {:name "backend passes literal ignore-case ripgrep options"
                     :fn backend-passes-ripgrep-options})
(table.insert tests {:name "backend blank query does not invoke ripgrep"
                     :fn backend-blank-query-does-not-invoke-ripgrep})
(table.insert tests {:name "backend dedupes multiple matches per entity"
                     :fn backend-dedupes-multiple-matches-per-entity})
(table.insert tests {:name "backend ignores non-entity matches"
                      :fn backend-ignores-non-entity-matches})
(table.insert tests {:name "search node creates with exact key"
                     :fn search-node-creates-with-exact-key})
(table.insert tests {:name "search node delegates and emits results"
                     :fn search-node-delegates-and-emits-results})
(table.insert tests {:name "search node cancels previous token"
                     :fn search-node-cancels-previous-token})
(table.insert tests {:name "search node ignores stale callbacks"
                      :fn search-node-ignores-stale-callbacks})
(table.insert tests {:name "search node clear results ignores pending callback"
                     :fn search-node-clear-results-ignores-pending-callback})
(table.insert tests {:name "search node open result loads string entity key"
                     :fn search-node-open-result-loads-string-entity-key})
(table.insert tests {:name "search node capture state omits query text"
                      :fn search-node-capture-state-omits-query-text})
(table.insert tests {:name "search node view click Search submits input"
                     :fn search-node-view-click-search-submits-input})
(table.insert tests {:name "search node view refreshes results and opens row"
                     :fn search-node-view-refreshes-results-and-opens-row})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "string-entity-search" :tests tests})))

{:name "string-entity-search"
 :tests tests
 :main main}
