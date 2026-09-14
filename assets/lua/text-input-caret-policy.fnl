(local {: resolve-mark-flag} (require :layout))
(local {: fallback-glyph : line-height} (require :text-utils))

(fn positive? [value]
  (and (= (type value) :number) (> value 0)))

(fn resolve-line-height [text-style fallback-height]
  (assert text-style "CaretPolicy.resolve-line-height requires text-style")
  (local value (line-height text-style))
  (if (positive? value)
      value
      (or fallback-height 0)))

(fn resolve-column-width [text-style caret-width]
  (assert text-style "CaretPolicy.resolve-column-width requires text-style")
  (local font (and text-style text-style.font))
  (if font
      (do
        (local glyph (fallback-glyph font 32))
        (local advance (and glyph (* glyph.advance text-style.scale)))
        (if (positive? advance)
            advance
            caret-width))
      caret-width))

(fn caret-color [colors mode]
  (assert colors "CaretPolicy.caret-color requires colors")
  (if (= mode :insert)
      (assert colors.caret-insert "CaretPolicy.caret-color requires colors.caret-insert")
      (assert colors.caret-normal "CaretPolicy.caret-color requires colors.caret-normal")))

(fn caret-visible? [input]
  (assert input "CaretPolicy.caret-visible? requires input")
  (and input.focused? true))

(fn mode-caret-width [text-style codepoint caret-width mode]
  (assert text-style "CaretPolicy.mode-caret-width requires text-style")
  (if (= mode :insert)
      caret-width
      (do
        (local font (and text-style text-style.font))
        (if font
            (do
              (local glyph (fallback-glyph font (or codepoint 32)))
              (local block-width (and glyph (* glyph.advance text-style.scale)))
              (if (positive? block-width)
                  block-width
                  caret-width))
            caret-width))))

(fn caret-height [line-height inner-height]
  (assert (= (type line-height) :number) "CaretPolicy.caret-height requires line-height")
  (assert (= (type inner-height) :number) "CaretPolicy.caret-height requires inner-height")
  (math.max 0.0001 (math.min line-height inner-height)))

(fn apply-caret-visual [input opts]
  (assert input "CaretPolicy.apply-caret-visual requires input")
  (local mark-layout-dirty? (resolve-mark-flag opts :mark-layout-dirty? true))
  (when input.caret
    (input.caret:set-visible (caret-visible? input)
                             {:mark-layout-dirty? mark-layout-dirty?})
    (set input.caret.color (caret-color input.colors input.mode))
    (when (and mark-layout-dirty? input.caret.layout)
      (input.caret.layout:mark-layout-dirty))))

{:resolve-line-height resolve-line-height
 :resolve-column-width resolve-column-width
 :caret-color caret-color
 :caret-visible? caret-visible?
 :mode-caret-width mode-caret-width
 :caret-height caret-height
 :apply-caret-visual apply-caret-visual}
