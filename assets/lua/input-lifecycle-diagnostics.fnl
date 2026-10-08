(fn truncate-diagnostic-string [value]
  (local text (if (= (type value) :string) value (tostring value)))
  (local limit 3000)
  (if (> (# text) limit)
      (.. (string.sub text 1 limit) "... <truncated>")
      text))

(fn safe-diagnostic-string [value]
  (local (ok result) (pcall tostring value))
  (if ok
      (truncate-diagnostic-string result)
      "<tostring failed>"))

(fn safe-traceback [label]
  (local debug-lib _G.debug)
  (if (and debug-lib debug-lib.traceback)
      (do
        (local (ok result) (pcall debug-lib.traceback label 3))
        (if ok
            (truncate-diagnostic-string result)
            "<traceback failed>"))
      "<traceback unavailable>"))

(fn current-frame-id []
  (safe-diagnostic-string (if (and app app.engine app.engine.frame-id)
                              app.engine.frame-id
                              "<no-frame>")))

(fn capture [label]
  {:frame (current-frame-id)
   :traceback (safe-traceback label)})

(fn first-nonempty-string [...]
  (local candidates [...])
  (var result nil)
  (each [_ value (ipairs candidates)]
    (when (and (not result)
               (= (type value) :string)
               (> (# value) 0))
      (set result value)))
  result)

(fn input-debug-name [options]
  (local name (first-nonempty-string options.name options.focus-name options.placeholder))
  (truncate-diagnostic-string
    (if name name "<unnamed input>")))

(fn safe-count [value]
  (if value
      (length value)
      0))

(fn model-text-summary [self]
  (local model self.model)
  (local text-length (safe-count (and model model.codepoints)))
  (string.format "text-length=%s codepoints=%s lines=%s cursor-index=%s cursor-line=%s cursor-column=%s"
                 (safe-diagnostic-string text-length)
                 (safe-diagnostic-string text-length)
                 (safe-diagnostic-string (safe-count (and model model.lines)))
                 (safe-diagnostic-string (if (and model model.cursor-index) model.cursor-index "<unknown>"))
                 (safe-diagnostic-string (if (and model model.cursor-line) model.cursor-line "<unknown>"))
                 (safe-diagnostic-string (if (and model model.cursor-column) model.cursor-column "<unknown>"))))

(fn input-hints [self]
  (string.format "layout=%s focus-node=%s focused=%s hovered=%s layout-happened=%s visible-lines=%s visible-columns=%s scroll-line=%s scroll-column=%s"
                 (safe-diagnostic-string (if (and self.layout self.layout.name) self.layout.name "<no-layout>"))
                 (safe-diagnostic-string (if (and self.focus-node self.focus-node.name) self.focus-node.name "<no-focus-node>"))
                 (safe-diagnostic-string self.focused?)
                 (safe-diagnostic-string self.hovered?)
                 (safe-diagnostic-string self.layout-happened?)
                 (safe-diagnostic-string self.visible-line-count)
                 (safe-diagnostic-string self.visible-column-count)
                 (safe-diagnostic-string (if (and self.scroll self.scroll.line) self.scroll.line "<unknown>"))
                 (safe-diagnostic-string (if (and self.scroll self.scroll.column) self.scroll.column "<unknown>"))))

(fn lifecycle-event-lines [label event]
  [(.. label " frame=" (safe-diagnostic-string (and event event.frame)))
   (.. label " traceback:\n" (safe-diagnostic-string (and event event.traceback)))])

(fn append-lines [target source]
  (each [_ line (ipairs source)]
    (table.insert target line))
  target)

(fn unsafe-double-drop-message [self]
  (local diagnostics (if self.__lifecycle-diagnostics self.__lifecycle-diagnostics {}))
  (local lines [(.. "Input dropped twice: " (safe-diagnostic-string (if diagnostics.name diagnostics.name "<unnamed input>")))
                (.. "hints: " (input-hints self))
                (.. "model: " (model-text-summary self))])
  (append-lines lines (lifecycle-event-lines "created" diagnostics.created))
  (append-lines lines (lifecycle-event-lines "first drop" diagnostics.first-drop))
  (append-lines lines (lifecycle-event-lines "second drop" (capture "Input second drop")))
  (table.concat lines "\n"))

(fn double-drop-message [self]
  (local (ok result) (pcall unsafe-double-drop-message self))
  (if ok
      result
      (.. "Input dropped twice: diagnostic collection failed: " (safe-diagnostic-string result))))

{:capture capture
 :double-drop-message double-drop-message
 :input-debug-name input-debug-name}
