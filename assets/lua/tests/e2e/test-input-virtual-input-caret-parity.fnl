(local Harness (require :tests.e2e.harness))
(local fs (require :fs))
(local glm (require :glm))
(local Text (require :text))
(local TextStyle (require :text-style))
(local Input (require :input))
(local InputState (require :input-state-router))
(local VirtualInput (require :virtual-input))
(local LazyTextSource (require :lazy-text-source))
(local LazyTextBuffer (require :lazy-text-buffer))
(local Sized (require :sized))
(local {: Flex : FlexChild} (require :flex))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "e2e-input-virtual-input-caret-parity"))

(fn approx [a b tolerance]
  (local resolved-tolerance (if (= tolerance nil) 0.001 tolerance))
  (<= (math.abs (- a b)) resolved-tolerance))

(fn line-codepoint-count [entry]
  (if (and entry entry.codepoints)
      (length entry.codepoints)
      0))

(fn line-newline-length [entry]
  (if (and entry entry.newline-length)
      entry.newline-length
      0))

(fn cursor-index-for-line-col [model line col]
  (local lines (assert model.lines "cursor-index-for-line-col requires model lines"))
  (var index 0)
  (var i 0)
  (while (< i line)
    (local entry (. lines (+ i 1)))
    (local line-len (line-codepoint-count entry))
    (local newline-len (line-newline-length entry))
    (set index (+ index line-len newline-len))
    (set i (+ i 1)))
  (local entry (. lines (+ line 1)))
  (local line-len (line-codepoint-count entry))
  (local clamped-col (math.max 0 (math.min col line-len)))
  (+ index clamped-col))

(fn codepoint-at [input line col]
  (local rows (assert input.lines "codepoint-at requires input lines"))
  (local row (. rows (+ line 1)))
  (and row row.codepoints (. row.codepoints (+ col 1))))

(fn caret-local [input]
  {:x (- input.caret.layout.position.x input.layout.position.x)
   :y (- input.caret.layout.position.y input.layout.position.y)})

(fn active-key-down [payload]
  (local state (assert (app.states:active-state) "routed caret parity requires active app state"))
  (assert state.on-key-down "routed caret parity active state requires on-key-down")
  (state:on-key-down payload))

(fn active-text-input [payload]
  (local state (assert (app.states:active-state) "routed caret parity requires active app state"))
  (assert state.on-text-input "routed caret parity active state requires on-text-input")
  (state:on-text-input payload))

(fn color-components [color]
  (assert color "color-components requires color")
  [color.x color.y color.z color.w])

(fn assert-color-parity [scenario eager virtual]
  (local eager-color (color-components eager.caret.color))
  (local virtual-color (color-components virtual.caret.color))
  (each [i expected (ipairs eager-color)]
    (local actual (. virtual-color i))
    (assert (approx actual expected 0.001)
            (.. scenario " caret color component " i " mismatch: input=" (tostring expected)
                " virtual=" (tostring actual)))))

(fn assert-caret-parity [scenario eager virtual expected-mode]
  (assert eager.caret.visible? (.. scenario " Input caret should be visible"))
  (assert virtual.caret.visible? (.. scenario " VirtualInput caret should be visible"))
  (assert (= eager.mode expected-mode)
          (.. scenario " Input mode mismatch: " (tostring eager.mode)))
  (assert (= virtual.mode expected-mode)
          (.. scenario " VirtualInput mode mismatch: " (tostring virtual.mode)))
  (assert (= eager.mode virtual.mode) (.. scenario " caret mode parity mismatch"))
  (assert (= eager.cursor-line virtual.cursor-line)
          (.. scenario " cursor line mismatch: input=" eager.cursor-line
              " virtual=" virtual.cursor-line))
  (assert (= eager.cursor-column virtual.cursor-column)
          (.. scenario " cursor column mismatch: input=" eager.cursor-column
              " virtual=" virtual.cursor-column))
  (if (= expected-mode :insert)
      (do
        (assert (approx eager.caret.layout.size.x eager.caret-width 0.001)
                (.. scenario " Input insert caret should be thin"))
        (assert (approx virtual.caret.layout.size.x virtual.caret-width 0.001)
                (.. scenario " VirtualInput insert caret should be thin")))
      (do
        (local cp (codepoint-at eager eager.cursor-line eager.cursor-column))
        (assert cp (.. scenario " normal block caret requires a visible current codepoint"))
        (assert (> eager.caret.layout.size.x eager.caret-width)
                (.. scenario " Input normal caret should be block width"))
        (assert (> virtual.caret.layout.size.x virtual.caret-width)
                (.. scenario " VirtualInput normal caret should be block width"))))
  (assert (approx eager.caret.layout.size.x virtual.caret.layout.size.x 0.001)
          (.. scenario " caret width mismatch: input=" eager.caret.layout.size.x
              " virtual=" virtual.caret.layout.size.x))
  (local eager-local (caret-local eager))
  (local virtual-local (caret-local virtual))
  (assert (approx eager-local.x virtual-local.x 0.01)
          (.. scenario " caret local x mismatch: input=" eager-local.x
              " virtual=" virtual-local.x
              " input-scroll=" (tostring (and eager.scroll eager.scroll.column))
              " virtual-scroll=" (tostring virtual.scroll-column)))
  (assert (approx eager-local.y virtual-local.y 0.01)
          (.. scenario " caret local y mismatch: input=" eager-local.y
              " virtual=" virtual-local.y))
  (assert-color-parity scenario eager virtual))

(fn assert-caret-in-padded-bounds [scenario input]
  (local local-pos (caret-local input))
  (local max-x (- input.layout.size.x input.padding.x))
  (local max-y (- input.layout.size.y input.padding.y))
  (assert (>= local-pos.x input.padding.x)
          (.. scenario " caret x should be inside padded content: " local-pos.x))
  (assert (<= local-pos.x max-x)
          (.. scenario " caret x should be before right padding: " local-pos.x " max=" max-x))
  (assert (>= local-pos.y input.padding.y)
          (.. scenario " caret y should be inside padded content: " local-pos.y))
  (assert (<= local-pos.y max-y)
          (.. scenario " caret y should be before top padding: " local-pos.y " max=" max-y)))

(fn assert-horizontal-scroll [state]
  (local input-scroll (assert state.input.scroll "hscroll requires Input scroll state"))
  (assert (> input-scroll.column 0)
          (.. "Input should be horizontally scrolled before hscroll snapshot; got " input-scroll.column))
  (assert (> state.virtual.scroll-column 0)
          (.. "VirtualInput should be horizontally scrolled before hscroll snapshot; got " state.virtual.scroll-column))
  (assert-caret-in-padded-bounds "hscroll Input" state.input)
  (assert-caret-in-padded-bounds "hscroll VirtualInput" state.virtual))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "caret-parity-" (os.time) "-" temp-counter)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn make-buffer [dir content]
  (local path (fs.join-path dir "virtual-input-caret-parity.txt"))
  (fs.write-file path content)
  (LazyTextBuffer {:source (LazyTextSource.file path {:chunk-bytes 9})}))

(fn install-state-hud! [ctx]
  (local hud-target (Harness.make-hud-target {:width ctx.width
                                              :height ctx.height}))
  (app.states:set-hud-provider (fn [_states] hud-target))
  (app.states:set-focus-manager-provider (fn [_states] hud-target.focus-manager))
  hud-target)

(fn make-parity-column [label child-builder label-style size]
  (Flex {:axis :y
         :yspacing 0.25
         :xalign :start
         :children [(FlexChild (Text {:text label :style label-style}) 0)
                    (FlexChild (Sized {:size size
                                        :child child-builder}) 0)]}))

(fn make-title-child-builder [state]
  (fn [_ctx]
    state.title))

(fn make-input-child-builder [state]
  (fn [child-ctx]
    (set state.input ((Input state.input-opts) child-ctx))
    state.input))

(fn make-virtual-child-builder [state]
  (fn [child-ctx]
    (set state.virtual ((VirtualInput state.virtual-opts) child-ctx))
    state.virtual))

(fn make-comparison-row-builder [state label-style]
  (Flex {:axis :x
         :xspacing 1.2
         :yalign :start
         :children [(FlexChild (make-parity-column "Input"
                                                   (make-input-child-builder state)
                                                   label-style
                                                   state.widget-size) 0)
                    (FlexChild (make-parity-column "VirtualInput"
                                                   (make-virtual-child-builder state)
                                                   label-style
                                                   state.widget-size) 0)]}))

(fn make-builder [state]
  (fn [ctx]
    (local title-style (TextStyle {:scale 1.25}))
    (local label-style (TextStyle {:scale 0.95}))
    (set state.title ((Text {:text "Input vs VirtualInput caret parity: normal block caret"
                             :style title-style}) ctx))
    (local title-child-builder (make-title-child-builder state))
    (local row-builder (make-comparison-row-builder state label-style))
    ((Flex {:axis :y
            :yspacing 0.6
            :xalign :start
            :children [(FlexChild title-child-builder 0)
                       (FlexChild row-builder 0)]}) ctx)))

(fn set-focused! [input]
  (set input.focused? true)
  (input:update-focus-visual {:mark-layout-dirty? true}))

(fn set-mode! [state mode]
  (if (= mode :insert)
      (do
        (state.input:set-mode :insert)
        (state.virtual:enter-insert-mode))
      (do
        (state.input:set-mode :normal)
        (state.virtual:enter-normal-mode))))

(fn set-caret-line-column! [state line column]
  (local index (cursor-index-for-line-col state.input.model line column))
  (assert (state.input:move-caret-to index)
          (.. "Input should move caret to line " line " column " column))
  (assert (state.virtual:move-caret-to-line-column line column)
          (.. "VirtualInput should move caret to line " line " column " column)))

(fn assert-routed-active [label widget expected-state expected-mode]
  (assert (= (InputState.active-input) widget)
          (.. label " should be the active routed input"))
  (assert (= (app.states:active-name) expected-state)
          (.. label " app state mismatch: expected=" (tostring expected-state)
              " actual=" (tostring (app.states:active-name))))
  (assert (= widget.mode expected-mode)
          (.. label " widget mode mismatch: expected=" (tostring expected-mode)
              " actual=" (tostring widget.mode))))

(fn activate-through-route [target widget event label]
  (set widget.focused? false)
  (widget:on-click event)
  (target:update)
  (assert-routed-active label widget :text :normal))

(fn enter-insert-through-route [target widget label]
  (assert (active-key-down {:key (string.byte "i")})
          (.. label " active TextState should enter insert on i"))
  (assert (active-text-input {:text "i"})
          (.. label " active InsertState should consume paired i text input"))
  (target:update)
  (assert-routed-active label widget :insert :insert)
  (assert widget.caret.visible? (.. label " routed insert caret should be visible"))
  (assert (approx widget.caret.layout.size.x widget.caret-width 0.001)
          (.. label " routed insert caret should be thin")))

(fn return-normal-through-route [target widget label]
  (assert (active-key-down {:key 27})
          (.. label " active InsertState should return to text on Escape"))
  (target:update)
  (assert-routed-active label widget :text :normal)
  (assert widget.caret.visible? (.. label " routed normal caret should be visible"))
  (assert (> widget.caret.layout.size.x widget.caret-width)
          (.. label " routed normal caret should be block width")))

(fn exercise-input-routed-cycle [target state]
  (activate-through-route target state.input {} "Input routed")
  (enter-insert-through-route target state.input "Input routed")
  (return-normal-through-route target state.input "Input routed"))

(fn prepare-routed-parity-companion [state mode]
  (local index (cursor-index-for-line-col state.input.model state.virtual.cursor-line state.virtual.cursor-column))
  (state.input:move-caret-to index)
  (set-focused! state.input)
  (if (= mode :insert)
      (state.input:set-mode :insert)
      (state.input:set-mode :normal)))

(fn update-and-capture [ctx target state scenario]
  (target:update)
  (assert-caret-parity scenario.label state.input state.virtual scenario.mode)
  (when scenario.hscroll?
    (assert-horizontal-scroll state))
  (when scenario.active-input
    (assert-routed-active scenario.label scenario.active-input scenario.app-state scenario.mode))
  (state.title:set-text scenario.title)
  (target:update)
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (Harness.capture-snapshot {:name scenario.snapshot
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2}))

(fn run [ctx]
  (local dir (make-temp-dir))
  (local content "Alpha caret parity\nBravo text sample\nCharlie row target\nLongLine-abcdefghijklmnopqrstuvwxyz-0123456789")
  (local text-style (TextStyle {:scale 1.15}))
  (local state {:widget-size (glm.vec3 16.5 5.8 0)
                :input-opts {:text content
                             :multiline? true
                             :line-wrap? false
                             :line-count 3
                             :column-count 12
                             :padding [0.35 0.35]
                             :caret-width 0.06
                             :text-style text-style}
                :virtual-opts {:buffer (make-buffer dir content)
                               :line-count 3
                               :column-count 12
                                :padding [0.35 0.35]
                                :caret-width 0.06
                                :text-style text-style}})
  (local hud-target (install-state-hud! ctx))
  (local target (Harness.make-screen-target {:width ctx.width
                                             :height ctx.height
                                             :world-units-per-pixel ctx.units-per-pixel
                                             :builder (make-builder state)}))
  (set-focused! state.input)
  (set-focused! state.virtual)
  (target:update)
  (set-caret-line-column! state 0 0)
  (set-mode! state :normal)
  (update-and-capture ctx target state
                      {:label "normal"
                       :title "Input vs VirtualInput caret parity: normal block caret"
                       :mode :normal
                       :snapshot "input-virtual-input-caret-parity-normal"})
  (set-mode! state :insert)
  (update-and-capture ctx target state
                      {:label "insert"
                       :title "Input vs VirtualInput caret parity: insert thin caret"
                       :mode :insert
                       :snapshot "input-virtual-input-caret-parity-insert"})
  (set-mode! state :normal)
  (set-caret-line-column! state 2 0)
  (update-and-capture ctx target state
                      {:label "moved"
                       :title "Input vs VirtualInput caret parity: moved via update path"
                       :mode :normal
                       :snapshot "input-virtual-input-caret-parity-moved"})
  (set-caret-line-column! state 3 24)
  (update-and-capture ctx target state
                      {:label "hscroll"
                       :title "Input vs VirtualInput caret parity: horizontal scroll on long line"
                       :mode :normal
                       :hscroll? true
                       :snapshot "input-virtual-input-caret-parity-hscroll"})
  (exercise-input-routed-cycle target state)
  (activate-through-route target state.virtual {:row-index 1 :column 0} "VirtualInput routed")
  (enter-insert-through-route target state.virtual "VirtualInput routed")
  (prepare-routed-parity-companion state :insert)
  (update-and-capture ctx target state
                      {:label "routed insert"
                       :title "Input vs VirtualInput caret parity: routed insert current state"
                       :mode :insert
                       :app-state :insert
                       :active-input state.virtual
                       :snapshot "input-virtual-input-caret-parity-routed-insert"})
  (return-normal-through-route target state.virtual "VirtualInput routed")
  (prepare-routed-parity-companion state :normal)
  (update-and-capture ctx target state
                      {:label "routed normal"
                       :title "Input vs VirtualInput caret parity: routed return to normal"
                       :mode :normal
                       :app-state :text
                       :active-input state.virtual
                       :snapshot "input-virtual-input-caret-parity-routed-normal"})
  (Harness.cleanup-target target)
  (Harness.cleanup-target hud-target)
  (fs.remove-all dir))

(fn run-main [ctx]
  (run ctx))

(fn main []
  (Harness.with-app {:width 1280 :height 720}
                    run-main)
  (print "E2E input/virtual-input caret parity snapshots complete"))

{:run run
 :main main}
