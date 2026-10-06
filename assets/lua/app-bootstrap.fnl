(local logging (require :logging))

(fn init-themes []
  (local Themes (require :themes))
  (set app.themes (Themes))
  (app.themes.add-theme :dark (require :dark-theme))
  (app.themes.add-theme :light (require :light-theme))
  (local stored-theme
    (and app.settings app.settings.get-value
         (app.settings.get-value "ui.theme" nil)))
  (local fallback-theme :dark)
  (local desired-theme (or stored-theme fallback-theme))
  (local (ok _result-or-error)
    (pcall app.themes.set-theme desired-theme))
  (when (not ok)
    (when stored-theme
      (logging.warn
        (string.format
          "[space] stored ui.theme '%s' is unavailable; falling back to %s"
          (tostring stored-theme)
          (tostring fallback-theme))))
    (app.themes.set-theme fallback-theme))
  app.themes)

(fn init-lights []
  (local {:LightSystem LightSystem} (require :light-system))
  (set app.lights (LightSystem {}))
  app.lights)

(fn init-input-systems []
  (local Intersectables (require :intersectables))
  (local Clickables (require :clickables))
  (local Hoverables (require :hoverables))
  (local Movables (require :movables))
  (local Resizables (require :resizables))
  (local TouchGestureTargets (require :touch-gesture-targets))
  (local SystemCursors (require :system-cursors))
  (set app.intersectables (Intersectables))
  (set app.clickables (Clickables {:intersectables app.intersectables}))
  (set app.hoverables (Hoverables {:intersectables app.intersectables})) (local clickables (assert app.clickables "input systems require app.clickables")) (local hoverables (assert app.hoverables "input systems require app.hoverables"))
  (set app.movables (Movables {:intersectables app.intersectables}))
  (set app.resizables (Resizables {:intersectables app.intersectables}))
  (set app.touch-gesture-targets
       (TouchGestureTargets {:intersectables app.intersectables}))
  (set app.system-cursors (SystemCursors))
  {:intersectables app.intersectables
   :clickables clickables
   :hoverables hoverables
   :movables app.movables
   :resizables app.resizables
   :touch-gesture-targets app.touch-gesture-targets
   :system-cursors app.system-cursors})

(fn init-renderers [opts]
  (local Renderers (require :renderers))
  (set app.renderers (Renderers))
  (local options (or opts {}))
  (when (and app.renderers options.viewport)
    (app.renderers:on-viewport-changed options.viewport))

  app.renderers)

(fn init-icons []
  (local Icons (require :icons))
  (set app.icons (Icons))
  app.icons)

(fn drop-states []
  (local StateSystemBindings (require :state-system-bindings))
  (when app.states
    (assert app.states.drop "app.states requires drop before replacement")
    (app.states:drop))
  (StateSystemBindings.bind-states-host nil)
  (set app.states nil)
  nil)

(fn init-states []
  (drop-states)
  (local States (require :states))
  (local StateSystemBindings (require :state-system-bindings))
  (set app.states
       (States {:hud_provider (fn [_states]
                                app.hud)
                :focus_manager_provider (fn [_states]
                                          app.focus)}))
  (StateSystemBindings.bind-states-host app.states)
  (app.states:add-state :normal ((require :normal-state)))
  (app.states:add-state :leader ((require :leader-state)))
  (app.states:add-state :context-menu ((require :context-menu-state)))
  (app.states:add-state :quit ((require :quit-state)))
  (app.states:add-state :text ((require :text-state)))
  (app.states:add-state :insert ((require :insert-state)))
  (app.states:add-state :camera ((require :camera-state)))
  (app.states:add-state :fpc ((require :fpc-state)))
  (app.states:add-state :terrain-rect-pick ((require :terrain-rect-pick-state)))
  (app.states:add-state :terrain-paint ((require :terrain-paint-state)))
  (app.states:add-state :car ((require :car-state)))
  (app.states:add-state :tetris ((require :tetris-state)))
  (app.states:set-state :normal)
  app.states)

{:init-themes init-themes
 :init-lights init-lights
 :init-input-systems init-input-systems
 :init-renderers init-renderers
 :init-icons init-icons
 :init-states init-states
 :drop-states drop-states}
