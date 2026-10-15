(local fs (require :fs))
(local tempfile (require :tempfile))

(fn with-root [f]
  (local resource (tempfile.TemporaryDirectory {:prefix "reference-lifecycle-"}))
  (local (ok result) (pcall f (fs.absolute resource.path)))
  (local (cleanup-ok cleanup-error) (pcall resource.drop resource))
  (if (not ok) (error result)
      (not cleanup-ok) (error cleanup-error)
      result))

(fn stores [root]
  (local base-dir (fs.absolute root))
  (local Identity (require :entities/identity))
  (local identity-store (Identity.IdentityStore {:base-dir base-dir}))
  (local options {:base-dir base-dir :identity-store identity-store})
  {:base-dir base-dir
   :identity-store identity-store
   :string-store ((. (require :entities/string) :StringEntityStore) options)
   :code-store ((. (require :entities/code) :CodeEntityStore) options)
   :list-store ((. (require :entities/list) :ListEntityStore) options)
   :dict-store ((. (require :entities/dict) :DictEntityStore) options)
   :link-store ((. (require :entities/link) :LinkEntityStore) options)
   :notebook-store ((. (require :notebooks/store) :NotebookStore) options)
   :workflow-store ((. (require :workflows/store) :WorkflowStore) options)})

(fn assert-error [fragment f]
  (local (ok result) (pcall f))
  (assert (not ok) (.. "expected error containing: " fragment))
  (local message (tostring result))
  (assert (string.find message fragment 1 true)
          (.. "expected error containing " fragment ", got: " message))
  message)

(fn snapshot-tree [root]
  (local out {})
  (fn visit [path prefix]
    (each [_ entry (ipairs (fs.list-dir path true))]
      (local relative (.. prefix entry.name))
      (if entry.is-dir
          (visit entry.path (.. relative "/"))
          entry.is-file
          (set (. out relative) (fs.read-file entry.path)))))
  (visit root "")
  out)

(fn with-fs-failure [method path f]
  (local original (assert (. fs method) (.. "missing native fs method: " method)))
  (local target (fs.absolute path))
  (tset fs method
        (fn [candidate ...]
          (if (= (fs.absolute candidate) target)
              (error (.. "injected permission denied: " method " " path))
              (original candidate ...))))
  (local (ok result) (pcall f))
  (tset fs method original)
  (if ok result (error result)))

(fn with-graph [s f]
  (local Graph (require :graph/core))
  (local GraphMap (require :graph/map))
  (local Entities (require :graph/extensions/builtins/entities))
  (local Catalog (require :entities/type-catalog))
  (local graph (Graph {:identity-store s.identity-store :link-store s.link-store
                      :string-store s.string-store :morphs {} :entity-events? false}))
  (local options (collect [key value (pairs s)] key value))
  (set options.entity-type-catalog (Catalog.EntityTypeCatalog {:types (Entities.entity-types)}))
  (local descriptor (. (Entities.descriptors options) 1))
  (descriptor.install-loaders graph {:owner-id descriptor.unit-id :extension-id descriptor.id})
  (local map (GraphMap.GraphMap {:graph graph}))
  (local (ok result) (pcall f graph map))
  (local (cleanup-ok cleanup-error) (pcall (fn [] (map:drop) (graph:drop))))
  (if (not ok) (error result)
      (not cleanup-ok) (error cleanup-error)
      result))

(fn with-fields [target fields f]
  (local previous {})
  (each [key value (pairs fields)]
    (tset previous key (. target key))
    (tset target key value))
  (local (ok result) (pcall f))
  (each [key _ (pairs fields)] (tset target key (. previous key)))
  (if ok result (error result)))

(fn assert-reference [identity-store key terminal]
  (assert (= (string.sub key 1 9) "identity:") (.. "expected stable reference, got " key))
  (assert (= (identity-store:resolve-key key) terminal) "stable reference must preserve terminal meaning"))

{:with-root with-root
 :stores stores
 :assert-error assert-error
 :snapshot-tree snapshot-tree
 :with-fs-failure with-fs-failure
 :with-graph with-graph
 :with-fields with-fields
 :assert-reference assert-reference}
