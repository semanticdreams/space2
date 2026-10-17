(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Input (require :input))
(local ListView (require :list-view))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Utils (require :graph/view/utils))

(fn build-item-rows [identity-store items]
  (assert identity-store "Notebook presentation requires owning IdentityStore")
  (local total (length (or items [])))
  (icollect [i k (ipairs (or items []))]
    (do
      (local key (tostring k))
      (local terminal-key (identity-store:resolve-key key))
      {:index i :total total :key key :terminal-key terminal-key})))

(fn key-scheme [key]
  (when (and key (= (type key) "string"))
    (local (start _end) (string.find key ":" 1 true))
    (if start
        (string.sub key 1 (- start 1))
        key)))

(fn type-label-from-key [key]
  (local scheme (or (key-scheme key) "unknown"))
  (tostring scheme))

(fn resolve-preview-node [target terminal-key]
  (local graph (and target target.graph))
  (when (and graph (not (= (key-scheme terminal-key) "identity")))
    (assert (= (type graph.load-by-key) :function) "Notebook preview requires graph load-by-key")
    (graph:load-by-key terminal-key)))

(fn build-preview-widget [target terminal-key child-ctx]
  (local resolved (resolve-preview-node target terminal-key))
  (if (= resolved nil)
      ((Text {:text (Utils.truncate-with-ellipsis terminal-key 42)}) child-ctx)
      (do
        (assert (= (type resolved.preview) :function)
                (.. "Resolved notebook item requires callable preview: " terminal-key))
        (local builder (resolved.preview resolved {:node resolved}))
        (assert (= (type builder) :function)
                (.. "Notebook preview requires callable builder: " terminal-key))
        (local preview-widget (builder child-ctx))
        (assert (and preview-widget preview-widget.layout)
                (.. "Notebook preview builder must return widget with layout for " terminal-key))
        preview-widget)))

(fn resolve-item-rows [target]
  (local identity-store (assert (and target target.store target.store.identity-store)
                               "Notebook presentation requires owning IdentityStore"))
  (local current (and target.get-notebook (target:get-notebook)))
  (build-item-rows identity-store (or (and current current.items) [])))

(fn publish-item-rows [view rows]
  (view.items-label:set-text (.. "Items (" (# rows) "):"))
  (view.list:set-items rows))

(fn initialize-view [view rows signal handler]
  (fn populate []
    (publish-item-rows view rows)
    (when signal (signal:connect handler)))
  (local (ok result) (pcall populate))
  (when (not ok)
    ;; The builder has not returned, so its caller cannot own/drop this root yet.
    (pcall view.drop view)
    (error result 0))
  view)

(fn NotebookNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "NotebookNodeView requires a build context")
    (local initial-rows (resolve-item-rows target))
    (local notebook (and target target.get-notebook (target:get-notebook)))

    (local name-input
      ((Input {:text ""
               :placeholder "Notebook name..."
               :on-change (fn [_input new-value]
                            (when (and target target.update-name)
                              (target:update-name new-value)))})
       build-ctx))
    (local initial-name (or (and notebook notebook.name) ""))
    (when (and name-input name-input.set-text (> (string.len initial-name) 0))
      (name-input:set-text initial-name {:reset-cursor? false}))

    (local items-label
      ((Text {:text ""
              :name "notebook-items-label"
              :color (glm.vec4 0.9 0.9 0.9 1)})
       build-ctx))

    (local list
      ((ListView {:name "notebook-items"
                  :items []
                  :scroll true
                  :paginate false
                  :show-head false
                  :item-spacing 0.25
                  :builder (fn [item child-ctx]
                              (local item-key (tostring (or item.key "")))
                              (local terminal-key item.terminal-key)
                              (local index (tonumber (or item.index 1)))
                              (local total (tonumber (or item.total 0)))
                              (local preview-widget (build-preview-widget target terminal-key child-ctx))
                              (local type-label (type-label-from-key terminal-key))

                             (local type-text
                               ((Text {:text type-label
                                       :style (TextStyle {:scale 0.9
                                                          :color (glm.vec4 0.75 0.75 0.75 1)})})
                                child-ctx))

                             (local up-button
                               ((Button {:icon "expand_less"
                                         :variant :ghost
                                         :padding [0.12 0.12]
                                         :on-click (fn [_button _event]
                                                     (when (and target target.move-item (> index 1))
                                                       (target:move-item index (- index 1))))})
                                child-ctx))

                             (local down-button
                               ((Button {:icon "expand_more"
                                         :variant :ghost
                                         :padding [0.12 0.12]
                                         :on-click (fn [_button _event]
                                                     (when (and target target.move-item (< index total))
                                                       (target:move-item index (+ index 1))))})
                                child-ctx))

                             (local remove-button
                               ((Button {:icon "delete"
                                         :variant :ghost
                                         :padding [0.12 0.12]
                                         :on-click (fn [_button _event]
                                                     (when (and target target.remove-item)
                                                       (target:remove-item item-key)))})
                                child-ctx))

                             (local controls
                               ((Flex {:axis 2
                                       :xalign :stretch
                                       :yspacing 0
                                       :children [(FlexChild (fn [_] up-button) 0)
                                                  (FlexChild (fn [_] down-button) 0)
                                                  (FlexChild (fn [_] remove-button) 0)]})
                                child-ctx))

                             (local content-row
                               ((Flex {:axis 1
                                       :yalign :stretch
                                       :children [(FlexChild (fn [_] controls) 0)
                                                  (FlexChild (fn [_] preview-widget) 1)]})
                                child-ctx))

                             ((Flex {:axis 2
                                     :xalign :stretch
                                     :yspacing 0
                                     :children [(FlexChild (fn [_] type-text) 0)
                                                (FlexChild (fn [_] content-row) 1)]})
                              child-ctx))})
       build-ctx))

    (local add-selected-button
      ((Button {:icon "playlist_add"
                :text "Add Selected"
                :variant :ghost
                :on-click (fn [_button _event]
                            (local selected (or (and app.graph-view
                                                     app.graph-view.selection
                                                     app.graph-view.selection.selected-nodes)
                                                []))
                            (each [_ selected-node (ipairs selected)]
                              (local key (or (and selected-node selected-node.key) nil))
                              (when (and key target target.add-item)
                                (target:add-item key))))})
       build-ctx))

    (local add-string-entity-button
      ((Button {:icon "add"
                :text "Add String Entity"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.add-string-entity)
                              (target:add-string-entity {})))})
       build-ctx))

    (local delete-button
      ((Button {:icon "delete"
                :text "Delete Notebook"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.delete-notebook)
                              (target:delete-notebook)))})
       build-ctx))

    (local actions-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] add-selected-button) 0)
                         (FlexChild (fn [_] add-string-entity-button) 0)
                         (FlexChild (fn [_] delete-button) 0)]})
       build-ctx))

    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.4
              :children [(FlexChild (fn [_] name-input) 0)
                         (FlexChild (fn [_] items-label) 0)
                         (FlexChild (fn [_] list) 1)
                         (FlexChild (fn [_] actions-row) 0)]})
       build-ctx))

    (fn refresh-items [self]
      (publish-item-rows self (resolve-item-rows target)))

    (local items-signal (and target target.items-changed))
    (fn items-handler [_payload] (refresh-items {:items-label items-label :list list}))

    (fn drop [_self]
      (when items-signal
        (items-signal:disconnect items-handler true))
      (flex:drop))

    (local view {:name-input name-input :items-label items-label :list list
                 :actions-row actions-row :layout flex.layout
                 :refresh-items refresh-items :drop drop})
    (initialize-view view initial-rows items-signal items-handler)))

NotebookNodeView
