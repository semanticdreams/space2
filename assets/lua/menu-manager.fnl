(local glm (require :glm))
(local Menu (require :menu))
(local RootContextMenuActions (require :root-context-menu-actions))

(local SDLK_ESCAPE 27)

(fn value-or [value fallback]
  (if (= value nil) fallback value))

(fn action-name [action]
  (if action.name action.name action.text))

(fn screen-coordinate [screen axis]
  (if (and screen (. screen axis)) (. screen axis) 0))

(fn event-button [event]
  (if (and event event.button) event.button 3))

(fn MenuManager [opts]
  (local options (value-or opts {}))
  (local clickables (value-or options.clickables app.clickables))
  (local hud (value-or options.hud app.hud))
  (local static-root-actions options.root-actions)
  (local root-actions-provider
    (if options.root-actions-provider
        options.root-actions-provider
        (fn [_event]
          (if static-root-actions static-root-actions (RootContextMenuActions.actions-for-event _event)))))

  (assert clickables "MenuManager requires clickables")
  (assert hud "MenuManager requires hud")

  (var active-menu nil)
  (var right-click-callback nil)
  (var left-click-callback nil)
  (var mouse-button-handler nil)
  (var key-down-handler nil)

  (fn active? [_self]
    (not (= active-menu nil)))

  (fn screen-pos->hud [screen]
    (local x (screen-coordinate screen :x))
    (local y (screen-coordinate screen :y))
    (local ray (and hud hud.screen-pos-ray (hud:screen-pos-ray {:x x :y y})))
    (if (and ray ray.origin ray.direction)
        (do
          (local dz (value-or ray.direction.z 0))
          (local t (if (not (= dz 0)) (/ (- 0 ray.origin.z) dz) 0))
          (+ ray.origin (* ray.direction t)))
        (glm.vec3 x y 0)))

  (fn close []
    (when active-menu
      (when (and hud hud.remove-overlay-child)
        (hud:remove-overlay-child active-menu))
      (set active-menu nil)
      ))

  (fn wrap-actions [actions]
    (icollect [_ action (ipairs (value-or actions []))]
      (if (= action.type :separator)
          {:type :separator}
          {:name (action-name action)
           :text action.text
           :icon action.icon
           :variant action.variant
           :padding action.padding
           :on-click (fn [button event]
                       (when action.fn
                         (action.fn button event))
                       (when action.handler
                         (action.handler button event))
                       (when action.on-click
                         (action.on-click button event))
                       (close))})))

  (fn open [self opts]
    (local open-opts (value-or opts {}))
    (local actions (wrap-actions open-opts.actions))
    (local position (value-or open-opts.position (glm.vec3 0 0 0)))
    (close)
    (when (and hud hud.add-overlay-child)
      (local builder (Menu {:actions actions}))
      (set active-menu (hud:add-overlay-child {:builder builder
                                               :position position
                                               :depth-offset-index open-opts.depth-offset-index}))))

  (fn open-root [self event]
    (local screen (and event event.screen))
    (local position (screen-pos->hud screen))
    (open nil {:actions (root-actions-provider event)
               :position position
               :ignore-button (event-button event)}))

  (fn on-left-click-void [_event]
    (when active-menu
      (close)))

  (fn on-key-down [payload]
    (when (and active-menu payload (= payload.key SDLK_ESCAPE))
      (close)))

  (fn drop [self]
    (close)
    (when (and clickables right-click-callback)
      (clickables:unregister-right-click-void-callback right-click-callback)
      (set right-click-callback nil))
    (when (and clickables left-click-callback)
      (clickables:unregister-left-click-void-callback left-click-callback)
      (set left-click-callback nil))
    (when (and app.engine app.engine.events key-down-handler)
      (app.engine.events.key-down:disconnect key-down-handler true)
      (set key-down-handler nil)))

  (set right-click-callback
       (fn [event]
         (open-root nil event)))
  (clickables:register-right-click-void-callback right-click-callback)
  (set left-click-callback
       (fn [event]
         (on-left-click-void event)))
  (clickables:register-left-click-void-callback left-click-callback)

  (when (and app.engine app.engine.events)
    (set key-down-handler
         (app.engine.events.key-down:connect on-key-down)))

  {:open open
   :open-root open-root
   :close (fn [_self] (close))
   :drop drop
   :active? active?
   :menu (fn [] active-menu)})

MenuManager
