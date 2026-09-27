(local supported-types {:string true :number true :boolean true :select true})
(local schema-keys {:fields true})
(local field-keys {:id true :type true :label true :default true})
(local select-field-keys {:id true :type true :label true :default true :options true})
(local option-keys {:value true :label true})

(fn schema-error [message]
  (error (.. "[app-host.command-payload-schema] " message)))

(fn scalar? [value]
  (local t (type value))
  (if (= t :string) true
      (= t :number) true
      (= t :boolean) true
      (= t :nil) true
      false))

(fn field-name [field]
  (tostring (if field field.id nil)))

(fn option-matches? [option value]
  (= option.value value))

(fn select-has-value? [field value]
  (var found? false)
  (each [_ option (ipairs field.options)]
    (when (option-matches? option value)
      (set found? true)))
  found?)

(fn validate-default [field]
  (when (not (= field.default nil))
    (local default-type (type field.default))
    (when (and (= field.type :string) (not (= default-type :string)))
      (schema-error (.. "default for field " (field-name field) " must be string")))
    (when (and (= field.type :number) (not (= default-type :number)))
      (schema-error (.. "default for field " (field-name field) " must be number")))
    (when (and (= field.type :boolean) (not (= default-type :boolean)))
      (schema-error (.. "default for field " (field-name field) " must be boolean")))))

(fn validate-allowed-keys [value allowed kind]
  (each [key _item (pairs value)]
    (when (not (. allowed key))
      (schema-error (.. "unsupported " kind " key: " (tostring key))))))

(fn validate-label [field]
  (when (and (not (= field.label nil)) (not (scalar? field.label)))
    (schema-error (.. "label for field " (field-name field) " must be scalar"))))

(fn list-index? [key]
  (and (= (type key) :number)
       (>= key 1)
       (= key (math.floor key))))

(fn validate-ordered-list [items message]
  (var count 0)
  (var max-index 0)
  (each [key _item (pairs items)]
    (when (not (list-index? key))
      (schema-error message))
    (set count (+ count 1))
    (when (> key max-index)
      (set max-index key)))
  (when (not (= count max-index))
    (schema-error message))
  (for [index 1 max-index]
    (when (= (. items index) nil)
      (schema-error message)))
  max-index)

(fn validate-fields-list [fields]
  (validate-ordered-list fields "fields must be an ordered list"))

(fn validate-options-list [field]
  (validate-ordered-list field.options (.. "options for field " (field-name field) " must be an ordered list")))

(fn validate-select-options [field]
  (when (not (= (type field.options) :table))
    (schema-error (.. "select field " (field-name field) " requires options")))
  (when (= (# field.options) 0)
    (schema-error (.. "select field " (field-name field) " requires non-empty options")))
  (local option-count (validate-options-list field))
  (for [index 1 option-count]
    (local option (. field.options index))
    (when (not (= (type option) :table))
      (schema-error (.. "select field " (field-name field) " option must be a table")))
    (validate-allowed-keys option option-keys "option")
    (when (= option.value nil)
      (schema-error (.. "select field " (field-name field) " option requires value")))
    (when (not (scalar? option.value))
      (schema-error (.. "select field " (field-name field) " option value must be scalar")))
    (when (and (not (= option.label nil)) (not (scalar? option.label)))
      (schema-error (.. "select field " (field-name field) " option label must be scalar"))))
  (when (and (not (= field.default nil)) (not (select-has-value? field field.default)))
    (schema-error (.. "select field " (field-name field) " default must match an option"))))

(fn validate-field [field seen-ids]
  (when (not (= (type field) :table))
    (schema-error "field must be a table"))
  (when (= field.id nil)
    (schema-error "field requires id"))
  (when (. seen-ids field.id)
    (schema-error (.. "duplicate field id: " (tostring field.id))))
  (set (. seen-ids field.id) true)
  (when (not (. supported-types field.type))
    (schema-error (.. "unsupported field type: " (tostring field.type))))
  (validate-allowed-keys field (if (= field.type :select) select-field-keys field-keys) "field")
  (validate-label field)
  (validate-default field)
  (when (= field.type :select)
    (validate-select-options field)))

(fn validate-schema [schema _context]
  (when (not (= (type schema) :table))
    (schema-error "schema must be a table"))
  (validate-allowed-keys schema schema-keys "schema")
  (when (not (= (type schema.fields) :table))
    (schema-error "schema requires fields table"))
  (local field-count (validate-fields-list schema.fields))
  (local seen-ids {})
  (for [index 1 field-count]
    (validate-field (. schema.fields index) seen-ids))
  schema)

(fn default-value [field]
  (if (= field.type :string) (if (= field.default nil) "" field.default)
      (= field.type :number) (if (= field.default nil) "" (tostring field.default))
      (= field.type :boolean) (if (= field.default nil) false field.default)
      (= field.type :select) (if (not (= field.default nil)) field.default (. (. field.options 1) :value))
      nil))

(fn display-value [field value]
  (if (= field.type :select)
      (do
        (var label nil)
        (each [_ option (ipairs field.options)]
          (when (option-matches? option value)
            (set label option.label)))
        (if (not (= label nil)) (tostring label) (tostring value)))
      (= field.type :boolean) (if value "true" "false")
      (= value nil) ""
      (tostring value)))

(fn payload-value [field field-values]
  (local value (. field-values field.id))
  (if (= field.type :string)
      (if (= value nil) "" value)
      (= field.type :number)
      (do
        (local number-value (tonumber value))
        (when (= number-value nil)
          (schema-error (.. "number field " (field-name field) " requires numeric value")))
        number-value)
      (= field.type :boolean)
      (do
        (when (not (= (type value) :boolean))
          (schema-error (.. "boolean field " (field-name field) " requires boolean value")))
        value)
      (= field.type :select)
      (do
        (when (not (select-has-value? field value))
          (schema-error (.. "select field " (field-name field) " requires declared option value")))
        value)
      value))

(fn payload-from-values [schema field-values context]
  (validate-schema schema context)
  (when (not (= (type field-values) :table))
    (schema-error "values must be a table"))
  (local payload {})
  (each [_ field (ipairs schema.fields)]
    (set (. payload field.id) (payload-value field field-values)))
  payload)

{:validate-schema validate-schema
 :default-value default-value
 :display-value display-value
 :payload-from-values payload-from-values}
