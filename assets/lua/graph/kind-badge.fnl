(local glm (require :glm))
(local Utils (require :graph/core/utils))

(local KindBadge {})
(local default-background (glm.vec4 0.35 0.38 0.42 1))
(local default-foreground (glm.vec4 0.96 0.97 1 1))

(fn trim [text]
  (string.match text "^%s*(.-)%s*$"))

(fn scheme-text [key]
  (when (= (type key) :string)
    (local colon-at (string.find key ":" 1 true))
    (when (and colon-at (> colon-at 1))
      (string.upper (string.sub key 1 (- colon-at 1))))))

(fn normalize-text [text]
  (assert (= (type text) :string)
          "kind-badge.text must be a non-empty string")
  (local normalized (trim text))
  (assert (> (string.len normalized) 0)
          "kind-badge.text must be a non-empty string")
  normalized)

(fn normalize-color [value fallback]
  (Utils.ensure-glm-vec4 value fallback))

(fn KindBadge.normalize [opts]
  (local options (or opts {}))
  (local value options.value)
  (local text
    (if (= value false)
        false
        (= value nil)
        (scheme-text options.key)
        (= (type value) :string)
        (normalize-text value)
        (= (type value) :table)
        (normalize-text value.text)
        (error "kind-badge must be false, string, or table")))
  (if (= text false)
      false
      text
      {:text text
       :background-color (normalize-color (and (= (type value) :table) value.background-color)
                                          (normalize-color (or options.color options.accent) default-background))
       :foreground-color (normalize-color (and (= (type value) :table) value.foreground-color)
                                          default-foreground)}
      nil))

KindBadge
