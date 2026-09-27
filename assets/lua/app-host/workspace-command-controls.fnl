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

(fn set-running-button-state [state active-command-id]
  (each [command-id button (pairs state.buttons-by-id)]
    (local active? (= command-id active-command-id))
    (when button.set-enabled
      (button:set-enabled active?))
    (if active?
        (do
          (set-button-label button "Cancel")
          (tset state.button-labels-by-id command-id "Cancel"))
        (do
          (set-button-label button "Run")
          (tset state.button-labels-by-id command-id "Run")))))

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

(fn restore-after-structural-error [state previous-summary apply-result-summary]
  (apply-result-summary previous-summary)
  (set state.busy? false)
  (set-active-command state nil)
  (set-command-buttons-enabled state true)
  (restore-button-labels state))

(fn make-initial-state [snapshot commands initial-summary]
  {:snapshot snapshot
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
    :active-invocation nil
    :active-run-token 0
    :result-summary initial-summary
    :result-message initial-summary.message
    :result-badge nil})

(fn callback-current? [state dropped?-fn token command-id]
  (and (not (dropped?-fn))
       (= state.active-run-token token)
       (= state.active-command-id command-id)))

(fn finish-terminal-result [state apply-result-summary command result]
  (set state.last-result result)
  (set state.busy? false)
  (set state.active-invocation nil)
  (set-active-command state nil)
  (set-command-buttons-enabled state true)
  (restore-button-labels state)
  (apply-result-summary (ResultModel.result-summary command result))
  result)

(fn cancel-active-command [state apply-result-summary command]
  (local invocation state.active-invocation)
  (local result {:id command.id :status :cancelled})
  (set state.active-invocation nil)
  (set state.busy? false)
  (set-active-command state nil)
  (set-command-buttons-enabled state true)
  (restore-button-labels state)
  (when (and invocation invocation.cancel)
    (invocation:cancel))
  (set state.last-result result)
  (apply-result-summary (ResultModel.result-summary command result))
  result)

(fn start-async-command [descriptor state apply-result-summary dropped?-fn command payload previous-summary]
  (set state.active-run-token (+ state.active-run-token 1))
  (local token state.active-run-token)
  (set state.busy? true)
  (set-active-command state command.id)
  (set-running-button-state state command.id)
  (apply-result-summary (ResultModel.running-summary command))
  (fn on-progress [progress]
    (when (callback-current? state dropped?-fn token command.id)
      (apply-result-summary (ResultModel.progress-summary command progress))))
  (fn on-result [result]
    (when (callback-current? state dropped?-fn token command.id)
      (finish-terminal-result state apply-result-summary command result)))
  (fn invoke-async []
    (descriptor:run-command-async command.id payload {:on-progress on-progress :on-result on-result}))
  (local (ok invocation-or-error) (pcall invoke-async))
  (if ok
      (do
        (when (callback-current? state dropped?-fn token command.id)
          (set state.active-invocation invocation-or-error))
        invocation-or-error)
      (do
        (restore-after-structural-error state previous-summary apply-result-summary)
        (set state.active-invocation nil)
        (error invocation-or-error))))

(fn run-sync-command [descriptor state apply-result-summary command payload previous-summary]
  (set state.active-run-token (+ state.active-run-token 1))
  (set state.busy? true)
  (set-active-command state command.id)
  (set-command-buttons-enabled state false)
  (apply-result-summary (ResultModel.running-summary command))
  (fn invoke-sync []
    (descriptor:run-command command.id payload))
  (local (ok result-or-error) (pcall invoke-sync))
  (if ok
      (finish-terminal-result state apply-result-summary command result-or-error)
      (do
        (restore-after-structural-error state previous-summary apply-result-summary)
        (error result-or-error))))

(fn build-command-payload [form]
  (if form (form:build-payload) nil))

(fn execute-command [descriptor state apply-result-summary dropped?-fn command previous-summary]
  (local form (. state.forms-by-id command.id))
  (set state.confirming-command-id nil)
  (restore-button-labels state)
  (local (payload-ok payload-or-error) (pcall #(build-command-payload form)))
  (when (not payload-ok)
    (restore-after-structural-error state previous-summary apply-result-summary)
    (error payload-or-error))
  (local payload payload-or-error)
  (if (. descriptor :run-command-async)
      (start-async-command descriptor state apply-result-summary dropped?-fn command payload previous-summary)
      (run-sync-command descriptor state apply-result-summary command payload previous-summary)))

(fn prompt-for-confirmation [state apply-result-summary command confirmation]
  (restore-button-labels state)
  (set state.confirming-command-id command.id)
  (local message (confirmation-message command confirmation))
  (apply-result-summary (ResultModel.confirmation-summary command message))
  (local button (. state.buttons-by-id command.id))
  (set-button-label button "Confirm")
  (tset state.button-labels-by-id command.id "Confirm")
  nil)

(fn make-run-command [descriptor state apply-result-summary dropped?-fn]
  (fn run-command [command]
    (if state.busy?
        (if (= state.active-command-id command.id)
            (cancel-active-command state apply-result-summary command)
            nil)
        (do
          (local confirmation (Metadata.confirmation command))
          (local requires-confirmation? (Metadata.confirmation-required? command))
          (local already-confirming? (= state.confirming-command-id command.id))
          (if (and requires-confirmation? (not already-confirming?))
              (prompt-for-confirmation state apply-result-summary command confirmation)
              (execute-command descriptor state apply-result-summary dropped?-fn command state.result-summary))))))

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
    (local state (make-initial-state snapshot commands initial-summary))

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

    (fn dropped []
      dropped?)
    (set state.run-command (make-run-command descriptor state apply-result-summary dropped))
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
        (local invocation state.active-invocation)
        (set state.active-invocation nil)
        (set dropped? true)
        (when (and invocation invocation.drop)
          (invocation:drop))
        (root:drop)))

    {:layout root.layout
     :drop drop
     :hosted-app-workspace-panel descriptor
     :__command-controls state}))

{:WorkspaceCommandControls WorkspaceCommandControls}
