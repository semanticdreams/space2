(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local {: Layout} (require :layout))
(local Card (require :card))
(local Button (require :button))
(local Text (require :text))
(local Padding (require :padding))
(local {: get-button-theme-colors} (require :widget-theme-utils))

(local colors (require :colors))
(fn make-flex-spacer []
  (fn build [_ctx]
    (local layout
      (Layout {:name "dialog-flex-spacer"
               :measurer (fn [self]
                           (set self.measure (glm.vec3 0 0 0)))
               :layouter (fn [_self] nil)}))
    (fn drop [self]
      (self.layout:drop))
    {:layout layout :drop drop}))

(fn resolve-action-name [action]
  (or action.name (. action 1)))

(fn resolve-action-handler [action]
  (or action.on-click action.handler action.fn (. action 2)))

(fn normalize-actions [actions]
  (local normalized [])
  (each [_ entry (ipairs (or actions []))]
    (when (not (= (type entry) :table))
      (error "Dialog actions must be provided as tables"))
    (local name (resolve-action-name entry))
    (assert name "Dialog action is missing a name")
    (table.insert normalized
                  {:name name
                   :handler (resolve-action-handler entry)
                   :variant entry.variant
                   :padding entry.padding
                   :icon (or entry.icon name)}))
  normalized)

(fn resolve-action-variant [options]
  (or options.action-variant :tertiary))

(fn resolve-titlebar-color [ctx options action-variant]
  (if options.titlebar-color
      options.titlebar-color
      (if options.titlebar-background-color
          options.titlebar-background-color
          (do
            (local theme-colors (get-button-theme-colors ctx action-variant))
            (if (and theme-colors theme-colors.background)
                theme-colors.background
                (glm.vec4 0.2 0.2 0.2 1))))))

(fn resolve-body-padding [options]
  (if (= options.body-padding false)
      nil
      (if options.body-padding
          options.body-padding
          (if options.content-padding options.content-padding [0.6 0.6]))))

(fn make-action-row [actions options action-variant]
  (local resolved-variant (if action-variant action-variant (resolve-action-variant options)))
  (local action-padding (if options.action-padding options.action-padding [0.2 0.2]))
  (local action-spacing (if options.action-spacing options.action-spacing 0))
  (Flex
    {:axis 1
     :xspacing action-spacing
     :yalign :center
     :children
     (icollect [_ action (ipairs actions)]
                (FlexChild
                  (Button {:icon action.icon
                           :variant (if action.variant action.variant resolved-variant)
                           :padding (if action.padding action.padding action-padding)
                           :focusable? (= action.focusable? true)
                           :on-click (if action.handler
                                      (fn [button event]
                                        (action.handler button event))
                                      nil)})
                 0))}))

(fn Dialog [opts]
  (local options (or opts {}))
  (assert options.title "Dialog requires :title")
  (assert options.child "Dialog requires :child")
  (when options.title-prefix
    (assert (= (type options.title-prefix) :function)
            "Dialog title-prefix must be a builder function"))
  (local actions (normalize-actions options.actions))
  (local title-span
    (Text {:text options.title
           :style options.title-style}))
  (local title
    (Padding {:child title-span
              :edge-insets (or options.title-padding [0.9 0.5])}))
  (local action-variant (resolve-action-variant options))
  (local action-row (make-action-row actions options action-variant))
  (local spacer (make-flex-spacer))
  (local titlebar-children [])
  (when options.title-prefix
    (table.insert titlebar-children (FlexChild options.title-prefix 0)))
  (table.insert titlebar-children (FlexChild title 0))
  (when (> (length actions) 0)
    (table.insert titlebar-children (FlexChild spacer 1))
    (table.insert titlebar-children (FlexChild action-row 0)))
  (local titlebar-content
    (Flex {:axis 1
           :xspacing (or options.titlebar-spacing 0.5)
           :yalign :center
           :children titlebar-children}))
  (local titlebar
    (fn [ctx]
      (local color (resolve-titlebar-color ctx options action-variant))
      ((Card {:child titlebar-content :color color}) ctx)))
  (local body-padding (resolve-body-padding options))
  (local body-content
    (if body-padding
        (Padding {:edge-insets body-padding
                  :child options.child})
        options.child))
  (local body-card
    (Card {:child body-content}))
  (local flex-builder
    (Flex {:axis 2
           :xalign :stretch
           :yspacing (or options.yspacing 0)
           :children [(FlexChild titlebar 0)
                      (FlexChild body-card 1)]}))

  (fn build [ctx]
    (flex-builder ctx))
  build)

Dialog
