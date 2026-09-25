(local WorkspaceMount (require :app-host.workspace-mount))

(fn panel-error [message]
  (error (.. "[app-host.workspace-panel] " message)))

(fn resolve-hud [opts]
  (local shell (and opts opts.app))
  (local hud (if (and shell shell.hud)
                 shell.hud
                 (and app app.hud)))
  (when (not hud)
    (panel-error "open requires :app.hud or app.hud"))
  (when (not (= (type hud.add-panel-child) :function))
    (panel-error "HUD requires add-panel-child"))
  (when (not (= (type hud.remove-panel-child) :function))
    (panel-error "HUD requires remove-panel-child"))
  hud)

(fn open [opts]
  (when (= opts nil)
    (panel-error "open requires options"))
  (local options opts)
  (local hud (resolve-hud options))
  (local mount (WorkspaceMount.mount options))
  (local controller mount.controller)
  (var closed? false)
  (var hud-child nil)
  (var session nil)
  (var descriptor nil)

  (fn pause [_self]
    (controller:set-paused true))

  (fn resume [_self]
    (controller:set-paused false))

  (fn step [_self delta-ms]
    (controller:step delta-ms))

  (fn close [_self]
    (when (not closed?)
      (set closed? true)
      (when hud-child
        (hud:remove-panel-child hud-child))
      (mount:drop))
    nil)

  (fn build-panel [_ctx _builder-options]
    descriptor)

  (set session {:mount mount
                :pause pause
                :resume resume
                :step step
                :close close})
  (set descriptor {:kind :hosted-app-workspace-panel
                   :mount mount
                   :controller controller
                   :session session
                   :builder build-panel})
  (set hud-child (hud:add-panel-child descriptor))
  session)

{:open open}
