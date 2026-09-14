(local _ (require :main))
(local InputModel (require :input-model))
(local Runtime (require :state-runtime))
(local TextNormalCommands (require :text-normal-commands))

(local tests [])

(local SHIFT-MOD 1)
(local KEY_ESCAPE 27)
(local KEY_LEFT 1073741904)
(local KEY_RIGHT 1073741903)

(fn make-ctx []
  (local ctx {:transitions []
              :executed 0})
  (set ctx.set-state (fn [name]
                       (table.insert ctx.transitions name)))
  (tset ctx :mark-command-executed! (fn []
                                      (set ctx.executed (+ ctx.executed 1))))
  ctx)

(fn make-input [opts]
  (local options (if (= opts nil) {} opts))
  (local text (if (= options.text nil) "abc" options.text))
  (local model (InputModel {:text text}))
  (local input {:model model
                :multiline? (= options.multiline? true)
                :inserted []})
  (set input.move-caret (fn [_self delta]
                          (model:move-caret delta)))
  (set input.move-caret-to (fn [_self position]
                             (model:move-caret-to position)))
  (set input.insert-text (fn [self text]
                           (table.insert self.inserted text)
                           (model:insert-text text)
                           true))
  (set input.delete-at-cursor (fn [_self]
                                (model:delete-at-cursor)))
  (set input.enter-insert-mode (fn [_self]
                                 (model:enter-insert-mode)
                                 true))
  (set input.enter-normal-mode (fn [_self]
                                 (model:enter-normal-mode)
                                 true))
  (set input.submit (fn [_self _payload]
                      true))
  (when options.cursor
    (model:move-caret-to options.cursor))
  input)

(fn handle [ctx state input key opts]
  (local payload {:key key})
  (when (and opts opts.shift?)
    (set payload.mod SHIFT-MOD))
  (TextNormalCommands.handle-key ctx state input payload))

(fn assert-cursor [input line column label]
  (assert (= input.model.cursor-line line) (.. label " line"))
  (assert (= input.model.cursor-column column) (.. label " column")))

(fn label-entry [entries label]
  (var found nil)
  (each [_ item (ipairs entries)]
    (when (= item.label label)
      (set found item)))
  found)

(fn entry-priority [entries label]
  (. (label-entry entries label) :priority))

(fn insert-commands-enter-insert-mode []
  (Runtime.reset)
  (local ctx (make-ctx))
  (local state (TextNormalCommands.make-state))
  (local input (make-input {:text "abc" :cursor 1}))
  (assert (handle ctx state input (string.byte "i")) "i should be handled")
  (assert (= input.model.mode :insert) "i should enter insert mode")
  (assert (= (. ctx.transitions 1) :insert) "i should route to insert state")
  (assert (= ctx.executed 1) "handled insert command should mark executed")

  (local append (make-input {:text "abc" :cursor 1}))
  (assert (handle (make-ctx) (TextNormalCommands.make-state) append (string.byte "a"))
          "a should be handled")
  (assert (= append.model.cursor-column 2) "a should advance one character")
  (assert (= append.model.mode :insert) "a should enter insert mode")

  (local line-end (make-input {:text "abc" :cursor 0}))
  (assert (handle (make-ctx) (TextNormalCommands.make-state) line-end (string.byte "a") {:shift? true})
          "A should be handled")
  (assert (= line-end.model.cursor-column 3) "A should append after line end")
  (Runtime.reset))

(fn linewise-insert-and-open-commands []
  (Runtime.reset)
  (local insert-start (make-input {:text "  foo" :multiline? true :cursor 4}))
  (assert (handle (make-ctx) (TextNormalCommands.make-state) insert-start (string.byte "i") {:shift? true})
          "I should be handled")
  (assert (= insert-start.model.cursor-column 2) "I should move to first nonblank")
  (assert (= insert-start.model.mode :insert) "I should enter insert mode")

  (local below (make-input {:text "foo\nbar" :multiline? true :cursor 0}))
  (assert (handle (make-ctx) (TextNormalCommands.make-state) below (string.byte "o"))
          "o should be handled for multiline input")
  (assert (= (below.model:get-text) "foo\n\nbar") "o should open a line below")
  (assert (= below.model.mode :insert) "o should enter insert mode")

  (local above (make-input {:text "foo\nbar\nbaz" :multiline? true :cursor 4}))
  (assert (handle (make-ctx) (TextNormalCommands.make-state) above (string.byte "o") {:shift? true})
          "O should be handled for multiline input")
  (assert (= (above.model:get-text) "foo\n\nbar\nbaz") "O should open a line above")
  (assert-cursor above 1 0 "O opened line")
  (Runtime.reset))

(fn navigation-commands-use-port []
  (Runtime.reset)
  (local input (make-input {:text "abc\ndef" :multiline? true :cursor 2}))
  (local ctx (make-ctx))
  (local state (TextNormalCommands.make-state))
  (assert (handle ctx state input (string.byte "h")) "h should move left")
  (assert-cursor input 0 1 "h")
  (assert (handle ctx state input KEY_RIGHT) "right arrow should move right")
  (assert-cursor input 0 2 "right arrow")
  (assert (handle ctx state input (string.byte "h")) "h should move left before line-end")
  (assert-cursor input 0 1 "h before line-end")
  (assert (handle ctx state input (string.byte "4") {:shift? true}) "$ should move to line end")
  (assert-cursor input 0 2 "$")
  (assert (handle ctx state input (string.byte "0")) "0 should move to line start")
  (assert-cursor input 0 0 "0")
  (assert (handle ctx state input (string.byte "l")) "l should move right before left-arrow")
  (assert (handle ctx state input KEY_LEFT) "left arrow should move left")
  (assert-cursor input 0 0 "left arrow")
  (assert (handle ctx state input (string.byte "j")) "j should move down")
  (assert-cursor input 1 0 "j")
  (assert (handle ctx state input (string.byte "l")) "l should move right")
  (assert-cursor input 1 1 "l")
  (assert (handle ctx state input (string.byte "k")) "k should move up")
  (assert-cursor input 0 1 "k"))

(fn line-jump-first-nonblank-and-delete-commands []
  (Runtime.reset)
  (local input (make-input {:text "one\n  two\nthree" :multiline? true :cursor 5}))
  (local ctx (make-ctx))
  (local state (TextNormalCommands.make-state))
  (assert (handle ctx state input (string.byte "6") {:shift? true}) "^ should be handled")
  (assert-cursor input 1 2 "^")
  (assert (handle ctx state input (string.byte "g")) "first g should enter goto prefix")
  (assert (= state.pending-keymap state.goto-keymap) "g should set goto prefix")
  (assert (handle ctx state input (string.byte "g")) "gg should be handled")
  (assert-cursor input 0 0 "gg")
  (assert (handle ctx state input (string.byte "g") {:shift? true}) "G should be handled")
  (assert-cursor input 2 0 "G")

  (local deleting (make-input {:text "abc" :cursor 3}))
  (assert (handle (make-ctx) (TextNormalCommands.make-state) deleting (string.byte "x"))
          "x should delete at cursor after clamping")
  (assert (= (deleting.model:get-text) "ab") "x should delete the clamped character")
  (assert (= deleting.model.cursor-column 1) "x should clamp caret after delete"))

(fn prefix-fallback-and-cancel-clear_pending_keymap []
  (Runtime.reset)
  (local input (make-input {:text "abc" :cursor 1}))
  (local state (TextNormalCommands.make-state))
  (assert (handle (make-ctx) state input (string.byte "g")) "g should enter prefix")
  (assert (handle (make-ctx) state input (string.byte "l")) "g l should fall back to root l")
  (assert (= state.pending-keymap nil) "fallback should clear pending prefix")
  (assert (= input.model.cursor-column 2) "fallback l should move right")

  (assert (handle (make-ctx) state input (string.byte "g")) "g should enter prefix again")
  (local handled (handle (make-ctx) state input KEY_ESCAPE))
  (assert (not handled) "escape cancellation does not execute a command")
  (assert (= state.pending-keymap nil) "escape should clear pending prefix"))

(fn unbound-keys-do-not-create_port_or_clamp []
  (Runtime.reset)
  (local ctx (make-ctx))
  (local state (TextNormalCommands.make-state))
  (local incomplete-input {:kind :missing-port-ops})
  (local (ok handled) (pcall #(TextNormalCommands.handle-key ctx state incomplete-input {:key 1073741882})))
  (assert ok "unbound F1 should not create a port or clamp")
  (assert (not handled) "unbound F1 should not be handled by command engine")
  (assert (= ctx.executed 0) "unbound F1 should not mark command executed")
  (local (tab-ok tab-handled) (pcall #(TextNormalCommands.handle-key ctx state incomplete-input {:key 9})))
  (assert tab-ok "unbound Tab should not create a port or clamp")
  (assert (not tab-handled) "unbound Tab should not be handled by command engine"))

(fn command-hints-preserve_labels_priorities_and_prefix_meta []
  (Runtime.reset)
  (local state (TextNormalCommands.make-state))
  (local (entries prefix-meta) (TextNormalCommands.command-hint-entries state {}))
  (assert (= prefix-meta nil) "root hints should not have prefix meta")
  (assert (= (entry-priority entries "insert") 10) "i priority should be preserved")
  (assert (= (entry-priority entries "append-after") 11) "a priority should be preserved")
  (assert (= (entry-priority entries "append-line-end") 12) "A priority should be preserved")
  (assert (= (entry-priority entries "insert-line-start") 13) "I priority should be preserved")
  (assert (= (entry-priority entries "open-below") 14) "o priority should be preserved")
  (assert (= (entry-priority entries "open-above") 15) "O priority should be preserved")
  (assert (= (entry-priority entries "goto") 20) "g priority should be preserved")
  (assert (= (entry-priority entries "last-line") 21) "G priority should be preserved")
  (assert (= (entry-priority entries "left") 30) "h priority should be preserved")
  (assert (= (entry-priority entries "right") 31) "l priority should be preserved")
  (assert (= (entry-priority entries "down") 32) "j priority should be preserved")
  (assert (= (entry-priority entries "up") 33) "k priority should be preserved")
  (assert (= (entry-priority entries "line-start") 40) "0 priority should be preserved")
  (assert (= (entry-priority entries "line-end") 41) "$ priority should be preserved")
  (assert (= (entry-priority entries "first-nonblank") 42) "^ priority should be preserved")
  (assert (= (entry-priority entries "delete-char") 50) "x priority should be preserved")

  (set state.pending-keymap state.goto-keymap)
  (local (prefix-entries prefix) (TextNormalCommands.command-hint-entries state {}))
  (assert (= prefix.title "GOTO") "goto prefix title should be preserved")
  (assert (= (entry-priority prefix-entries "first-line") 10) "gg hint priority should be preserved")
  (assert (= (entry-priority prefix-entries "cancel-prefix") 90) "escape hint priority should be preserved"))

(fn sync-mode-enters-normal_mode []
  (Runtime.reset)
  (local input (make-input))
  (input:enter-insert-mode)
  (assert (TextNormalCommands.sync-mode input) "sync-mode should report handled input")
  (assert (= input.model.mode :normal) "sync-mode should enter normal mode"))

(table.insert tests {:name "Text normal commands insert and append" :fn insert-commands-enter-insert-mode})
(table.insert tests {:name "Text normal commands linewise insert and open lines" :fn linewise-insert-and-open-commands})
(table.insert tests {:name "Text normal commands navigate through port" :fn navigation-commands-use-port})
(table.insert tests {:name "Text normal commands line jumps first-nonblank and delete" :fn line-jump-first-nonblank-and-delete-commands})
(table.insert tests {:name "Text normal commands prefix fallback and cancel" :fn prefix-fallback-and-cancel-clear_pending_keymap})
(table.insert tests {:name "Text normal commands ignore unbound keys without port side effects" :fn unbound-keys-do-not-create_port_or_clamp})
(table.insert tests {:name "Text normal commands preserve command hints" :fn command-hints-preserve_labels_priorities_and_prefix_meta})
(table.insert tests {:name "Text normal commands sync mode" :fn sync-mode-enters-normal_mode})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "text-normal-commands"
                       :tests tests})))

{:name "text-normal-commands"
 :tests tests
 :main main}
