(local glm (require :glm))
(local _ (require :main))
(local Menu (require :menu))
(local MenuManager (require :menu-manager))
(local {: Layout} (require :layout))

(local tests [])

(fn noop [_self _value] nil)

(fn vector-allocate [_self _count] 1)
(fn vector-delete [_self _handle] nil)
(fn vector-set [_self _handle _offset _value] nil)

(fn icon-resolve [_self _name] nil)

(fn upsert-text [_batcher _key _opts] nil)
(fn update-text-transform [_batcher _key _opts] nil)
(fn remove-text [_batcher _key] nil)
(fn text-batcher [_self]
  {:upsert-text upsert-text
   :update-text-transform update-text-transform
   :remove-text remove-text})

(fn text-vector [buffer]
  (fn [_self _font]
    buffer))

(fn overlay-measurer [self]
  (set self.measure (glm.vec3 0 0 0)))

(fn overlay-layouter [_self] nil)

(fn overlay-child [element position]
  {:element element :position position})

(fn overlay-ray [_self pos]
  {:origin (glm.vec3 pos.x pos.y 10)
   :direction (glm.vec3 0 0 -1)})

(fn reset-engine-events []
  (when _G.reset-engine-events
    (_G.reset-engine-events)))

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate vector-allocate)
  (set buffer.delete vector-delete)
  (set buffer.set-glm-vec3 vector-set)
  (set buffer.set-glm-vec4 vector-set)
  (set buffer.set-glm-vec2 vector-set)
  (set buffer.set-float vector-set)
  buffer)

(fn make-clickables-stub []
  (local state {:right-void nil :left-void nil})
  (local stub {:state state})
  (set stub.register noop)
  (set stub.unregister noop)
  (set stub.register-right-click noop)
  (set stub.unregister-right-click noop)
  (set stub.register-double-click noop)
  (set stub.unregister-double-click noop)
  (set stub.register-left-click-void-callback (fn [_self cb] (set state.left-void cb)))
  (set stub.register-right-click-void-callback (fn [_self cb] (set state.right-void cb)))
  (set stub.unregister-left-click-void-callback
       (fn [_self cb]
         (when (= state.left-void cb)
           (set state.left-void nil))))
  (set stub.unregister-right-click-void-callback
       (fn [_self cb]
         (when (= state.right-void cb)
           (set state.right-void nil))))
  stub)

(fn make-hoverables-stub []
  (local stub {})
  (set stub.register noop)
  (set stub.unregister noop)
  stub)

(fn make-test-ctx [opts]
  (local options (if opts opts {}))
  (local text-buffer (make-vector-buffer))
  (local ctx {:triangle-vector (make-vector-buffer)
              :pointer-target options.pointer-target
              :clickables options.clickables
              :hoverables options.hoverables
              :icons {:resolve icon-resolve}})
  (set ctx.get-text-vector (text-vector text-buffer))
  (set ctx.get-text-ssbo-batcher text-batcher)
  ctx)


(fn make-add-overlay-child [ctx overlay-root overlay-layout]
  (fn [_self opts]
    (local builder (assert opts.builder "target.add-overlay-child requires builder"))
    (local element (builder ctx {}))
    (table.insert overlay-root.children (overlay-child element opts.position))
    (overlay-layout:add-child element.layout)
    element))

(fn make-remove-overlay-child [overlay-root overlay-layout]
  (fn [_self element]
    (var removed? false)
    (for [idx (length overlay-root.children) 1 -1]
      (when (= (. overlay-root.children idx :element) element)
        (set removed? true)
        (overlay-layout:remove-child idx)
        (table.remove overlay-root.children idx)))
    (when (and removed? element element.drop)
      (element:drop))
    removed?))

(fn make-hud-stub [ctx]
  (local overlay-layout
    (Layout {:name "test-overlay"
             :measurer overlay-measurer
             :layouter overlay-layouter}))
  (local overlay-root {:children [] :layout overlay-layout})
  (local hud {:build-context ctx :overlay-root overlay-root})
  (set hud.add-overlay-child (make-add-overlay-child ctx overlay-root overlay-layout))
  (set hud.remove-overlay-child (make-remove-overlay-child overlay-root overlay-layout))
  (set hud.screen-pos-ray overlay-ray)
  (set ctx.pointer-target hud)
  hud)

(fn insert-call [calls name]
  (fn [_button _event]
    (table.insert calls name)))

(fn menu-separator-renders-non-clickable-row []
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local calls [])
  (local menu ((Menu {:actions [{:name "Alpha" :on-click (insert-call calls "Alpha")}
                                {:type :separator}
                                {:name "Beta" :on-click (insert-call calls "Beta")}]}) ctx))
  (assert (= (length menu.actions) 3) "Menu should preserve separator entries in normalized actions")
  (assert (= (. menu.actions 1 :type) :action) "Menu should normalize named entries as action entries")
  (assert (= (. menu.actions 2 :type) :separator) "Menu should normalize separator entries by type")
  (assert (= (. menu.actions 3 :type) :action) "Menu should preserve action order after separator")
  (assert (= (length menu.buttons) 2) "Menu should build buttons only for action entries")
  (local flex-layout (. menu.layout.children 1))
  (assert (= (length flex-layout.children) 3) "Menu layout should include one row per action or separator entry")
  (assert (= (. flex-layout.children 2 :name) "menu-separator") "Menu separator row should use a named separator layout")
  (local first-button (. menu.buttons 1))
  (local second-button (. menu.buttons 2))
  (first-button:on-click {:button 1})
  (second-button:on-click {:button 1})
  (assert (= (length calls) 2) "Menu action buttons before and after a separator should remain invokable")
  (assert (= (. calls 1) "Alpha") "First action should fire before separator-adjacent action")
  (assert (= (. calls 2) "Beta") "Second action should fire after separator")
  (menu:drop))

(fn menu-unknown-nameless-entry-errors []
  (local ctx (make-test-ctx {:clickables (make-clickables-stub) :hoverables (make-hoverables-stub)}))
  (local (ok err) (pcall (fn [] ((Menu {:actions [{:type :unknown}]}) ctx))))
  (assert (not ok) "Menu should reject unknown nameless entries")
  (assert (string.find (tostring err) "Menu entry has unknown type" 1 true) "Menu should report unknown entry types explicitly"))

(fn menu-manager-preserves-separators-without-close-action []
  (reset-engine-events)
  (local clickables (make-clickables-stub))
  (local hoverables (make-hoverables-stub))
  (local ctx (make-test-ctx {:clickables clickables :hoverables hoverables}))
  (local hud (make-hud-stub ctx))
  (local calls [])
  (local manager (MenuManager {:clickables clickables :hud hud}))
  (manager:open {:actions [{:name "First" :fn (insert-call calls "First")}
                           {:type :separator}
                           {:name "Second" :fn (insert-call calls "Second")}]
                 :position (glm.vec3 1 2 0)})
  (assert (= (length hud.overlay-root.children) 1) "MenuManager should open a menu with separator entries")
  (local element (. (. hud.overlay-root.children 1) :element))
  (assert (= (length element.actions) 3) "MenuManager should preserve separator entries in menu actions")
  (assert (= (. element.actions 2 :type) :separator) "MenuManager should pass separator entries through to Menu")
  (assert (= (length element.buttons) 2) "MenuManager should not create a button for the separator")
  (local second-button (. element.buttons 2))
  (second-button:on-click {:button 1})
  (assert (= (length calls) 1) "Action after separator should remain invokable")
  (assert (= (. calls 1) "Second") "Second action should fire through MenuManager wrapper")
  (assert (= (length hud.overlay-root.children) 0) "MenuManager should close after action click, not because of separator")
  (manager:drop))

(table.insert tests {:name "Menu separator renders non-clickable row"
                     :fn menu-separator-renders-non-clickable-row})
(table.insert tests {:name "Menu unknown nameless entry errors"
                     :fn menu-unknown-nameless-entry-errors})
(table.insert tests {:name "Menu separator manager preserves entries"
                     :fn menu-manager-preserves-separators-without-close-action})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "menu-separators"
                       :tests tests})))

{:name "menu-separators"
 :tests tests
 :main main}
