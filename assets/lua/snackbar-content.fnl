(local glm (require :glm))
(local Stack (require :stack))
(local Rectangle (require :rectangle))
(local Padding (require :padding))
(local {: Flex : FlexChild} (require :flex))
(local WrappedText (require :wrapped-text))
(local Button (require :button))
(local TextStyle (require :text-style))
(local SnackbarTheme (require :snackbar-theme))

(fn variant-colors [theme entry]
  (local variant (if (= entry.variant nil) :info entry.variant))
  (local colors (and theme theme.variants (. theme.variants variant)))
  (assert colors (.. "SnackbarContent unsupported variant: " (tostring variant)))
  colors)

(fn action-label [action]
  (if (not (= action.label nil))
      action.label
      action.text))

(fn value-or [value fallback]
  (if (not (= value nil)) value fallback))

(fn make-action-button [entry handle action]
  (Button {:text (action-label action)
           :variant (if (= action.button-variant nil) :ghost action.button-variant)
           :padding [0.25 0.2]
           :on-click (fn [button event]
                       (when action.on-click
                         (action.on-click entry handle button event)))}))

(fn content-row-builder [theme colors entry handle]
  (fn build-row [_ctx]
    (local text-style (TextStyle {:color colors.foreground}))
    (local text (value-or entry.text ""))
    (local actions (value-or entry.actions []))
    (local children [(FlexChild (WrappedText {:text text
                                             :style text-style})
                               1)])
    (each [_ action (ipairs actions)]
      (table.insert children (FlexChild (make-action-button entry handle action) 0)))
    ((Flex {:axis 1
            :xspacing (value-or theme.action-spacing 0.35)
            :yalign :center
            :children children}) _ctx)))

(fn default-builder [opts]
  (local options (value-or opts {}))
  (fn build-content [ctx entry handle]
    (local theme (SnackbarTheme.resolve ctx options.theme))
    (local colors (variant-colors theme entry))
    (local theme-padding (value-or theme.padding [0.45 0.35]))
    (local padding (value-or options.padding theme-padding))
    (local border-size (if (= options.border-size nil) 0.05 options.border-size))
    (local background (Rectangle {:color colors.background}))
    (local border (Rectangle {:color (value-or colors.border (glm.vec4 1 1 1 1))}))
    (local row (content-row-builder theme colors entry handle))
    ((Stack {:children [border
                        (Padding {:edge-insets [border-size border-size]
                                  :child background})
                        (Padding {:edge-insets padding
                                  :child row})]
             :depth-offset-step 1})
     ctx)))

{:default-builder default-builder}
