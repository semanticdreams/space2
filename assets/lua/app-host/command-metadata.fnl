(local PayloadSchema (require :app-host.command-payload-schema))

(local danger-levels {:normal true :warning true :danger true})
(local confirmation-keys {:message true :required? true})

(fn metadata-error [message]
  (error (.. "[app-host.command-metadata] " message)))

(fn validate-confirmation [conf _context]
  (if (= conf nil)
      nil
      (do
        (when (not (= (type conf) :table))
          (metadata-error "confirmation must be a table"))
        (each [key _value (pairs conf)]
          (when (not (. confirmation-keys key))
            (metadata-error (.. "unsupported confirmation key: " (tostring key)))))
        (when (and (not (= conf.message nil)) (not (= (type conf.message) :string)))
          (metadata-error "confirmation.message must be a string"))
        (when (and (not (= conf.required? nil)) (not (= (type conf.required?) :boolean)))
          (metadata-error "confirmation.required? must be a boolean"))
        (local normalized {:required? (if (= conf.required? nil) true conf.required?)})
        (when (not (= conf.message nil))
          (set normalized.message conf.message))
        normalized)))

(fn danger-level [command]
  (local level command.danger-level)
  (if (= level nil)
      :normal
      (. danger-levels level)
      level
      (metadata-error (.. "unsupported danger-level: " (tostring level)))))

(fn confirmation [command]
  (validate-confirmation command.confirmation nil))

(fn confirmation-required? [command]
  (local conf (confirmation command))
  (and (not (= conf nil)) (= conf.required? true)))

(fn validate-command [command context]
  (when (not (= (type command) :table))
    (metadata-error "command must be a table"))
  (danger-level command)
  (validate-confirmation command.confirmation context)
  (when (not (= command.payload-schema nil))
    (PayloadSchema.validate-schema command.payload-schema context))
  command)

{:validate-command validate-command
 :danger-level danger-level
 :confirmation confirmation
 :confirmation-required? confirmation-required?}
