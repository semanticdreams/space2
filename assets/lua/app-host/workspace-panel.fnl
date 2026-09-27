(local WorkspaceMount (require :app-host.workspace-mount))
(local Snapshot (require :app-host.workspace-inspector-snapshot))
(local CommandRunner (require :app-host.command-runner))
(local CommandControls (require :app-host.workspace-command-controls))

(fn panel-error [message]
  (error (.. "[app-host.workspace-panel] " message)))

(fn remove-active-async-handle [active-async-handles handle]
  (when handle
    (tset active-async-handles handle nil)))

(fn make-async-callbacks [active-async-handles callbacks current-handle]
  {:on-progress callbacks.on-progress
   :on-result (fn [result]
                (remove-active-async-handle active-async-handles current-handle.handle)
                (callbacks.on-result result))})

(fn drop-async-handle [handle]
  (handle:drop))

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
  (local active-async-handles {})
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

  (fn read-inspector-snapshot [_self]
    (Snapshot.read-host mount.host))

  (fn run-command [_self command-id payload]
    (CommandRunner.run-host mount.host command-id payload))

  (fn run-command-async [_self command-id payload callbacks]
    (local current-handle {:handle nil})
    (local wrapped-callbacks (make-async-callbacks active-async-handles callbacks current-handle))
    (local handle (CommandRunner.run-host-async mount.host command-id payload wrapped-callbacks))
    (set current-handle.handle handle)
    (when (= handle.status :running)
      (tset active-async-handles handle true))
    handle)

  (fn drop-active-async-handles []
    (var first-error nil)
    (each [handle _ (pairs active-async-handles)]
      (local (ok err) (pcall drop-async-handle handle))
      (when (and (not ok) (= first-error nil))
        (set first-error err)))
    (each [handle _ (pairs active-async-handles)]
      (tset active-async-handles handle nil))
    first-error)

  (fn close [_self]
    (when (not closed?)
      (set closed? true)
      (local cleanup-error (drop-active-async-handles))
      (when hud-child
        (hud:remove-panel-child hud-child))
      (mount:drop)
      (when cleanup-error
        (error cleanup-error)))
    nil)

  (fn build-panel [ctx _builder-options]
    (local builder (CommandControls.WorkspaceCommandControls {:descriptor descriptor}))
    (builder ctx))

  (fn add-panel-descriptor []
    (hud:add-panel-child descriptor))

  (fn drop-mounted-app []
    (mount:drop))

  (set session {:mount mount
                 :pause pause
                 :resume resume
                  :step step
                  :read-inspector-snapshot read-inspector-snapshot
                  :run-command run-command
                  :run-command-async run-command-async
                  :close close})
  (set descriptor {:kind :hosted-app-workspace-panel
                   :mount mount
                   :controller controller
                    :session session
                    :read-inspector-snapshot read-inspector-snapshot
                    :run-command run-command
                    :run-command-async run-command-async
                    :builder build-panel})
  (local (child-ok? child-or-err) (pcall add-panel-descriptor))
  (if child-ok?
      (set hud-child child-or-err)
      (do
        (pcall drop-mounted-app)
        (error child-or-err)))
  session)

{:open open}
