(local tests [])

(local glm (require :glm))
(local BuildContext (require :build-context))
(local {: Layout} (require :layout))
(local SnackbarManager (require :snackbar-manager))
(local SnackbarHost (require :snackbar-host))
(local SnackbarContent (require :snackbar-content))
(local Snackbar (require :snackbar))

(fn assert-error-contains [body expected]
  (local (ok err) (pcall body))
  (assert (not ok) "Expected function to fail")
  (assert (and (= (type err) :string)
               (string.find err expected 1 true))
          (.. "Expected error to contain '" expected "', got '" (tostring err) "'")))

(fn make-clickables-stub []
  (fn register [self button]
    (table.insert self.registered button))
  (fn noop [_self _button] nil)
  {:registered []
   :register register
   :register-right-click noop
   :register-double-click noop
   :unregister noop
   :unregister-right-click noop
   :unregister-double-click noop})

(fn make-hoverables-stub []
  (fn register [self button]
    (table.insert self.registered button))
  (fn noop [_self _button] nil)
  {:registered []
   :register register
   :unregister noop})

(fn make-ctx []
  (BuildContext {:clickables (make-clickables-stub)
                 :hoverables (make-hoverables-stub)}))

(fn probe-drop-count [drops id]
  (if (not (= (. drops id) nil))
      (. drops id)
      0))

(fn make-probe-widget [drops entry]
  (fn measurer [self]
    (set self.measure (glm.vec3 2 1 0)))
  (fn layouter [_self] nil)
  (local layout (Layout {:name (.. "probe-" entry.id)
                         :measurer measurer
                         :layouter layouter}))
  (fn drop [self]
    (set (. drops self.entry.id) (+ (probe-drop-count drops self.entry.id) 1))
    (self.layout:drop))
  {:layout layout
   :entry entry
   :drop drop})

(fn make-probe-builder [drops]
  (fn build-probe [_ctx entry _handle]
    (make-probe-widget drops entry)))

(fn make-constrained-width-widget [drops entry]
  (fn measurer [self]
    (set self.measure (glm.vec3 18 1 0)))
  (fn constrained-measurer [self constraints]
    (set self.measure (glm.vec3 (math.min 18 constraints.max.x) 1 0)))
  (fn layouter [_self] nil)
  (local layout (Layout {:name (.. "constrained-probe-" entry.id)
                         :measurer measurer
                         :constrained-measurer constrained-measurer
                         :layouter layouter}))
  (fn drop [self]
    (set (. drops self.entry.id) (+ (probe-drop-count drops self.entry.id) 1))
    (self.layout:drop))
  {:layout layout
   :entry entry
   :drop drop})

(fn make-constrained-width-builder [drops]
  (fn build-probe [_ctx entry _handle]
    (make-constrained-width-widget drops entry)))

(fn build-probe-host [manager drops opts]
  (local host-builder
    (SnackbarHost {:manager manager
                   :content-builder (make-probe-builder drops)
                   :theme (and opts opts.theme)
                   :placement (and opts opts.placement)
                   :spacing (and opts opts.spacing)
                   :max-width (and opts opts.max-width)}))
  (host-builder (make-ctx)))

(fn host-requires-manager []
  (assert-error-contains
    (fn []
      ((SnackbarHost {}) (make-ctx)))
    "SnackbarHost requires :manager"))

(fn host-renders-visible-entries []
  (local manager (SnackbarManager {:max-visible 3}))
  (local drops {})
  (local host (build-probe-host manager drops))
  (manager:show {:id "one" :text "One" :persistent? true})
  (assert (= (length host.children) 1) "one visible entry should render one child")
  (manager:show {:id "two" :text "Two" :persistent? true})
  (assert (= (length host.children) 2) "two visible entries should render two children")
  (host:drop)
  (manager:drop))

(fn dismiss-drops-removed-child-once []
  (local manager (SnackbarManager {:max-visible 2}))
  (local drops {})
  (local host (build-probe-host manager drops))
  (manager:show {:id "one" :text "One" :persistent? true})
  (manager:show {:id "two" :text "Two" :persistent? true})
  (manager:dismiss "one")
  (assert (= (. drops :one) 1) "dismissed child should drop exactly once")
  (assert (= (. drops :two) nil) "remaining child should not be dropped")
  (host:drop)
  (assert (= (. drops :one) 1) "dismissed child should not drop again on host drop")
  (assert (= (. drops :two) 1) "remaining child should drop once on host drop")
  (manager:drop))

(fn clear-drops-all-children-once []
  (local manager (SnackbarManager {:max-visible 2}))
  (local drops {})
  (local host (build-probe-host manager drops))
  (manager:show {:id "one" :text "One" :persistent? true})
  (manager:show {:id "two" :text "Two" :persistent? true})
  (manager:clear)
  (assert (= (length host.children) 0) "clear should remove rendered children")
  (assert (= (. drops :one) 1) "first cleared child should drop once")
  (assert (= (. drops :two) 1) "second cleared child should drop once")
  (host:drop)
  (assert (= (. drops :one) 1) "first cleared child should not drop again")
  (assert (= (. drops :two) 1) "second cleared child should not drop again")
  (manager:drop))

(fn host-drop-disconnects-and-drops-remaining []
  (local manager (SnackbarManager {:max-visible 2}))
  (local drops {})
  (local host (build-probe-host manager drops))
  (manager:show {:id "one" :text "One" :persistent? true})
  (host:drop)
  (assert (= (. drops :one) 1) "host drop should drop rendered child once")
  (manager:show {:id "two" :text "Two" :persistent? true})
  (assert (= (length host.children) 0) "dropped host should disconnect from manager changes")
  (assert (= (. drops :one) 1) "host drop should be idempotent for children")
  (host:drop)
  (assert (= (. drops :one) 1) "second host drop should not drop again")
  (manager:drop))

(fn default-content-renders-layout-for-text []
  (local manager (SnackbarManager))
  (local host ((SnackbarHost {:manager manager}) (make-ctx)))
  (manager:show {:id "simple" :text "Saved" :persistent? true})
  (local child (. host.children 1))
  (assert child "simple text entry should render a child")
  (assert child.layout "default content child should have a layout")
  (host:drop)
  (manager:drop))

(fn visit-widget-tables [value visited visitor]
  (when (and (= (type value) :table)
             (not (. visited value)))
    (set (. visited value) true)
    (visitor value)
    (each [key child (pairs value)]
      (when (and (not (= key :layout))
                 (not (= key :parent))
                 (not (= key :root)))
        (visit-widget-tables child visited visitor)))))

(fn buttons-in [widget]
  (local buttons [])
  (visit-widget-tables widget {} (fn [candidate]
                                  (when (and candidate.clicked candidate.on-click candidate.stack)
                                    (table.insert buttons candidate))))
  buttons)

(fn action-buttons-invoke-action-callback []
  (local manager (SnackbarManager))
  (local event {:source :test})
  (var callback-entry nil)
  (var callback-handle nil)
  (var callback-button nil)
  (var callback-event nil)
  (fn on-action [entry handle button event]
    (set callback-entry entry)
    (set callback-handle handle)
    (set callback-button button)
    (set callback-event event))
  (local host ((SnackbarHost {:manager manager}) (make-ctx)))
  (local handle
    (manager:show {:id "action" :text "Saved" :persistent? true
                   :actions [{:label "Undo"
                              :on-click on-action}]}))
  (local child (. host.children 1))
  (local buttons (buttons-in child))
  (assert (= (length buttons) 1) "one action should build one button")
  (local button (. buttons 1))
  (button:on-click event)
  (assert (= callback-entry handle.entry) "action callback should receive entry")
  (assert (= callback-handle handle) "action callback should receive handle")
  (assert (= callback-button button) "action callback should receive button")
  (assert (= callback-event event) "action callback should receive event")
  (host:drop)
  (manager:drop))

(fn entry-content-builder-overrides-default []
  (local manager (SnackbarManager))
  (var received-ctx nil)
  (var received-entry nil)
  (var received-handle nil)
  (fn builder [ctx entry handle]
    (set received-ctx ctx)
    (set received-entry entry)
    (set received-handle handle)
    ((make-probe-builder {}) ctx entry handle))
  (local ctx (make-ctx))
  (local host ((SnackbarHost {:manager manager}) ctx))
  (local handle (manager:show {:id "custom" :content-builder builder :persistent? true}))
  (assert (= received-ctx ctx) "entry content builder should receive build ctx")
  (assert (= received-entry handle.entry) "entry content builder should receive entry")
  (assert (= received-handle handle) "entry content builder should receive handle")
  (assert (= (length host.children) 1) "custom content should render")
  (host:drop)
  (manager:drop))

(fn manager-change-marks-host-measure-dirty []
  (local manager (SnackbarManager))
  (local drops {})
  (local host (build-probe-host manager drops))
  (set host.layout.measure-dirty false)
  (manager:show {:id "dirty" :text "Dirty" :persistent? true})
  (assert host.layout.measure-dirty "manager changes should mark host layout measure dirty")
  (host:drop)
  (manager:drop))

(fn layout-host [host]
  (host.layout:measurer)
  (set host.layout.position (glm.vec3 10 20 0))
  (set host.layout.size (glm.vec3 30 15 0))
  (host.layout:layouter))

(fn placement-top-right-uses-right-edge-and-spacing []
  (local manager (SnackbarManager {:max-visible 2}))
  (local drops {})
  (local host (build-probe-host manager drops {:placement :top-right :spacing 0.75 :max-width 5}))
  (manager:show {:id "one" :text "One" :persistent? true})
  (manager:show {:id "two" :text "Two" :persistent? true})
  (layout-host host)
  (local first (. host.children 1))
  (local second (. host.children 2))
  (local right-edge (+ host.layout.position.x host.layout.size.x))
  (assert (= (+ first.layout.position.x first.layout.size.x) right-edge)
          "top-right child should align to host right edge")
  (assert (= (+ second.layout.position.x second.layout.size.x) right-edge)
          "top-right second child should align to host right edge")
  (assert (= second.layout.position.y (+ first.layout.position.y first.layout.size.y 0.75))
          "top-right placement should use configured vertical spacing")
  (host:drop)
  (manager:drop))

(fn top-right-clamps-child-width-to-host-bounds []
  (local manager (SnackbarManager))
  (local drops {})
  (local host-builder
    (SnackbarHost {:manager manager
                   :content-builder (make-constrained-width-builder drops)
                   :placement :top-right
                   :max-width 18}))
  (local host (host-builder (make-ctx)))
  (manager:show {:id "wide" :text "Wide" :persistent? true})
  (host.layout:measure-constrained {:max (glm.vec3 10 15 0)})
  (set host.layout.position (glm.vec3 10 20 0))
  (set host.layout.size (glm.vec3 10 15 0))
  (host.layout:layouter)
  (local child (. host.children 1))
  (assert (= child.layout.measure.x 10) "child width should be clamped to host constrained width")
  (assert (= child.layout.position.x host.layout.position.x)
          "clamped top-right child should stay inside host left edge")
  (assert (= (+ child.layout.position.x child.layout.size.x)
             (+ host.layout.position.x host.layout.size.x))
          "clamped top-right child should align to host right edge")
  (host:drop)
  (manager:drop))

(fn finite-zero-width-constraint-clamps-child-width []
  (local manager (SnackbarManager))
  (local drops {})
  (local host-builder
    (SnackbarHost {:manager manager
                   :content-builder (make-constrained-width-builder drops)
                   :placement :top-right
                   :max-width 18}))
  (local host (host-builder (make-ctx)))
  (manager:show {:id "zero" :text "Zero" :persistent? true})
  (host.layout:measure-constrained {:max (glm.vec3 0 15 0)})
  (set host.layout.position (glm.vec3 10 20 0))
  (set host.layout.size (glm.vec3 0 15 0))
  (host.layout:layouter)
  (local child (. host.children 1))
  (assert (= child.layout.measure.x 0) "finite zero-width constraint should clamp child measured width to zero")
  (assert (= child.layout.position.x host.layout.position.x)
          "zero-width top-right child should remain inside host left edge")
  (assert (= child.layout.size.x 0) "zero-width constrained child should lay out with zero width")
  (host:drop)
  (manager:drop))

(fn assigned-zero-host-width-clamps-child-width []
  (local manager (SnackbarManager))
  (local drops {})
  (local host-builder
    (SnackbarHost {:manager manager
                   :content-builder (make-constrained-width-builder drops)
                   :placement :top-right
                   :max-width 18}))
  (local host (host-builder (make-ctx)))
  (manager:show {:id "assigned-zero" :text "Assigned zero" :persistent? true})
  (set host.layout.size (glm.vec3 0 15 0))
  (host.layout:measurer)
  (set host.layout.position (glm.vec3 10 20 0))
  (host.layout:layouter)
  (local child (. host.children 1))
  (assert (= child.layout.measure.x 0) "assigned zero host width should clamp child measured width to zero")
  (assert (= child.layout.position.x host.layout.position.x)
          "assigned zero host width should keep top-right child inside host left edge")
  (assert (= child.layout.size.x 0) "assigned zero host width should lay child out with zero width")
  (host:drop)
  (manager:drop))

(fn placement-top-left-uses-left-edge []
  (local manager (SnackbarManager))
  (local drops {})
  (local host (build-probe-host manager drops {:theme {:placement :top-left :spacing 0.25}}))
  (manager:show {:id "left" :text "Left" :persistent? true})
  (layout-host host)
  (local child (. host.children 1))
  (assert (= child.layout.position.x host.layout.position.x)
          "top-left child should align to host left edge")
  (host:drop)
  (manager:drop))

(fn same-id-replacement-rebuilds-rendered-child []
  (local manager (SnackbarManager))
  (local drops {})
  (local host (build-probe-host manager drops))
  (local first-handle
    (manager:show {:id "save" :replace-key "save" :text "Saving" :persistent? true}))
  (local first-child (. host.children 1))
  (local second-handle
    (manager:show {:id "save" :replace-key "save" :text "Saved" :persistent? true}))
  (local second-child (. host.children 1))
  (assert (not (= first-handle second-handle)) "manager replacement should issue a new handle")
  (assert (not (= first-child second-child)) "same-id replacement should rebuild rendered child")
  (assert (= (. drops :save) 1) "same-id replacement should drop old rendered child once")
  (assert (= second-child.entry.text "Saved") "rebuilt child should use replacement entry content")
  (host:drop)
  (assert (= (. drops :save) 2) "replacement child should drop once on host drop")
  (manager:drop))

(fn snackbar-host-does-not-require-scroll-view []
  (local source-path "assets/lua/snackbar-host.fnl")
  (local handle (assert (io.open source-path "r") "should open snackbar-host source"))
  (local source (handle:read "*a"))
  (handle:close)
  (assert (not (string.find source "scroll%-view")) "snackbar host should not require scroll-view"))

(fn public-facade-creates-scoped-manager-and-host []
  (assert Snackbar.SnackbarManager "facade should export SnackbarManager")
  (assert Snackbar.SnackbarHost "facade should export SnackbarHost")
  (assert Snackbar.SnackbarTheme "facade should export SnackbarTheme")
  (local scope (Snackbar.create-scope {:max-visible 1}))
  (assert scope.manager "scope should include manager")
  (assert scope.host-builder "scope should include host builder")
  (local host (scope.host-builder (make-ctx)))
  (scope.manager:show {:id "scoped" :text "Scoped" :persistent? true})
  (assert (= (length host.children) 1) "scope host should use scope manager")
  (host:drop)
  (assert (= (scope:drop) true) "scope drop should return true")
  (assert-error-contains (fn [] (scope.manager:show {:text "late"})) "SnackbarManager is dropped"))

(table.insert tests {:name "SnackbarHost requires manager"
                     :fn host-requires-manager})
(table.insert tests {:name "SnackbarHost renders visible entries"
                     :fn host-renders-visible-entries})
(table.insert tests {:name "SnackbarHost dismiss drops removed child once"
                     :fn dismiss-drops-removed-child-once})
(table.insert tests {:name "SnackbarHost clear drops all children once"
                     :fn clear-drops-all-children-once})
(table.insert tests {:name "SnackbarHost drop disconnects and drops remaining once"
                     :fn host-drop-disconnects-and-drops-remaining})
(table.insert tests {:name "SnackbarContent default builder renders text layout"
                     :fn default-content-renders-layout-for-text})
(table.insert tests {:name "SnackbarContent action buttons invoke callbacks"
                     :fn action-buttons-invoke-action-callback})
(table.insert tests {:name "SnackbarHost uses entry content builder"
                     :fn entry-content-builder-overrides-default})
(table.insert tests {:name "SnackbarHost manager changes mark measure dirty"
                     :fn manager-change-marks-host-measure-dirty})
(table.insert tests {:name "SnackbarHost top-right placement uses right edge and spacing"
                      :fn placement-top-right-uses-right-edge-and-spacing})
(table.insert tests {:name "SnackbarHost top-right clamps child width to host bounds"
                      :fn top-right-clamps-child-width-to-host-bounds})
(table.insert tests {:name "SnackbarHost finite zero-width constraint clamps child width"
                      :fn finite-zero-width-constraint-clamps-child-width})
(table.insert tests {:name "SnackbarHost assigned zero host width clamps child width"
                      :fn assigned-zero-host-width-clamps-child-width})
(table.insert tests {:name "SnackbarHost top-left placement uses left edge"
                      :fn placement-top-left-uses-left-edge})
(table.insert tests {:name "SnackbarHost same-id replacements rebuild rendered child"
                     :fn same-id-replacement-rebuilds-rendered-child})
(table.insert tests {:name "SnackbarHost does not require scroll-view"
                     :fn snackbar-host-does-not-require-scroll-view})
(table.insert tests {:name "Snackbar facade creates scoped manager and host"
                     :fn public-facade-creates-scoped-manager-and-host})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "snackbar-host"
                     :tests tests}))

{:main main}
