(local glm (require :glm))
(local Font (require :font))
(local {: adjust : make-button-variant} (require :widget-theme-utils))

(fn DarkTheme []
  (local font (Font {:metadata-path "ubuntu-font/msdf/UbuntuMono-R.json"
                     :texture-path "ubuntu-font/msdf/UbuntuMono-R.png"
                     :texture-name "font-UbuntuMono-R"}))
  (local italic-font (Font {:metadata-path "ubuntu-font/msdf/UbuntuMono-RI.json"
                            :texture-path "ubuntu-font/msdf/UbuntuMono-RI.png"
                            :texture-name "font-UbuntuMono-RI"}))
  (local bold-font (Font {:metadata-path "ubuntu-font/msdf/UbuntuMono-B.json"
                          :texture-path "ubuntu-font/msdf/UbuntuMono-B.png"
                          :texture-name "font-UbuntuMono-B"}))
  (local bold-italic-font (Font {:metadata-path "ubuntu-font/msdf/UbuntuMono-BI.json"
                                 :texture-path "ubuntu-font/msdf/UbuntuMono-BI.png"
                                 :texture-name "font-UbuntuMono-BI"}))
  (local text-color (glm.vec4 0.92 0.94 0.98 1))
  (local secondary-base (glm.vec4 0.17 0.21 0.31 1))
  (local input-base (glm.vec4 0.12 0.15 0.2 0.95))
  {:name :dark
   :font font
   :italic-font italic-font
   :bold-font bold-font
   :bold-italic-font bold-italic-font
   :text {:foreground text-color
          :dim-foreground (glm.vec4 0.55 0.58 0.64 1)
          :scale 1.6}
   :transcript {:user {:background (glm.vec4 0.15 0.22 0.38 0.95)
                       :foreground (glm.vec4 0.94 0.95 1 1)}
                :assistant {:background (glm.vec4 0.12 0.13 0.17 0.95)
                            :foreground (glm.vec4 0.88 0.9 0.95 1)}
                :tool {:background (glm.vec4 0.1 0.14 0.18 0.95)
                       :foreground (glm.vec4 0.82 0.85 0.9 1)}
                :error {:background (glm.vec4 0.28 0.1 0.12 0.95)
                        :foreground (glm.vec4 0.98 0.75 0.72 1)}
                :event {:background (glm.vec4 0.08 0.1 0.12 0.8)
                        :foreground (glm.vec4 0.55 0.58 0.64 1)}}
   :approval {:background (glm.vec4 0.22 0.17 0.05 1)
              :title-foreground (glm.vec4 0.95 0.73 0.31 1)
              :foreground (glm.vec4 0.92 0.88 0.75 1)}
   :list-view {:header {:foreground text-color}
               :item-selected-background (glm.vec4 0.18 0.22 0.34 1)
               :item-foreground text-color}
   :combo-box {:items-per-page 10}
   :graph {:background (glm.vec4 0.095 0.105 0.13 1)
           :edge-color (glm.vec4 0.36 0.45 0.68 0.9)
           :edge-thickness 4.0
           :label-color text-color
           :label-target-pixels 13.0
           :label-min-scale 4.0
           :selection-border-color (glm.vec4 0.2 0.55 0.95 0.95)}
   :chrome {:rail-background (glm.vec4 0.075 0.09 0.12 0.98)
            :panel-background (glm.vec4 0.12 0.13 0.18 0.98)}
   :terrain-selection {:fill (glm.vec4 0.24 0.58 0.98 0.22)
                       :border (glm.vec4 0.34 0.68 1.0 0.98)}
   :physics-containment {:visualization {:color (glm.vec4 0.45 0.72 0.95 0.28)}}
   :flat-terrain {:dark (glm.vec4 0.12 0.14 0.18 1.0)
                  :light (glm.vec4 0.18 0.21 0.27 1.0)}
    :card {:background (glm.vec4 0.12 0.13 0.18 1)
           :foreground text-color}
    :snackbar {:placement :top-right
               :spacing 0.3
               :padding [0.45 0.35]
               :max-width 18.0
               :max-visible 3
               :max-queued 20
               :duration-ms 4000
               :variants {:info {:background (glm.vec4 0.12 0.16 0.22 0.98)
                                  :foreground (glm.vec4 0.92 0.95 1 1)
                                  :border (glm.vec4 0.32 0.48 0.86 0.95)}
                          :success {:background (glm.vec4 0.09 0.22 0.14 0.98)
                                    :foreground (glm.vec4 0.88 0.98 0.91 1)
                                    :border (glm.vec4 0.22 0.64 0.38 0.95)}
                          :warning {:background (glm.vec4 0.28 0.19 0.08 0.98)
                                    :foreground (glm.vec4 1 0.92 0.74 1)
                                    :border (glm.vec4 0.88 0.58 0.18 0.95)}
                          :error {:background (glm.vec4 0.28 0.09 0.11 0.98)
                                  :foreground (glm.vec4 1 0.83 0.82 1)
                                  :border (glm.vec4 0.82 0.22 0.3 0.95)}}}
    :qr-code {:foreground (glm.vec4 0.05 0.06 0.08 1)
              :background (glm.vec4 0.98 0.98 0.99 1)}
   :input {:background input-base
           :hover-background (adjust input-base 0.04)
           :focused-background (adjust input-base 0.06)
           :foreground text-color
           :placeholder (glm.vec4 0.58 0.62 0.72 0.85)
           :caret-normal (glm.vec4 0.95 0.73 0.31 1)
           :caret-insert (glm.vec4 0.32 0.69 0.38 1)
           :focus-outline (glm.vec4 0.9 0.52 0.12 0.9)}
   :button
   {:default-variant :secondary
    :variants
    {:primary (make-button-variant (glm.vec4 0.25 0.43 0.96 1))
     :secondary (make-button-variant secondary-base)
     :success (make-button-variant (glm.vec4 0.17 0.55 0.36 1))
     :warning (make-button-variant (glm.vec4 0.85 0.57 0.21 1))
     :danger (make-button-variant (glm.vec4 0.78 0.22 0.31 1))}}})

DarkTheme
