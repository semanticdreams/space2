(local Harness (require :tests.e2e.harness))
(local fs (require :fs))
(local glm (require :glm))
(local Graph (require :graph/init))
(local GraphView (require :graph/view))
(local InputState (require :input-state-router))
(local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
(local FsFileViewerNodeView (require :graph/view/views/fs-file-viewer))
(local {:Layout Layout} (require :layout))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "e2e-fs-file-viewer-virtual-input"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "viewer-" (os.time) "-" temp-counter)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn write-temp-file [dir]
  (local path (fs.join-path dir "viewer.txt"))
  (fs.write-file path "abcdefghijklmnopqrstuvwxyz\nsecond line\n")
  (fs.absolute path))

(fn active-key-down [payload]
  (local state (assert (app.states:active-state) "E2E requires active app state"))
  (assert state.on-key-down "E2E active state requires on-key-down")
  (state:on-key-down payload))

(fn active-mouse-button-down [payload]
  (local state (assert (app.states:active-state) "E2E requires active app state"))
  (assert state.on-mouse-button-down "E2E active state requires on-mouse-button-down")
  (state:on-mouse-button-down payload))

(fn active-mouse-button-up [payload]
  (local state (assert (app.states:active-state) "E2E requires active app state"))
  (assert state.on-mouse-button-up "E2E active state requires on-mouse-button-up")
  (state:on-mouse-button-up payload))

(fn active-text-input [payload]
  (local state (assert (app.states:active-state) "E2E requires active app state"))
  (assert state.on-text-input "E2E active state requires on-text-input")
  (state:on-text-input payload))

(fn text-of [text-widget]
  (table.concat
    (icollect [_ codepoint (ipairs (text-widget:get-codepoints))]
      (utf8.char codepoint))
    ""))

(fn status-string [view]
  (text-of view.status-text))

(fn assert-caret-inside-input [input]
  (input.layout:layouter)
  (assert input.caret.visible? "file viewer caret should be visible")
  (local local-x (- input.caret.layout.position.x input.layout.position.x))
  (assert (>= local-x input.padding.x) "caret should be inside left input edge")
  (assert (<= local-x (- input.layout.size.x input.padding.x))
          "caret should be inside right input edge"))

(fn install-state-hud! [ctx]
  (local hud-target (Harness.make-hud-target {:width ctx.width
                                              :height ctx.height}))
  (app.states:set-hud-provider (fn [_states] hud-target))
  (app.states:set-focus-manager-provider (fn [_states] hud-target.focus-manager))
  hud-target)

(fn make-view-builder [node view-ref]
  (fn build-view [child-ctx]
    (set view-ref.view ((FsFileViewerNodeView node {}) child-ctx))
    view-ref.view))

(fn make-view-target [ctx node view-ref]
  (Harness.make-screen-target
    {:width ctx.width
     :height ctx.height
     :world-units-per-pixel ctx.units-per-pixel
     :builder (make-view-builder node view-ref)}))

(fn make-expanded-persistence [node position]
  {:saved-position (fn [_self candidate]
                     (when (= candidate node)
                       position))
   :saved-presentation (fn [_self candidate]
                         (when (= candidate node)
                           :expanded))
   :saved-size (fn [_self _candidate] nil)
   :saved-camera-state (fn [_self] nil)
   :set-presentation (fn [_self _candidate _presentation] nil)
   :set-size (fn [_self _candidate _size] nil)
   :set-camera-state (fn [_self _camera-state] nil)
   :schedule-save (fn [_self] nil)
   :persist (fn [_self _points _force?] nil)})

(fn expanded-target-root-measurer [ctx]
  (fn [self]
    (set self.measure ctx.world-size)))

(fn expanded-target-root-layouter [_ctx]
  (fn [self]
    (set self.size self.measure)))

(fn make-expanded-target-root [ctx graph-ref view-ref]
  (local layout
    (Layout {:name "expanded-graph-file-viewer-e2e-root"
             :measurer (expanded-target-root-measurer ctx)
             :layouter (expanded-target-root-layouter ctx)}))
  {:layout layout
   :drop (fn [_self]
           (when view-ref.graph-view
             (view-ref.graph-view:drop))
           (when graph-ref.graph
             (graph-ref.graph:drop))
           (layout:drop))})

(fn make-expanded-graph-builder [ctx node graph-ref view-ref position]
  (fn [child-ctx]
    (set graph-ref.graph (Graph {:with-start false}))
    (graph-ref.graph:add-node node)
    (set view-ref.graph-view
         (GraphView {:graph-map graph-ref.graph
                     :ctx child-ctx
                     :data-dir (fs.join-path "/tmp/space/tests" "graph-fs-file-viewer-virtual-input")
                     :persistence (make-expanded-persistence node position)}))
    (make-expanded-target-root ctx graph-ref view-ref)))

(fn make-expanded-graph-target [ctx node graph-ref view-ref focus-manager]
  (local position (glm.vec3 (/ ctx.world-size.x 2)
                            (/ ctx.world-size.y 2)
                            0))
  (Harness.make-screen-target
    {:width ctx.width
     :height ctx.height
     :world-units-per-pixel ctx.units-per-pixel
     :focus-manager focus-manager
     :builder (make-expanded-graph-builder ctx node graph-ref view-ref position)}))

(fn screen-point-for-layout-center [ctx layout]
  (assert layout "screen point requires layout")
  (local world-x (+ layout.position.x (/ layout.size.x 2)))
  (local world-y (+ layout.position.y (/ layout.size.y 2)))
  {:x (/ world-x ctx.units-per-pixel)
   :y (- ctx.height (/ world-y ctx.units-per-pixel))})

(fn clickable-label [object graph-card virtual-input]
  (if (= object virtual-input)
      "VirtualInput"
      (= object graph-card)
      "expanded graph card"
      (and object object.layout object.layout.name)
      object.layout.name
      (and object object.node object.node.key)
      object.node.key
      object
      (tostring object)
      "none"))

(fn force-narrow-input-allocation [input]
  (set input.layout.size
       (glm.vec3 (+ (* 2 input.padding.x)
                    (* 6 input.column-width))
                 (+ (* 2 input.padding.y)
                    (* 3 input.line-height))
                 0))
  (input.layout:layouter))

(fn run [ctx]
  (local dir (make-temp-dir))
  (local file (write-temp-file dir))
  (local node (FsFileViewerNode {:path file}))
  (local view-ref {})
  (local hud-target (install-state-hud! ctx))
  (local target (make-view-target ctx node view-ref))
  (target:update)
  (local view view-ref.view)
  (assert view "E2E should build FsFileViewerNodeView")
  (assert view.virtual-input "file viewer should expose VirtualInput")
  (force-narrow-input-allocation view.virtual-input)
  (view.virtual-input:on-click {:row-index 1 :column 0})
  (assert (= (InputState.active-input) view.virtual-input)
          "click should focus file viewer VirtualInput")
  (assert (= (app.states:active-name) :text)
          "click should enter text state")
  (assert (active-key-down {:key (string.byte "i")})
          "Vim i should enter insert through active state")
  (assert (= (app.states:active-name) :insert)
          "active state should become insert")
  (assert (active-text-input {:text "i"})
          "insert-entering text event should be consumed through active insert state")
  (assert (active-text-input {:text "!"})
          "insert text should route through active insert state")
  (assert (active-key-down {:key 27})
          "escape should return to text mode")
  (assert (= (app.states:active-name) :text)
          "escape should return to text state")
  (for [_ 1 12]
    (active-key-down {:key (string.byte "l")}))
  (assert (> view.virtual-input.scroll-column 0)
          "long-line navigation should scroll horizontally")
  (assert-caret-inside-input view.virtual-input)
  (assert (active-key-down {:key (string.byte "s") :mod 64})
          "Ctrl+S should save through file viewer key route")
  (local saved-content (fs.read-file file))
  (assert (= saved-content "!abcdefghijklmnopqrstuvwxyz\nsecond line\n")
          (.. "saved file should contain routed insert edit, got: " saved-content))
  (assert (string.find (status-string view) "Saved" 1 true)
          "status should report saved")
  (Harness.cleanup-target target)
  (Harness.cleanup-target hud-target)
  (node:drop)
  (fs.remove-all dir))

(fn run-expanded-graph-routed-click [ctx]
  (local dir (make-temp-dir))
  (local file (write-temp-file dir))
  (local node (FsFileViewerNode {:path file}))
  (local graph-ref {})
  (local view-ref {})
  (local hud-target (install-state-hud! ctx))
  (local target (make-expanded-graph-target ctx node graph-ref view-ref hud-target.focus-manager))
  (target:update)
  (local graph-view (assert view-ref.graph-view "E2E should build GraphView"))
  (local graph-card (assert (. graph-view.points node) "GraphView should expand file viewer node"))
  (local view (assert graph-card.view-widget "expanded graph card should embed file viewer preview"))
  (assert view.virtual-input "expanded graph file viewer should expose VirtualInput")
  (view.virtual-input.layout:layouter)
  (local pointer (screen-point-for-layout-center ctx view.virtual-input.layout))
  (local down-payload {:x pointer.x :y pointer.y :button 1 :timestamp 10})
  (local up-payload {:x pointer.x :y pointer.y :button 1 :timestamp 20})
  (active-mouse-button-down down-payload)
  (local active-entry app.clickables.active-entry)
  (local active-object (and active-entry active-entry.object))
  (local winner (clickable-label active-object graph-card view.virtual-input))
  (active-mouse-button-up up-payload)
  (assert (= (InputState.active-input) view.virtual-input)
          (.. "routed click inside expanded graph file viewer VirtualInput should focus it; "
              "mouse-down clickable=" winner
              ", screen=(" (tostring pointer.x) "," (tostring pointer.y) ")"))
  (assert (active-key-down {:key (string.byte "l")})
          "focused expanded graph file viewer VirtualInput should consume h/j/k/l navigation")
  (Harness.cleanup-target target)
  (Harness.cleanup-target hud-target)
  (node:drop)
  (fs.remove-all dir))

(fn run-main [ctx]
  (run ctx)
  (run-expanded-graph-routed-click ctx))

(fn main []
  (Harness.with-app {:width 960 :height 720} run-main)
  (print "E2E fs file viewer VirtualInput usability complete"))

{:run run
 :run-expanded-graph-routed-click run-expanded-graph-routed-click
 :main main}
