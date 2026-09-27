(local max-value-length 500)
(local truncation-suffix "... [truncated]")
(local max-table-depth 4)
(local max-table-entries 24)

(fn command-label [command]
  (if (and command command.title)
      (tostring command.title)
      (and command command.id)
      (tostring command.id)
      "command"))

(fn scalar-text [value]
  (local value-type (type value))
  (if (= value-type :function)
      "<function>"
      (= value-type :thread)
      "<thread>"
      (= value-type :userdata)
      "<userdata>"
      (tostring value)))

(fn key-display-text [key]
  (if (= (type key) :string)
      (.. ":" key)
      (= (type key) :table)
      "<table>"
      (scalar-text key)))

(fn key-sort-text [key]
  (local key-type (type key))
  (if (= key-type :string)
      (.. "1:string:" key)
      (= key-type :number)
      (.. "2:number:" (tostring key))
      (= key-type :boolean)
      (.. "3:boolean:" (tostring key))
      (= key-type :table)
      "8:table"
      (= key-type :function)
      "8:function"
      (= key-type :thread)
      "8:thread"
      (= key-type :userdata)
      "8:userdata"
      (.. "9:other:" key-type)))

(fn sorted-table-keys [tbl]
  (local keys [])
  (each [key value (pairs tbl)]
    (table.insert keys key))
  (table.sort keys (fn [a b] (< (key-sort-text a) (key-sort-text b))))
  keys)

(fn sorted-table-entry-texts [tbl seen render-value depth]
  (local keys (sorted-table-keys tbl))
  (local entries [])
  (local entry-count (# keys))
  (local render-count (math.min entry-count max-table-entries))
  (for [index 1 render-count]
    (local key (. keys index))
    (local rendered-value (render-value (. tbl key) seen (+ depth 1)))
    (local text (.. (key-display-text key) "=" rendered-value))
    (table.insert entries {:sort (.. (key-sort-text key) "\31" rendered-value "\31" text)
                           :text text}))
  (table.sort entries (fn [a b] (< a.sort b.sort)))
  (local parts [])
  (each [_ entry (ipairs entries)]
    (table.insert parts entry.text))
  (when (> entry-count max-table-entries)
    (table.insert parts (.. "... " (- entry-count max-table-entries) " more entries")))
  parts)

(fn raw-value-text [value seen depth]
  (if (= value nil)
      nil
      (= (type value) :table)
      (if (>= depth max-table-depth)
          "<max depth>"
          (. seen value)
          "<cycle>"
          (do
            (tset seen value true)
            (local parts (sorted-table-entry-texts value seen raw-value-text depth))
            (tset seen value nil)
            (.. "{" (table.concat parts ", ") "}")))
      (scalar-text value)))

(fn truncate-value [text]
  (if (and text (> (# text) max-value-length))
      (.. (string.sub text 1 (- max-value-length (# truncation-suffix))) truncation-suffix)
      text))

(fn value-text [value]
  (truncate-value (raw-value-text value {} 0)))

(fn summary [phase badge-text tone message command result]
  {:phase phase
   :badge-text badge-text
   :tone tone
   :message message
   :command-id (if command command.id nil)
   :result result})

(fn initial-summary []
  (summary :idle "Idle" :neutral "No command run yet" nil nil))

(fn confirmation-summary [command message]
  (summary :confirming "Confirm" :warning message command nil))

(fn running-summary [command]
  (summary :running "Running" :info (.. (command-label command) " is running...") command nil))

(fn progress-percent-text [progress]
  (local value (and progress progress.value))
  (if (and (= (type value) :number) (>= value 0) (<= value 1))
      (.. (math.floor (+ (* value 100) 0.5)) "%")
      nil))

(fn progress-summary [command progress]
  (local label (command-label command))
  (local message (and progress progress.message))
  (local percent (progress-percent-text progress))
  (summary :running "Running" :info
           (if (and message percent)
               (.. label " is running: " message " (" percent ")")
               message
               (.. label " is running: " message)
               percent
               (.. label " is running: " percent)
               (.. label " is running..."))
           command nil))

(fn result-summary [command result]
  (local label (command-label command))
  (if (= result.status :ok)
      (do
        (local rendered (value-text result.value))
        (summary :ok "Success" :success
                 (if rendered (.. label " succeeded: " rendered) (.. label " succeeded"))
                  command result))
      (= result.status :error)
      (summary :error "Error" :danger (.. label " failed: " (tostring result.error)) command result)
      (= result.status :cancelled)
      (summary :cancelled "Cancelled" :warning
               (if result.error
                   (.. label " cancelled: " (tostring result.error))
                   (.. label " cancelled"))
               command result)
      (summary :unknown "Unknown" :warning (.. label " returned status " (tostring result.status)) command result)))

{:initial-summary initial-summary
 :confirmation-summary confirmation-summary
 :running-summary running-summary
 :progress-summary progress-summary
 :result-summary result-summary
 :value-text value-text}
