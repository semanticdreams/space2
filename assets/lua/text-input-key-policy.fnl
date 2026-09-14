(local Modifiers (require :input-modifiers))

(local KEY_PAGEUP 1073741899)
(local KEY_PAGEDOWN 1073741902)

(fn ctrl-key? [payload char]
  (if (not payload)
      false
      (not (Modifiers.ctrl-held? payload.mod))
      false
      (= payload.key (string.byte char))
      true
      (= payload.key (string.byte (string.upper char)))
      true
      false))

(fn handle-direct-key [input payload]
  (assert input "KeyPolicy.handle-direct-key requires input")
  (if (not (and payload payload.key))
      false
      (if (ctrl-key? payload "s")
          (do
            (assert input.save "KeyPolicy Ctrl+S requires input.save")
            (input:save)
            true)
          (ctrl-key? payload "c")
          (do
            (assert input.copy-selection "KeyPolicy Ctrl+C requires input.copy-selection")
            (if (input:copy-selection) true false))
          (= payload.key KEY_PAGEUP)
          (do
            (assert input.scroll-lines "KeyPolicy PageUp requires input.scroll-lines")
            (assert (= (type input.visible-line-count) :number)
                    "KeyPolicy PageUp requires visible-line-count")
            (input:scroll-lines (- input.visible-line-count)
                                {:extend-selection? (Modifiers.shift-held? payload.mod)}))
          (= payload.key KEY_PAGEDOWN)
          (do
            (assert input.scroll-lines "KeyPolicy PageDown requires input.scroll-lines")
            (assert (= (type input.visible-line-count) :number)
                    "KeyPolicy PageDown requires visible-line-count")
            (input:scroll-lines input.visible-line-count
                                {:extend-selection? (Modifiers.shift-held? payload.mod)}))
          false)))

{:handle-direct-key handle-direct-key}
