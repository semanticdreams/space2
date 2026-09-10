(local State (require :state))
(local Routes (require :state-routes))
(local HoverHandlers (require :state-handlers/hover))
(local TextInputHandlers (require :state-handlers/text-input))
(local FocusHandlers (require :state-handlers/focus))
(local PointerHandlers (require :state-handlers/pointer))
(local TouchHandlers (require :state-handlers/touch-pointer))
(local PenPointer (require :state-handlers/pen-pointer))
(local GamepadHandlers (require :state-handlers/gamepad))
(local CameraHandlers (require :state-handlers/camera))
(local Runtime (require :state-runtime))
(local InputState (require :input-state-router))
(local {: entry : section : KEY_F1} (require :command-hints))

(local SDLK_RETURN 13)
(local SDLK_LEFT 1073741904)
(local SDLK_RIGHT 1073741903)

(local KEY
  {:i (string.byte "i")
   :a (string.byte "a")
   :A (string.byte "A")
   :I (string.byte "I")
   :o (string.byte "o")
   :O (string.byte "O")
   :g (string.byte "g")
   :G (string.byte "G")
   :h (string.byte "h")
   :j (string.byte "j")
   :k (string.byte "k")
   :l (string.byte "l")
   :x (string.byte "x")
   :zero (string.byte "0")
   :dollar (string.byte "$")
   :caret (string.byte "^")})

(local shifted-key-map
  {(string.byte "a") (string.byte "A")
   (string.byte "i") (string.byte "I")
   (string.byte "o") (string.byte "O")
   (string.byte "g") (string.byte "G")
   (string.byte "4") (string.byte "$")
   (string.byte "6") (string.byte "^")})

(fn resolve-key [payload]
  (local key (and payload payload.key))
  (if (and key (Runtime.shift-held? payload))
      (if (= (. shifted-key-map key) nil)
          key
          (. shifted-key-map key))
      key))

(local whitespace-codepoints {})
(tset whitespace-codepoints 9 true)
(tset whitespace-codepoints 10 true)
(tset whitespace-codepoints 11 true)
(tset whitespace-codepoints 12 true)
(tset whitespace-codepoints 13 true)
(tset whitespace-codepoints 32 true)

(fn whitespace? [codepoint]
  (and codepoint (. whitespace-codepoints codepoint)))

(fn active-input []
  (and InputState InputState.active-input (InputState.active-input)))

(fn enter-insert-mode [ctx]
  ((. ctx :set-state) :insert))

(fn input-model [input]
  (if (and input input.model)
      input.model
      input))

(fn input-lines [input]
  (local model (input-model input))
  (and model model.lines))

(fn line-count [lines]
  (if lines
      (length lines)
      0))

(fn clamp-line-index [lines idx]
  (local total (line-count lines))
  (if (<= total 0)
      0
      (math.max 0 (math.min idx (- total 1)))))

(fn line-length [lines idx]
  (local line (and lines (. lines (+ idx 1))))
  (if (and line line.codepoints)
      (length line.codepoints)
      0))

(fn last-valid-column [line-size]
  (local size (if (= line-size nil) 0 line-size))
  (if (> size 0)
      (- size 1)
      0))

(fn clamp-column-to-line [line-size column]
  (local limit (last-valid-column line-size))
  (local value (if (= column nil) 0 column))
  (math.max 0 (math.min value limit)))

(fn line-start-index [lines idx]
  (var total 0)
  (var i 0)
  (while (< i idx)
    (local line (and lines (. lines (+ i 1))))
    (when line
      (local cp-count (length (if line.codepoints line.codepoints [])))
      (local newline-length (if (= line.newline-length nil) 0 line.newline-length))
      (set total (+ total cp-count newline-length)))
    (set i (+ i 1)))
  total)

(fn line-first-nonblank [line]
  (if (not line)
      0
      (do
        (local codepoints (if line.codepoints line.codepoints []))
        (var column 0)
        (var found nil)
        (each [_ codepoint (ipairs codepoints)]
          (when (not found)
            (if (whitespace? codepoint)
                (set column (+ column 1))
                (set found column))))
        (if (= found nil) 0 found))))

(fn current-line-index [input]
  (local model (input-model input))
  (math.max 0 (if (and model model.cursor-line) model.cursor-line 0)))

(fn current-column [input]
  (local model (input-model input))
  (math.max 0 (if (and model model.cursor-column) model.cursor-column 0)))

(fn has-logical-navigation? [input]
  (and input input.text-line-count input.text-line-length
       input.text-line-first-nonblank input.text-cursor-line-column
       input.move-caret-to-line-column))

(fn logical-current-line-index [input]
  (if input.bounded-logical-navigation?
      (current-line-index input)
      (has-logical-navigation? input)
      (do
        (local (line _column) (input:text-cursor-line-column))
        (math.max 0 (if (= line nil) 0 line)))
      (current-line-index input)))

(fn logical-current-column [input]
  (if input.bounded-logical-navigation?
      (current-column input)
      (has-logical-navigation? input)
      (do
        (local (_line column) (input:text-cursor-line-column))
        (math.max 0 (if (= column nil) 0 column)))
      (current-column input)))

(fn logical-line-count [input lines]
  (if (has-logical-navigation? input)
      (input:text-line-count)
      (line-count lines)))

(fn logical-line-length [input lines idx]
  (if (has-logical-navigation? input)
      (input:text-line-length idx)
      (line-length lines idx)))

(fn logical-clamp-line-index [input lines idx]
  (local total (logical-line-count input lines))
  (if (<= total 0)
      0
      (math.max 0 (math.min idx (- total 1)))))

(fn remember-column [input column]
  (if column
      (set input.__preferred-column column)
      (set input.__preferred-column (logical-current-column input)))
  input.__preferred-column)

(fn preferred-column [input]
  (if (= input.__preferred-column nil)
      (logical-current-column input)
      input.__preferred-column))

(fn bounded-hot-key? [input key]
  (if (not (and input input.bounded-logical-navigation?))
      false
      (= key KEY.h)
      true
      (= key KEY.l)
      true
      (= key KEY.j)
      true
      (= key KEY.k)
      true
      (= key SDLK_LEFT)
      true
      (= key SDLK_RIGHT)
      true
      false))

(fn move-to-line-column [input line-index column]
  (local lines (input-lines input))
  (local model (input-model input))
  (if (has-logical-navigation? input)
      (do
        (local total (input:text-line-count))
        (if (<= total 0)
            (do
              (local moved (input:move-caret-to-line-column 0 0))
              (remember-column input 0)
              moved)
            (do
              (local requested-line (if (= line-index nil) 0 line-index))
              (local clamped-line (math.max 0 (math.min requested-line (- total 1))))
              (local line-size (input:text-line-length clamped-line))
              (local clamped-column (clamp-column-to-line line-size column))
              (local moved (input:move-caret-to-line-column clamped-line clamped-column))
              (remember-column input clamped-column)
              moved)))
      (not lines)
      (do
        (local codepoints (if (and model model.codepoints) model.codepoints []))
        (local total (length codepoints))
        (local clamped (clamp-column-to-line total column))
        (local moved (input:move-caret-to clamped))
        (remember-column input clamped)
        moved)
      (do
        (local total (line-count lines))
        (if (<= total 0)
            (do
              (local moved (input:move-caret-to 0))
              (remember-column input 0)
              moved)
            (do
              (local clamped (clamp-line-index lines line-index))
              (local line-size (line-length lines clamped))
              (local clamped-column (clamp-column-to-line line-size column))
              (local start (line-start-index lines clamped))
              (local target (+ start clamped-column))
              (local moved (input:move-caret-to target))
              (remember-column input clamped-column)
              moved)))))

(fn move-to-line-edge [input edge]
  (local lines (input-lines input))
  (if (has-logical-navigation? input)
      (do
        (local current (logical-clamp-line-index input lines (logical-current-line-index input)))
        (local line-size (logical-line-length input lines current))
        (local column (if (= edge :start)
                          0
                          (last-valid-column line-size)))
        (move-to-line-column input current column))
      (not lines)
      (do
        (local model (input-model input))
        (local codepoints (if (and model model.codepoints) model.codepoints []))
        (local column (if (= edge :start)
                          0
                          (last-valid-column (length codepoints))))
        (move-to-line-column input 0 column))
      (do
        (local current (clamp-line-index lines (current-line-index input)))
        (local line-size (line-length lines current))
        (local column (if (= edge :start)
                          0
                          (last-valid-column line-size)))
        (move-to-line-column input current column))))

(fn move-to-first-nonblank [input]
  (local lines (input-lines input))
  (if (has-logical-navigation? input)
      (do
        (local current (logical-clamp-line-index input lines (logical-current-line-index input)))
        (local column (input:text-line-first-nonblank current))
        (move-to-line-column input current column))
      (not lines)
      (move-to-line-edge input :start)
      (do
        (local current (clamp-line-index lines (logical-current-line-index input)))
        (local line (. lines (+ current 1)))
        (local column (line-first-nonblank line))
        (move-to-line-column input current column))))

(fn move-to-first-line [input]
  (remember-column input nil)
  (move-to-line-column input 0 0))

(fn move-to-last-line [input]
  (remember-column input nil)
  (local lines (input-lines input))
  (local total (logical-line-count input lines))
  (if (<= total 0)
      false
      (move-to-line-column input (- total 1) (preferred-column input))))

(fn move-horizontal [input delta]
  (if (and input.bounded-logical-navigation? input.move-caret-horizontal-bounded)
      (do
        (local moved (input:move-caret-horizontal-bounded delta))
        (when moved
          (remember-column input nil))
        moved)
      (do
        (local model (input-model input))
        (local lines (input-lines input))
        (if (if (not model) true (and (not lines) (not (has-logical-navigation? input))))
            (input:move-caret delta)
            (do
              (local column (logical-current-column input))
              (local line-index (logical-current-line-index input))
              (local line-size (logical-line-length input lines line-index))
              (local max-column (last-valid-column line-size))
              (if (< delta 0)
                  (if (> column 0)
                      (do
                        (local moved (input:move-caret delta))
                        (when moved
                          (remember-column input nil))
                        moved)
                      false)
                  (if (and (> line-size 0)
                           (< column max-column))
                      (do
                        (local moved (input:move-caret delta))
                        (when moved
                          (remember-column input nil))
                        moved)
                      false)))))))

(fn move-vertical [input delta]
  (if (and input.bounded-logical-navigation? input.move-caret-vertical-bounded)
      (do
        (when (= input.__preferred-column nil)
          (remember-column input nil))
        (input:move-caret-vertical-bounded delta))
      (do
        (remember-column input nil)
        (local lines (input-lines input))
        (if (and (not lines) (not (has-logical-navigation? input)))
            false
            (do
              (local total (logical-line-count input lines))
              (if (<= total 0)
                  false
                  (do
                    (local current (logical-clamp-line-index input lines (logical-current-line-index input)))
                    (local target (math.max 0 (math.min (+ current delta) (- total 1))))
                    (if (= target current)
                        false
                        (move-to-line-column input target (preferred-column input))))))))))

(fn clamp-caret-to-current-line [input]
  (local lines (input-lines input))
  (if (and (not lines) (not (has-logical-navigation? input)))
      (move-to-line-column input 0 (logical-current-column input))
      (do
        (local current-line (logical-clamp-line-index input lines (logical-current-line-index input)))
        (local column (logical-current-column input))
        (local line-size (logical-line-length input lines current-line))
        (local clamped (clamp-column-to-line line-size column))
        (if (= column clamped)
            false
            (move-to-line-column input current-line clamped)))))

(fn enter-insert-state [ctx input]
  (input:enter-insert-mode)
  (Runtime.ignore-next-text-input)
  (enter-insert-mode ctx)
  true)

(fn open-line-below [ctx input]
  (if (not (= input.multiline? true))
      false
      (do
        (move-to-line-edge input :end)
        (input:move-caret 1)
        (input:insert-text "\n")
        (remember-column input 0)
        (enter-insert-state ctx input))))

(fn open-line-above [ctx input]
  (if (not (= input.multiline? true))
      false
      (do
        (local lines (input-lines input))
        (if (has-logical-navigation? input)
            (do
              (local current (logical-clamp-line-index input lines (logical-current-line-index input)))
              (move-to-line-column input current 0)
              (input:insert-text "\n")
              (move-to-line-column input current 0)
              (remember-column input 0)
              (enter-insert-state ctx input))
            (not lines)
            false
            (do
              (local current (clamp-line-index lines (logical-current-line-index input)))
              (local start (line-start-index lines current))
              (input:move-caret-to start)
              (input:insert-text "\n")
              (input:move-caret-to start)
              (remember-column input 0)
              (enter-insert-state ctx input))))))

(fn command-enter-insert [input _state ctx]
  (enter-insert-state ctx input))

(fn command-insert-after [input _state ctx]
  (input:move-caret 1)
  (enter-insert-state ctx input))

(fn command-append-line-end [input _state ctx]
  (move-to-line-edge input :end)
  (input:move-caret 1)
  (enter-insert-state ctx input))

(fn command-insert-line-start [input _state ctx]
  (move-to-first-nonblank input)
  (enter-insert-state ctx input))

(fn command-open-line-below [input _state ctx]
  (open-line-below ctx input))

(fn command-open-line-above [input _state ctx]
  (open-line-above ctx input))

(fn command-go-last-line [input _state]
  (move-to-last-line input))

(fn command-go-first-line [input _state]
  (move-to-first-line input))

(fn command-move-horizontal [delta]
  (fn [input _state]
    (move-horizontal input delta)))

(fn command-move-vertical [delta]
  (fn [input _state]
    (move-vertical input delta)))

(fn command-line-edge [edge]
  (fn [input _state]
    (move-to-line-edge input edge)))

(fn command-first-nonblank [input _state]
  (move-to-first-nonblank input))

(fn command-delete-forward [input _state]
  (local removed (input:delete-at-cursor))
  (when removed
    (clamp-caret-to-current-line input))
  removed)

(fn make-default-keymap []
  (local move-left (command-move-horizontal -1))
  (local move-right (command-move-horizontal 1))
  (local move-down (command-move-vertical 1))
  (local move-up (command-move-vertical -1))
  (local line-start (command-line-edge :start))
  (local line-end (command-line-edge :end))
  (local keymap {})
  (local root-entries [])
  (local prefixes {})
  (fn bind [target key binding]
    (tset target key binding))
  (fn hint [key label priority opts]
    (local options (if (= opts nil) {} opts))
    (entry key label {:priority priority
                      :show-collapsed? options.show-collapsed?}))
  (bind keymap KEY.i {:handler command-enter-insert})
  (table.insert root-entries (hint "i" "insert" 10))
  (bind keymap KEY.a {:handler command-insert-after})
  (table.insert root-entries (hint "a" "append-after" 11))
  (bind keymap KEY.A {:handler command-append-line-end})
  (table.insert root-entries (hint "A" "append-line-end" 12 {:show-collapsed? false}))
  (bind keymap KEY.I {:handler command-insert-line-start})
  (table.insert root-entries (hint "I" "insert-line-start" 13 {:show-collapsed? false}))
  (bind keymap KEY.o {:handler command-open-line-below})
  (table.insert root-entries (hint "o" "open-below" 14))
  (bind keymap KEY.O {:handler command-open-line-above})
  (table.insert root-entries (hint "O" "open-above" 15 {:show-collapsed? false}))
  (local g-map {})
  (bind g-map KEY.g {:handler command-go-first-line})
  (set (. prefixes g-map)
       {:title "GOTO"
        :entries [(hint "g" "first-line" 10)
                  (hint "esc" "cancel-prefix" 90)]})
  (bind keymap KEY.g {:next g-map})
  (table.insert root-entries (hint "g" "goto" 20))
  (bind keymap KEY.G {:handler command-go-last-line})
  (table.insert root-entries (hint "G" "last-line" 21 {:show-collapsed? false}))
  (bind keymap KEY.h {:handler move-left})
  (table.insert root-entries (hint "h" "left" 30))
  (bind keymap KEY.l {:handler move-right})
  (table.insert root-entries (hint "l" "right" 31))
  (bind keymap KEY.j {:handler move-down})
  (table.insert root-entries (hint "j" "down" 32))
  (bind keymap KEY.k {:handler move-up})
  (table.insert root-entries (hint "k" "up" 33))
  (bind keymap KEY.zero {:handler line-start})
  (table.insert root-entries (hint "0" "line-start" 40 {:show-collapsed? false}))
  (bind keymap KEY.dollar {:handler line-end})
  (table.insert root-entries (hint "$" "line-end" 41 {:show-collapsed? false}))
  (bind keymap KEY.caret {:handler command-first-nonblank})
  (table.insert root-entries (hint "^" "first-nonblank" 42 {:show-collapsed? false}))
  (bind keymap KEY.x {:handler command-delete-forward})
  (table.insert root-entries (hint "x" "delete-char" 50))
  (bind keymap SDLK_LEFT {:handler move-left})
  (bind keymap SDLK_RIGHT {:handler move-right})
  {:keymap keymap
   :root-entries root-entries
   :prefixes prefixes})

(fn binding-handler [binding]
  (if (= (type binding) "table")
      binding.handler
      (if (= (type binding) "function")
          binding
          nil)))

(fn binding-next [binding]
  (and (= (type binding) "table") binding.next))

(fn apply-binding [ctx state input binding]
  (local next (binding-next binding))
  (if next
      (do
        (set state.pending-keymap next)
        true)
      (do
        (local handler (binding-handler binding))
        (set state.pending-keymap nil)
        (if (not handler)
            false
            (do
              (local handled (handler input state ctx))
              (when handled
                ((. ctx :mark-command-executed!)))
              handled)))))

(fn resolve-binding [state key]
  (local keymap (if state.pending-keymap state.pending-keymap state.keymap))
  (local binding (and keymap (. keymap key)))
  (if binding
      binding
      (if state.pending-keymap
          (do
            (set state.pending-keymap nil)
            (resolve-binding state key))
          nil)))

(fn handle-key-command [ctx state input key]
  (local binding (resolve-binding state key))
  (if binding
      (apply-binding ctx state input binding)
      false))

(fn handle-text-key [ctx state payload]
  (local input (active-input))
  (if (not input)
      false
      (do
        (local key (resolve-key payload))
        (when (and key (not (bounded-hot-key? input key)))
          (clamp-caret-to-current-line input))
        (if (not key)
            false
            (handle-key-command ctx state input key)))))

(fn handle-submit [ctx payload]
  (local input (active-input))
  (if (not input)
      false
      (if (and payload
               (= payload.key SDLK_RETURN)
               (Runtime.ctrl-held? payload))
          (do
            (input:submit payload)
            ((. ctx :mark-command-executed!))
            true)
          false)))

(fn on-key-down [ctx state payload]
  (local mark-command (fn []
                        ((. ctx :mark-command-executed!))))
  (local controls (and app.presentation-input-controls
                        (app.presentation-input-controls)))
  (if (handle-submit ctx payload)
      true
      (InputState.dispatch-input :on-key-down payload)
      (do
        (mark-command)
        true)
      (handle-text-key ctx state payload)
      true
      (Runtime.handle-focus-tab ctx payload)
      (do
        (mark-command)
        true)
      (and (active-input)
           (not (= (and payload payload.key) KEY_F1)))
      true
      controls
      (do
        (local handled (controls:on-key-down payload))
        (when handled
          (mark-command))
        handled)
      false))

(fn sync-mode []
  (local input (active-input))
  (when input
    (input:enter-normal-mode)))

(fn command-hint-entries [state payload]
  (local prefixes state.command_hints_prefixes)
  (local pending state.pending-keymap)
  (local prefix-meta (and prefixes pending (. prefixes pending)))
  (local focus-manager (and payload payload.focus-manager))
  (local entries [])
  (if prefix-meta
      (each [_ hint (ipairs (if prefix-meta.entries prefix-meta.entries []))]
        (table.insert entries hint))
      (do
        (each [_ hint (ipairs (if state.command_hints_root state.command_hints_root []))]
          (table.insert entries hint))
        (table.insert entries (entry "ctrl+enter" "submit" {:priority 16 :show-collapsed? false}))
        (when focus-manager
          (table.insert entries (entry "tab" "focus-next" {:priority 60 :show-collapsed? false})))))
  (values entries prefix-meta))

(fn text-command-hints-provider [state payload]
  (local (entries prefix-meta) (command-hint-entries state payload))
  (if (> (length entries) 0)
      [(section :mode
                (if (and prefix-meta prefix-meta.title)
                    (.. "MODE " prefix-meta.title)
                    "MODE")
                entries)]
      []))

(fn TextState []
  (var state nil)
  (local PenHandlers (PenPointer.PenPointerHandlers {}))
  (fn on-text-lifecycle-enter [_ctx]
    (when state
      (set state.pending-keymap nil))
    (sync-mode))
  (fn on-text-command-key-down [ctx payload]
    (not (not (on-key-down ctx state payload))))
  (fn on-text-command-hints [_self payload]
    (text-command-hints-provider state payload))
  (local TextLifecycle
    {:enter on-text-lifecycle-enter})
  (local TextCommands
    {:key-down on-text-command-key-down})
  (set state
       (State
        {:name :text
         :route-wrappers [Routes.CommandHints]
          :command_hints_provider on-text-command-hints
          :routes {:touch-down (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseDown])
                   :touch-motion (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseMotion])
                   :touch-up (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseUp])
                   :touch-canceled (Routes.FirstHandlerWins [TouchHandlers.PrimaryTouchMouseCanceled])
                   :pen-proximity-in (Routes.Chain [PenHandlers.PenProximityIn])
                   :pen-proximity-out (Routes.Chain [PenHandlers.PenProximityOut])
                   :pen-motion (Routes.Chain [PenHandlers.PenMotion])
                   :pen-down (Routes.Chain [PenHandlers.PenDown])
                   :pen-up (Routes.Chain [PenHandlers.PenUp])
                   :pen-button-down (Routes.Chain [PenHandlers.PenButtonDown])
                   :pen-button-up (Routes.Chain [PenHandlers.PenButtonUp])
                   :pen-axis (Routes.Chain [PenHandlers.PenAxis])
                   :text-input (Routes.FirstHandlerWins [TextInputHandlers.TextInputDispatch])
                   :text-editing (Routes.FirstHandlerWins [TextInputHandlers.TextEditingDispatch])
                   :key-down (Routes.FirstHandlerWins [TextCommands])
                   :key-up (Routes.FirstHandlerWins [FocusHandlers.InputKeyUpDispatch
                                                    FocusHandlers.ActiveInputKeyBlock])
                   :mouse-button-down (Routes.Chain [PointerHandlers.InputMouseButtonDownDispatch
                                                     PointerHandlers.ResizableMouseButtonDown
                                                     PointerHandlers.ClickableMouseButtonDown
                                                     PointerHandlers.MovableMouseButtonDown
                                                     PointerHandlers.SelectionMouseButtonDown
                                                     PointerHandlers.CameraMouseButtonDown])
                   :mouse-button-up (Routes.Chain [PointerHandlers.InputMouseButtonUpDispatch
                                                   PointerHandlers.ResizableMouseButtonUp
                                                   PointerHandlers.ClickableMouseButtonUp
                                                   PointerHandlers.MovableMouseButtonUp
                                                   PointerHandlers.SelectionMouseButtonUp
                                                   PointerHandlers.CameraMouseButtonUp
                                                   HoverHandlers.HoverAfterMouseButtonUp])
                   :mouse-motion (Routes.Chain [PointerHandlers.InputMouseMotionDispatch
                                                PointerHandlers.MovableMouseMotion
                                                PointerHandlers.ResizableMouseMotion
                                                PointerHandlers.CameraDragMouseMotion
                                                PointerHandlers.SelectionMouseMotion
                                                PointerHandlers.CameraMouseMotion
                                                HoverHandlers.HoverMouseMotion])
                   :mouse-wheel (Routes.FirstHandlerWins [PointerHandlers.InputMouseWheelDispatch
                                                         PointerHandlers.HoveredMouseWheel
                                                         PointerHandlers.CameraMouseWheel])
                   :gamepad-button-down (Routes.FirstHandlerWins [GamepadHandlers.GamepadButtonDown])
                   :gamepad-axis-motion (Routes.FirstHandlerWins [GamepadHandlers.GamepadAxisMotion])
                   :gamepad-removed (Routes.FirstHandlerWins [GamepadHandlers.GamepadRemoved])
                   :updated (Routes.Chain [CameraHandlers.CameraUpdated
                                           HoverHandlers.HoverUpdated])}
          :enter [PenHandlers.PenLifecycle
                  TouchHandlers.TouchLifecycle
                  HoverHandlers.HoverLifecycle
                  TextLifecycle]
          :leave [PenHandlers.PenLifecycle
                  TouchHandlers.TouchLifecycle
                  HoverHandlers.HoverLifecycle]}))
  (local keymap-model (make-default-keymap))
  (set state.keymap keymap-model.keymap)
  (set state.command_hints_root keymap-model.root-entries)
  (set state.command_hints_prefixes keymap-model.prefixes)
  (set state.pending-keymap nil)
  state)

TextState
