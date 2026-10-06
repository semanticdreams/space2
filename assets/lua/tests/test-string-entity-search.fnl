(local fs (require :fs))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "string-entity-search"))

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

(table.insert tests {:name "backend passes literal ignore-case ripgrep options"
                     :fn backend-passes-ripgrep-options})
(table.insert tests {:name "backend blank query does not invoke ripgrep"
                     :fn backend-blank-query-does-not-invoke-ripgrep})
(table.insert tests {:name "backend dedupes multiple matches per entity"
                     :fn backend-dedupes-multiple-matches-per-entity})
(table.insert tests {:name "backend ignores non-entity matches"
                     :fn backend-ignores-non-entity-matches})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "string-entity-search" :tests tests})))

{:name "string-entity-search"
 :tests tests
 :main main}
