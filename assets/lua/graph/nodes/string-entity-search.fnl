(local glm (require :glm))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local Signal (require :signal))
(local StringEntityStore (require :entities/string))
(local StringSearch (require :entities/string-search))

(local GREEN (glm.vec4 0.15 0.35 0.2 1))
(local GREEN_ACCENT (glm.vec4 0.2 0.45 0.25 1))
(local KEY "string-entity-search")

(fn resolve-options [opts]
  (if opts opts {}))

(fn payload-results [payload]
  (if (and payload payload.results)
      payload.results
      []))

(fn result-count [payload]
  (length (payload-results payload)))

(fn status-for-result [payload]
  (if (not (and payload payload.ok))
      "Search failed"
      (= (result-count payload) 1)
      "Found 1 result"
      (string.format "Found %d results" (result-count payload))))

(fn cancel-token [token]
  (when (and token token.cancel)
    (token:cancel {:suppress-callback true})))

(fn make-search-callback [node seq]
  (fn [payload]
    (when (= seq node.search-seq)
      (set node.results (payload-results payload))
      (set node.status (status-for-result payload))
      (node.results-changed:emit node.results)
      (node.status-changed:emit node.status))))

(fn resolve-store [options]
  (if options.store
      options.store
      (StringEntityStore.get-default)))

(fn resolve-backend [options store]
  (if options.backend
      options.backend
      (StringSearch.RipgrepStringEntitySearchBackend {:store store})))

(fn StringEntitySearchNode [opts]
  (local options (resolve-options opts))
  (local store (resolve-store options))
  (local backend (resolve-backend options store))
  (local StringEntitySearchNodeView (require :graph/view/views/string-entity-search))
  (local node (GraphNode {:key KEY
                          :label "string entity text search"
                          :color GREEN
                          :sub-color GREEN_ACCENT
                          :size 8.0
                          :view StringEntitySearchNodeView}))
  (set node.store store)
  (set node.backend backend)
  (set node.query "")
  (set node.results [])
  (set node.status "Enter text to search string entities")
  (set node.results-changed (Signal))
  (set node.status-changed (Signal))
  (set node.search-token nil)
  (set node.search-seq 0)
  (set node.search-text
       (fn [self query]
         (set self.search-seq (+ self.search-seq 1))
         (local seq self.search-seq)
         (cancel-token self.search-token)
         (set self.query (if query query ""))
         (set self.status "Searching...")
         (self.status-changed:emit self.status)
         (set self.search-token
              (self.backend:search-text self.query (make-search-callback self seq)))
         self.search-token))
  (set node.clear-results
       (fn [self]
         (set self.search-seq (+ self.search-seq 1))
         (cancel-token self.search-token)
         (set self.search-token nil)
         (set self.results [])
         (set self.status "Enter text to search string entities")
         (self.results-changed:emit self.results)
         (self.status-changed:emit self.status)))
  (set node.open-result
       (fn [self result]
         (local entity-id (assert (and result result.entity-id)
                                  "StringEntitySearchNode.open-result requires entity-id"))
         (local graph-map (assert self.graph
                                  "StringEntitySearchNode.open-result requires mounted GraphMap"))
         (assert graph-map.load-by-key
                 "StringEntitySearchNode.open-result requires GraphMap:load-by-key")
         (local loaded (graph-map:load-by-key (.. "string-entity:" entity-id)))
         (assert loaded
                 (.. "StringEntitySearchNode.open-result failed to load string-entity:" entity-id))
         loaded))
  (set node.drop
       (fn [self]
         (cancel-token self.search-token)
         (set self.search-token nil)
         (self.results-changed:clear)
         (self.status-changed:clear)))
  node)

(fn register-loader [graph opts]
  (local options (resolve-options opts))
  (local store (resolve-store options))
  (graph:register-key-loader KEY
    (fn [key]
      (when (= key KEY)
        (StringEntitySearchNode {:store store})))))

{:StringEntitySearchNode StringEntitySearchNode
 :register-loader register-loader
 :key KEY}
