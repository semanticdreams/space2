(local glm (require :glm))
(local _ (require :main))
(local Input (require :input))
(local BuildContext (require :build-context))
(local {: FocusManager} (require :focus))
(local {: LayoutRoot} (require :layout))
(local States (require :states))
(local InputState (require :input-state-router))
(local TextState (require :text-state))
(local InsertState (require :insert-state))
(local StateSystemBindings (require :state-system-bindings))
(local {: fallback-glyph} (require :text-utils))
(local gl (require :gl))

(local tests [])

(fn codepoints->text [codepoints]
  (table.concat
    (icollect [_ codepoint (ipairs codepoints)]
              (utf8.char codepoint))))

(local MathUtils (require :math-utils))
(local approx (. MathUtils :approx))

(fn queue-size [queue]
  (var count 0)
  (each [_ _ (pairs queue.lookup)]
    (set count (+ count 1)))
  count)

(fn make-command-hints-stub []
  {:handle-toggle-key (fn [_self _payload] true)
   :close-on-handled-event (fn [_self _route-key _payload] false)})

(fn make-command-hints-hud-stub []
  {:command-hints (make-command-hints-stub)})

(fn command-hints-hud-provider [_self]
  (make-command-hints-hud-stub))

(fn ensure-command-hints-hud! [states]
  (when (and states states.get-hud states.set-hud-provider (not (states:get-hud)))
    (states:set-hud-provider command-hints-hud-provider))
  states)

(fn set-app-states! [states]
  (ensure-command-hints-hud! states)
  (StateSystemBindings.bind-states-host states)
  (set app.states states)
  states)

(fn own-test-state! [name state]
  (local states (States {:hud_provider command-hints-hud-provider}))
  (states:add-state :normal {})
  (states:add-state name state)
  (states:set-state name)
  (set-app-states! states)
  states)

(fn make-clickables-stub []
  (local state {:register 0 :unregister 0})
  (local stub {:state state})
  (set stub.register (fn [_self _obj]
                       (set state.register (+ state.register 1))))
  (set stub.unregister (fn [_self _obj]
                         (set state.unregister (+ state.unregister 1))))
  (set stub.register-right-click (fn [_self _obj]
                                   (set state.register-right-click (+ (or state.register-right-click 0) 1))))
  (set stub.unregister-right-click (fn [_self _obj]
                                     (set state.unregister-right-click (+ (or state.unregister-right-click 0) 1))))
  (set stub.register-double-click (fn [_self _obj]
                                    (set state.register-double-click (+ (or state.register-double-click 0) 1))))
  (set stub.unregister-double-click (fn [_self _obj]
                                      (set state.unregister-double-click (+ (or state.unregister-double-click 0) 1))))
  stub)

(fn make-hoverables-stub []
  (local state {:register 0 :unregister 0})
  (local stub {:state state})
  (set stub.register (fn [_self _obj]
                       (set state.register (+ state.register 1))))
  (set stub.unregister (fn [_self _obj]
                         (set state.unregister (+ state.unregister 1))))
  stub)

(fn make-system-cursors-stub []
  (local state {:calls []})
  (local stub {:state state})
  (set stub.set-cursor (fn [_self name]
                         (table.insert state.calls name)
                         (set state.last name)))
  stub)

(fn with-pointer-stubs [body]
  (local clickables (assert (make-clickables-stub) "input pointer stubs require clickables"))
  (local hoverables (assert (make-hoverables-stub) "input pointer stubs require hoverables"))
  (local cursors (assert (make-system-cursors-stub) "input pointer stubs require system cursors"))
  (local (ok result) (pcall body {:clickables clickables
                                  :hoverables hoverables
                                  :cursors cursors}))
  (when (not ok)
    (error result))
  result)

(fn make-focus-build-ctx [opts]
  (local options (assert opts "input focus build context requires pointer stubs"))
  (local manager (FocusManager {:root-name "input-test"}))
  (local root (manager:get-root-scope))
  (local scope (manager:create-scope {:name "input-scope"}))
  (manager:attach scope root)
  {:ctx (BuildContext {:focus-manager manager
                            :focus-scope scope
                            :clickables (assert options.clickables "input focus build context requires clickables")
                            :hoverables (assert options.hoverables "input focus build context requires hoverables")
                            :system-cursors (assert options.cursors "input focus build context requires system cursors")})
   :manager manager})

(fn make-first-person-stub []
  (local state {:key-down 0 :key-up 0})
  (local stub {:state state})
  (set stub.on-key-down (fn [_self _payload]
                          (set state.key-down (+ state.key-down 1))))
  (set stub.on-key-up (fn [_self _payload]
                        (set state.key-up (+ state.key-up 1))))
  (set stub.on-mouse-button-down (fn [_self _payload] nil))
  (set stub.on-mouse-button-up (fn [_self _payload] nil))
  (set stub.on-mouse-motion (fn [_self _payload] nil))
  (set stub.on-mouse-wheel (fn [_self _payload] nil))
  (set stub.on-gamepad-button-down (fn [_self _payload] nil))
  (set stub.on-gamepad-axis-motion (fn [_self _payload] nil))
  (set stub.on-gamepad-removed (fn [_self _payload] nil))
  (set stub.update (fn [_self _delta] nil))
  stub)

(fn with-first-person-controls [stub body]
  (local original app.first-person-controls)
  (set app.first-person-controls stub)
  (let [(ok result) (pcall body stub)]
    (set app.first-person-controls original)
    (when (not ok)
      (error result))
    result))

(fn make-menu-manager-stub []
  (local state {:opened nil})
  (local stub {:state state})
  (set stub.open (fn [_self opts]
                   (set state.opened opts)))
  (set stub.drop (fn [_self] nil))
  stub)

(fn with-menu-manager [stub body]
  (local original app.menu-manager)
  (set app.menu-manager stub)
  (let [(ok result) (pcall body stub)]
    (set app.menu-manager original)
    (when (not ok)
      (error result))
    result))

(fn with-clipboard-stub [body]
  (local original-set gl.clipboard-set)
  (local original-get gl.clipboard-get)
  (var clipboard "")
  (set gl.clipboard-set
       (fn [value]
         (set clipboard (or value ""))))
  (set gl.clipboard-get
       (fn []
         clipboard))
  (local (ok result) (pcall body))
  (set gl.clipboard-set original-set)
  (set gl.clipboard-get original-get)
  (if ok
      result
      (error result)))

(fn string-from-text [entity]
  (codepoints->text (entity:get-codepoints)))

(fn input-placeholder-updates []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:placeholder "NAME"})
                     ctx-info.ctx))
      (assert (= (string-from-text input.placeholder) "NAME"))
      (input:set-text "ABC")
      (assert (= (string-from-text input.placeholder) ""))
      (input:set-text "")
      (assert (= (string-from-text input.placeholder) "NAME"))
      (input:drop))))

(fn input-context-menu-default-actions []
  (with-clipboard-stub
    (fn []
      (with-pointer-stubs
        (fn [_stubs]
          (local menu (make-menu-manager-stub))
          (with-menu-manager menu
            (fn [_menu]
              (local ctx-info (make-focus-build-ctx _stubs))
              (local input ((Input {:text "alpha"}) ctx-info.ctx))
              (gl.clipboard-set "")
              (input:on-right-click {:point (glm.vec3 1 2 0)
                                     :button 3})
              (local actions (. menu.state.opened :actions))
              (assert (= (length actions) 3) "Input context menu should include 3 default actions")
              (assert (= (. (. actions 1) :name) "Copy"))
              (assert (= (. (. actions 2) :name) "Paste"))
              (assert (= (. (. actions 3) :name) "Clear"))
              ((. (. actions 1) :fn) nil nil)
              (assert (= (gl.clipboard-get) "alpha") "Copy should write full input text to clipboard")
              (input:set-text "ab")
              (input:move-caret-to 1)
              (gl.clipboard-set "Z")
              ((. (. actions 2) :fn) nil nil)
              (assert (= (input:get-text) "aZb") "Paste should insert at cursor position")
              ((. (. actions 3) :fn) nil nil)
              (assert (= (input:get-text) "") "Clear should remove input text")
              (input:drop))))))))

(fn input-context-menu-custom-actions []
  (with-clipboard-stub
    (fn []
      (with-pointer-stubs
        (fn [_stubs]
          (local menu (make-menu-manager-stub))
          (with-menu-manager menu
            (fn [_menu]
              (local ctx-info (make-focus-build-ctx _stubs))
              (local input ((Input {:text "alpha"
                                    :context-menu (fn [_input _event]
                                                    [{:name "Only"
                                                      :fn (fn [_button _event]
                                                            (gl.clipboard-set "custom"))}])})
                           ctx-info.ctx))
              (input:on-right-click {:point (glm.vec3 1 2 0)
                                     :button 3})
              (local actions (. menu.state.opened :actions))
              (assert (= (length actions) 1) "Custom context menu should replace defaults")
              (assert (= (. (. actions 1) :name) "Only"))
              ((. (. actions 1) :fn) nil nil)
              (assert (= (gl.clipboard-get) "custom"))
              (input:drop))))))))

(fn input-context-menu-extend-actions []
  (with-clipboard-stub
    (fn []
      (with-pointer-stubs
        (fn [_stubs]
          (local menu (make-menu-manager-stub))
          (with-menu-manager menu
            (fn [_menu]
              (local ctx-info (make-focus-build-ctx _stubs))
              (local input ((Input {:text "alpha"
                                    :context-menu (fn [input event]
                                                    (local actions (Input.standard-context-menu input event))
                                                    (table.insert actions {:name "Extra"
                                                                           :fn (fn [_button _event]
                                                                                 (gl.clipboard-set "extra"))})
                                                    actions)})
                           ctx-info.ctx))
              (input:on-right-click {:point (glm.vec3 1 2 0)
                                     :button 3})
              (local actions (. menu.state.opened :actions))
              (assert (= (length actions) 4) "Extended context menu should include defaults plus extras")
              (assert (= (. (. actions 1) :name) "Copy"))
              (assert (= (. (. actions 4) :name) "Extra"))
              ((. (. actions 4) :fn) nil nil)
              (assert (= (gl.clipboard-get) "extra"))
              (input:drop))))))))

(fn input-context-menu-resolves-late-menu-manager []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local original-menu-manager app.menu-manager)
      (var input nil)
      (var opened nil)
      (set app.menu-manager nil)
      (local (ok result)
             (pcall
               (fn []
                 (set input ((Input {:text "alpha"}) ctx-info.ctx))
                 (set app.menu-manager {:open (fn [_self opts]
                                                (set opened opts))})
                 (input:on-right-click {:point (glm.vec3 4 5 0)
                                        :button 3})
                 (assert opened
                         "Input should resolve app.menu-manager at click time"))))
      (when input
        (input:drop))
      (set app.menu-manager original-menu-manager)
      (when (not ok)
        (error result))
      result)))

(fn input-registers-double-click []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {}) ctx-info.ctx))
      (assert (= (or (. _stubs.clickables.state :register-double-click) 0) 1)
              "Input should register for double click")
      (input:drop)
      (assert (= (or (. _stubs.clickables.state :unregister-double-click) 0) 1)
              "Input should unregister from double click"))))

(fn input-text-and-insert-states-edit-text []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {}) ctx-info.ctx))
      (local original-states app.states)
      (local states (States))
      (var transitions [])
      (local text-state (TextState))
      (local insert-state (InsertState))
      (states:add-state :text text-state)
      (states:add-state :insert insert-state)
      (states:set-state :text)
      (local original-set-state states.set-state)
      (set states.set-state
           (fn [_self name]
             (when (not (states:get-state name))
               (states:add-state name {}))
             (table.insert transitions name)
             (original-set-state states name)))
      (set-app-states! states)
      (let [(ok result)
            (pcall
              (fn []
                (InputState.connect-input input)
                (text-state.on-key-down {:key (string.byte "i")})
                (assert (= input.mode :insert))
                (assert (= (input:get-text) ""))
                (insert-state.on-text-input {:text "i"})
                (insert-state.on-text-input {:text "z"})
                (assert (= (input:get-text) "z"))
                (insert-state.on-key-down {:key 27})
                (assert (= input.mode :normal))
                (assert (= (. transitions 1) :insert))
                (assert (= (. transitions 2) :text))
                (text-state.on-key-down {:key (string.byte "l")})
                (assert (= input.cursor-index 0))))]
        (InputState.disconnect-input input)
        (set-app-states! original-states)
        (input:drop)
        (when (not ok)
          (error result))))))

(fn with-input-state-spy [body]
  (local original-connect InputState.connect-input)
  (local original-disconnect InputState.disconnect-input)
  (var connect-count 0)
  (var disconnect-count 0)
  (var last-input nil)
  (set InputState.connect-input
       (fn [input]
         (set connect-count (+ connect-count 1))
         (set last-input input)
         (original-connect input)))
  (set InputState.disconnect-input
       (fn [input]
         (set disconnect-count (+ disconnect-count 1))
         (when (= last-input input)
           (set last-input nil))
         (original-disconnect input)))
  (let [(ok result) (pcall body {:connect-count (fn [] connect-count)
                                  :disconnect-count (fn [] disconnect-count)
                                  :last-input (fn [] last-input)})]
    (set InputState.connect-input original-connect)
    (set InputState.disconnect-input original-disconnect)
    (when (not ok)
      (error result))
    result))

(fn input-focus-connects-to-input-state []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local original-states app.states)
      (local states (States))
      (states:add-state :normal {})
      (states:add-state :text {})
      (states:set-state :normal)
      (set-app-states! states)
      (with-input-state-spy
        (fn [spy]
          (local input ((Input {}) ctx-info.ctx))
          (assert (= (spy.connect-count) 0))
          (assert (= (spy.disconnect-count) 0))
          (input.focus-node:request-focus)
          (assert (= (spy.connect-count) 1))
          (assert (= (spy.last-input) input))
          (input:drop)
          (assert (= (spy.disconnect-count) 1))))
      (set-app-states! original-states))))

(fn input-double-drop-errors []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:name "diagnostic-input" :placeholder "Search" :text "RAW-SENTINEL-INPUT-TEXT"}) ctx-info.ctx))
      (input:drop)
      (local (ok err) (pcall (fn [] (input:drop))))
      (assert (not ok) "Dropping an input twice should error")
      (local message (tostring err))
      (assert (and (string.find message "Input dropped twice" 1 true) (string.find message "diagnostic-input" 1 true) (string.find message "created" 1 true) (string.find message "first drop" 1 true) (string.find message "second drop" 1 true) (not (string.find message "RAW-SENTINEL-INPUT-TEXT" 1 true))) (.. "double-drop diagnostic should include lifecycle context without raw text: " message)))))


(fn input-caret-switches-shape-with-mode []
      (with-pointer-stubs
        (fn [_stubs]
          (local ctx-info (make-focus-build-ctx _stubs))
          (local input ((Input {:text "A"}) ctx-info.ctx))
          (input:move-caret-to 0)
          (local measure-caret
                 (fn []
                   (input.layout:measurer)
                   (set input.layout.size input.layout.measure)
                   (input.layout:layouter)
                   input.caret.layout.size.x))
          (local font (and input.text input.text.style input.text.style.font))
          (local glyph (and font (fallback-glyph font (. input.codepoints (+ input.cursor-index 1)))))
          (assert font "Input caret test requires a font on the text style")
          (assert glyph "Input caret test requires a fallback glyph")
          (local expected-block (* glyph.advance input.text.style.scale))
          (assert (approx (measure-caret) expected-block))
          (input:enter-insert-mode)
          (assert (approx (measure-caret) input.caret-width))
          (input:drop))))

(fn input-single-line-stretched-content-centers-on-text-line []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:text "ABC"}) ctx-info.ctx))
      (input:enter-insert-mode)
      (input:move-caret-to 1)
      (input.layout:measurer)
      (set input.layout.size (glm.vec3 input.layout.measure.x (+ input.layout.measure.y 3) 0))
      (input.layout:layouter)
      (local inner-height (math.max 0 (- input.layout.size.y (* 2 input.padding.y))))
      (assert (> inner-height input.line-height)
              "Test requires a stretched single-line input")
      (local expected-y (+ input.layout.position.y
                           input.padding.y
                           (/ (- inner-height input.line-height) 2)))
      (assert (approx input.text.layout.position.y expected-y)
              "Stretched single-line input text should center inside extra height")
      (assert (approx input.caret.layout.size.y input.line-height)
              "Stretched single-line input caret should stay text-line height")
      (assert (approx input.caret.layout.position.y input.text.layout.position.y)
              "Stretched single-line input caret should share the text line origin")
      (input:drop))))

(fn input-auto-computes-visible-lines-and-columns []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :line-wrap? false}) ctx-info.ctx))
      (input.layout:measurer)
      (set input.layout.size (glm.vec3 12 6 0))
      (input.layout:layouter)
      (local padding input.padding)
      (local inner-height (math.max 0 (- input.layout.size.y (* 2 padding.y))))
      (local inner-width (math.max 0 (- input.layout.size.x (* 2 padding.x))))
      (local expected-lines
            (if (> input.line-height 0)
                (math.max input.min-lines
                          (math.min input.max-lines
                                    (math.max 1 (math.floor (/ inner-height input.line-height)))))
                input.min-lines))
      (local expected-columns
            (if (> input.column-width 0)
                (math.max input.min-columns
                          (math.min input.max-columns
                                    (math.max 1 (math.floor (/ inner-width input.column-width)))))
                input.min-columns))
      (assert (= input.visible-line-count expected-lines))
      (assert (= input.visible-column-count expected-columns))
      (input:drop))))

(fn input-scrolls-text-vertically-when-caret-moves []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true
                            :line-wrap? false
                            :line-count 2
                            :column-count 8}) ctx-info.ctx))
      (input:set-text "alpha\nbeta\ngamma")
      (input.layout:measurer)
      (set input.layout.size (glm.vec3 12 6 0))
      (input.layout:layouter)
      (input:move-caret-to (length input.codepoints))
      (input.layout:layouter)
      (assert (= input.visible-line-count 2))
      (assert (= input.scroll.line 1))
      (assert (= (string-from-text input.text) "beta\ngamma"))
      (input:drop))))

(fn input-scrolls-text-horizontally-when-exceeding-columns []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:column-count 4}) ctx-info.ctx))
      (input:set-text "ABCDEFGH")
      (input.layout:measurer)
      (set input.layout.size (glm.vec3 8 input.layout.measure.y 0))
      (input.layout:layouter)
      (input:move-caret-to (length input.codepoints))
      (input.layout:layouter)
      (assert (= input.visible-column-count 4))
      (assert (= input.scroll.column 4))
      (assert (= (string-from-text input.text) "EFGH"))
      (input:drop))))

(fn input-emits-submitted-on-ctrl-enter []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true}) ctx-info.ctx))
      (local text-state (TextState))
      (local original-states app.states)
      (own-test-state! :text text-state)
      (var submitted 0)
      (local listener
        (input.submitted:connect
          (fn [_payload]
            (set submitted (+ submitted 1)))))
      (InputState.connect-input input)
      (text-state.on-key-down {:key 13 :mod 64})
      (assert (= submitted 1))
      (InputState.disconnect-input input)
      (set-app-states! original-states)
      (input.submitted:disconnect listener true)
      (input:drop))))

(fn input-insert-state-ctrl-enter-submits-without-newline []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true}) ctx-info.ctx))
      (local insert-state (InsertState))
      (local original-states app.states)
      (own-test-state! :insert insert-state)
      (var submitted 0)
      (local listener
        (input.submitted:connect
          (fn [_payload]
            (set submitted (+ submitted 1)))))
      (input:set-text "line")
      (InputState.connect-input input)
      (insert-state.on-key-down {:key 13 :mod 64})
      (assert (= submitted 1))
      (assert (= (input:get-text) "line"))
      (InputState.disconnect-input input)
      (set-app-states! original-states)
      (input.submitted:disconnect listener true)
      (input:drop))))

(fn input-caret-move-only-dirties-caret-layout []
  (with-pointer-stubs
    (fn [stubs]
      (local ctx (BuildContext {:clickables stubs.clickables
                                :hoverables stubs.hoverables}))
      (local root (LayoutRoot))
      (local input ((Input {:text "abc" :column-count 5}) ctx))
      (input.layout:measurer)
      (set input.layout.size input.layout.measure)
      (input.layout:set-root root)
      (input.layout:mark-measure-dirty)
      (root:update)
      (input:move-caret-to 0)
      (root:update)
      (input:move-caret 1)
      (assert (= (queue-size root.measure-dirt) 0))
      (assert (. root.layout-dirt.lookup input.caret.layout))
      (assert (not (. root.layout-dirt.lookup input.layout)))
      (assert (not (. root.layout-dirt.lookup input.text.layout)))
      (assert (= (queue-size root.layout-dirt) 1))
      (root:update)
      (input:drop))))

(fn input-scroll-dirties-text-and-caret-layouts []
  (with-pointer-stubs
    (fn [stubs]
      (local ctx (BuildContext {:clickables stubs.clickables
                                :hoverables stubs.hoverables}))
      (local root (LayoutRoot))
      (local input ((Input {:text "ABCDEFGH" :column-count 4}) ctx))
      (input.layout:measurer)
      (set input.layout.size input.layout.measure)
      (input.layout:set-root root)
      (input.layout:mark-measure-dirty)
      (root:update)
      (input:move-caret-to 0)
      (root:update)
      (input:move-caret-to (length input.codepoints))
      (assert (= (queue-size root.measure-dirt) 0))
      (assert (. root.layout-dirt.lookup input.caret.layout))
      (assert (. root.layout-dirt.lookup input.text.layout))
      (assert (= (queue-size root.layout-dirt) 2))
      (root:update)
      (input:drop))))

(fn make-state-tracker []
  (local tracker {:current :normal
                  :transitions [:normal]})
  (local states (States))
  (local original-set states.set-state)
  (states:add-state :normal {:on-enter (fn []
                                         (table.insert tracker.transitions :normal)
                                         (set tracker.current :normal))})
  (states:add-state :text {:on-enter (fn []
                                       (table.insert tracker.transitions :text)
                                       (set tracker.current :text))})
  (states:add-state :insert {:on-enter (fn []
                                         (set tracker.current :insert))})
  (set states.set-state
       (fn [self-or-name maybe-name]
         (local name (if maybe-name maybe-name self-or-name))
         (when name
           (when (not (states:get-state name))
             (states:add-state name {}))
           (local result (original-set states name))
           (set tracker.current name)
           result)))
  {:states states
   :tracker tracker})

(fn input-blur-via-click-restores-normal-state []
  (with-pointer-stubs
    (fn [_stubs]
      (local state-info (make-state-tracker))
      (local state-tracker state-info.tracker)
      (local states state-info.states)
      (local original-states app.states)
      (var manager nil)
      (var input nil)
      (let [(ok result)
            (pcall
              (fn []
                (set-app-states! states)
                (InputState.release-active-input)
                (states:set-state :normal)
                (local ctx-info (make-focus-build-ctx _stubs))
                (set manager ctx-info.manager)
                (set input ((Input {}) ctx-info.ctx))
                (input:on-click {})
                (var text-index nil)
                (each [idx name (ipairs state-tracker.transitions)]
                  (when (and (not text-index) (= name :text))
                    (set text-index idx)))
                (assert text-index
                        (.. "Input should enter text state after click; transitions="
                            (table.concat state-tracker.transitions ",")
                            " current=" (tostring state-tracker.current)))
                (assert (= state-tracker.current :text))
                (manager:clear-focus)
                (var normal-index nil)
                (each [idx name (ipairs state-tracker.transitions)]
                  (when (and (> idx (or text-index 0)) (= name :normal) (not normal-index))
                    (set normal-index idx)))
                (assert normal-index
                        (.. "Input should return to normal after blur; transitions="
                            (table.concat state-tracker.transitions ",")
                            " current=" (tostring state-tracker.current)))
                (assert (= state-tracker.current :normal))
                (assert (not (InputState.active-input)))))]
        (when input
          (input:drop))
        (when manager
          (manager:drop))
        (set-app-states! original-states)
        (when (not ok)
          (error result))))))

(fn input-blur-returns-to-normal-state []
  (with-pointer-stubs
    (fn [_stubs]
      (local state-info (make-state-tracker))
      (local state-tracker state-info.tracker)
      (local states state-info.states)
      (local original-states app.states)
      (var manager nil)
      (var input nil)
      (let [(ok result)
            (pcall
              (fn []
                (set-app-states! states)
                (InputState.release-active-input)
                (states:set-state :normal)
                (local ctx-info (make-focus-build-ctx _stubs))
                (set manager ctx-info.manager)
                (set input ((Input {}) ctx-info.ctx))
                (input.focus-node:request-focus)
                (manager:clear-focus)
                (var text-index nil)
                (var normal-index nil)
                (each [idx name (ipairs state-tracker.transitions)]
                  (when (and (not text-index) (= name :text))
                    (set text-index idx))
                  (when (and text-index (> idx text-index) (= name :normal) (not normal-index))
                    (set normal-index idx)))
                (assert text-index
                        (.. "Focused input should enter text state; transitions="
                            (table.concat state-tracker.transitions ",")
                            " current=" (tostring state-tracker.current)))
                (assert normal-index
                        (.. "Focused input blur should return to normal state; transitions="
                            (table.concat state-tracker.transitions ",")
                            " current=" (tostring state-tracker.current)))
                (assert (= state-tracker.current :normal))
                (assert (not (InputState.active-input)))))]
        (when input
          (input:drop))
        (when manager
          (manager:drop))
        (set-app-states! original-states)
        (when (not ok)
          (error result))))))

(fn input-line-wrap-defaults-on-for-multiline []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local multiline ((Input {:multiline? true}) ctx-info.ctx))
      (assert (= multiline.line-wrap? true)
              "Multiline input should enable line-wrap by default")
      (multiline:drop)
      (local single-line ((Input {}) ctx-info.ctx))
      (assert (= single-line.line-wrap? false)
              "Single-line input should disable line-wrap by default")
      (single-line:drop))))

(fn input-line-wrap-explicit-opt-out []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :line-wrap? false}) ctx-info.ctx))
      (assert (= input.line-wrap? false)
              "Explicit :line-wrap? false should disable wrapping")
      (input:drop))))

(fn input-line-wrap-horizontal-scroll-errors []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true}) ctx-info.ctx))
      (input.layout:measurer)
      (set input.layout.size input.layout.measure)
      (input.layout:layouter)
      (local (ok err) (pcall (fn [] (input:scroll-columns 1))))
      (assert (not ok) "scroll-columns should error when line-wrap is enabled")
      (assert (string.find (tostring err) "not available") "error message should mention line-wrap")
      (input:drop))))

(fn input-line-wrap-set-scroll-position-errors []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true}) ctx-info.ctx))
      (input.layout:measurer)
      (set input.layout.size input.layout.measure)
      (input.layout:layouter)
      (local (ok err) (pcall (fn [] (input:set-scroll-position {:line 0 :column 1}))))
      (assert (not ok) "set-scroll-position with column should error when line-wrap is enabled")
      (assert (string.find (tostring err) "horizontal") "error message should mention horizontal")
      ;; Setting scroll line without column should still work
      (local moved (input:set-scroll-position {:line 0 :column 0}))
      (assert (= moved false) "setting to same position reports no change")
      (input:drop))))

(fn input-line-wrap-produces-soft-newlines []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 5}) ctx-info.ctx))
      (input:set-text "ABCDEFGHIJ")
      (input.layout:measurer)
      (local narrow-w (math.max 1 (* 4 (or input.column-width 0.5))))
      (set input.layout.size (glm.vec3 narrow-w 10 0))
      (input.layout:layouter)
      (local text-codepoints (input.text:get-codepoints))
      (local newline-cp 10)
      (var newline-count 0)
      (each [_ cp (ipairs text-codepoints)]
        (when (= cp newline-cp)
          (set newline-count (+ newline-count 1))))
      (assert (> newline-count 0)
              (.. "Wrapped text should contain soft newlines, got " (tostring newline-count) " from width=" (tostring narrow-w)))
      (input:drop))))

(fn input-line-wrap-content-preserved []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 5}) ctx-info.ctx))
      (input:set-text "ABCDEFG")
      (input.layout:measurer)
      (local narrow-w (math.max 1 (* 4 (or input.column-width 0.5))))
      (set input.layout.size (glm.vec3 narrow-w 10 0))
      (input.layout:layouter)
      (local text-codepoints (input.text:get-codepoints))
      (local newline-cp 10)
      (var chars [])
      (each [_ cp (ipairs text-codepoints)]
        (when (not (= cp newline-cp))
          (table.insert chars cp)))
      (assert (= (length chars) 7) "All original characters preserved")
      (var ok true)
      (for [i 1 7]
        (local expected (string.byte (string.sub "ABCDEFG" i i)))
        (local actual (. chars i))
        (when (not (= actual expected))
          (set ok false)))
      (assert ok "Characters should match original text")
      (input:drop))))

(fn input-line-wrap-logical-caret-stable []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 5}) ctx-info.ctx))
      (input:set-text "ABCDEFGH")
      (input:move-caret-to 6)
      (input.layout:measurer)
      (set input.layout.size input.layout.measure)
      (input.layout:layouter)
      (assert (= input.model.cursor-line 0)
              "Cursor logical line should be 0 (same line)")
      (assert (= input.model.cursor-column 6)
              "Cursor logical column should be 6 (unchanged by wrapping)")
      (assert (= input.cursor-line 0))
      (assert (= input.cursor-column 6))
      (input:drop))))

(fn input-line-wrap-caret-visual-y-offset []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 5}) ctx-info.ctx))
      (input:set-text "ABCDEFGHIJKLMNO")
      (input:move-caret-to 0)
      (input.layout:measurer)
      (local narrow-w (math.max 1 (* 5 (or input.column-width 0.5))))
      (set input.layout.size (glm.vec3 narrow-w 10 0))
      (input.layout:layouter)
      (local y0 input.caret.layout.position.y)
      (input:move-caret-to 10)
      (input.layout:layouter)
      (local y10 input.caret.layout.position.y)
      (assert (and input.line-height (> input.line-height 0))
              "test requires valid line-height")
      (assert (> (math.abs (- y10 y0)) (* input.line-height 0.5))
              (.. "Caret at pos 10 should be on different visual row; y0=" (tostring y0) " y10=" (tostring y10)))
      (input:drop))))

(fn input-line-wrap-empty-text-no-crash []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true}) ctx-info.ctx))
      (input.layout:measurer)
      (set input.layout.size input.layout.measure)
      (let [(ok result) (pcall (fn [] (input.layout:layouter)))]
        (assert ok (.. "Empty text with line-wrap should not crash: " (tostring result))))
      (input:drop))))

(fn input-line-wrap-single-line-disabled []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:column-count 5}) ctx-info.ctx))
      (assert (= input.line-wrap? false)
              "Single-line input should have line-wrap disabled by default")
      (input:set-text "ABCDEFGH")
      (input.layout:measurer)
      (set input.layout.size input.layout.measure)
      (input.layout:layouter)
      (local text-codepoints (input.text:get-codepoints))
      (local newline-cp 10)
      (var newline-count 0)
      (each [_ cp (ipairs text-codepoints)]
        (when (= cp newline-cp)
          (set newline-count (+ newline-count 1))))
      (assert (= newline-count 0)
              "Single-line input should not have soft newlines even with long text")
      (input:drop))))

(fn input-line-wrap-scroll-lines-still-works []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true}) ctx-info.ctx))
      (input:set-text "a\nb\nc\nd\ne")
      (input:move-caret-to 0)
      (input.layout:measurer)
      (set input.layout.size (glm.vec3 10 (* 2 (or input.line-height 1)) 0))
      (input.layout:layouter)
      (local scroll-before input.scroll.line)
      (local moved (input:scroll-lines 1))
      (assert moved "scroll-lines should work in wrapped mode")
      (assert (> input.scroll.line scroll-before)
              (.. "Scroll should advance in wrapped mode; before=" (tostring scroll-before) " after=" (tostring input.scroll.line)))
      (input:drop))))

(fn input-line-wrap-scroll-lines-in-single-long-line []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 10}) ctx-info.ctx))
      (input:set-text "AAAAAAAAAABBBBBBBBBBCCCCCCCCCC")
      (input:move-caret-to 0)
      (input.layout:measurer)
      (local narrow-w (math.max 1 (* 5 (or input.column-width 0.5))))
      (set input.layout.size (glm.vec3 narrow-w (* 3 (or input.line-height 1)) 0))
      (input.layout:layouter)
      (local scroll-before input.scroll.line)
      ;; Visual rows should exist for the single wrapped line
      (assert (> (length input.visual-rows) 1)
              (.. "Single long line should produce multiple visual rows, got " (tostring (length input.visual-rows))))
      ;; Scroll by one visual row
      (local moved (input:scroll-lines 1))
      (assert moved "scroll-lines should move within a single wrapped line")
      (assert (> input.scroll.line scroll-before)
              (.. "Scroll should advance within wrapped line; before=" (tostring scroll-before) " after=" (tostring input.scroll.line)))
      (input:drop))))

(fn input-line-wrap-resize-repositions-caret []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 10}) ctx-info.ctx))
      (input:set-text "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
      (input:move-caret-to 25)
      (input.layout:measurer)
      (local wide-w 50)
      (set input.layout.size (glm.vec3 wide-w 10 0))
      (input.layout:layouter)
      (local scroll-before input.scroll.line)
      ;; Narrow the width — caret should stay visible after resize
      (local narrow-w (math.max 1 (* 3 (or input.column-width 0.5))))
      (set input.layout.size (glm.vec3 narrow-w 10 0))
      (input.layout:layouter)
      ;; Compute caret visual row inline from input.visual-rows and model state
      (var caret-vr 0)
      (local cursor-line input.model.cursor-line)
      (local cursor-column input.model.cursor-column)
      (each [i vr (ipairs input.visual-rows)]
        (when (= vr.line-index cursor-line)
          (if (>= cursor-column vr.end-col)
              (set caret-vr (- i 1))
              (when (and (>= cursor-column vr.start-col) (< cursor-column vr.end-col))
                (set caret-vr (- i 1))))))
      (local viewport-lines (math.max 1 input.visible-line-count))
      (assert (>= caret-vr input.scroll.line)
              (.. "Caret visual row " (tostring caret-vr) " should be >= scroll " (tostring input.scroll.line)))
      (assert (< caret-vr (+ input.scroll.line viewport-lines))
              (.. "Caret visual row " (tostring caret-vr) " should be visible"))
      (input:drop))))

(fn input-line-wrap-set-scroll-position-values []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 10}) ctx-info.ctx))
      (input:set-text "AAA\nBBB\nCCC\nDDD\nEEE\nFFF")
      (input:move-caret-to 0)
      (input.layout:measurer)
      (set input.layout.size (glm.vec3 15 (* 2 (or input.line-height 1)) 0))
      (input.layout:layouter)
      ;; set-scroll-position with :line in wrapped mode means visual row
      (local moved (input:set-scroll-position {:line 1 :column 0}))
      (assert moved "set-scroll-position should move scroll in wrapped mode")
      (assert (= input.scroll.line 1)
              (.. "scroll.line should be set to 1, got " (tostring input.scroll.line)))
      ;; Setting to same position returns false
      (local same (input:set-scroll-position {:line 1 :column 0}))
      (assert (= same false) "Setting to same position should return false")
      ;; Setting beyond max should clamp and move
      (local big (input:set-scroll-position {:line 999 :column 0}))
      (assert big "Setting beyond max should still return true (clamped)")
      (assert (< input.scroll.line 999)
              "Scroll should be clamped, not set to 999")
      (input:drop))))

(fn input-line-wrap-single-line-with-wrap-errors []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local (ok err) (pcall (fn [] ((Input {:line-wrap? true}) ctx-info.ctx))))
      (assert (not ok) "Single-line input with :line-wrap? true should error")
      (assert (string.find (tostring err) "multiline")
              "Error message should mention multiline"))))

(fn input-line-wrap-multiple-logical-lines []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 10}) ctx-info.ctx))
      (input:set-text "AAA\nBBBBBBBBB\nCC")
      (input.layout:measurer)
      (local narrow-w (math.max 1 (* 4 (or input.column-width 0.5))))
      (set input.layout.size (glm.vec3 narrow-w 10 0))
      (input.layout:layouter)
      ;; Visual rows should exist for all three logical lines
      (assert (> (length input.visual-rows) 2)
              (.. "Should have visual rows for multiple logical lines, got " (tostring (length input.visual-rows))))
      ;; First visual row of line 1 should be after line 0's visual rows
      (var line0-rows 0)
      (var line1-start -1)
      (each [i vr (ipairs input.visual-rows)]
        (when (= vr.line-index 0)  ;; using 0-based from ensure-visual-rows
          (set line0-rows (+ line0-rows 1)))
        (when (and (= vr.line-index 1) (= line1-start -1))
          (set line1-start (- i 1))))
      (assert (>= line1-start line0-rows)
              "First visual row of logical line 1 should come after line 0 visual rows")
      (input:drop))))

(fn input-line-wrap-edit-after-layout []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 10}) ctx-info.ctx))
      (input:set-text "short")
      (input:move-caret-to 0)
      (input.layout:measurer)
      (local narrow-w (math.max 1 (* 4 (or input.column-width 0.5))))
      (set input.layout.size (glm.vec3 narrow-w 10 0))
      (input.layout:layouter)
      (local rows-before (length input.visual-rows))
      ;; Replace with long text that wraps
      (input:set-text "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
      (input.layout:layouter)
      (local rows-after (length input.visual-rows))
      (assert (> rows-after rows-before)
              (.. "Longer text should produce more visual rows; before=" (tostring rows-before) " after=" (tostring rows-after)))
      (input:drop))))

(fn input-line-wrap-caret-visible-after-edit []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 5}) ctx-info.ctx))
      (input:set-text "AAAAA")
      (input:move-caret-to 5)
      (input.layout:measurer)
      (local narrow-w (math.max 1 (* 3 (or input.column-width 0.5))))
      (set input.layout.size (glm.vec3 narrow-w 10 0))
      (input.layout:layouter)
      ;; Append more text — caret at end of long line, should stay visible
      (input:insert-text "BBBBBCCCCCDDDDDEEEEE")
      (input.layout:layouter)
      ;; Caret y should be within or very close to the text vertical range
      (local caret-y input.caret.layout.position.y)
      (local text-y input.text.layout.position.y)
      (local text-h (or input.text.layout.measure.y input.text.layout.size.y 0))
      (local text-bottom (- text-y text-h))
      (assert (>= caret-y (- text-bottom 0.01))
              (.. "Caret y=" (tostring caret-y) " should be near text bottom=" (tostring text-bottom)))
      (assert (<= caret-y (+ text-y 0.01))
              (.. "Caret y=" (tostring caret-y) " should be near text top=" (tostring text-y)))
      (input:drop))))

(fn input-line-wrap-resize-updates-rows []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 10}) ctx-info.ctx))
      (input:set-text "ABCDEFGHIJKLMNO")
      (input.layout:measurer)
      (local wide-w 30)
      (set input.layout.size (glm.vec3 wide-w 10 0))
      (input.layout:layouter)
      (local rows-wide (length input.visual-rows))
      ;; Narrow the width significantly — wrapping should increase
      (local narrow-w (math.max 1 (* 2 (or input.column-width 0.5))))
      (set input.layout.size (glm.vec3 narrow-w 10 0))
      (input.layout:layouter)
      (local rows-narrow (length input.visual-rows))
      (assert (> rows-narrow rows-wide)
              (.. "Narrower width should increase visual rows; wide=" (tostring rows-wide) " narrow=" (tostring rows-narrow)))
      (input:drop))))

(fn input-line-wrap-prefers-min-width []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :min-columns 8}) ctx-info.ctx))
      (input:set-text "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
      (input.layout:measurer)
      ;; Preferred width should be based on min-columns, not unwrapped text
      (local min-expected (* input.column-width 8))
      (local inner-width (- input.layout.measure.x (* 2 input.padding.x)))
      (assert (< inner-width (* input.column-width 26))
              (.. "Wrapped input preferred width should not grow to full text; inner=" (tostring inner-width) " min-expected~" (tostring min-expected)))
      (input:drop))))

(fn input-line-wrap-cursor-at-end-of-line-visible []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 5}) ctx-info.ctx))
      (input:set-text "ABCDEFGHIJKLMNO")
      (input:move-caret-to 15)
      (input.layout:measurer)
      (local narrow-w (math.max 1 (* 3 (or input.column-width 0.5))))
      (set input.layout.size (glm.vec3 narrow-w 10 0))
      (input.layout:layouter)
      ;; Cursor at end of line (col 15) should map to the last visual row of logical line 0
      (var last-for-line0 -1)
      (each [i vr (ipairs input.visual-rows)]
        (when (= vr.line-index 0)
          (set last-for-line0 (- i 1))))
      (assert (>= last-for-line0 0)
              "Should have visual rows for logical line 0")
      ;; The cursor at end of line should be on the last visual row; scroll should make it visible
      (local scroll input.scroll.line)
      (local viewport-lines (math.max 1 input.visible-line-count))
      (assert (>= last-for-line0 scroll)
              (.. "Last visual row " (tostring last-for-line0) " should be >= scroll " (tostring scroll)))
      (assert (< last-for-line0 (+ scroll viewport-lines))
              (.. "Last visual row " (tostring last-for-line0) " should be visible (scroll=" (tostring scroll) " viewport=" (tostring viewport-lines) ")"))
      (input:drop))))

(fn input-line-wrap-constrained-measure-height []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true}) ctx-info.ctx))
      (input:set-text "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
      (input.layout:measurer)
      (local unconstrained-height input.layout.measure.y)
      ;; Narrow constraint should produce taller measurement
      (input.layout:measure-constrained {:max (glm.vec3 3 100 0)})
      (local narrow-height input.layout.measure.y)
      (assert (> narrow-height unconstrained-height)
              (.. "Narrow constrained should be taller; unconstrained=" (tostring unconstrained-height) " narrow=" (tostring narrow-height)))
      ;; Wider constraint should produce shorter measurement than narrow
      (input.layout:measure-constrained {:max (glm.vec3 30 100 0)})
      (local wide-height input.layout.measure.y)
      (assert (< wide-height narrow-height)
              (.. "Wide constrained should be shorter than narrow; narrow=" (tostring narrow-height) " wide=" (tostring wide-height)))
      (input:drop))))

(fn input-line-wrap-caret-offscreen-after-manual-scroll []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :column-count 10}) ctx-info.ctx))
      (input:set-text "line0\nline1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9")
      (input:move-caret-to 0)
      (input.layout:measurer)
      (set input.layout.size (glm.vec3 15 (* 3 (or input.line-height 1)) 0))
      (input.layout:layouter)
      ;; Scroll to the bottom so caret at top is above the viewport
      (input:set-scroll-position {:line 99 :column 0})
      (input.layout:layouter)
      (local caret-y input.caret.layout.position.y)
      (local text-y input.text.layout.position.y)
      ;; Caret at row 0 should be drawn above the visible text position
      (assert (> caret-y text-y)
              (.. "Caret should be drawn above viewport when scrolled past it; caret-y=" (tostring caret-y) " text-y=" (tostring text-y)))
      (input:drop))))

(fn input-line-wrap-constrained-measure-max-lines []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :max-lines 3}) ctx-info.ctx))
      (input:set-text "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
      ;; Constrained narrow measurement should be capped by max-lines
      (input.layout:measure-constrained {:max (glm.vec3 3 100 0)})
      (local capped-height input.layout.measure.y)
      (local max-line-height (* input.max-lines (math.max 0.01 input.line-height)))
      (assert (<= capped-height (+ max-line-height (* 2 input.padding.y) 0.5))
              (.. "Constrained measurement should respect max-lines; capped-height=" (tostring capped-height) " max=" (tostring max-line-height) " padding=" (tostring (* 2 input.padding.y))))
      (input:drop))))

(fn input-line-wrap-constrained-measure-scroll-independent []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true}) ctx-info.ctx))
      (input:set-text "line0\nline1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9")
      ;; Lay out with narrow width and scroll halfway down
      (input.layout:measurer)
      (set input.layout.size (glm.vec3 15 (* 4 (or input.line-height 1)) 0))
      (input.layout:layouter)
      (input:set-scroll-position {:line 3 :column 0})
      (input.layout:layouter)
      (assert (> input.scroll.line 0) "scroll should be > 0 for meaningful test")
      ;; Measure constrained — height should reflect full content, not just from scroll
      (input.layout:measure-constrained {:max (glm.vec3 3 100 0)})
      (local scroll-independent-height input.layout.measure.y)
      ;; Now reset scroll and measure again — should be same height
      (input:set-scroll-position {:line 0 :column 0})
      (input.layout:layouter)
      (input.layout:measure-constrained {:max (glm.vec3 3 100 0)})
      (local scroll-zero-height input.layout.measure.y)
      (assert (< (math.abs (- scroll-independent-height scroll-zero-height)) 0.01)
              (.. "Constrained measurement should not depend on scroll position; scrolled=" (tostring scroll-independent-height) " top=" (tostring scroll-zero-height)))
      (input:drop))))

(fn input-line-wrap-layout-fits-constrained-measure []
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      (local input ((Input {:multiline? true :min-columns 2}) ctx-info.ctx))
      (input:set-text "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
      ;; Measure constrained narrow, lay out at reported size, verify no cliff
      (input.layout:measure-constrained {:max (glm.vec3 8 100 0)})
      (local measured input.layout.measure)
      (assert (> measured.x 0) "Measured width should be positive")
      (assert (> measured.y 0) "Measured height should be positive")
      (set input.layout.size measured)
      (input.layout:layouter)
      (local visual-rows input.visual-rows)
      (local viewport-lines (math.max 1 input.visible-line-count))
      (assert (>= viewport-lines (length visual-rows))
              (.. "Viewport " (tostring viewport-lines) " should fit all " (tostring (length visual-rows)) " visual rows after layout at measured size"))
      (input:drop))))

(fn input-line-wrap-zero-width-still-wraps []
  "Constrained measurement with max.x <= 2*padding must still produce wrapping rows."
  (with-pointer-stubs
    (fn [_stubs]
      (local ctx-info (make-focus-build-ctx _stubs))
      ;; Neutralize min-height and min-lines so height comes purely from wrapping
      (local input ((Input {:multiline? true
                            :min-height 0
                            :min-lines 1}) ctx-info.ctx))
      (input:set-text "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
      ;; max.x = 0.5 with default padding 0.35 gives constrained-inner-width = 0
      ;; wrap-width fallback of 0.001 ensures wrapping still occurs (~1 char per row)
      (input.layout:measure-constrained {:max (glm.vec3 0.5 100 0)})
      ;; Inner height should be at least 26 * line-height (one row per character)
      (local inner-height (- input.layout.measure.y (* 2 input.padding.y)))
      (local expected-min (* 26 input.line-height))
      (assert (> inner-height (* 0.5 expected-min))
              (.. "Zero-width constraint should wrap; inner-height=" (tostring inner-height)
                  " expected-min~" (tostring expected-min)))
      (input:drop))))

(table.insert tests {:name "Input line-wrap single-line with wrap errors" :fn input-line-wrap-single-line-with-wrap-errors})
(table.insert tests {:name "Input line-wrap handles multiple logical lines" :fn input-line-wrap-multiple-logical-lines})
(table.insert tests {:name "Input line-wrap updates visual rows after text edit" :fn input-line-wrap-edit-after-layout})
(table.insert tests {:name "Input line-wrap caret stays visible after edit" :fn input-line-wrap-caret-visible-after-edit})
(table.insert tests {:name "Input line-wrap rebuilds rows on resize" :fn input-line-wrap-resize-updates-rows})
(table.insert tests {:name "Input line-wrap prefers min-width over unwrapped text" :fn input-line-wrap-prefers-min-width})
(table.insert tests {:name "Input line-wrap cursor at end of line maps to last visual row" :fn input-line-wrap-cursor-at-end-of-line-visible})
(table.insert tests {:name "Input line-wrap constrained measure grows height when narrow" :fn input-line-wrap-constrained-measure-height})
(table.insert tests {:name "Input line-wrap layout fits constrained measured size" :fn input-line-wrap-layout-fits-constrained-measure})
(table.insert tests {:name "Input line-wrap zero-width constraint still wraps" :fn input-line-wrap-zero-width-still-wraps})
(table.insert tests {:name "Input line-wrap constrained measure respects max-lines" :fn input-line-wrap-constrained-measure-max-lines})
(table.insert tests {:name "Input line-wrap constrained measure is scroll-independent" :fn input-line-wrap-constrained-measure-scroll-independent})
(table.insert tests {:name "Input line-wrap caret drawn offscreen after manual scroll past" :fn input-line-wrap-caret-offscreen-after-manual-scroll})

(table.insert tests {:name "Input wraps lines by default for multiline inputs" :fn input-line-wrap-defaults-on-for-multiline})
(table.insert tests {:name "Input line-wrap can be explicitly disabled" :fn input-line-wrap-explicit-opt-out})
(table.insert tests {:name "Input line-wrap horizontal scroll errors" :fn input-line-wrap-horizontal-scroll-errors})
(table.insert tests {:name "Input line-wrap set-scroll-position column errors" :fn input-line-wrap-set-scroll-position-errors})
(table.insert tests {:name "Input line-wrap produces soft newlines in visible text" :fn input-line-wrap-produces-soft-newlines})
(table.insert tests {:name "Input line-wrap preserves all content characters" :fn input-line-wrap-content-preserved})
(table.insert tests {:name "Input line-wrap keeps logical caret coordinates stable" :fn input-line-wrap-logical-caret-stable})
(table.insert tests {:name "Input line-wrap caret moves to lower visual row on long line" :fn input-line-wrap-caret-visual-y-offset})
(table.insert tests {:name "Input line-wrap empty text does not crash" :fn input-line-wrap-empty-text-no-crash})
(table.insert tests {:name "Input single-line line-wrap disabled by default" :fn input-line-wrap-single-line-disabled})
(table.insert tests {:name "Input line-wrap scroll-lines still works" :fn input-line-wrap-scroll-lines-still-works})
(table.insert tests {:name "Input line-wrap scroll-lines works within a single wrapped line" :fn input-line-wrap-scroll-lines-in-single-long-line})
(table.insert tests {:name "Input line-wrap resize repositions caret into view" :fn input-line-wrap-resize-repositions-caret})
(table.insert tests {:name "Input line-wrap set-scroll-position uses visual row line" :fn input-line-wrap-set-scroll-position-values})

(table.insert tests {:name "Input hides placeholder after text entry" :fn input-placeholder-updates})
(table.insert tests {:name "Input context menu default actions" :fn input-context-menu-default-actions})
(table.insert tests {:name "Input context menu custom actions" :fn input-context-menu-custom-actions})
(table.insert tests {:name "Input context menu extend actions" :fn input-context-menu-extend-actions})
(table.insert tests {:name "Input context menu resolves late menu manager"
                     :fn input-context-menu-resolves-late-menu-manager})
(table.insert tests {:name "Input registers for double click" :fn input-registers-double-click})
(table.insert tests {:name "Text and insert states edit input text" :fn input-text-and-insert-states-edit-text})
(table.insert tests {:name "Focused input connects through input state" :fn input-focus-connects-to-input-state})
(table.insert tests {:name "Input double drop errors" :fn input-double-drop-errors})
(table.insert tests {:name "Input blur via click restores normal state" :fn input-blur-via-click-restores-normal-state})
(table.insert tests {:name "Input blur returns to normal state" :fn input-blur-returns-to-normal-state})
(table.insert tests {:name "Input caret switches between block and bar by mode" :fn input-caret-switches-shape-with-mode})
(table.insert tests {:name "Input single-line stretched content centers on text line"
                     :fn input-single-line-stretched-content-centers-on-text-line})
(table.insert tests {:name "Input auto computes visible lines and columns" :fn input-auto-computes-visible-lines-and-columns})
(table.insert tests {:name "Input scrolls vertically to keep caret visible" :fn input-scrolls-text-vertically-when-caret-moves})
(table.insert tests {:name "Input scrolls horizontally when exceeding columns" :fn input-scrolls-text-horizontally-when-exceeding-columns})
(table.insert tests {:name "Input emits submitted signal on ctrl enter" :fn input-emits-submitted-on-ctrl-enter})
(table.insert tests {:name "Insert state ctrl enter submits without newline" :fn input-insert-state-ctrl-enter-submits-without-newline})
(table.insert tests {:name "Input caret move dirties only caret layout" :fn input-caret-move-only-dirties-caret-layout})
(table.insert tests {:name "Input scroll dirties caret and text layouts" :fn input-scroll-dirties-text-and-caret-layouts})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "input"
                       :tests tests})))

{:name "input"
 :tests tests
 :main main}
