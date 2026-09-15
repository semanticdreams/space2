(local glm (require :glm))
(local {: Flex : FlexChild} (require :flex))
(local {: Layout} (require :layout))
(local Button (require :button))
(local Rectangle (require :rectangle))

(fn value-or [value fallback]
  (if (= value nil) fallback value))

(fn resolve-action-name [action]
  (if action.name
      action.name
      action.text
      action.text
      (. action 1)))

(fn resolve-action-handler [action]
  (if action.on-click
      action.on-click
      action.handler
      action.handler
      action.fn
      action.fn
      (. action 2)))

(local default-separator-height 1)
(local default-separator-thickness 0.08)
(local default-separator-color (glm.vec4 0.35 0.35 0.35 1))

(fn separator-entry? [entry]
  (= entry.type :separator))

(fn normalize-actions [actions]
  (local normalized [])
  (each [_ entry (ipairs (value-or actions []))]
    (when (not (= (type entry) :table))
      (error "Menu actions must be provided as tables"))
    (if (separator-entry? entry)
        (table.insert normalized {:type :separator})
        entry.type
        (error (.. "Menu entry has unknown type: " (tostring entry.type)))
        (do
          (local name (resolve-action-name entry))
          (assert name "Menu action is missing a name")
          (table.insert normalized
                        {:type :action
                         :name name
                         :handler (resolve-action-handler entry)
                         :icon entry.icon
                         :variant entry.variant
                         :padding entry.padding}))))
  normalized)

(fn separator-row-size [layout]
  (if layout.size
      layout.size
      layout.measure
      layout.measure
      (glm.vec3 0 default-separator-height 0)))

(fn MenuSeparator []
  (fn build [ctx]
    (local rectangle ((Rectangle {:color default-separator-color}) ctx))

    (fn measurer [self]
      (set self.measure (glm.vec3 0 default-separator-height 0)))

    (fn layouter [self]
      (local row-size (separator-row-size self))
      (local thickness (math.min default-separator-thickness row-size.y))
      (set rectangle.layout.size (glm.vec3 row-size.x thickness 0))
      (set rectangle.layout.position
           (+ self.position
              (glm.vec3 0 (* 0.5 (- row-size.y thickness)) 0)))
      (set rectangle.layout.rotation self.rotation)
      (set rectangle.layout.depth-offset-index self.depth-offset-index)
      (set rectangle.layout.clip-region self.clip-region)
      (rectangle.layout:layouter))

    (local layout
      (Layout {:name "menu-separator"
               :children [rectangle.layout]
               :measurer measurer
               :layouter layouter}))

    (fn drop [_self]
      (layout:drop)
      (rectangle:drop))

    {:layout layout
     :rectangle rectangle
     :drop drop}))

(fn action-click-handler [handler]
  (if handler
      (fn [btn event]
        (handler btn event))
      nil))

(fn build-action-button [action child-ctx defaults buttons]
  (local button
    ((Button {:text action.name
              :icon action.icon
              :content-spacing (value-or action.content-spacing defaults.spacing)
              :variant (value-or action.variant defaults.variant)
              :padding (value-or action.padding defaults.padding)
              :on-click (action-click-handler action.handler)})
     child-ctx))
  (table.insert buttons button)
  button)

(fn build-menu-entry [action defaults buttons child-ctx]
  (if (= action.type :separator)
      ((MenuSeparator) child-ctx)
      (build-action-button action child-ctx defaults buttons)))

(fn menu-flex-child [action defaults buttons]
  (FlexChild
    (fn [child-ctx]
      (build-menu-entry action defaults buttons child-ctx))
    0))

(fn menu-base-size [layout]
  (if layout.size
      layout.size
      layout.measure
      layout.measure
      (glm.vec3 0 0 0)))

(fn Menu [opts]
  (local options (value-or opts {}))
  (local actions (normalize-actions options.actions))
  (local default-variant options.action-variant)
  (local default-padding options.action-padding)
  (local default-spacing (value-or options.content-spacing 1))
  (local min-width (value-or options.min-width 20))

  (fn build [ctx]
    (local buttons [])
    (local defaults {:variant default-variant
                     :padding default-padding
                     :spacing default-spacing})
    (local children
      (icollect [_ action (ipairs actions)]
        (menu-flex-child action defaults buttons)))
    (local flex
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0
              :children children})
       ctx))

    (fn measurer [self]
      (flex.layout:measurer)
      (local measure flex.layout.measure)
      (set self.measure (glm.vec3 (math.max (. measure 1) min-width)
                                  (. measure 2)
                                  (. measure 3))))

    (fn layouter [self]
      (local base-size (menu-base-size self))
      (local size (glm.vec3 (math.max (. base-size 1) min-width)
                            (. base-size 2)
                            (. base-size 3)))
      (set self.size size)
      (set flex.layout.size size)
      (set flex.layout.position (+ self.position (glm.vec3 0 (- size.y) 0)))
      (set flex.layout.rotation self.rotation)
      (set flex.layout.depth-offset-index (+ self.depth-offset-index 1))
      (set flex.layout.clip-region self.clip-region)
      (flex.layout:layouter))

    (local layout
      (Layout {:name (value-or options.name "menu")
               :children [flex.layout]
               :measurer measurer
               :layouter layouter}))

    (fn drop [self]
      (self.layout:drop)
      (flex:drop))

    {:layout layout
     :buttons buttons
     :actions actions
     :drop drop}))

Menu
