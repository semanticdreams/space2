(local RuntimeController (require :app-host.runtime-controller))

(fn mount [opts]
  (when (= opts nil)
    (error "HostedAppRuntime.mount requires options"))
  (RuntimeController.create opts))

(fn mount-in-workspace [opts]
  (local WorkspaceMount (require :app-host.workspace-mount))
  (WorkspaceMount.mount opts))

{:mount mount
 :mount-in-workspace mount-in-workspace}
