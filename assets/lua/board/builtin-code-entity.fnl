(local Registry (require :board/registry))
(local CodeStore (require :entities/code))
(local Text (require :text))
(local {: Layout} (require :layout))
(local fs (require :fs))

(local ITEM_TYPE "code-entity")

(fn owning-store [view field default]
  (local store (or (. view field) (default)))
  (assert (= (fs.absolute store.base-dir) (fs.absolute view.identity-store.base-dir))
          (.. "Board " field " root mismatch"))
  store)

(fn resolve-subject [item view]
  (assert (and view view.identity-store) "Board entity rendering requires identity-store")
  (local key (view.identity-store:resolve-key item.subject-key))
  (local (kind id) (string.match key "^([^:]+):(.+)$"))
  (assert (and id (or (= kind "string-entity") (= kind ITEM_TYPE)))
          (.. "Unsupported board entity subject: " (tostring key)))
  (values key kind id))

(fn child-layout [child]
  (fn measure [layout]
    (child.layout:measurer)
    (set layout.measure child.layout.measure))
  (fn place [layout]
    (set child.layout.position layout.position)
    (set child.layout.rotation layout.rotation)
    (set child.layout.size layout.size)
    (set child.layout.clip-region layout.clip-region)
    (set child.layout.depth-offset-index layout.depth-offset-index)
    (child.layout:layouter))
  (Layout {:name "board-code-source" :children [child.layout] :measurer measure :layouter place}))

(fn code-source [item view]
  (local store (owning-store view :code-store CodeStore.get-default))
  (fn build [ctx]
    (assert ctx "Board code source requires build context")
    (local (_ kind id) (resolve-subject item view))
    (assert (= kind ITEM_TYPE) "Board code item requires code-entity subject")
    (local entity (assert (store:get-entity id) (.. "Board code source missing entity: " id)))
    (local text ((Text {:text entity.source}) ctx))
    (local layout (child-layout text))
    (var dropped? false)
    (fn refresh [_entity]
      (when (not dropped?)
        (local (_ next-kind next-id) (resolve-subject item view))
        (assert (= next-kind ITEM_TYPE) "Board code source retarget requires body replacement")
        (local current (assert (store:get-entity next-id) (.. "Board code source missing entity: " next-id)))
        (text:set-text current.source)))
    (local code-handler (store.code-entity-updated:connect refresh))
    (local identity-handler (view.identity-store.identity-updated:connect refresh))
    (fn drop [_self]
      (assert (not dropped?) "Board code source dropped twice")
      (set dropped? true)
      (store.code-entity-updated:disconnect code-handler true)
      (view.identity-store.identity-updated:disconnect identity-handler true)
      (layout:drop)
      (text:drop))
    {:item item :store store :text text :layout layout :drop drop}))

(fn build-code-entity [item view]
  (local (_ kind _id) (resolve-subject item view))
  (if (= kind ITEM_TYPE) (code-source item view)
      ((. (require :board/builtin-string-entity) :build) item view)))

(fn register [owner]
  (local existing (Registry.item-type ITEM_TYPE))
  (when existing (assert (= existing.owner owner) "Code board type registered by different owner"))
  (when (not existing)
    (Registry.register-item-type {:id ITEM_TYPE :label "Code" :icon "code" :builder build-code-entity} owner)
    true))

(fn unregister [owner] (Registry.unregister-item-type ITEM_TYPE owner))

{:item-type ITEM_TYPE :register register :unregister unregister :build build-code-entity
 :resolve-subject resolve-subject :owning-store owning-store}
