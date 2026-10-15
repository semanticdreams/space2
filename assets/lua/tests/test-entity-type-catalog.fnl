(local tests [])
(local fields [:id :label :action-name :icon :browser-key])

(fn descriptor [id]
  {:id id :label id :action-name (.. id " Entities")
   :icon "code" :browser-key (.. id "-entity-list")})

(fn make-catalog [types]
  (local {: EntityTypeCatalog} (require :entities/type-catalog))
  (EntityTypeCatalog {:types types}))

(fn assert-error [f expected]
  (local (ok err) (pcall f))
  (assert (not ok) (.. "expected error containing " expected))
  (assert (string.find (tostring err) expected 1 true)
          (.. "expected " expected ", got: " (tostring err))))

(fn assert-descriptor [actual expected]
  (each [_ field (ipairs fields)]
    (assert (= (. actual field) (. expected field))
            (.. "descriptor mismatch for " field))))

(fn preserves-declaration-order-and-lookup []
  (local input [(descriptor "string") (descriptor "link") (descriptor "code")])
  (local catalog (make-catalog input))
  (local rows (catalog:list-types))
  (assert (= (length rows) 3))
  (each [i expected (ipairs input)]
    (assert-descriptor (. rows i) expected)
    (assert-descriptor (catalog:get-type expected.id) expected)))

(fn isolates-input-and-output-mutations []
  (local input [{:id "code" :label "code" :action-name "Code Entities"
                :icon "code" :browser-key "code-entity-list"}])
  (local catalog (make-catalog input))
  (set (. input 1 :label) "mutated")
  (assert (= (. (catalog:get-type "code") :label) "code"))
  (local rows (catalog:list-types))
  (set (. rows 1 :browser-key) "wrong")
  (assert (= (. (catalog:get-type "code") :browser-key) "code-entity-list"))
  (local fetched (catalog:get-type "code"))
  (set fetched.id "changed")
  (table.remove rows 1)
  (table.insert input (descriptor "later"))
  (set (. input 1) (descriptor "replacement"))
  (local fresh (catalog:list-types))
  (assert (= (length fresh) 1))
  (assert (= (. fresh 1 :id) "code"))
  (assert (not (= fresh (catalog:list-types))))
  (assert (not (= (. fresh 1) (catalog:get-type "code")))))

(fn accepts-empty-catalog []
  (local catalog (make-catalog []))
  (assert (= (length (catalog:list-types)) 0))
  (assert-error #(catalog:get-type "unknown") "unknown"))

(fn rejects-unknown-lookup []
  (local catalog (make-catalog [(descriptor "code")]))
  (assert-error #(catalog:get-type "unknown") "unknown"))

(fn rejects-invalid-fields []
  (each [_ field (ipairs fields)]
    (local missing (descriptor "code"))
    (tset missing field nil)
    (assert-error #(make-catalog [missing]) field)
    (each [_ invalid (ipairs ["" 42 false {}])]
      (local item (descriptor "code"))
      (tset item field invalid)
      (assert-error #(make-catalog [item]) field))))

(fn rejects-duplicate-ids []
  (assert-error #(make-catalog [(descriptor "code") (descriptor "code")]) "code"))

(fn rejects-non-sequence-input []
  (assert-error #(make-catalog nil) "types")
  (each [_ invalid (ipairs [false 42 "code"
                            {:code (descriptor "code")}
                            {2 (descriptor "code")}
                            {1 (descriptor "code") 3 (descriptor "link")}
                            {0 (descriptor "code")}
                            {-1 (descriptor "code")}
                            {1.5 (descriptor "code")}
                            {1 (descriptor "code") :extra true}])]
    (assert-error #(make-catalog invalid) "types")))

(fn rejects-non-table-descriptors []
  (each [_ invalid (ipairs [false 42 "code"])]
    (assert-error #(make-catalog [invalid]) "descriptor")))

(fn catalogs-are-isolated []
  (local first (make-catalog [(descriptor "code")]))
  (local second (make-catalog [(descriptor "link")]))
  (assert (= (. (first:list-types) 1 :id) "code"))
  (assert (= (. (second:list-types) 1 :id) "link"))
  (assert-error #(second:get-type "code") "code"))

(fn builtin-manifests-are-ordered-and-fresh []
  (local expected
    [{:id "string" :label "string" :action-name "String Entities"
      :icon "text_fields" :browser-key "string-entity-list"}
     {:id "link" :label "link" :action-name "Link Entities"
      :icon "link" :browser-key "link-entity-list"}
     {:id "list" :label "list" :action-name "List Entities"
      :icon "list" :browser-key "list-entity-list"}
     {:id "dict" :label "dict" :action-name "Dict Entities"
      :icon "data_object" :browser-key "dict-entity-list"}
     {:id "code" :label "code" :action-name "Code Entities"
      :icon "code" :browser-key "code-entity-list"}])
  (local Entities (require :graph/extensions/builtins/entities))
  (local Builtins (require :graph/extensions/builtins))
  (each [_ module (ipairs [Entities Builtins])]
    (assert (= (type module.entity-types) "function") "entity-types API required")
    (local rows (module.entity-types))
    (assert (= (length rows) (length expected)))
    (each [i item (ipairs expected)]
      (assert-descriptor (. rows i) item))
    (set (. rows 1 :label) "mutated")
    (table.remove rows 5)
    (local fresh (module.entity-types))
    (assert (= (length fresh) 5))
    (assert-descriptor (. fresh 1) (. expected 1)))
  (local catalog (make-catalog (Builtins.entity-types)))
  (assert (= (length (catalog:list-types)) 5)))

(table.insert tests {:name "catalog preserves declaration order and lookup"
                     :fn preserves-declaration-order-and-lookup})
(table.insert tests {:name "catalog isolates input and output mutations"
                     :fn isolates-input-and-output-mutations})
(table.insert tests {:name "catalog accepts empty input" :fn accepts-empty-catalog})
(table.insert tests {:name "catalog rejects unknown lookup" :fn rejects-unknown-lookup})
(table.insert tests {:name "catalog validates every required field" :fn rejects-invalid-fields})
(table.insert tests {:name "catalog rejects duplicate IDs" :fn rejects-duplicate-ids})
(table.insert tests {:name "catalog rejects sparse and non-sequence input"
                     :fn rejects-non-sequence-input})
(table.insert tests {:name "catalog rejects non-table descriptors"
                     :fn rejects-non-table-descriptors})
(table.insert tests {:name "catalog instances are isolated" :fn catalogs-are-isolated})
(table.insert tests {:name "built-in entity manifests are ordered and fresh"
                     :fn builtin-manifests-are-ordered-and-fresh})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "test-entity-type-catalog" :tests tests}))

{:tests tests :main main}
