(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Input (require :input))
(local ListView (require :list-view))
(local Text (require :text))
(local Utils (require :graph/view/utils))

(fn build-item-rows [identity-store items]
  (assert identity-store "ListEntityNodeView requires its owning IdentityStore")
  (local total (length items))
  (icollect [i key (ipairs items)]
    (do
      (local text (identity-store:resolve-key key))
      {:index i :total total :key key :text text})))

(fn maybe-focus-node [node-key]
  (when (and app app.graph-view)
    (local graph (or app.graph-map
                    (and app.graph-view app.graph-view.graph-map)))
    (when graph
      (local node (and graph.lookup (graph:lookup node-key)))
      (when node
        (local focus-node (. app.graph-view.focus-nodes node))
        (when (and focus-node focus-node.request-focus)
          (focus-node:request-focus {:reason :list-entity}))))))

(fn resolve-item-rows [target]
  (local identity-store (assert (and target target.store target.store.identity-store)
                               "ListEntityNodeView requires its owning IdentityStore"))
  (local current (and target.get-entity (target:get-entity)))
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
    (pcall view.drop view)
    (error result 0))
  view)

(fn ListEntityNodeView [node opts]
  (local options (or opts {}))
  (local target (or node options.node))

  (fn build [ctx]
    (local build-ctx (or ctx options.ctx (and target target.graph target.graph.ctx)))
    (assert build-ctx "ListEntityNodeView requires a build context")
    (local initial-rows (resolve-item-rows target))
    (local entity (and target target.get-entity (target:get-entity)))

    (local name-input
      ((Input {:text ""
               :placeholder "Name..."
               :on-change (fn [_input new-value]
                            (when (and target target.update-name)
                              (target:update-name new-value)))})
       build-ctx))
    (local initial-name (or (and entity entity.name) ""))
    (when (and name-input name-input.set-text (> (string.len initial-name) 0))
      (name-input:set-text initial-name {:reset-cursor? false}))

    (local items-label
      ((Text {:text ""
              :name "list-entity-items-label"
              :color (glm.vec4 0.9 0.9 0.9 1)})
       build-ctx))

    (local list
      ((ListView {:name "list-entity-items"
                  :items []
                  :scroll true
                  :paginate false
                  :show-head false
                  :item-spacing 0.25
                  :builder (fn [item child-ctx]
                             (local item-key (tostring (or item.key "")))
                             (local index (tonumber (or item.index 1)))
                             (local total (tonumber (or item.total 0)))

                             (local key-button
                                ((Button {:text (Utils.truncate-with-ellipsis item.text 28)
                                         :variant :ghost
                                         :padding [0.35 0.35]
                                         :on-click (fn [_button _event]
                                                     (maybe-focus-node item-key))})
                                child-ctx))

                             (local up-button
                               ((Button {:text "↑"
                                         :variant :ghost
                                         :padding [0.25 0.25]
                                         :on-click (fn [_button _event]
                                                     (when (and target target.move-item (> index 1))
                                                       (target:move-item index (- index 1))))})
                                child-ctx))

                             (local down-button
                               ((Button {:text "↓"
                                         :variant :ghost
                                         :padding [0.25 0.25]
                                         :on-click (fn [_button _event]
                                                     (when (and target target.move-item (< index total))
                                                       (target:move-item index (+ index 1))))})
                                child-ctx))

                             (local remove-button
                               ((Button {:text "×"
                                         :variant :ghost
                                         :padding [0.25 0.25]
                                         :on-click (fn [_button _event]
                                                     (when (and target target.remove-item)
                                                       (target:remove-item item-key)))})
                                child-ctx))

                             ((Flex {:axis 1
                                     :xspacing 0.25
                                     :yalign :center
                                     :children [(FlexChild (fn [_] key-button) 1)
                                                (FlexChild (fn [_] up-button) 0)
                                                (FlexChild (fn [_] down-button) 0)
                                                (FlexChild (fn [_] remove-button) 0)]})
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

    (local delete-button
      ((Button {:icon "delete"
                :text "Delete List"
                :variant :ghost
                :on-click (fn [_button _event]
                            (when (and target target.delete-entity)
                              (target:delete-entity)))})
       build-ctx))

    (local actions-row
      ((Flex {:axis 1
              :xspacing 0.3
              :yalign :center
              :children [(FlexChild (fn [_] add-selected-button) 0)
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

ListEntityNodeView
