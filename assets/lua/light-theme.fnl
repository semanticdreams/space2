(local glm (require :glm))
(local Font (require :font))
(local {: adjust : make-button-variant} (require :widget-theme-utils))

(fn LightSnackbarTheme []
  {:placement :top-right
   :spacing 0.3
   :padding [0.45 0.35]
   :max-width 18.0
   :max-visible 3
   :max-queued 20
   :duration-ms 4000
   :variants {:info {:background (glm.vec4 0.92 0.96 1 0.98)
                      :foreground (glm.vec4 0.08 0.15 0.32 1)
                      :border (glm.vec4 0.24 0.48 0.88 0.95)}
              :success {:background (glm.vec4 0.88 0.97 0.9 0.98)
                        :foreground (glm.vec4 0.08 0.32 0.16 1)
                        :border (glm.vec4 0.2 0.6 0.32 0.95)}
              :warning {:background (glm.vec4 1 0.95 0.82 0.98)
                        :foreground (glm.vec4 0.42 0.26 0.04 1)
                        :border (glm.vec4 0.86 0.56 0.16 0.95)}
              :error {:background (glm.vec4 1 0.88 0.88 0.98)
                      :foreground (glm.vec4 0.58 0.08 0.09 1)
                      :border (glm.vec4 0.82 0.2 0.26 0.95)}}})

(fn LightTheme []
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
  (local text-color (glm.vec4 0.11 0.14 0.18 1))
  (local secondary-base (glm.vec4 0.885 0.905 0.935 1))
  (local tertiary-base (glm.vec4 0.83 0.86 0.91 1))
  (local input-base (glm.vec4 0.982 0.989 0.996 1))
  (local rail-surface (glm.vec4 0.82 0.85 0.89 0.98))
  (local app-background (glm.vec4 0.89 0.908 0.936 1))
  (local chrome-panel-surface (glm.vec4 0.94 0.952 0.972 0.98))
  (local card-surface (glm.vec4 0.972 0.98 0.992 1))
  (local panel-outline (glm.vec4 0.72 0.77 0.85 0.98))
  {:name :light
   :font font
   :italic-font italic-font
   :bold-font bold-font
   :bold-italic-font bold-italic-font
   :text {:foreground text-color
          :dim-foreground (glm.vec4 0.46 0.5 0.56 1)
          :scale 1.6}
   :transcript {:user {:background (glm.vec4 0.85 0.92 0.99 0.9)
                       :foreground (glm.vec4 0.08 0.15 0.35 1)}
                :assistant {:background (glm.vec4 0.92 0.93 0.95 1)
                            :foreground (glm.vec4 0.12 0.15 0.22 1)}
                :tool {:background (glm.vec4 0.9 0.93 0.97 0.9)
                       :foreground (glm.vec4 0.15 0.22 0.32 1)}
                :error {:background (glm.vec4 0.98 0.88 0.86 0.9)
                        :foreground (glm.vec4 0.6 0.08 0.08 1)}
                :event {:background (glm.vec4 0.95 0.96 0.98 0.8)
                        :foreground (glm.vec4 0.42 0.46 0.52 1)}}
   :approval {:background (glm.vec4 1 0.97 0.88 1)
              :title-foreground (glm.vec4 0.6 0.38 0.05 1)
              :foreground (glm.vec4 0.35 0.25 0.08 1)}
   :list-view {:header {:foreground text-color}
               :item-selected-background (glm.vec4 0.78 0.85 0.97 0.9)
               :item-foreground text-color}
   :combo-box {:items-per-page 10}
   :graph {:background app-background
           :edge-color (glm.vec4 0.28 0.34 0.45 0.82)
           :edge-thickness 4.0
           :label-color (glm.vec4 0.22 0.27 0.35 0.95)
           :label-target-pixels 13.0
           :label-min-scale 4.0
           :selection-border-color (glm.vec4 0.18 0.5 0.9 0.9)}
   :chrome {:rail-background rail-surface
            :panel-background chrome-panel-surface}
   :panel-border panel-outline
   :terrain-selection {:fill (glm.vec4 0.18 0.5 0.9 0.18)
                       :border (glm.vec4 0.16 0.47 0.88 0.95)}
   :physics-containment {:visualization {:color (glm.vec4 0.14 0.31 0.58 0.42)}}
   :flat-terrain {:dark (glm.vec4 0.86 0.89 0.93 1.0)
                  :light (glm.vec4 0.945 0.962 0.982 1.0)}
    :card {:background card-surface
           :foreground text-color}
    :snackbar (LightSnackbarTheme)
    :qr-code {:foreground (glm.vec4 0.08 0.1 0.13 1)
              :background (glm.vec4 1 1 1 1)}
   :input {:background input-base
           :hover-background (adjust input-base -0.012)
           :focused-background (adjust input-base -0.026)
           :foreground text-color
           :placeholder (glm.vec4 0.5 0.54 0.6 0.88)
           :caret-normal (glm.vec4 0.85 0.54 0.14 1)
           :caret-insert (glm.vec4 0.14 0.55 0.22 1)
           :focus-outline (glm.vec4 0.9 0.52 0.12 0.9)}
   :button
   {:default-variant :secondary
    :variants
    {:primary (make-button-variant (glm.vec4 0.2 0.48 0.98 1)
                                   {:foreground (glm.vec4 0.98 0.99 1 1)
                                    :hover-delta -0.05
                                    :pressed-delta -0.1
                                    :focus-outline (glm.vec4 0.9 0.52 0.12 0.9)})
     :secondary (make-button-variant secondary-base
                                     {:foreground text-color
                                      :hover-delta -0.028
                                      :pressed-delta -0.06
                                      :focus-outline (glm.vec4 0.9 0.52 0.12 0.9)})
     :tertiary (make-button-variant tertiary-base
                                    {:foreground text-color
                                     :hover-delta -0.03
                                     :pressed-delta -0.065
                                     :focus-outline (glm.vec4 0.9 0.52 0.12 0.9)})
     :success (make-button-variant (glm.vec4 0.2 0.64 0.32 1)
                                   {:foreground (glm.vec4 0.96 0.99 0.97 1)
                                    :hover-delta -0.04
                                    :pressed-delta -0.09})
     :warning (make-button-variant (glm.vec4 0.93 0.65 0.2 1)
                                   {:foreground (glm.vec4 0.2 0.14 0.05 1)
                                    :hover-delta -0.04
                                    :pressed-delta -0.1})
     :danger (make-button-variant (glm.vec4 0.86 0.26 0.3 1)
                                  {:foreground (glm.vec4 1 0.98 0.98 1)
                                   :hover-delta -0.04
                                   :pressed-delta -0.1})}}})

LightTheme
