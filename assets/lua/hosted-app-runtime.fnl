(local RuntimeController (require :app-host.runtime-controller))

(fn mount [opts]
  (when (= opts nil)
    (error "HostedAppRuntime.mount requires options"))
  (RuntimeController.create opts))

{:mount mount}
