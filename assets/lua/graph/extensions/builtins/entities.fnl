(local Common (require :graph/extensions/builtins/common))
(local KeyLoaderUtils (require :graph/key-loader-utils))
(local StringEntityNodeModule (require :graph/nodes/string-entity))
(local CodeEntityNodeModule (require :graph/nodes/code-entity))
(local ListEntityNodeModule (require :graph/nodes/list-entity))
(local LinkEntityNodeModule (require :graph/nodes/link-entity))
(local IdentityNodeModule (require :graph/nodes/identity))
(local NotebookNodeModule (require :graph/nodes/notebook))
(local StringEntityListNode (require :graph/nodes/string-entity-list))
(local ListEntityListNode (require :graph/nodes/list-entity-list))
(local LinkEntityListNode (require :graph/nodes/link-entity-list))
(local EntitiesNode (require :graph/nodes/entities))
(local NotebooksNode (require :graph/nodes/notebooks))
(local QuitNode (require :graph/nodes/quit))
(local StartNode (require :graph/nodes/start))
(local ClassNode (require :graph/nodes/class))

(local entity-schemes
  ["string-entity" "code-entity" "list-entity" "link-entity" "identity" "notebook"
   "string-entity-list" "list-entity-list" "link-entity-list" "entities" "notebooks"])
(local static-schemes ["start" "quit" "class"])

(fn loader-opts [ctx]
  {:owner-id ctx.owner-id :extension-id ctx.extension-id})

(fn register-store-node-loader [graph ctx scheme store make-node]
  (graph:register-key-loader scheme
    (fn [key]
      (local entity-id (KeyLoaderUtils.extract-id scheme key))
      (when entity-id
        (local entity (store:get-entity entity-id))
        (when entity
          (make-node entity-id))))
    (loader-opts ctx)))

(fn install-entity-loaders [options graph ctx]
  (local string-store (assert options.string-store "builtin-graph-entities requires :string-store"))
  (local code-store (assert options.code-store "builtin-graph-entities requires :code-store"))
  (local list-store (assert options.list-store "builtin-graph-entities requires :list-store"))
  (local link-store (assert options.link-store "builtin-graph-entities requires :link-store"))
  (local identity-store (assert options.identity-store "builtin-graph-entities requires :identity-store"))
  (local notebook-store (assert options.notebook-store "builtin-graph-entities requires :notebook-store"))
  (local handles [])
  (fn add! [handle] (table.insert handles handle))
  (fn make-string-entity [entity-id]
    (StringEntityNodeModule.StringEntityNode {:entity-id entity-id :store string-store}))
  (fn make-code-entity [entity-id]
    (CodeEntityNodeModule.CodeEntityNode {:entity-id entity-id :store code-store}))
  (fn make-list-entity [entity-id]
    (ListEntityNodeModule.ListEntityNode {:entity-id entity-id
                                          :store list-store
                                          :identity-store identity-store}))
  (fn make-link-entity [entity-id]
    (LinkEntityNodeModule.LinkEntityNode {:entity-id entity-id :store link-store}))
  (fn make-identity [entity-id]
    (IdentityNodeModule.IdentityNode {:entity-id entity-id :store identity-store}))
  (fn load-notebook [key]
    (local notebook-id (KeyLoaderUtils.extract-id "notebook" key))
    (when notebook-id
      (local notebook (notebook-store:get-notebook notebook-id))
      (when notebook
        (NotebookNodeModule.NotebookNode {:notebook-id notebook-id
                                          :store notebook-store
                                          :identity-store identity-store
                                          :string-store string-store}))))
  (fn make-string-entity-list [] (StringEntityListNode {:store string-store}))
  (fn make-list-entity-list [] (ListEntityListNode {:store list-store}))
  (fn make-link-entity-list [] (LinkEntityListNode {:store link-store}))
  (fn make-entities [] (EntitiesNode {}))
  (fn make-notebooks [] (NotebooksNode {:store notebook-store}))
  (add! (register-store-node-loader graph ctx "string-entity" string-store
      make-string-entity))
  (add! (register-store-node-loader graph ctx "code-entity" code-store
      make-code-entity))
  (add! (register-store-node-loader graph ctx "list-entity" list-store
      make-list-entity))
  (add! (register-store-node-loader graph ctx "link-entity" link-store
      make-link-entity))
  (add! (register-store-node-loader graph ctx "identity" identity-store
      make-identity))
  (add! (graph:register-key-loader "notebook"
      load-notebook
      (loader-opts ctx)))
  (add! (graph:register-key-loader "string-entity-list"
      (Common.exact-key-loader "string-entity-list"
        make-string-entity-list)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "list-entity-list"
      (Common.exact-key-loader "list-entity-list"
        make-list-entity-list)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "link-entity-list"
      (Common.exact-key-loader "link-entity-list"
        make-link-entity-list)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "entities"
      (Common.exact-key-loader "entities" make-entities)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "notebooks"
      (Common.exact-key-loader "notebooks" make-notebooks)
      (loader-opts ctx)))
  handles)

(fn install-static-loaders [options graph ctx]
  (local handles [])
  (fn add! [handle] (table.insert handles handle))
  (fn make-start []
    (local node (StartNode))
    (set node.auto-focus? true)
    node)
  (fn make-quit [] (QuitNode {}))
  (fn make-class [id _key] (ClassNode {:id id :name id}))
  (add! (graph:register-key-loader "start"
      (Common.exact-key-loader "start" make-start)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "quit"
      (Common.exact-key-loader "quit" make-quit)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "class"
      (Common.prefix-loader "class:" make-class)
      (loader-opts ctx)))
  handles)

(fn descriptors [opts]
  (local options (if opts opts {}))
  (fn install-entities [graph ctx]
    (install-entity-loaders options graph ctx))
  (fn install-static [graph ctx]
    (install-static-loaders options graph ctx))
  [(Common.descriptor
     {:id "builtin-graph-entities"
      :unit-id "builtin-graph-entities"
      :schemes entity-schemes
      :install-loaders install-entities})
   (Common.descriptor
     {:id "builtin-graph-static"
      :unit-id "builtin-graph-static"
      :schemes static-schemes
      :install-loaders install-static})])

{:descriptors descriptors}
