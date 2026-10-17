(local Registry (require :board/registry))
(local StringEntityStore (require :entities/string))
(local IdentityStore (require :entities/identity))
(local fs (require :fs))
(local Uuid (require :uuid))
(local StringEntityBoardWidget (require :board/string-entity-widget))
(local Code (require :board/builtin-code-entity))

(local ITEM_TYPE "string-entity")

(fn subject-key [entity]
  (.. "string-entity:" (tostring entity.id)))

(fn entity-id-from-subject [key]
  (when (= (type key) :string)
    (local prefix "string-entity:")
    (when (= (string.sub key 1 (# prefix)) prefix)
      (string.sub key (+ (# prefix) 1)))))

(fn build-string-entity [item view]
  (local (_ kind id) (Code.resolve-subject item view))
  (if (= kind Code.item-type) (Code.build item view)
      (StringEntityBoardWidget {:item item :entity-id id
                                :store (Code.owning-store view :string-store StringEntityStore.get-default)})))

(fn reserve-absent-id [store]
  (local id (Uuid.v4))
  (assert (= (. (store:snapshot-entity id) :value) false) "Board authoring id collision")
  id)

(fn acquire-subject! [attempt store identity-store options]
  (local entity
    (if options.entity
        (do
          (assert (store:get-entity options.entity.id)
                  (.. "String entity board create requires entity " (tostring options.entity.id) " to exist in string-store"))
          options.entity)
        (do
          (set attempt.string-id (reserve-absent-id store))
          (store:create-entity {:id attempt.string-id :value (or options.value "")}))))
  (set attempt.identity-id (reserve-absent-id identity-store))
  (local reserved-key (.. "identity:" attempt.identity-id))
  (set attempt.key (identity-store:ensure-key (subject-key entity) {:id attempt.identity-id}))
  ;; Existing direct identities belong to their original owner, not this attempt.
  (when (not (= attempt.key reserved-key)) (set attempt.identity-id nil)))

(fn rollback-creation! [board attempt store identity-store]
  (when board.remove-item
    (when attempt.item (board:remove-item attempt.item.id))
    (when attempt.key
      (each [_ existing (ipairs (assert board.items-in-order "Board rollback requires native items"))]
        (when (and (= existing.subject-key attempt.key) (not (. attempt.previous-items existing)))
          (board:remove-item existing.id)))))
  ;; Do not retire the representation if removing its new reference fails.
  (when attempt.identity-id (identity-store:retire-entity! attempt.identity-id))
  (when attempt.string-id (store:retire-entity! attempt.string-id)))

(fn create-string-entity [board opts]
  (local options (or opts {}))
  (assert (= options.store nil)
          "BuiltinStringEntity.create-string-entity does not accept :store; use :string-store")
  (local store (or options.string-store (StringEntityStore.get-default)))
  (local identity-store (or options.identity-store (IdentityStore.get-default {:base-dir store.base-dir})))
  (assert (= (fs.absolute store.base-dir) (fs.absolute identity-store.base-dir)) "Board authoring identity-store root mismatch")
  (local attempt {:previous-items {}})
  (each [_ existing (ipairs (or board.items-in-order []))] (tset attempt.previous-items existing true))
  (fn create []
    (acquire-subject! attempt store identity-store options)
    (set attempt.item (board:add-item {:type ITEM_TYPE :subject-key attempt.key
                                      :position options.position :rotation options.rotation
                                      :size options.size :state options.state})))
  (local (ok result) (pcall create))
  (when (not ok)
    (local (rollback-ok rollback-error) (pcall rollback-creation! board attempt store identity-store))
    (if rollback-ok (error result)
        (error (.. (tostring result) "; Board creation rollback failed: " (tostring rollback-error)))))
  attempt.item)

(fn register [owner]
  (local existing (Registry.item-type ITEM_TYPE))
  (when existing
    (assert (= existing.owner owner)
            "String-entity board item type already registered by different owner"))
  (when (not existing)
    (Registry.register-item-type {:id ITEM_TYPE
                                   :label "String"
                                   :icon "notes"
                                   :builder build-string-entity
                                   :create create-string-entity}
                                  owner)
    true))

(fn unregister [owner]
  (Registry.unregister-item-type ITEM_TYPE owner))

{:item-type ITEM_TYPE
 :build build-string-entity
 :subject-key subject-key
 :entity-id-from-subject entity-id-from-subject
 :create-string-entity create-string-entity
 :register register
 :unregister unregister}
