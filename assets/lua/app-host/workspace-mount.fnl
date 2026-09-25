(local HostedRuntime (require :hosted-app-runtime))
(local SpaceHost (require :app-host.space-host))

(fn mount-error [message]
  (error (.. "[app-host.workspace-mount] " message)))

(fn ensure-mount-list [runtime]
  (when (not runtime)
    (mount-error "mount requires :runtime"))
  (when (= runtime.hosted-app-mounts nil)
    (set runtime.hosted-app-mounts []))
  (when (not (= (type runtime.hosted-app-mounts) :table))
    (mount-error "runtime.hosted-app-mounts must be a table"))
  runtime.hosted-app-mounts)

(fn remove-mount [mounts mount]
  (var removed? false)
  (for [i (# mounts) 1 -1]
    (when (= (. mounts i) mount)
      (table.remove mounts i)
      (set removed? true)))
  removed?)

(fn note-error [state err]
  (when (not state.err)
    (set state.err err)))

(fn teardown-step [state cb]
  (local (ok err) (pcall cb))
  (when (not ok)
    (note-error state err)))

(fn drop-host [host]
  (host:drop))

(fn mount [opts]
  (when (= opts nil)
    (mount-error "mount requires options"))
  (local options opts)
  (local runtime options.runtime)
  (local mounts (ensure-mount-list runtime))
  (var dropped? false)
  (var mount nil)
  (var pending-close? false)
  (fn quit-host [_host]
    (if mount
        (mount:drop)
        (set pending-close? true)))
  (local host (SpaceHost.create {:runtime runtime
                                 :app options.app
                                 :viewport options.viewport
                                 :engine options.engine
                                 :asset-path-resolver options.asset-path-resolver
                                 :on-quit quit-host}))
  (fn create-controller []
    (HostedRuntime.mount {:module options.module
                          :module-name options.module-name
                          :host host}))
  (local (controller-ok? controller-or-err) (pcall create-controller))
  (when (not controller-ok?)
    (local cleanup-state {})
    (teardown-step cleanup-state #(drop-host host))
    (error controller-or-err))
  (local controller controller-or-err)

  (fn render-targets [_self]
    (if dropped?
        []
        (controller:render-targets)))

  (fn drop [_self]
    (when (not dropped?)
      (set dropped? true)
      (remove-mount mounts mount)
      (local teardown-state {})
      (fn drop-controller []
        (controller:drop))
      (teardown-step teardown-state drop-controller)
      (teardown-step teardown-state #(drop-host host))
      (when teardown-state.err
        (error teardown-state.err)))
    nil)

  (set mount {:controller controller
              :host host
              :render-targets render-targets
              :drop drop})
  (table.insert mounts mount)
  (when pending-close?
    (mount:drop))
  mount)

{:mount mount}
