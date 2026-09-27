(local Input (require :input))
(local Button (require :button))
(local WrappedText (require :wrapped-text))
(local Padding (require :padding))
(local {: Flex : FlexChild} (require :flex))
(local Schema (require :app-host.command-payload-schema))

(fn form-error [message]
  (error (.. "[app-host.workspace-command-payload-form] " message)))

(fn label-for-field [field]
  (if field.label
      (tostring field.label)
      field.id
      (tostring field.id)
      "field"))

(fn set-button-text [button text]
  (assert (and button button.text button.text.set-text)
          "payload form button text widget is required")
  (button.text:set-text text))

(fn next-select-value [field current]
  (local options field.options)
  (var index 1)
  (each [i option (ipairs options)]
    (when (= option.value current)
      (set index i)))
  (local next-index (if (>= index (# options)) 1 (+ index 1)))
  (. (. options next-index) :value))

(fn input-backed-field? [field]
  (if (= field.type :string) true
      (= field.type :number) true
      false))

(fn boolean-click-handler [field state]
  (fn on-boolean-click [button _event]
    (local next (not (. state.values-by-id field.id)))
    (set (. state.values-by-id field.id) next)
    (set-button-text button (Schema.display-value field next))
    next))

(fn select-click-handler [field state]
  (fn on-select-click [button _event]
    (local next (next-select-value field (. state.values-by-id field.id)))
    (set (. state.values-by-id field.id) next)
    (set-button-text button (Schema.display-value field next))
    next))

(fn build-input-control [field state ctx default-value]
  (local control ((Input {:text (Schema.display-value field default-value)
                          :min-width 6.0})
                  ctx))
  (set (. state.inputs-by-id field.id) control)
  control)

(fn build-button-control [field state ctx default-value click-handler]
  (set (. state.values-by-id field.id) default-value)
  (local control ((Button {:text (Schema.display-value field default-value)
                           :on-click click-handler})
                  ctx))
  (set (. state.buttons-by-id field.id) control)
  control)

(fn build-control [field state ctx default-value]
  (if (input-backed-field? field)
      (build-input-control field state ctx default-value)
      (= field.type :boolean)
      (build-button-control field state ctx default-value (boolean-click-handler field state))
      (= field.type :select)
      (build-button-control field state ctx default-value (select-click-handler field state))
      (form-error (.. "unsupported field type: " (tostring field.type)))))

(fn field-row-builder [field state]
  (fn build [ctx]
    (local label ((WrappedText {:text (label-for-field field)}) ctx))
    (local default-value (Schema.default-value field))
    (local control (build-control field state ctx default-value))
    (fn build-label [_ctx]
      label)
    (fn build-control [_ctx]
      control)
    ((Flex {:axis 1
            :xspacing 0.5
            :yalign :center
            :children [(FlexChild build-label 0)
                       (FlexChild build-control 1)]})
     ctx)))

(fn CommandPayloadForm [opts]
  (when (not (= (type opts) :table))
    (form-error "opts table is required"))
  (local command (if opts.command
                   opts.command
                   (form-error "opts.command is required")))
  (fn build [ctx]
    (local schema (Schema.validate-schema command.payload-schema {:command-id command.id}))
    (local state {:inputs-by-id {}
                  :buttons-by-id {}
                  :values-by-id {}})
    (local children [])
    (each [_ field (ipairs schema.fields)]
      (table.insert children (FlexChild (field-row-builder field state) 0)))
    (local root-builder
      (Padding {:edge-insets [0.25 0.25]
                :child (Flex {:axis 2
                              :yspacing 0.35
                              :xalign :stretch
                              :children children})}))
    (local root (root-builder ctx))
    (var dropped? false)

    (fn build-payload [_self]
      (local field-values {})
      (each [field-id input (pairs state.inputs-by-id)]
        (set (. field-values field-id) (input:get-text)))
      (each [field-id value (pairs state.values-by-id)]
        (set (. field-values field-id) value))
      (Schema.payload-from-values schema field-values {:command-id command.id}))

    (fn drop [_self]
      (when (not dropped?)
        (set dropped? true)
        (root:drop)))

    {:layout root.layout
     :drop drop
     :inputs-by-id state.inputs-by-id
     :buttons-by-id state.buttons-by-id
     :values-by-id state.values-by-id
     :build-payload build-payload}))

{:CommandPayloadForm CommandPayloadForm}
