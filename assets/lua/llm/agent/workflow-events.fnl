(local Temporal (require :temporal))

(local Migrations Temporal.migrations)

(local KIND_SESSION_CREATED :agent-session-created)
(local KIND_STATUS_CHANGED :agent-status-changed)
(local KIND_ITEM_APPENDED :agent-item-appended)
(local KIND_ITEM_UPSERTED :agent-item-upserted)
(local KIND_ITEM_UPDATED :agent-item-updated)
(local KIND_SESSION_DATA_UPDATED :agent-session-data-updated)

(fn table-or-empty [value]
  (if (= (type value) "table") value {}))

(fn projection-timestamp [value field-path]
  (when (not (= value nil))
    (Migrations.instant->timestamp value {:schema-id :agent-session-projection
                                          :field-path field-path})))

(fn deep-copy [value]
  (if (not (= (type value) "table"))
      value
      (do
        (local result {})
        (each [k v (pairs value)]
          (tset result k (deep-copy v)))
        result)))

(fn reserved-projection-key? [key]
  (if (= key :id)
      true
      (= key :workflow-run-id)
      true
      (= key :items)
      true
      (= key :agent-id)
      true
      (= key :status)
      true
      (= key :data)
      true
      (= key :created-at)
      true
      (= key :updated-at)
      true
      false))

(fn copy-projection-metadata! [session metadata]
  (each [k v (pairs (table-or-empty metadata))]
    (if (= k :id)
        (when (not session.legacy-session-id)
          (set session.legacy-session-id v))
        (= k :workflow-run-id)
        (when (not session.legacy-workflow-run-id)
          (set session.legacy-workflow-run-id v))
        (not (reserved-projection-key? k))
        (tset session k (deep-copy v))))
  session)

(fn assert-store [store]
  (assert store "workflow event helper requires store")
  (assert store.append-event "workflow event helper requires store:append-event")
  store)

(fn assert-run-id [run-id]
  (assert (= (type run-id) "string") "workflow event helper requires string run-id")
  run-id)

(fn assert-item [item]
  (assert (= (type item) "table") "agent item must be a table")
  (assert (= (type item.id) "string") "agent item requires string :id")
  item)

(fn assert-updates [updates]
  (assert (= (type updates) "table") "agent item updates must be a table")
  updates)

(fn item-index [items item-id]
  (var found nil)
  (each [idx item (ipairs (if items items []))]
    (when (= item.id item-id)
      (set found idx)))
  found)

(fn merge-into! [target updates]
  (each [k v (pairs (table-or-empty updates))]
    (tset target k v))
  target)

(fn relevant-event? [event]
  (if (= event.kind KIND_SESSION_CREATED)
      true
      (= event.kind KIND_STATUS_CHANGED)
      true
      (= event.kind KIND_ITEM_APPENDED)
      true
      (= event.kind KIND_ITEM_UPSERTED)
      true
      (= event.kind KIND_ITEM_UPDATED)
      true
      (= event.kind KIND_SESSION_DATA_UPDATED)
      true
      false))

(fn seed-session [run]
  (assert (= (type run) "table") "project-session requires workflow run")
  (local context (table-or-empty run.context))
  (local session {:id run.id
                  :workflow-run-id run.id
                  :agent-id context.agent-id
                  :status (or context.status run.status)
                  :items []
                  :data (deep-copy (table-or-empty context.data))
                  :created-at (projection-timestamp run.created-at "created-at")
                  :updated-at (projection-timestamp run.updated-at "updated-at")})
  (copy-projection-metadata! session context))

(fn apply-session-created! [session event]
  (local data (table-or-empty event.data))
  (when data.agent-id
    (set session.agent-id data.agent-id))
  (when data.data
    (set session.data (deep-copy data.data)))
  (copy-projection-metadata! session data)
  (when event.created-at
    (set session.created-at (projection-timestamp event.created-at "events[].created-at")))
  session)

(fn apply-session-data-updated! [session event]
  (set session.data (deep-copy (table-or-empty event.data)))
  session)

(fn append-projected-item! [session item]
  (assert-item item)
  (when (item-index session.items item.id)
    (error (.. "duplicate agent item id: " item.id)))
  (table.insert session.items (deep-copy item))
  session)

(fn upsert-projected-item! [session item]
  (assert-item item)
  (local index (item-index session.items item.id))
  (if index
      (tset session.items index (deep-copy item))
      (table.insert session.items (deep-copy item)))
  session)

(fn update-projected-item! [session item-id updates]
  (assert (= (type item-id) "string") "agent item update requires string :item-id")
  (assert-updates updates)
  (local index (item-index session.items item-id))
  (when (not index)
    (error (.. "missing agent item id for update: " item-id)))
  (merge-into! (. session.items index) (deep-copy updates))
  session)

(fn project-session [run]
  (local session (seed-session run))
  (each [_ event (ipairs (if run.events run.events []))]
    (if (= event.kind KIND_SESSION_CREATED)
        (apply-session-created! session event)
        (= event.kind KIND_STATUS_CHANGED)
        (set session.status event.status)
        (= event.kind KIND_ITEM_APPENDED)
        (append-projected-item! session event.item)
        (= event.kind KIND_ITEM_UPSERTED)
        (upsert-projected-item! session event.item)
        (= event.kind KIND_ITEM_UPDATED)
        (update-projected-item! session event.item-id event.updates)
        (= event.kind KIND_SESSION_DATA_UPDATED)
        (apply-session-data-updated! session event))
    (when (and (relevant-event? event) event.created-at)
      (set session.updated-at (projection-timestamp event.created-at "events[].created-at"))))
  session)

(fn current-session-if-readable [store run-id]
  (when store.get-run
    (local run (store:get-run run-id))
    (when run
      (project-session run))))

(fn append-isolated-event [store run-id event]
  (deep-copy (store:append-event run-id event)))

(fn append-session-created [store run-id data]
  (assert-store store)
  (assert-run-id run-id)
  (local payload (table-or-empty data))
  (append-isolated-event store run-id {:kind KIND_SESSION_CREATED
                                       :data (deep-copy payload)
                                       :created-at payload.created-at}))

(fn append-status [store run-id status data]
  (assert-store store)
  (assert-run-id run-id)
  (assert status "append-status requires status")
  (local payload (table-or-empty data))
  (append-isolated-event store run-id {:kind KIND_STATUS_CHANGED
                                       :status status
                                        :data (deep-copy payload)
                                        :created-at payload.created-at}))

(fn append-session-data-updated [store run-id data]
  (assert-store store)
  (assert-run-id run-id)
  (assert (= (type data) "table") "agent session data update must be a table")
  (append-isolated-event store run-id {:kind KIND_SESSION_DATA_UPDATED
                                       :data (deep-copy data)}))

(fn append-item [store run-id item]
  (assert-store store)
  (assert-run-id run-id)
  (assert-item item)
  (local session (current-session-if-readable store run-id))
  (when (and session (item-index session.items item.id))
    (error (.. "duplicate agent item id: " item.id)))
  (append-isolated-event store run-id {:kind KIND_ITEM_APPENDED
                                       :item (deep-copy item)
                                       :created-at item.created-at}))

(fn append-upsert [store run-id item]
  (assert-store store)
  (assert-run-id run-id)
  (assert-item item)
  (append-isolated-event store run-id {:kind KIND_ITEM_UPSERTED
                                       :item (deep-copy item)
                                       :created-at (if item.updated-at item.updated-at item.created-at)}))

(fn append-update [store run-id item-id updates]
  (assert-store store)
  (assert-run-id run-id)
  (assert (= (type item-id) "string") "append-update requires string item-id")
  (assert-updates updates)
  (local session (current-session-if-readable store run-id))
  (when (and session (not (item-index session.items item-id)))
    (error (.. "missing agent item id for update: " item-id)))
  (append-isolated-event store run-id {:kind KIND_ITEM_UPDATED
                                       :item-id item-id
                                       :updates (deep-copy updates)
                                       :created-at updates.updated-at}))

(fn session-summary [session]
  {:id session.id
   :agent-id session.agent-id
   :status session.status
   :item-count (length (if session.items session.items []))
   :created-at (projection-timestamp session.created-at "summary.created-at")
   :updated-at (projection-timestamp session.updated-at "summary.updated-at")})

{:KIND_SESSION_CREATED KIND_SESSION_CREATED
 :KIND_STATUS_CHANGED KIND_STATUS_CHANGED
  :KIND_ITEM_APPENDED KIND_ITEM_APPENDED
  :KIND_ITEM_UPSERTED KIND_ITEM_UPSERTED
  :KIND_ITEM_UPDATED KIND_ITEM_UPDATED
  :KIND_SESSION_DATA_UPDATED KIND_SESSION_DATA_UPDATED
  :append-session-created append-session-created
  :append-status append-status
  :append-session-data-updated append-session-data-updated
 :append-item append-item
 :append-upsert append-upsert
 :append-update append-update
 :project-session project-session
 :session-summary session-summary}
