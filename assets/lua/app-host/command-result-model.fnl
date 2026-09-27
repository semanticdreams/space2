(local max-value-length 500)
(local truncation-suffix "... [truncated]")

(fn command-label [command]
  (if (and command command.title)
      (tostring command.title)
      (and command command.id)
      (tostring command.id)
      "command"))

(fn sorted-table-keys [tbl]
  (local keys [])
  (each [k _v (pairs tbl)]
    (table.insert keys k))
  (table.sort keys (fn [a b] (< (tostring a) (tostring b))))
  keys)

(fn scalar-text [value]
  (local value-type (type value))
  (if (= value-type :function)
      "<function>"
      (= value-type :thread)
      "<thread>"
      (= value-type :userdata)
      "<userdata>"
      (tostring value)))

(fn key-text [key]
  (if (= (type key) :string)
      (.. ":" key)
      (tostring key)))

(fn raw-value-text [value seen]
  (if (= value nil)
      nil
      (= (type value) :table)
      (if (. seen value)
          "<cycle>"
          (do
            (tset seen value true)
            (local parts [])
            (each [_ key (ipairs (sorted-table-keys value))]
              (table.insert parts (.. (key-text key) "=" (raw-value-text (. value key) seen))))
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
