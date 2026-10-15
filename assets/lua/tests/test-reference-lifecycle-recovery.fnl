(local H (require :tests/test-reference-lifecycle-helpers))
(local fs (require :fs))
(local J (require :json-utils))
(local json (require :json))
(local R (require :reference-lifecycle/record-utils))
(local tests [])
(fn add [name f]
  (fn with-stores [root] (f (H.stores root)))
  (fn run [] (H.with-root with-stores))
  (table.insert tests {:name (.. "reference lifecycle recovery " name) :fn run}))
(fn same [a b] (assert (= (J.stable-json a) (J.stable-json b)) "values differ"))
(fn pending [s] ((require :reference-lifecycle/pending) s.base-dir))
(fn seed [s]
  (s.string-store:create-entity {:id "s" :value "source"})
  (s.list-store:create-entity {:id "l" :items ["string-entity:s"]}))
(fn payload [] {:name "new" :language "fnl" :source "source" :kernel 0})
(fn source-alive [s] (assert (. (s.string-store:snapshot-entity "s") :value) "incoming failure must preserve source"))
(fn done [s]
  (assert (= (s.string-store:get-entity "s") nil))
  (assert (= (length (. (s.list-store:get-entity "l") :items)) 0))
  (assert (= (: (pending s) :read) nil)))

(fn world-double [s path]
  (local world (H.empty-owner "worlds" s.base-dir))
  (set world.inventory (fn inventory [_]
    (local snapshot (R.snapshot path "json" json.loads))
    {:records {:world:w {:address "world:w" :snapshot snapshot :value snapshot.value}} :sites []}))
  (set world.prepare (fn prepare [_ _inv op]
    (local changes [])
    (when (not (= op.kind "migrate"))
      (local snapshot (R.snapshot path "json" json.loads))
      (local bytes (json.dumps {:board {:items []}}))
      (table.insert changes (R.make-change "worlds" "world:w" snapshot bytes "json" "incoming")))
    {:changes changes :runtime-state []}))
  (set world.apply! (fn apply [_ change] (J.write-json! change.path (json.loads change.after-bytes))))
  world)

;; One permanent named case per owning store. All reconciliation calls execute
;; against real files, with native write/rename/remove/create guards installed.
(fn publication [s kind]
  (local notebook? (= kind "notebook"))
  (local workflow? (= kind "workflow"))
  (local store (. s (.. kind "-store")))
  (local create (if notebook? store.create-notebook workflow? store.create-definition store.create-entity))
  (local snapshot (if notebook? store.snapshot-notebook workflow? store.snapshot-definition store.snapshot-entity))
  (local serialize (if notebook? store.serialize-notebook workflow? store.serialize-definition store.serialize-entity))
  (local persist (if notebook? store.persist-notebook! workflow? store.persist-definition! store.persist-entity!))
  (local method (if notebook? "reconcile-notebook!" workflow? "reconcile-definition!" "reconcile-entity!"))
  (local reconcile (assert (. store method) (.. "missing nonpersisting capability " method)))
  (local format (if (= kind "string") "string" "json"))
  (local held (create store {:id "held" :value "old" :source "old" :steps [{:id "step" :name "old" :code-entity-id "c"}]}))
  (local child (and workflow? (. held.steps 1)))
  (local before (snapshot store "held"))
  (local candidate (R.clone before.value))
  (set candidate.created-at 123)
  (when workflow? (set (. candidate.steps 1 :name) "new"))
  (local bytes (serialize store candidate))
  (local check (R.check-bytes bytes format))
  (persist store "held" bytes check)
  ;; Recreate a stale held projection without modifying the persisted after-image.
  (set held.created-at 999)
  (when child (set child.name "stale"))
  (local prefix (if notebook? "notebook" workflow? "definition" (= kind "identity") "identity" (.. kind "-entity")))
  (local seen [])
  (each [_ event (ipairs ["created" "updated" "deleted"])]
    (local signal (. store (.. prefix "-" event)))
    (signal:connect (fn capture-event [record] (table.insert seen {:event event :record record}))))
  (var item-signals 0)
  (local item-signal (. store (.. prefix "-items-changed")))
  (when item-signal (item-signal:connect (fn capture-items [event] (assert (= event.id "held")) (set item-signals (+ item-signals 1)))))
  (local tree (H.snapshot-tree s.base-dir))
  (H.no-writes (fn held-publication []
    (assert (= (reconcile store "held" bytes before.check check) held))
    (assert (= held.created-at 123))
    (when child (assert (= child (. held.steps 1))) (assert (= child.name "new")))
    (assert (= (reconcile store "held" bytes false check) held))))
  (same tree (H.snapshot-tree s.base-dir))
  (same (icollect [_ entry (ipairs seen)] entry.event) ["updated" "created"])
  (when item-signal (assert (= item-signals 2)))
  (local cold (. (H.stores s.base-dir) (.. kind "-store")))
  (H.no-writes (fn cold-publication []
    (local record ((. cold method) cold "held" bytes before.check check))
    (assert (= record.created-at 123))))
  (H.assert-error "after" (fn wrong-after [] (reconcile store "held" bytes before.check "wrong")))
  (if workflow?
      (H.assert-error "retire" (fn reject-definition-retirement [] (reconcile store "held" false check false)))
      (do
        (fs.remove before.path)
        (H.no-writes (fn held-delete [] (reconcile store "held" false check false)))
        (assert (= (. seen 3 :event) "deleted"))
        (assert (= (. seen 3 :record) held))
        (local cold-delete (. (H.stores s.base-dir) (.. kind "-store")))
        (var deleted nil)
        (: (. cold-delete (.. prefix "-deleted")) :connect (fn capture-delete [record] (set deleted record)))
        (H.no-writes (fn cold-retire [] ((. cold-delete method) cold-delete "held" false check false)))
        (same deleted candidate)))
  (each [_ event (ipairs ["created" "updated" "deleted"])]
    (local signal (. store (.. prefix "-" event))) (signal:clear))
  (when item-signal (item-signal:clear)))
(each [_ kind (ipairs ["string" "code" "list" "dict" "link" "identity" "notebook" "workflow"])]
  (add (.. "zero write publication " kind) (fn store-publication [s] (publication s kind))))

(add "pending write failure and collision" (fn pending-write [s]
  (seed s)
  (local service (H.ready s))
  (local path (fs.join-path s.base-dir "reference-lifecycle" "pending.json"))
  (H.with-fs-failure "write-file" (.. path ".tmp") (fn fail-pending []
    (H.assert-error "pending.json" (fn delete [] (service:delete! "string-entity:s")))))
  (source-alive s)
  (assert (= (length (. (s.list-store:get-entity "l") :items)) 1))
  (fs.create-dirs (.. path ".tmp"))
  (H.assert-error "pending.json" (fn collision [] (service:delete! "string-entity:s")))
  (source-alive s)
  (fs.remove-all (.. path ".tmp"))
  (service:delete! "string-entity:s") (done s)))
(add "incoming failure source last and cold restart" (fn incoming [s]
  (seed s)
  (local service (H.ready s))
  (local collision (fs.join-path s.list-store.entities-dir "l.json.tmp"))
  (fs.create-dirs collision)
  (H.assert-error "l.json" (fn reject-list-write [] (service:delete! "string-entity:s")))
  (source-alive s)
  (assert (: (pending s) :read))
  (fs.remove-all collision)
  (local cold (H.stores s.base-dir))
  (: (H.lifecycle cold) :start!) (done cold)))
(add "replacement identity failure reserves once" (fn identity-failure [s]
  (seed s)
  (local service (H.ready s))
  (local identity (. (s.identity-store:list-entities) 1))
  (local path (fs.join-path s.identity-store.entities-dir (.. identity.id ".json.tmp")))
  (H.with-fs-failure "write-file" path (fn fail-identity []
    (H.assert-error identity.id (fn morph [] (service:replace! "string-entity:s" (payload))))))
  (source-alive s)
  (local intent (: (pending s) :read))
  (assert (= (length (s.code-store:list-entities)) 1))
  (H.assert-error "pending" (fn other-command [] (service:delete! "string-entity:s")))
  (local result (service:replace! "string-entity:s" (payload)))
  (assert (= result.code-key intent.operation.target-key))
  (assert (= (length (s.code-store:list-entities)) 1))
  (assert (= result.code-entity.source "source"))
  (assert (= (s.string-store:get-entity "s") nil))))
(add "replacement write collision cold restart" (fn replacement [s]
  (seed s)
  (local service (H.ready s))
  ;; Fail the actual atomic replacement write regardless of the reserved UUID.
  (local write fs.write-file)
  (fn reject-code [path bytes]
    (if (= (fs.parent path) s.code-store.entities-dir) (error (.. "code write failure " path)) (write path bytes)))
  (H.with-fields fs {:write-file reject-code} (fn fail-code []
    (H.assert-error "code write" (fn morph [] (service:replace! "string-entity:s" (payload))))))
  (source-alive s)
  (local intent (: (pending s) :read))
  (local cold (H.stores s.base-dir))
  (: (H.lifecycle cold) :start!)
  (assert (= (length (cold.code-store:list-entities)) 1))
  (assert (= (. (cold.code-store:list-entities) 1 :id) intent.operation.replacement.id))))
(add "retirement failure fresh stores resume" (fn retirement [s]
  (seed s)
  (local service (H.ready s))
  (local path (. (s.string-store:snapshot-entity "s") :path))
  (H.with-fs-failure "remove" path (fn fail-retire []
    (H.assert-error "s.md" (fn delete [] (service:delete! "string-entity:s")))))
  (source-alive s)
  (local cold (H.stores s.base-dir))
  (local restarted (H.lifecycle cold))
  (var result nil)
  (local committed-handler (restarted.committed:connect (fn capture-result [value] (set result value))))
  (restarted:start!)
  (restarted.committed:disconnect committed-handler true)
  (assert (= result.source-record.id "s"))
  (assert (= result.source-record.value "source"))
  (done cold)))
(add "external before and after conflicts do not clobber" (fn conflicts [s]
  (seed s)
  (local service (H.ready s))
  (local path (. (s.list-store:snapshot-entity "l") :path))
  (H.with-fs-failure "write-file" (.. path ".tmp") (fn fail-list []
    (H.assert-error "l.json" (fn delete [] (service:delete! "string-entity:s")))))
  (H.raw-list s "l" ["external:changed"])
  (local edited (fs.read-file path))
  (H.assert-error "conflict" (fn before-conflict [] (service:delete! "string-entity:s")))
  (assert (= (fs.read-file path) edited))
  (source-alive s)
  (local intent (: (pending s) :read))
  (var incoming nil)
  (each [_ c (ipairs intent.changes)] (when (= c.address "list-entity:l") (set incoming c)))
  (fs.write-file path incoming.after-bytes)
  (local source-path (. (s.string-store:snapshot-entity "s") :path))
  (H.with-fs-failure "remove" source-path (fn fail-source []
    (H.assert-error "s.md" (fn delete [] (service:delete! "string-entity:s")))))
  (H.raw-list s "l" ["external:after-edit"])
  (H.assert-error "conflict" (fn after-conflict [] (: (H.lifecycle (H.stores s.base-dir)) :start!)))
  (source-alive s)))
(add "signal failure retries nonpersistingly" (fn signal-failure [s]
  (seed s)
  (local held (s.list-store:get-entity "l"))
  (local service (H.ready s))
  (local signal s.list-store.list-entity-updated)
  (local handler (signal:connect (fn reject-notify [_] (error "notification failed"))))
  (H.assert-error "notification failed" (fn delete [] (service:delete! "string-entity:s")))
  (source-alive s)
  (assert (= (length held.items) 0))
  (signal:disconnect handler true)
  (local path (. (s.list-store:snapshot-entity "l") :path))
  (H.with-fs-failure "write-file" (.. path ".tmp") (fn retry [] (service:delete! "string-entity:s")))
  (done s)))
(add "world afterimages transient retry no recapture" (fn transient [s]
  (seed s)
  (local world (H.empty-owner "worlds" s.base-dir))
  (local runtime (H.empty-owner "runtime" s.base-dir))
  (local directory (fs.join-path s.base-dir "worlds" "w"))
  (fs.create-dirs directory)
  (local path (fs.join-path directory "world.json"))
  (J.write-json! path {:board {:items ["string-entity:s"]}})
  (var captures 0) (var writes 0) (var fail? true)
  (set world.inventory (fn inventory [_]
    (local snapshot (R.snapshot path "json" json.loads))
    {:records {:world:w {:address "world:w" :value snapshot.value :snapshot snapshot}} :sites []}))
  (set world.prepare (fn prepare [_ _inv op]
    {:changes (if (= op.kind "migrate") [] [(R.make-change "worlds" "world:w" (R.snapshot path "json" json.loads)
                                   (json.dumps {:board {:items []}}) "json" "incoming")]) :runtime-state []}))
  (set world.apply! (fn apply [_ change] (set writes (+ writes 1)) (J.write-json! change.path (json.loads change.after-bytes))))
  (set runtime.prepare (fn prepare [_ _inv op]
    (when (not (= op.kind "migrate")) (set captures (+ captures 1)))
    {:changes [] :runtime-state (if (= op.kind "migrate") [] [{:owner "runtime" :world-id "w" :map-id false
                                                             :before {:board {:items ["string-entity:s"]}} :after {:board {:items []}}}])}))
  (set runtime.reconcile! (fn reconcile [_ intent]
    (when (> (length intent.runtime-state) 0)
      (assert (= (. intent.runtime-state 1 :after :board :items 1) nil))
      (when fail? (error "transient failure")))))
  (local service (H.ready s world runtime))
  (H.assert-error "transient failure" (fn delete [] (service:delete! "string-entity:s")))
  (source-alive s)
  (set fail? false)
  (service:delete! "string-entity:s")
  (same [captures writes] [1 1])
  (done s)))
(add "journal clear and committed failure replay" (fn clear-failure [s]
  (seed s)
  (local service (H.ready s))
  (local signal service.committed)
  (local handler (signal:connect (fn reject-notify [_] (error "committed notification"))))
  (H.assert-error "committed notification" (fn delete [] (service:delete! "string-entity:s")))
  (assert (: (pending s) :read))
  (signal:disconnect handler true)
  (local path (fs.join-path s.base-dir "reference-lifecycle" "pending.json"))
  (H.with-fs-failure "remove" path (fn fail-clear []
    (H.assert-error "pending.json" (fn delete [] (service:delete! "string-entity:s")))))
  (assert (: (pending s) :read))
  (local cold (H.stores s.base-dir)) (: (H.lifecycle cold) :start!) (done cold)))
(add "workflow ISO aggregate restart" (fn workflow-restart [s]
  (s.code-store:create-entity {:id "c"})
  (s.workflow-store:create-definition {:id "w" :steps [{:id "a" :code-entity-id "c"} {:id "b" :code-entity-id "c"} {:id "keep" :code-entity-id "other"}]})
  (local service (H.ready s))
  (local path (. (s.code-store:snapshot-entity "c") :path))
  (H.with-fs-failure "remove" path (fn fail-code []
    (H.assert-error "c.json" (fn delete [] (service:delete! "code-entity:c")))))
  (local intent (: (pending s) :read))
  (each [_ c (ipairs intent.changes)]
    (when (= c.owner "workflows")
      (assert (= (type (. (json.loads c.after-bytes) :updated-at)) "string"))
      (assert (= c.after-check (. (s.workflow-store:snapshot-definition "w") :check)))))
  (local cold (H.stores s.base-dir)) (: (H.lifecycle cold) :start!)
  (assert (= (length (. (cold.workflow-store:get-definition "w") :steps)) 1))))
(add "journal path is not a write capability" (fn confinement [s]
  (seed s)
  (local service (H.ready s))
  (local path (. (s.list-store:snapshot-entity "l") :path))
  (H.with-fs-failure "write-file" (.. path ".tmp") (fn fail-list []
    (H.assert-error "l.json" (fn delete [] (service:delete! "string-entity:s")))))
  (local intent (: (pending s) :read))
  (local harmless (fs.join-path s.base-dir "harmless.json"))
  (fs.write-file harmless "{}")
  (set (. intent.changes 1 :path) harmless)
  (: (pending s) :write! intent)
  (H.assert-error "path" (fn bad-path [] (: (H.lifecycle (H.stores s.base-dir)) :start!)))
  (assert (= (fs.read-file harmless) "{}"))
  (source-alive s)))
(add "busy guard restored after reentrant failure" (fn reentrant [s]
  (seed s)
  (local service (H.ready s))
  (local signal s.list-store.list-entity-updated)
  (local handler (signal:connect (fn reenter [_] (service:delete! "string-entity:s"))))
  (H.assert-error "busy" (fn delete [] (service:delete! "string-entity:s")))
  (signal:disconnect handler true)
  (service:delete! "string-entity:s") (done s)))
(add "migration marker only after verified recovery" (fn migration [s]
  (s.string-store:create-entity {:id "s" :value "source"})
  (H.raw-list s "l" ["string-entity:s"])
  (local path (. (s.list-store:snapshot-entity "l") :path))
  (local service (H.lifecycle s))
  (H.with-fs-failure "write-file" (.. path ".tmp") (fn fail-migration []
    (H.assert-error "l.json" (fn start [] (service:start!)))))
  (assert (not (fs.exists (fs.join-path s.base-dir "reference-lifecycle" "migration.json"))))
  (local intent (: (pending s) :read))
  (local cold (H.stores s.base-dir))
  (local report (: (H.lifecycle cold) :start!))
  (assert (= report.version 1))
  (assert (= (length (cold.identity-store:list-entities)) 1))
  (assert (= (. (cold.identity-store:list-entities) 1 :id) (. intent.operation.reference-plan.identities 1 :id)))))
(add "original Markdown cold deletion payload" (fn original-markdown [s]
  (local path (fs.join-path s.string-store.entities-dir "s.md"))
  (local bytes "---\nupdated-at: 2\nid: s\ncreated-at: 1\n---\n\n source \n\n")
  (fs.write-file path bytes)
  (s.list-store:create-entity {:id "l" :items ["string-entity:s"]})
  (local service (H.ready s))
  (local handler (service.committed:connect (fn reject [_] (error "retain original source"))))
  (H.assert-error "retain original source" (fn delete [] (service:delete! "string-entity:s")))
  (service.committed:disconnect handler true)
  (local cold (H.stores s.base-dir))
  (var deleted nil)
  (cold.string-store.string-entity-deleted:connect (fn capture [record] (set deleted record)))
  (: (H.lifecycle cold) :start!)
  (cold.string-store.string-entity-deleted:clear)
  (assert (= deleted.id "s"))
  (assert (= deleted.value " source \n\n"))
  (done cold)))
(add "new morph reservation cold restart" (fn new-reservation [s]
  (s.string-store:create-entity {:id "s" :value "source"})
  (local service (H.ready s))
  ;; Insert a legacy raw reference after migration, with no direct alias yet.
  (H.raw-list s "l" ["string-entity:s"])
  (local write fs.write-file)
  (fn reject-code [path bytes]
    (if (= (fs.parent path) s.code-store.entities-dir) (error "frozen code write failure") (write path bytes)))
  (H.with-fields fs {:write-file reject-code} (fn fail-code []
    (H.assert-error "frozen code" (fn morph [] (service:replace! "string-entity:s" (payload))))))
  (local intent (: (pending s) :read))
  (assert (= (length intent.operation.reference-plan.identities) 1))
  (assert (= (. intent.operation.reference-plan.identities 1 :target-key) intent.operation.target-key))
  (source-alive s)
  (local cold (H.stores s.base-dir))
  (: (H.lifecycle cold) :start!)
  (assert (= (length (cold.code-store:list-entities)) 1))
  (local code (. (cold.code-store:list-entities) 1))
  (assert (= code.id intent.operation.replacement.id))
  (assert (= code.source "source"))
  (assert (= (length (cold.identity-store:list-entities)) 1))
  (H.assert-reference cold.identity-store (. (cold.list-store:get-entity "l") :items 1) intent.operation.target-key)))
(add "world restart without loaded maps" (fn cold-world [s]
  (seed s)
  (local path (fs.join-path s.base-dir "worlds" "w" "world.json"))
  (fs.create-dirs (fs.parent path))
  (J.write-json! path {:board {:items ["string-entity:s"]}})
  (local runtime (H.empty-owner "runtime" s.base-dir))
  (set runtime.prepare (fn prepare [_ _inv op]
    {:changes [] :runtime-state (if (= op.kind "migrate") [] [{:owner "runtime" :world-id "w" :map-id "m"
                                  :before {:maps {:nodes ["string-entity:s"]}} :after {:maps {:nodes []}}}])}))
  (set runtime.reconcile! (fn reconcile [_ intent]
    (when (> (length intent.runtime-state) 0) (error "loaded map reconciliation failed"))))
  (local service (H.ready s (world-double s path) runtime))
  (H.assert-error "loaded map" (fn delete [] (service:delete! "string-entity:s")))
  (source-alive s)
  (same (. (json.loads (fs.read-file path)) :board :items) [])
  (local cold (H.stores s.base-dir))
  (local unloaded (H.empty-owner "runtime" s.base-dir))
  (set unloaded.prepare (fn forbid-capture [_ _inv _op] (error "restart must not recapture")))
  (H.with-fs-failure "write-file" (.. path ".tmp") (fn restart []
    (: (H.lifecycle cold (world-double cold path) unloaded) :start!)))
  (done cold)))
;; Real retained-journal mutations: only the supplied external edit may change
;; files. Fresh-store validation must reject before applying OR publishing.
(fn retained-incoming [s key morph?]
  (s.list-store:create-entity {:id "incoming" :items [key]})
  (local service (H.ready s))
  ;; Morph retargets the existing identity without rewriting this stable list.
  ;; Retain its journal at source removal instead of expecting a list write.
  (local path (if morph? (. (s.string-store:snapshot-entity "s") :path)
                  (.. (. (s.list-store:snapshot-entity "incoming") :path) ".tmp")))
  (H.with-fs-failure (if morph? "remove" "write-file") path (fn fail-incoming []
    (H.assert-error (if morph? "s.md" "incoming.json") (fn command []
      (if morph? (service:replace! key (payload)) (service:delete! key))))))
  (: (pending s) :read))
(fn change-at [intent address]
  (var found nil)
  (each [_ change (ipairs intent.changes)] (when (= change.address address) (set found change)))
  (assert found "test requires prepared change"))
(fn reject-edited [s intent fragment]
  (: (pending s) :write! intent)
  (local before (H.snapshot-tree s.base-dir))
  (local cold (H.stores s.base-dir))
  (local runtime (H.empty-owner "runtime" s.base-dir))
  (var reconciles 0)
  (set runtime.prepare (fn forbid-capture [_ _inv _op] (error "validation must not recapture")))
  (set runtime.reconcile! (fn reconcile [_ _intent] (set reconciles (+ reconciles 1))))
  (local service (H.lifecycle cold nil runtime))
  (local signals [service.committed])
  (each [_ kind (ipairs ["string" "code" "list" "dict" "link" "identity" "notebook" "workflow"])]
    (local store (. cold (.. kind "-store")))
    (local prefix (if (= kind "workflow") "definition" (= kind "notebook") "notebook"
                     (= kind "identity") "identity" (.. kind "-entity")))
    (each [_ event (ipairs ["created" "updated" "deleted" "items-changed"])]
      (local signal (. store (.. prefix "-" event)))
      (when signal (table.insert signals signal))))
  (var notifications 0)
  (fn notified [_] (set notifications (+ notifications 1)))
  (local handlers (icollect [_ signal (ipairs signals)] (signal:connect notified)))
  (local (ok result) (pcall service.start! service))
  (each [index signal (ipairs signals)] (signal:disconnect (. handlers index) true))
  (same before (H.snapshot-tree s.base-dir))
  (same [notifications reconciles] [0 0])
  (assert (not ok) (.. "expected replay rejection: " fragment))
  (assert (string.find (tostring result) fragment 1 true) (tostring result)))
(each [_ missing (ipairs ["before" "after" "both"])]
  (add (.. "capture " (if (= missing "both") "both missing" (.. "missing " missing)) " rejected")
    (fn missing-state [s]
      (seed s)
      (local intent (retained-incoming s "string-entity:s" false))
      (local capture {:owner "runtime" :world-id "w" :map-id false :before {} :after {}})
      (when (not (= missing "after")) (set capture.before nil))
      (when (not (= missing "before")) (set capture.after nil))
      (set intent.runtime-state [capture])
      (reject-edited s intent "runtime capture"))))
(add "capture asymmetric roles rejected" (fn asymmetric [s]
  (seed s)
  (local intent (retained-incoming s "string-entity:s" false))
  (each [_ role (ipairs ["board" "maps" "views" "metadata"])]
    (each [_ side (ipairs ["before" "after"])]
      (local capture {:owner "runtime" :world-id "w" :map-id "m" :before {} :after {}})
      (tset (. capture side) role {})
      (set intent.runtime-state [capture])
      (reject-edited s intent "runtime capture")))))
(fn seed-source [s kind]
  (if (= kind "notebook") (s.notebook-store:create-notebook {:id "s"})
      (= kind "morph") (s.string-store:create-entity {:id "s" :value "source"})
      (do
        (local store (. s (.. kind "-store")))
        (store:create-entity {:id "s" :value "source" :target-key "external:keep"
                              :source-key "external:from"})))
  (.. (if (= kind "notebook") "notebook" (= kind "identity") "identity"
          (= kind "morph") "string-entity" (.. kind "-entity")) ":s"))
(each [_ kind (ipairs ["string" "code" "list" "dict" "link" "identity" "notebook" "morph"])]
  (add (.. "source noop rejected " kind) (fn noop-source [s]
    (local key (seed-source s kind))
    (local intent (retained-incoming s key (= kind "morph")))
    (local source (change-at intent key))
    (assert (= source.phase "retire"))
    ;; Keep address/path/phase/fingerprint/request/operation unchanged.
    (set source.after-bytes source.before-check)
    (set source.after-check source.before-check)
    (reject-edited s intent "source"))))
(fn workflow-intent [s]
  (s.workflow-store:create-definition {:id "w" :steps [{:id "a" :code-entity-id "c"} {:id "keep" :code-entity-id "k"}]
    :edges [{:id "out" :source-step-id "a" :target-step-id "keep"}
            {:id "in" :source-step-id "keep" :target-step-id "a"}]})
  (retained-incoming s "workflow-step:w:a" false))
(each [_ variant (ipairs ["noop" "whole definition" "wrong definition" "incident edges"])]
  (add (.. "workflow source " variant " rejected") (fn invalid-workflow [s]
    (local intent (workflow-intent s))
    (local source (change-at intent "workflow:w"))
    (local after (json.loads source.after-bytes))
    (if (= variant "wrong definition") (set after.id "other")
        (= variant "incident edges") (set after.edges (. (json.loads source.before-check) :edges)))
    (set source.after-bytes (if (= variant "noop") source.before-check
                               (= variant "whole definition") false (json.dumps after)))
    (set source.after-check (R.check-bytes source.after-bytes "json"))
    (reject-edited s intent (if (= variant "incident edges") "workflow edge" "source")))))
(add "dependent retire update rejected" (fn dependent-retire [s]
  (seed s)
  (s.link-store:create-entity {:id "dependent" :source-key "string-entity:s" :target-key "external:keep"})
  (local intent (retained-incoming s "string-entity:s" false))
  (local change (change-at intent "link-entity:dependent"))
  (assert (= change.phase "retire"))
  (set change.after-bytes change.before-check)
  (set change.after-check change.before-check)
  (reject-edited s intent "retire")))
{:tests tests}
