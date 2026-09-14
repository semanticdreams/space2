(local Runtime (require :state-runtime))
(local TextEditingPort (require :text-editing-port))
(local {: entry} (require :command-hints))

(local SDLK_LEFT 1073741904)
(local SDLK_RIGHT 1073741903)
(local KEY_ESCAPE 27)

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

(fn port-for [input]
  (TextEditingPort.from-input input))

(fn enter-insert-mode [ctx]
  ((. ctx :set-state) :insert))

(fn enter-insert-state [ctx port]
  (port:enter-insert-mode)
  (Runtime.ignore-next-text-input)
  (enter-insert-mode ctx)
  true)

(fn open-line-below [ctx port]
  (if (not (port:multiline?))
      false
      (do
        (port:move-to-line-edge :end)
        (port:move-caret 1)
        (port:insert-text "\n")
        (enter-insert-state ctx port))))

(fn open-line-above [ctx port]
  (if (not (port:multiline?))
      false
      (do
        (local (current _column) (port:cursor-line-column))
        (port:move-to-line-column current 0)
        (port:insert-text "\n")
        (port:move-to-line-column current 0)
        (enter-insert-state ctx port))))

(fn command-enter-insert [port _state ctx]
  (enter-insert-state ctx port))

(fn command-insert-after [port _state ctx]
  (port:move-caret 1)
  (enter-insert-state ctx port))

(fn command-append-line-end [port _state ctx]
  (port:move-to-line-edge :end)
  (port:move-caret 1)
  (enter-insert-state ctx port))

(fn command-insert-line-start [port _state ctx]
  (port:move-to-first-nonblank)
  (enter-insert-state ctx port))

(fn command-open-line-below [port _state ctx]
  (open-line-below ctx port))

(fn command-open-line-above [port _state ctx]
  (open-line-above ctx port))

(fn command-go-last-line [port _state]
  (port:move-to-last-line))

(fn command-go-first-line [port _state]
  (port:move-to-first-line))

(fn command-move-horizontal [delta]
  (fn [port _state]
    (port:move-horizontal delta)))

(fn command-move-vertical [delta]
  (fn [port _state]
    (port:move-vertical delta)))

(fn command-line-edge [edge]
  (fn [port _state]
    (port:move-to-line-edge edge)))

(fn command-first-nonblank [port _state]
  (port:move-to-first-nonblank))

(fn command-delete-forward [port _state]
  (port:delete-at-cursor))

(fn binding-handler [binding]
  (if (= (type binding) "table")
      binding.handler
      (if (= (type binding) "function")
          binding
          nil)))

(fn binding-next [binding]
  (and (= (type binding) "table") binding.next))

(fn apply-binding [ctx state input binding key]
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
              (local port (port-for input))
              (port:clamp-before-command-key key)
              (local handled (handler port state ctx))
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

(fn hint [key label priority opts]
  (local options (if (= opts nil) {} opts))
  (entry key label {:priority priority
                    :show-collapsed? options.show-collapsed?}))

(fn make-state []
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
   :prefixes prefixes
   :goto-keymap g-map
   :pending-keymap nil})

(fn handle-key [ctx command-state input payload]
  (local key (resolve-key payload))
  (if (not (and input key))
      false
      (if (and command-state.pending-keymap (= key KEY_ESCAPE))
          (do
            (set command-state.pending-keymap nil)
          false)
          (do
            (local binding (resolve-binding command-state key))
            (if binding
                (apply-binding ctx command-state input binding key)
                false)))))

(fn command-hint-entries [command-state _payload]
  (local prefixes command-state.prefixes)
  (local pending command-state.pending-keymap)
  (local prefix-meta (and prefixes pending (. prefixes pending)))
  (local entries [])
  (if prefix-meta
      (each [_ hint-entry (ipairs (if prefix-meta.entries prefix-meta.entries []))]
        (table.insert entries hint-entry))
      (each [_ hint-entry (ipairs (if command-state.root-entries command-state.root-entries []))]
        (table.insert entries hint-entry)))
  (values entries prefix-meta))

(fn sync-mode [input]
  (if input
      (do
        (local port (port-for input))
        (port:enter-normal-mode)
        true)
      false))

{:make-state make-state
 :handle-key handle-key
 :command-hint-entries command-hint-entries
 :sync-mode sync-mode}
