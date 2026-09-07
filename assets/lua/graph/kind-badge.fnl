(local glm (require :glm))

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
  (if (= value nil)
      fallback
      (= (type value) :userdata)
      (if (glm.is-vec3 value)
          (error "color must be a glm.vec4, not glm.vec3")
          (glm.vec4 value.x value.y value.z value.w))
      (= (type value) :table)
      (glm.vec4 (table.unpack value))
      (error "color must be a vec4 or table color")))

(fn normalize-explicit-color [field value fallback]
  (if (= value nil)
      fallback
      (and (not= (type value) :userdata) (not= (type value) :table))
      (error (.. "kind-badge." field " must be a vec4 or table color"))
      (do
        (local (ok color-or-error)
          (pcall normalize-color value fallback))
        (if ok
            color-or-error
            (error (.. "kind-badge." field " must be a vec4 or table color: "
                       (tostring color-or-error)))))))

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
        :background-color (normalize-explicit-color :background-color
                                                   (if (= (type value) :table) value.background-color nil)
                                                   (normalize-color (or options.color options.accent) default-background))
        :foreground-color (normalize-explicit-color :foreground-color
                                                   (if (= (type value) :table) value.foreground-color nil)
                                                   default-foreground)}
      nil))

KindBadge
