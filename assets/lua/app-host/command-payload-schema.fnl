(local supported-types {:string true :number true :boolean true :select true})

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

(fn validate-select-options [field]
  (when (not (= (type field.options) :table))
    (schema-error (.. "select field " (field-name field) " requires options")))
  (when (= (# field.options) 0)
    (schema-error (.. "select field " (field-name field) " requires non-empty options")))
  (each [_ option (ipairs field.options)]
    (when (not (= (type option) :table))
      (schema-error (.. "select field " (field-name field) " option must be a table")))
    (when (= option.value nil)
      (schema-error (.. "select field " (field-name field) " option requires value")))
    (when (not (scalar? option.value))
      (schema-error (.. "select field " (field-name field) " option value must be scalar"))))
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
  (validate-default field)
  (when (= field.type :select)
    (validate-select-options field)))

(fn validate-schema [schema _context]
  (when (not (= (type schema) :table))
    (schema-error "schema must be a table"))
  (when (not (= (type schema.fields) :table))
    (schema-error "schema requires fields table"))
  (local seen-ids {})
  (each [_ field (ipairs schema.fields)]
    (validate-field field seen-ids))
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
