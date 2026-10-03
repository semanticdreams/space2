(local glm (require :glm))

(fn copy-table [source]
  (local target {})
  (local input (if source source {}))
  (each [key value (pairs input)]
    (set (. target key)
         (if (= (type value) :table)
             (copy-table value)
             value)))
  target)

(fn merge-into [target source]
  (local input (if source source {}))
  (each [key value (pairs input)]
    (local existing (. target key))
    (set (. target key)
         (if (and (= (type value) :table)
                  (= (type existing) :table))
             (merge-into (copy-table existing) value)
             (if (= (type value) :table)
                 (copy-table value)
                 value))))
  target)

(fn defaults []
  {:placement :top-right
   :spacing 0.3
   :padding [0.45 0.35]
   :max-width 18.0
   :max-visible 3
   :max-queued 20
   :duration-ms 4000
   :variants
   {:info {:background (glm.vec4 0.12 0.16 0.22 0.98)
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
            :border (glm.vec4 0.82 0.22 0.3 0.95)}}})

(fn resolve [ctx-or-theme overrides]
  (local resolved (defaults))
  (local ctx-theme-snackbar
    (and ctx-or-theme ctx-or-theme.theme ctx-or-theme.theme.snackbar))
  (local direct-snackbar
    (and ctx-or-theme ctx-or-theme.snackbar))
  (merge-into resolved ctx-theme-snackbar)
  (merge-into resolved direct-snackbar)
  (merge-into resolved overrides)
  resolved)

{:defaults defaults
 :resolve resolve}
