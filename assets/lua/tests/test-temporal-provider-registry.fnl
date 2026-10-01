(local Temporal (require :temporal))
(local create-provider-registry (require :temporal/provider-registry))

(local tests [])

(fn assert= [actual expected message]
  (when (not (= actual expected))
    (error (or message (.. "expected " (tostring expected) ", got " (tostring actual))))))

(fn assert-error [f expected]
  (local (ok err) (pcall f))
  (when ok
    (error (.. "expected error containing: " expected)))
  (when (not (string.find (tostring err) expected 1 true))
    (error (.. "expected error containing " expected ", got " (tostring err)))))

(fn assert-empty [items message]
  (assert= (length items) 0 message))

(fn sample-provider [id priority]
  {:id id
   :version "1.0"
   :priority priority
   :capabilities [:natural]
   :parse (fn [text _context]
            [{:kind :sample :text text}])})

(fn formatting-provider [id]
  {:id id
   :version "1.0"
   :capabilities [:localized-format]
   :format (fn [_value _context]
             "formatted")})

(fn noop-parse [_text _context]
  [])

(fn facade-exports-providers []
  (assert (= (type Temporal.providers) :table) "Temporal.providers should be exported")
  (assert (= (type Temporal.providers.register) :function) "Temporal.providers.register should be exported")
  (assert (= (type Temporal.providers.unregister) :function) "Temporal.providers.unregister should be exported")
  (assert (= (type Temporal.providers.list) :function) "Temporal.providers.list should be exported")
  (assert (= (type Temporal.providers.all) :function) "Temporal.providers.all should be exported")
  (assert (= (type Temporal.providers.parse) :function) "Temporal.providers.parse should be exported")
  (assert (= (type Temporal.providers.business-calendar) :function)
          "Temporal.providers.business-calendar should be exported"))

(fn orders-providers []
  (local registry (create-provider-registry {}))
  (registry.register (sample-provider "later" 20))
  (registry.register (sample-provider "alpha" 10))
  (registry.register (sample-provider "beta" 10))
  (local listed (registry.list :natural))
  (assert= (. listed 1 :id) "alpha")
  (assert= (. listed 2 :id) "beta")
  (assert= (. listed 3 :id) "later"))

(fn rejects-duplicate-provider-ids []
  (local registry (create-provider-registry {}))
  (registry.register (sample-provider "duplicate" 10))
  (assert-error #(registry.register (sample-provider "duplicate" 20))
                "duplicate temporal provider id"))

(fn rejects-invalid-manifests []
  (local registry (create-provider-registry {}))
  (assert-error #(registry.register nil) "temporal provider must be a table")
  (assert-error #(registry.register {:id "" :version "1.0" :capabilities [:natural] :parse noop-parse})
                "temporal provider id must be a non-empty string")
  (assert-error #(registry.register {:id "empty-version" :version "" :capabilities [:natural] :parse noop-parse})
                "temporal provider version must be a non-empty string")
  (assert-error #(registry.register {:id "empty-capabilities" :version "1.0" :capabilities [] :parse noop-parse})
                "temporal provider capabilities must not be empty")
  (local sparse-capabilities [:natural])
  (tset sparse-capabilities 3 :calendar)
  (assert-error #(registry.register {:id "sparse-capabilities" :version "1.0" :capabilities sparse-capabilities :parse noop-parse})
                "temporal provider capabilities must be a sequential array")
  (assert-error #(registry.register {:id "hash-capabilities" :version "1.0" :capabilities {:natural true} :parse noop-parse})
                "temporal provider capabilities must be a sequential array")
  (assert-error #(registry.register {:id "non-keyword-capability" :version "1.0" :capabilities [42] :parse noop-parse})
                "temporal provider capability must be a keyword")
  (assert-error #(registry.register {:id "duplicate-capability" :version "1.0" :capabilities [:natural :natural] :parse noop-parse})
                "duplicate temporal provider capability")
  (assert-error #(registry.register {:id "unknown-key" :version "1.0" :capabilities [:natural] :parse noop-parse :legacy true})
                 "invalid temporal provider key")
  (assert-error #(registry.register {:id "bad-parse-type" :version "1.0" :capabilities [:natural] :parse "parse" :format noop-parse})
                "temporal provider parse must be a function")
  (assert-error #(registry.register {:id "bad-format-type" :version "1.0" :capabilities [:natural] :parse noop-parse :format {}})
                "temporal provider format must be a function")
  (assert-error #(registry.register {:id "bad-calendar-type" :version "1.0" :capabilities [:natural] :parse noop-parse :calendar 42})
                "temporal provider calendar must be a function or table")
  (assert-error #(registry.register {:id "bad-business-calendar-type" :version "1.0" :capabilities [:natural] :parse noop-parse :business-calendar "business"})
                "temporal provider business-calendar must be a function or table")
  (assert-error #(registry.register {:id "no-operation" :version "1.0" :capabilities [:natural]})
                 "temporal provider requires an operational field"))

(fn unregister-handles []
  (local registry (create-provider-registry {}))
  (local handle (registry.register (sample-provider "temporary" 10)))
  (assert= handle.registry nil "handle should not expose registry state")
  (assert= (length (registry.all)) 1)
  (assert= (registry.unregister handle) true)
  (assert-empty (registry.all) "provider should be removed")
  (assert= (registry.unregister handle) false)
  (assert-error #(registry.unregister {:kind :temporal-provider-handle :id "temporary" :active? true})
                "invalid temporal provider handle")
  (assert-error #(registry.unregister {:id "temporary"})
                "invalid temporal provider handle"))

(fn summaries-are-defensive []
  (local registry (create-provider-registry {}))
  (registry.register (sample-provider "stable" 10))
  (local first-list (registry.list :natural))
  (tset (. first-list 1 :capabilities) 1 :mutated)
  (tset (. first-list 1) :id "changed")
  (local second-list (registry.list :natural))
  (assert= (. second-list 1 :id) "stable")
  (assert= (. second-list 1 :capabilities 1) :natural))

(fn parse-returns-empty-when-no-providers-match []
  (local registry (create-provider-registry {}))
  (assert-empty (registry.parse "tomorrow" {}) "empty registry should not parse")
  (registry.register (formatting-provider "formatter"))
  (assert-empty (registry.parse "tomorrow" {}) "non-natural provider should not parse"))

(fn later-parse [text context]
  [{:kind :later :text text :context-marker context.marker}])

(fn alpha-parse [_text _context]
  [{:kind :alpha}
   {:kind :preserved :provider-id "custom"}])

(fn nil-parse [_text _context]
  nil)

(fn parse-composes-candidates []
  (local registry (create-provider-registry {}))
  (registry.register {:id "later" :version "1.0" :priority 20 :capabilities [:natural] :parse later-parse})
  (registry.register {:id "alpha" :version "1.0" :priority 10 :capabilities [:natural] :parse alpha-parse})
  (registry.register {:id "beta" :version "1.0" :priority 10 :capabilities [:natural] :parse nil-parse})
  (local candidates (registry.parse "next week" {:marker :seen}))
  (assert= (length candidates) 3)
  (assert= (. candidates 1 :kind) :alpha)
  (assert= (. candidates 1 :provider-id) "alpha")
  (assert= (. candidates 2 :kind) :preserved)
  (assert= (. candidates 2 :provider-id) "custom")
  (assert= (. candidates 3 :kind) :later)
  (assert= (. candidates 3 :provider-id) "later")
  (assert= (. candidates 3 :text) "next week")
  (assert= (. candidates 3 :context-marker) :seen))

(fn bad-parse [_text _context]
  (error "boom"))

(fn parse-prefixes-provider-failures []
  (local registry (create-provider-registry {}))
  (registry.register {:id "bad" :version "1.0" :capabilities [:natural] :parse bad-parse})
  (assert-error #(registry.parse "tomorrow" {})
                "temporal provider bad parse failed:"))

(fn parse-rejects-invalid-result-shapes []
  (local sparse-results [{:kind :first}])
  (tset sparse-results 3 {:kind :third})
  (local sparse-registry (create-provider-registry {}))
  (sparse-registry.register {:id "sparse" :version "1.0" :capabilities [:natural]
                             :parse (fn [_text _context] sparse-results)})
  (assert-error #(sparse-registry.parse "tomorrow" {})
                "temporal provider parse result must be a sequential array")
  (local hash-registry (create-provider-registry {}))
  (hash-registry.register {:id "hash" :version "1.0" :capabilities [:natural]
                           :parse (fn [_text _context] {:candidate {:kind :hash}})})
  (assert-error #(hash-registry.parse "tomorrow" {})
                "temporal provider parse result must be a sequential array"))

(fn default-natural-provider-parses-today []
  (local candidates (Temporal.providers.parse "today" {:locale "en-US"}))
  (assert (> (# candidates) 0) "default natural provider should return candidates for today")
  (assert= (. candidates 1 :provider-id) "space.temporal.natural-seed")
  (assert= (. candidates 1 :kind) :natural-candidate)
  (assert= (. candidates 1 :locale) "en-US"))

(fn candidate-signature [candidate]
  [candidate.provider-id candidate.locale candidate.phrase-id candidate.family candidate.rank])

(fn default-natural-provider-order-is-deterministic []
  (local first (Temporal.providers.parse "Tuesday" {:locale "en-US"}))
  (local second (Temporal.providers.parse "Tuesday" {:locale "en-US"}))
  (assert= (# first) (# second))
  (each [index candidate (ipairs first)]
    (local expected (candidate-signature (. second index)))
    (local actual (candidate-signature candidate))
    (each [field value (ipairs actual)]
      (assert= value (. expected field)))))

(fn default-natural-provider-returns-empty-for-unsupported-text []
  (local (ok candidates) (pcall Temporal.providers.parse "not a temporal phrase" {:locale "en-US"}))
  (assert ok (.. "provider parse should not throw for unsupported natural text: " (tostring candidates)))
  (assert-empty candidates "unsupported natural text should return no provider candidates"))

(fn function-provider-business-calendar [operation request]
  {:operation operation
   :jurisdiction request.jurisdiction})

(fn table-provider-is-business-day [request]
  {:plain request.plain
   :business? true})

(fn later-business-calendar [_operation _request]
  {:provider-id "later"})

(fn beta-business-calendar [_operation _request]
  {:provider-id "beta"})

(fn alpha-business-calendar [_operation _request]
  {:provider-id "alpha"})

(fn bad-business-calendar [_operation _request]
  (error "boom"))

(fn missing-is-business-day [_request]
  true)

(fn business-calendar-function-provider-dispatches []
  (local registry (create-provider-registry {}))
  (registry.register {:id "function-provider"
                      :version "1.0"
                      :capabilities [:business-calendar]
                      :business-calendar function-provider-business-calendar})
  (local result (registry.business-calendar "holidays" {:jurisdiction "US-FED"}))
  (assert= result.operation "holidays")
  (assert= result.jurisdiction "US-FED"))

(fn business-calendar-table-provider-dispatches []
  (local registry (create-provider-registry {}))
  (registry.register {:id "table-provider"
                      :version "1.0"
                      :capabilities [:business-calendar]
                      :business-calendar {:is-business-day table-provider-is-business-day}})
  (local result (registry.business-calendar "is-business-day" {:plain "2026-01-02"}))
  (assert= result.plain "2026-01-02")
  (assert= result.business? true))

(fn business-calendar-uses-deterministic-provider-order []
  (local registry (create-provider-registry {}))
  (registry.register {:id "later" :version "1.0" :priority 20 :capabilities [:business-calendar]
                      :business-calendar later-business-calendar})
  (registry.register {:id "beta" :version "1.0" :priority 10 :capabilities [:business-calendar]
                      :business-calendar beta-business-calendar})
  (registry.register {:id "alpha" :version "1.0" :priority 10 :capabilities [:business-calendar]
                      :business-calendar alpha-business-calendar})
  (local result (registry.business-calendar "holidays" {}))
  (assert= result.provider-id "alpha"))

(fn business-calendar-rejects-invalid-operation-and-request []
  (local registry (create-provider-registry {}))
  (assert-error #(registry.business-calendar 42 {})
                "temporal provider business-calendar operation must be a string")
  (assert-error #(registry.business-calendar "holidays" nil)
                "temporal provider business-calendar request must be a table"))

(fn business-calendar-prefixes-provider-failures []
  (local registry (create-provider-registry {}))
  (registry.register {:id "bad-calendar"
                      :version "1.0"
                      :capabilities [:business-calendar]
                      :business-calendar bad-business-calendar})
  (assert-error #(registry.business-calendar "holidays" {})
                "temporal provider bad-calendar business-calendar failed:"))

(fn business-calendar-errors-when-handler-missing []
  (local registry (create-provider-registry {}))
  (registry.register {:id "missing"
                      :version "1.0"
                      :capabilities [:business-calendar]
                      :business-calendar {:is-business-day missing-is-business-day}})
  (assert-error #(registry.business-calendar "holidays" {})
                "no temporal business-calendar provider handled operation: holidays"))

(table.insert tests {:name "temporal facade exports providers" :fn facade-exports-providers})
(table.insert tests {:name "orders providers by priority then id" :fn orders-providers})
(table.insert tests {:name "rejects duplicate provider ids" :fn rejects-duplicate-provider-ids})
(table.insert tests {:name "rejects invalid manifests" :fn rejects-invalid-manifests})
(table.insert tests {:name "unregister handles are idempotent and validated" :fn unregister-handles})
(table.insert tests {:name "summaries are defensive copies" :fn summaries-are-defensive})
(table.insert tests {:name "parse returns empty array when no providers match" :fn parse-returns-empty-when-no-providers-match})
(table.insert tests {:name "parse composes deterministic candidates and annotates provider ids" :fn parse-composes-candidates})
(table.insert tests {:name "parse prefixes provider failures" :fn parse-prefixes-provider-failures})
(table.insert tests {:name "parse rejects hash-shaped and sparse results" :fn parse-rejects-invalid-result-shapes})
(table.insert tests {:name "default natural provider parses today candidates" :fn default-natural-provider-parses-today})
(table.insert tests {:name "default natural provider order is deterministic" :fn default-natural-provider-order-is-deterministic})
(table.insert tests {:name "default natural provider returns empty for unsupported text" :fn default-natural-provider-returns-empty-for-unsupported-text})
(table.insert tests {:name "business-calendar dispatches to function provider" :fn business-calendar-function-provider-dispatches})
(table.insert tests {:name "business-calendar dispatches to table provider" :fn business-calendar-table-provider-dispatches})
(table.insert tests {:name "business-calendar uses deterministic provider order" :fn business-calendar-uses-deterministic-provider-order})
(table.insert tests {:name "business-calendar rejects invalid operation and request" :fn business-calendar-rejects-invalid-operation-and-request})
(table.insert tests {:name "business-calendar prefixes provider failures" :fn business-calendar-prefixes-provider-failures})
(table.insert tests {:name "business-calendar errors when handler missing" :fn business-calendar-errors-when-handler-missing})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal-provider-registry"
                       :tests tests})))

{:name "temporal-provider-registry"
 :tests tests
 :main main}
