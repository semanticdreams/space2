(local H (require :tests/test-reference-lifecycle-helpers))
(local Graph (require :graph/core))
(local {: GraphMap} (require :graph/map))
(local Entities (require :graph/extensions/builtins/entities))
(local {: EntityTypeCatalog} (require :entities/type-catalog))
(local BuildContext (require :build-context))
(local tests [])

(local store-modules {:identity-store :entities/identity :string-store :entities/string
                      :code-store :entities/code :list-store :entities/list :dict-store :entities/dict
                      :link-store :entities/link :notebook-store :notebooks/store :workflow-store :workflows/store})

;; Fresh real lazy default caches, scoped to this fixture only. Production factories
;; still receive actual owning stores, never fake providers or changed global dirs.
(fn with-defaults [root f]
  (local cleared {})
  (each [_ name (pairs store-modules)] (require name) (tset cleared name false))
  (fn scoped []
    (local identity-store ((. (require :entities/identity) :get-default) {:base-dir root}))
    (local s {:base-dir root :identity-store identity-store})
    (each [field name (pairs store-modules)]
      (when (not (= field :identity-store))
        (tset s field ((. (require name) :get-default) {:base-dir root :identity-store identity-store}))))
    (f s))
  (H.with-fields package.loaded cleared scoped))

(fn with-native [s f]
  (local lifecycle (H.ready s))
  (local options (collect [key value (pairs s)] key value))
  (set options.lifecycle lifecycle)
  (set options.entity-events? false)
  (set options.morphs {})
  (set options.entity-type-catalog (EntityTypeCatalog {:types (Entities.entity-types)}))
  (local graph (Graph options))
  (local descriptor (. (Entities.descriptors options) 1))
  (descriptor.install-loaders graph {:owner-id descriptor.unit-id :extension-id descriptor.id})
  (local map (GraphMap {:graph graph :lifecycle lifecycle}))
  (local (ok result) (pcall f map lifecycle))
  (local (drop-ok drop-error) (pcall (fn cleanup [] (map:drop) (graph:drop))))
  (if (not ok) (error result) (not drop-ok) (error drop-error) result))

(fn create-subject [s kind]
  (local store (. s (.. kind "-store")))
  (if (= kind "notebook") (store:create-notebook {:id "subject"})
      (store:create-entity {:id "subject" :value "subject" :name "Subject"})))

(fn open-browser-child [map browser-key subject key]
  (local browser (assert (map:load-by-key browser-key) "native browser must load"))
  (local ctx (BuildContext {:clickables (assert app.clickables) :hoverables (assert app.hoverables)
                           :icons ((require :icons))}))
  (local view ((browser.view browser {}) ctx))
  (local (ok result) (pcall (fn submit []
    (view.search.submitted:emit [subject "Subject"])
    (assert (map:lookup key) "real browser submit must mount its child"))))
  (view:drop)
  (if ok result (error result)))

(fn exercise [s kind browser-key]
  (local subject (create-subject s kind))
  (local scheme (if (= kind "notebook") "notebook" (.. kind "-entity")))
  (local key (.. scheme ":" subject.id))
  (s.list-store:create-entity {:id "unopened" :items [key]})
  (fn action [map lifecycle]
    (open-browser-child map browser-key subject key)
    (local child (assert (map:lookup key)))
    (assert (= child.graph map) "native GraphMap owns the browser child")
    (assert (= (child:resolve-reference-lifecycle!) lifecycle))
    (when (not (= kind "code")) (assert (= child.lifecycle nil) "direct browser child has no explicit service"))
    (local deleted (if (= kind "notebook") (child:delete-notebook) (child:delete-entity)))
    ;; The old frontend physically retires the record but leaves this cold site.
    (assert (= (# (. (s.list-store:snapshot-entity "unopened") :value :items)) 0)
            "ordinary browser delete must prune unopened durable incoming membership")
    (assert (= deleted.id subject.id) "ordinary frontend retains its record result")
    (when (= kind "code")
      (assert (= (s.code-store:get-entity subject.id) nil) "canonical code cache must observe deletion")))
  (with-native s action))

(fn add-browser [kind browser-key]
  (fn custom [root] (exercise (H.stores root) kind browser-key))
  (fn canonical [root] (with-defaults root #(exercise $1 kind browser-key)))
  (fn run [] (H.with-root canonical) (H.with-root custom))
  (table.insert tests {:name (.. "reference lifecycle composition browser " kind " child delete") :fn run}))

(each [_ row (ipairs [["string" "string-entity-list"] ["list" "list-entity-list"]
                      ["dict" "dict-entity-list"] ["link" "link-entity-list"]
                      ["notebook" "notebooks"] ["code" "code-entity-list"]])]
  (add-browser (. row 1) (. row 2)))

{:tests tests}
