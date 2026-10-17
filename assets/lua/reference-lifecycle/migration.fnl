(local fs (require :fs))
(local Uuid (require :uuid))
(local J (require :json-utils))
(local R (require :reference-lifecycle/record-utils))

(local eligible {:list-item true :notebook-item true :dict-slot true
                 :link-source true :link-target true :board-subject true})
(local known {:string-entity true :code-entity true :list-entity true :dict-entity true
              :link-entity true :identity true :notebook true :workflow-step true})
(local owner-ids {:entities true :identities true :workflows true :worlds true :runtime true})

(fn inventories [owners stores]
  (local out [])
  (local seen {})
  (local root (fs.absolute stores.base-dir))
  (assert (= root stores.base-dir) "migration requires canonical base-dir")
  (each [_ owner (ipairs owners)]
    (assert (and (. owner-ids owner.id) (not (. seen owner.id))) "invalid or duplicate owner")
    (tset seen owner.id true)
    (assert (= owner.base-dir root) "migration owner base-dir mismatch")
    (each [_ method (ipairs ["preflight!" "inventory" "expand" "prepare" "apply!" "reconcile!"])]
      (assert (= (type (. owner method)) :function) (.. "missing owner capability: " method)))
    (assert (owner:preflight!) "owner preflight failed")
    (table.insert out {:owner owner :inventory (owner:inventory)}))
  out)
(fn collect-records [entries]
  (local records {})
  (each [_ entry (ipairs entries)]
    (each [key record (pairs entry.inventory.records)]
      (assert (not (. records key)) (.. "duplicate inventory key: " key))
      (tset records key record)))
  records)
(fn resolve [records key]
  (var current key)
  (local visited {})
  (var depth 0)
  (while (= (string.sub current 1 9) "identity:")
    (assert (not (. visited current)) (.. "migration identity cycle: " current))
    (tset visited current true)
    (local record (. records current))
    (when (or (not record) (= record.value.target-key "")) (lua "return current"))
    (assert (< depth 32) (.. "migration identity depth exhausted: " current))
    (set current record.value.target-key)
    (set depth (+ depth 1)))
  current)
(fn missing-known? [records key]
  (local scheme (string.match key "^([^:]+):"))
  (when (. known scheme)
    (local native-id (string.match key "^[^:]+:(.*)$"))
    (if (= scheme "workflow-step")
        (do
          (local (definition-id step-id) (string.match native-id "^([^:]+):([^:]+)$"))
          (R.require-id definition-id)
          (R.require-id step-id))
        (R.require-id native-id)))
  (and (. known scheme) (not (. records key))))
(fn ordered-sites [entries]
  (local sites [])
  (each [_ entry (ipairs entries)]
    (each [_ site (ipairs entry.inventory.sites)]
      (local copied (R.clone site))
      (set copied.owner entry.owner.id)
      (table.insert sites copied)))
  (fn before? [a b]
    (< (.. a.owner "|" a.address "|" (J.stable-json a.field))
       (.. b.owner "|" b.address "|" (J.stable-json b.field))))
  (table.sort sites before?)
  sites)
(fn direct-identities [records]
  (local direct {})
  (each [key record (pairs records)]
    (when (= (string.sub key 1 9) "identity:")
      (resolve records key)
      (local target record.value.target-key)
      (assert (= (type target) :string) (.. "invalid identity target at " record.address))
      (when (and (not (= target "")) (or (not (. direct target)) (< key (. direct target))))
        (tset direct target key))))
  direct)
(fn reference-plan [records sites timestamp]
  (local direct (direct-identities records))
  (local raw {})
  (local dangling [])
  (each [_ site (ipairs sites)]
    (local terminal (resolve records site.target-key))
    (if (missing-known? records terminal)
        (table.insert dangling site)
        (and (. eligible site.kind) (not (= site.target-key ""))
             (not (= (string.sub site.target-key 1 9) "identity:")))
        (tset raw site.target-key true)))
  (local keys (icollect [key _ (pairs raw)] key))
  (table.sort keys)
  (local rewrites [])
  (local identities [])
  (local reserved {})
  (each [_ key (ipairs keys)]
    (var stable (. direct key))
    (when (not stable)
      (local id (Uuid.v4))
      (assert (and (not (. records (.. "identity:" id))) (not (. reserved id))) "reserved identity collision")
      (tset reserved id true)
      (set stable (.. "identity:" id))
      (table.insert identities {:id id :target-key key :created-at timestamp :updated-at timestamp :metadata {}}))
    (table.insert rewrites {:from-key key :to-key stable}))
  (table.sort identities (fn by-id [a b] (< a.id b.id)))
  (values {:rewrites rewrites :identities identities} dangling))
(fn append-preparation! [out paths captures owner preparation]
  (assert (and (= (type preparation.changes) :table) (= (type preparation.runtime-state) :table)) "owner must return Preparation")
  (each [_ change (ipairs preparation.changes)]
    (assert (= change.owner owner.id) "change owner namespace mismatch")
    (local path (fs.absolute change.path))
    (assert (not (. paths path)) (.. "duplicate durable path: " path))
    (tset paths path true)
    (assert (= (R.check-bytes change.after-bytes change.format) change.after-check) "invalid frozen change")
    (table.insert out.changes (R.clone change)))
  (each [_ capture (ipairs preparation.runtime-state)]
    (assert (= capture.owner owner.id) "runtime capture owner namespace mismatch")
    (R.require-id capture.world-id)
    (when (not (= capture.map-id false)) (R.require-id capture.map-id))
    (local key (J.stable-json [owner.id capture.world-id capture.map-id]))
    (assert (not (. captures key)) "duplicate runtime capture")
    (tset captures key true)
    (table.insert out.runtime-state (R.clone capture))))
(fn prepare [owners stores]
  (local entries (inventories owners stores))
  (local records (collect-records entries))
  (local timestamp (os.time))
  (local (plan dangling) (reference-plan records (ordered-sites entries) timestamp))
  (local operation {:kind "migrate" :source-key false :target-key false :retiring []
                    :updated-identity-keys [] :replacement false :reference-plan plan :timestamp timestamp})
  (local out {:operation operation :changes [] :runtime-state [] :dangling dangling})
  (local paths {})
  (local captures {})
  (each [_ entry (ipairs entries)]
    (append-preparation! out paths captures entry.owner (entry.owner:prepare entry.inventory operation)))
  out)
{:version 1 :prepare prepare}
