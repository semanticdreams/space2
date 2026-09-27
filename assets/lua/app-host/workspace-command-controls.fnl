(local Button (require :button))
(local Padding (require :padding))
(local WrappedText (require :wrapped-text))
(local StatusBadge (require :status-badge))
(local {: Flex : FlexChild} (require :flex))
(local PayloadForm (require :app-host.workspace-command-payload-form))
(local Schema (require :app-host.command-payload-schema))

(fn controls-error [message]
  (error (.. "[app-host.workspace-command-controls] " message)))

(fn label-for-command [command]
  (if command.title
      (tostring command.title)
      command.id
      (tostring command.id)
      "command"))

(fn result-message [command result]
  (local label (label-for-command command))
  (if (= result.status :ok)
      (.. label " succeeded")
      (= result.status :error)
      (.. label " failed: " (tostring result.error))
      (.. label " returned status " (tostring result.status))))

(fn command-description [command]
  (local title (label-for-command command))
  (if command.description
      (.. title "\n" (tostring command.description))
      title))

(fn status-text-for-command [command]
  (if (not (= command.status nil))
      (tostring command.status)
      "metadata"))

(fn validate-command-schemas [commands]
  (each [_ command (ipairs commands)]
    (when (not (= command.payload-schema nil))
      (Schema.validate-schema command.payload-schema {:command-id command.id}))))

(fn build-command-header-row [command state ctx]
  (local text ((WrappedText {:text (command-description command)}) ctx))
  (local badge ((StatusBadge {:text (status-text-for-command command)
                              :tone :neutral})
                ctx))
  (fn on-run-button-click [_button _event]
    (state.run-command command))
  (local button ((Button {:text "Run"
                          :on-click on-run-button-click})
                 ctx))
  (when command.id
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
    (validate-command-schemas commands)
    (var result-text nil)
    (var dropped? false)
    (local state {:snapshot snapshot
                   :commands commands
                   :buttons-by-id {}
                   :forms-by-id {}
                   :last-result nil
                   :result-message "No command run yet"})

    (fn run-command [command]
      (local form (. state.forms-by-id command.id))
      (local payload (if form (form:build-payload) nil))
      (local result (descriptor:run-command command.id payload))
      (local message (result-message command result))
      (set state.last-result result)
      (set state.result-message message)
      (result-text:set-text message)
      result)

    (set state.run-command run-command)
    (fn result-builder [child-ctx]
      (set result-text ((WrappedText {:text state.result-message}) child-ctx))
      result-text)
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
