(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Input (require :input))
(local json (require :json))

(fn get-selected-key []
  (local selected (or (and app app.graph-view
                           app.graph-view.selection
                           app.graph-view.selection.selected-nodes)
                      []))
  (if (= (length selected) 1)
      (or (. selected 1 :key) "")
      nil))

(fn set-presented-text! [state input text]
  (local previous state.presenting?)
  (set state.presenting? true)
  (local (ok err) (pcall input.set-text input text {:reset-cursor? false}))
  (set state.presenting? previous)
  (when (not ok) (error err 0)))

(fn source-change-handler [state]
  (fn source-changed [_input text]
    (when (not state.presenting?) (state.node:update-source text))))

(fn target-change-handler [state]
  (fn target-changed [_input text]
    (when (not state.presenting?) (state.node:update-target text))))

(fn use-selected-source-handler [state]
  (fn use-selected-source [_button _event]
    (local key (get-selected-key))
    (when key
      (local text (state.node:endpoint-text key))
      (state.node:update-source key)
      (set-presented-text! state state.source-input text))))

(fn use-selected-target-handler [state]
  (fn use-selected-target [_button _event]
    (local key (get-selected-key))
    (when key
      (local text (state.node:endpoint-text key))
      (state.node:update-target key)
      (set-presented-text! state state.target-input text))))

(fn swap-handler [state]
  (fn swap-endpoints [_button _event]
    (local current (assert (state.node:get-entity) "Swap requires current link entity"))
    ;; Snapshot both canonical references before either side publishes a mutation.
    (local source current.source-key)
    (local target current.target-key)
    (local source-text (state.node:endpoint-text target))
    (local target-text (state.node:endpoint-text source))
    (state.node:update-source target)
    (state.node:update-target source)
    (set-presented-text! state state.source-input source-text)
    (set-presented-text! state state.target-input target-text)))

(fn delete-handler [node]
  (fn delete-entity [_button _event] (node:delete-entity)))

(fn widget-child [widget]
  (fn build-child [_ctx] widget))

(fn endpoint-row [ctx input button]
  ((Flex {:axis 1 :xspacing 0.3 :yalign :center
          :children [(FlexChild (widget-child input) 1)
                     (FlexChild (widget-child button) 0)]}) ctx))

(fn selected-button [ctx handler]
  ((Button {:icon "my_location" :text "Use Selected" :variant :ghost :on-click handler}) ctx))

(fn metadata-display [ctx entity]
  (local input ((Input {:text "" :placeholder "No metadata" :multiline? true
                       :min-lines 2 :max-lines 8 :editable? false}) ctx))
  (local metadata (if entity (assert entity.metadata "Link entity requires metadata") {}))
  (local (ok text) (pcall json.dumps metadata))
  (when (and ok text (> (string.len text) 2))
    (input:set-text text {:reset-cursor? false}))
  input)

(fn entity-deleted [_entity] nil)

(fn LinkEntityNodeView [node opts]
  (local options (or opts {}))
  (local target (assert (or node options.node) "LinkEntityNodeView requires node"))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target.graph target.graph.ctx)))
    (assert build-ctx "LinkEntityNodeView requires a build context")
    (local entity (target:get-entity))
    ;; Resolve both sides before constructing widgets; presentation never authors.
    (local source-text (target:endpoint-text (and entity entity.source-key)))
    (local target-text (target:endpoint-text (and entity entity.target-key)))
    (local state {:node target :presenting? false})
    (local source-input ((Input {:text source-text :placeholder "Source node key..."
                                 :on-change (source-change-handler state)}) build-ctx))
    (local target-input ((Input {:text target-text :placeholder "Target node key..."
                                 :on-change (target-change-handler state)}) build-ctx))
    (set state.source-input source-input)
    (set state.target-input target-input)
    (local source-button (selected-button build-ctx (use-selected-source-handler state)))
    (local target-button (selected-button build-ctx (use-selected-target-handler state)))
    (local source-row (endpoint-row build-ctx source-input source-button))
    (local swap-button ((Button {:icon "swap_vert" :text "Swap" :variant :ghost
                                :on-click (swap-handler state)}) build-ctx))
    (local target-row (endpoint-row build-ctx target-input target-button))
    (local metadata-input (metadata-display build-ctx entity))
    (local delete-button ((Button {:icon "delete" :text "Delete Entity" :variant :ghost
                                  :on-click (delete-handler target)}) build-ctx))
    (local flex ((Flex {:axis 2 :xalign :stretch :yspacing 0.4
                       :children [(FlexChild (widget-child source-row) 0)
                                  (FlexChild (widget-child swap-button) 0)
                                  (FlexChild (widget-child target-row) 0)
                                  (FlexChild (widget-child metadata-input) 0)
                                  (FlexChild (widget-child delete-button) 0)]}) build-ctx))
    (local deleted-signal target.entity-deleted)
    (local deleted-handler (and deleted-signal (deleted-signal:connect entity-deleted)))
    (fn drop [_self]
      (when deleted-handler (deleted-signal:disconnect deleted-handler true))
      (flex:drop))
    {:source-input source-input :target-input target-input :metadata-input metadata-input
     :layout flex.layout :drop drop}))

LinkEntityNodeView
