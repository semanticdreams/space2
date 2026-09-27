(local max-value-length 500)
(local truncation-suffix "... [truncated]")

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

(fn sorted-table-entry-texts [tbl seen render-value]
  (local entries [])
  (each [key value (pairs tbl)]
    (local rendered-value (render-value value seen))
    (local text (.. (key-display-text key) "=" rendered-value))
    (table.insert entries {:sort (.. (key-sort-text key) "\31" rendered-value "\31" text)
                           :text text}))
  (table.sort entries (fn [a b] (< a.sort b.sort)))
  (local parts [])
  (each [_ entry (ipairs entries)]
    (table.insert parts entry.text))
  parts)

(fn raw-value-text [value seen]
  (if (= value nil)
      nil
      (= (type value) :table)
      (if (. seen value)
          "<cycle>"
          (do
            (tset seen value true)
            (local parts (sorted-table-entry-texts value seen raw-value-text))
            (tset seen value nil)
            (.. "{" (table.concat parts ", ") "}")))
      (scalar-text value)))

(fn truncate-value [text]
  (if (and text (> (# text) max-value-length))
      (.. (string.sub text 1 (- max-value-length (# truncation-suffix))) truncation-suffix)
      text))

(fn value-text [value]
  (truncate-value (raw-value-text value {})))

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
      (summary :unknown "Unknown" :warning (.. label " returned status " (tostring result.status)) command result)))

{:initial-summary initial-summary
 :confirmation-summary confirmation-summary
 :running-summary running-summary
 :result-summary result-summary
 :value-text value-text}
