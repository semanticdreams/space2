(local Button (require :button))
(local Padding (require :padding))
(local WrappedText (require :wrapped-text))
(local StatusBadge (require :status-badge))
(local {: Flex : FlexChild} (require :flex))
(local PayloadForm (require :app-host.workspace-command-payload-form))
(local Metadata (require :app-host.command-metadata))
(local ResultModel (require :app-host.command-result-model))

(fn controls-error [message]
  (error (.. "[app-host.workspace-command-controls] " message)))

(fn label-for-command [command]
  (if command.title
      (tostring command.title)
      command.id
      (tostring command.id)
      "command"))

(fn command-description [command]
  (local title (label-for-command command))
  (if command.description
      (.. title "\n" (tostring command.description))
      title))

(fn danger-tone [level]
  (if (= level :warning) :warning
      (= level :danger) :danger
      :neutral))

(fn danger-button-variant [level]
  (if (= level :warning) :warning
      (= level :danger) :danger
      nil))

(fn command-label [command]
  (label-for-command command))

(fn confirmation-message [command confirmation]
  (if (and confirmation confirmation.message)
      confirmation.message
      (.. "Confirm run for " (command-label command) "?")))

(fn validate-commands [commands]
  (each [_ command (ipairs commands)]
    (Metadata.validate-command command {:command-id command.id})))

(fn set-button-label [button label]
  (when (and button button.text button.text.set-text)
    (button.text:set-text label))
  label)

(fn restore-button-labels [state]
  (each [command-id button (pairs state.buttons-by-id)]
    (set-button-label button "Run")
    (tset state.button-labels-by-id command-id "Run")))

(fn set-command-buttons-enabled [state enabled?]
  (each [_ button (pairs state.buttons-by-id)]
    (when button.set-enabled
      (button:set-enabled enabled?))))

(fn set-active-command [state command-id]
  (set state.active-command-id command-id))

(fn build-command-header-row [command state ctx]
  (local text ((WrappedText {:text (command-description command)}) ctx))
  (local level (Metadata.danger-level command))
  (local badge ((StatusBadge {:text (tostring level)
                              :tone (danger-tone level)})
                 ctx))
  (local variant (danger-button-variant level))
  (fn on-run-button-click [_button _event]
    (state.run-command command))
  (local button ((Button {:text "Run"
                          :variant variant
                          :on-click on-run-button-click})
                  ctx))
  (set button.variant variant)
  (set badge.tone (danger-tone level))
  (set badge.text (tostring level))
  (when command.id
    (tset state.danger-levels-by-id command.id level)
    (tset state.danger-badges-by-id command.id badge)
    (tset state.button-labels-by-id command.id "Run")
    (tset state.buttons-by-id command.id button))
  (fn build-text [_ctx]
    text)
  (fn build-badge [_ctx]
    badge)
  (fn build-button [_ctx]
    button)
  ((Flex {:axis 1
          :xspacing 0.5
          :yalign :center
          :children [(FlexChild build-text 1)
                     (FlexChild build-badge 0)
                     (FlexChild build-button 0)]})
   ctx))

(fn build-command-row [command state ctx]
  (local header (build-command-header-row command state ctx))
  (if (not (= command.payload-schema nil))
      (do
        (local form-builder (PayloadForm.CommandPayloadForm {:command command}))
        (local form (form-builder ctx))
        (when command.id
          (tset state.forms-by-id command.id form))
        (fn build-header [_ctx]
          header)
        (fn build-form [_ctx]
          form)
        ((Flex {:axis 2
                :yspacing 0.25
                :xalign :stretch
                :children [(FlexChild build-header 0)
                           (FlexChild build-form 0)]})
         ctx))
      header))

(fn command-row [command state]
  (fn build [ctx]
    (build-command-row command state ctx)))

(fn WorkspaceCommandControls [opts]
  (when (not (= (type opts) :table))
    (controls-error "opts table is required"))
  (local descriptor (if opts.descriptor
                       opts.descriptor
                       (controls-error "opts.descriptor is required")))
  (fn build [ctx]
    (local snapshot (descriptor:read-inspector-snapshot))
    (local commands (if snapshot.commands snapshot.commands []))
    (validate-commands commands)
    (local initial-summary (ResultModel.initial-summary))
    (var result-text nil)
    (var dropped? false)
    (local state {:snapshot snapshot
                    :commands commands
                    :buttons-by-id {}
                    :button-labels-by-id {}
                    :danger-levels-by-id {}
                    :danger-badges-by-id {}
                     :forms-by-id {}
                     :confirming-command-id nil
                     :last-result nil
                     :busy? false
                     :active-command-id nil
                     :result-summary initial-summary
                     :result-message initial-summary.message
                     :result-badge nil})

    (fn apply-result-summary [summary]
      (set state.result-summary summary)
      (set state.result-message summary.message)
      (when state.result-badge
        (state.result-badge:set-text summary.badge-text)
        (state.result-badge:set-tone summary.tone)
        (set state.result-badge.text summary.badge-text)
        (set state.result-badge.tone summary.tone))
      (when result-text
        (result-text:set-text summary.message))
      summary)

    (fn run-command [command]
      (if state.busy?
          nil
          (do
            (local confirmation (Metadata.confirmation command))
            (local requires-confirmation? (Metadata.confirmation-required? command))
            (local already-confirming? (= state.confirming-command-id command.id))
            (if (and requires-confirmation? (not already-confirming?))
                (do
                  (restore-button-labels state)
                  (set state.confirming-command-id command.id)
                  (local message (confirmation-message command confirmation))
                  (apply-result-summary (ResultModel.confirmation-summary command message))
                  (local button (. state.buttons-by-id command.id))
                  (set-button-label button "Confirm")
                  (tset state.button-labels-by-id command.id "Confirm")
                  nil)
                (do
                  (local previous-summary state.result-summary)
                  (local form (. state.forms-by-id command.id))
                  (local payload (if form (form:build-payload) nil))
                  (set state.confirming-command-id nil)
                  (restore-button-labels state)
                  (set state.busy? true)
                  (set-active-command state command.id)
                  (set-command-buttons-enabled state false)
                  (apply-result-summary (ResultModel.running-summary command))
                  (local (ok result-or-error) (pcall #(descriptor:run-command command.id payload)))
                  (set-command-buttons-enabled state true)
                  (set state.busy? false)
                  (set-active-command state nil)
                  (restore-button-labels state)
                  (if ok
                      (do
                        (set state.last-result result-or-error)
                        (apply-result-summary (ResultModel.result-summary command result-or-error))
                        result-or-error)
                      (do
                        (apply-result-summary previous-summary)
                        (error result-or-error))))))))

    (set state.run-command run-command)
    (fn result-builder [child-ctx]
      (local badge ((StatusBadge {:text state.result-summary.badge-text
                                  :tone state.result-summary.tone})
                     child-ctx))
      (set badge.text state.result-summary.badge-text)
      (set badge.tone state.result-summary.tone)
      (set state.result-badge badge)
      (set result-text ((WrappedText {:text state.result-message}) child-ctx))
      (fn build-badge [_ctx]
        badge)
      (fn build-text [_ctx]
        result-text)
      ((Flex {:axis 1
              :xspacing 0.5
              :yalign :center
              :children [(FlexChild build-badge 0)
                         (FlexChild build-text 1)]})
       child-ctx))
    (local children [])
    (each [_ command (ipairs commands)]
      (table.insert children (FlexChild (command-row command state) 0)))
    (table.insert children (FlexChild result-builder 0))
    (local root-builder
      (Padding {:edge-insets [0.5 0.5]
                :child (Flex {:axis 2
                              :yspacing 0.5
                              :xalign :stretch
                              :children children})}))
    (local root (root-builder ctx))

    (fn drop [_self]
      (when (not dropped?)
        (set dropped? true)
        (root:drop)))

    {:layout root.layout
     :drop drop
     :hosted-app-workspace-panel descriptor
     :__command-controls state}))

{:WorkspaceCommandControls WorkspaceCommandControls}
