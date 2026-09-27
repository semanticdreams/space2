(local ResultModel (require :app-host.command-result-model))

(local default-limit 10)

(fn default-now []
  (os.time))

(fn valid-limit [limit]
  (if (and (= (type limit) :number) (>= limit 1))
      limit
      default-limit))

(fn command-title [command]
  (if (and command command.title)
      (tostring command.title)
      (and command command.id)
      (tostring command.id)
      "command"))

(fn bounded-text [value]
  (ResultModel.value-text value))

(fn status-text [status]
  (bounded-text (tostring status)))

(fn entry-for-id [history run-id]
  (. history.by-id run-id))

(fn trim-history! [history]
  (while (> (# history.entries) history.limit)
    (local evicted (table.remove history.entries))
    (when evicted
      (tset history.by-id evicted.run-id nil))))

(fn create [opts]
  (local options (if opts opts {}))
  {:entries []
   :by-id {}
   :next-run-id 1
   :limit (valid-limit options.limit)
   :now (if options.now options.now default-now)})

(fn entry-command [entry command]
  (if command
      command
      {:id entry.command-id :title entry.title}))

(fn start-run! [history command]
  (local now (history.now))
  (local run-id history.next-run-id)
  (set history.next-run-id (+ history.next-run-id 1))
  (local entry {:run-id run-id
                :command-id (and command command.id)
                :title (command-title command)
                :status :running
                :started-at now
                :updated-at now})
  (table.insert history.entries 1 entry)
  (tset history.by-id run-id entry)
  (trim-history! history)
  entry)

(fn set-payload! [history run-id payload]
  (local entry (entry-for-id history run-id))
  (when entry
    (set entry.payload-text (bounded-text payload))
    (set entry.updated-at (history.now)))
  entry)

(fn progress! [history run-id command progress]
  (local entry (entry-for-id history run-id))
  (when entry
    (set entry.command-id (if (and command command.id) command.id entry.command-id))
    (set entry.title (command-title (entry-command entry command)))
    (set entry.status :running)
    (set entry.progress-text (and progress progress.message (bounded-text progress.message)))
    (set entry.progress-value (and progress progress.value))
    (set entry.updated-at (history.now)))
  entry)

(fn finish! [history run-id command result]
  (local entry (entry-for-id history run-id))
  (when entry
    (set entry.command-id (if (and command command.id) command.id entry.command-id))
    (set entry.title (command-title (entry-command entry command)))
    (local status (and result result.status))
    (if (= status :ok)
        (do
          (set entry.status :ok)
          (set entry.result-text (bounded-text (and result result.value))))
        (= status :error)
        (do
          (set entry.status :error)
          (set entry.error-text (bounded-text (tostring (and result result.error)))))
        (= status :cancelled)
        (do
          (set entry.status :cancelled)
          (when (and result result.error)
            (set entry.error-text (bounded-text (tostring result.error)))))
        (do
          (set entry.status :unknown)
          (set entry.result-status-text (status-text status))))
    (set entry.updated-at (history.now)))
  entry)

(fn fail! [history run-id command err]
  (local entry (entry-for-id history run-id))
  (when entry
    (set entry.command-id (if (and command command.id) command.id entry.command-id))
    (set entry.title (command-title (entry-command entry command)))
    (set entry.status :error)
    (set entry.error-text (bounded-text (tostring err)))
    (set entry.updated-at (history.now)))
  entry)

(fn entries [history]
  history.entries)

(fn add-part! [parts label value]
  (when value
    (table.insert parts (.. label value))))

(fn entry-text [entry]
  (local parts [(.. entry.title " [" (tostring entry.status) "]")])
  (add-part! parts "payload=" entry.payload-text)
  (add-part! parts "progress=" entry.progress-text)
  (add-part! parts "result=" entry.result-text)
  (add-part! parts "error=" entry.error-text)
  (add-part! parts "status=" entry.result-status-text)
  (table.concat parts " | "))

(fn list-text [history]
  (local lines ["Recent runs"])
  (if (= (# history.entries) 0)
      (table.insert lines "No command runs yet")
      (each [_ entry (ipairs history.entries)]
        (table.insert lines (entry-text entry))))
  (table.concat lines "\n"))

{:create create
 :start-run! start-run!
 :set-payload! set-payload!
 :progress! progress!
 :finish! finish!
 :fail! fail!
 :entries entries
 :entry-text entry-text
 :list-text list-text}
