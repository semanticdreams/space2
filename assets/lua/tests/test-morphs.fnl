(local fs (require :fs))
(local Graph (require :graph/init))

(local tests [])

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "morphs"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "morphs-" (os.time) "-" temp-counter)))

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

(fn make-morphs []
  (local Morphs (require :morphs/init))
  (local register-string->code (require :morphs/string-entity-to-code-entity))
  (local morphs (Morphs.Morphs {}))
  (register-string->code morphs)
  morphs)

(fn morphs-register-string-to-code-target []
  (local morphs (make-morphs))
  (local items (morphs:target-items {:key "string-entity:abc"}))
  (assert (= (length items) 1) "string-entity should expose one morph target")
  (assert (= (. items 1 1 :to-scheme) "code-entity")
          "target should be code-entity"))

(fn morphs-string-to-code-updates-identity-and-graph []
  (with-temp-dir
    (fn [root]
      (local morphs (make-morphs))
      (local H (require :tests/test-reference-lifecycle-helpers))
      (local stores (H.stores root))
      (local string-store stores.string-store)
      (local code-store stores.code-store)
      (local identity-store stores.identity-store)
      (local source-entity (string-store:create-entity {:id "s1"
                                                        :value "(+ 1 2)"}))
      (local source-key (.. "string-entity:" source-entity.id))
      (local identity (identity-store:create-entity {:id "id-s1"
                                                     :target-key source-key}))
      (local lifecycle (H.ready stores))
      (local graph (Graph {:with-start false :lifecycle lifecycle
                            :string-store string-store :link-store stores.link-store
                           :identity-store identity-store
                           :morphs morphs}))
      (local {:register-loader register-string-loader} (require :graph/nodes/string-entity))
      (local {:register-loader register-code-loader} (require :graph/nodes/code-entity))
      (register-string-loader graph {:store string-store :lifecycle lifecycle})
      (register-code-loader graph {:store code-store :lifecycle lifecycle})
      (local source-node (graph:load-by-key source-key))
      (assert source-node "source node should load before morph")

      (local result
        (morphs:apply source-node "code-entity" {:lifecycle lifecycle}))

      (local code-key (and result result.code-key))
      (assert code-key "morph should return code key")
      (assert (= (string.sub code-key 1 12) "code-entity:")
              "result code key should be code-entity key")
      (assert (= (string-store:get-entity source-entity.id) nil)
              "source string entity should be deleted")
      (local codes (code-store:list-entities))
      (assert (= (length codes) 1) "code entity should be created")
      (assert (= (. codes 1 :source) "(+ 1 2)") "string value should become code source")
      (assert (= (. codes 1 :language) "fnl") "code language should default to fnl")
      (assert (= (. codes 1 :name) "") "code name should default to empty")
      (local identity-updated (identity-store:get-entity identity.id))
      (assert (= identity-updated.target-key code-key)
              "identity target key should update to morphed code key")
      (assert (= (graph:lookup source-key) nil)
              "old source node should be removed from graph")
      (assert (graph:lookup code-key)
              "new code node should be present in graph")

      (graph:drop))))

(fn morph-view-loads []
  (local MorphView (require :morph-view))
  (assert MorphView "MorphView should load")
  (assert (= (type MorphView) "function") "MorphView should be a function"))

(table.insert tests {:name "morphs register string-entity to code-entity target"
                     :fn morphs-register-string-to-code-target})
(table.insert tests {:name "morph string-entity to code-entity updates identity and graph"
                     :fn morphs-string-to-code-updates-identity-and-graph})
(table.insert tests {:name "morph view loads"
                     :fn morph-view-loads})

tests
