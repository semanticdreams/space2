(local Capabilities (require :app-host.capabilities))

(fn host-error [message]
  (error (.. "[app-host] " message)))

(fn require-function [service capability method]
  (local fn-value (. service method))
  (if (= (type fn-value) :function)
      fn-value
      (host-error (.. "capability " (tostring capability) " missing method: " (tostring method)))))

(fn load-module [opts]
  (if opts.module
      opts.module
      (do
        (local module-name (. opts :module-name))
        (if module-name
            (require module-name)
            (host-error "RuntimeController.create requires :module or :module-name")))))

(fn facet-list [runtime name]
  (local facets (. runtime name))
  (if (= facets nil)
      []
      facets))

(fn register-facet-list [host capability facets]
  (when (> (# facets) 0)
    (local service (Capabilities.require host capability))
    (local register (require-function service capability :register))
    (each [_ facet (ipairs facets)]
      (register service facet))))

(fn create [opts]
  (when (= opts nil)
    (host-error "RuntimeController.create requires options"))
  (local options opts)
  (local host
    (if options.host
        options.host
        (host-error "RuntimeController.create requires :host")))
  (local module (load-module options))
  (when (not (= (type module.create) :function))
    (host-error "hostable module must export create(host)"))
  (local scheduler-service (Capabilities.require host :scheduler))
  (local runtime (module.create host))
  (when (not (= (type runtime) :table))
    (host-error "hostable module create(host) must return a runtime table"))
  (local inspectors (facet-list runtime :inspectors))
  (local commands (facet-list runtime :commands))
  (local scheduler runtime.scheduler)
  (var dropped? false)

  (when scheduler
    (local register (require-function scheduler-service :scheduler :register))
    (register scheduler-service scheduler))
  (register-facet-list host :inspectors inspectors)
  (register-facet-list host :commands commands)

  (fn controller-runtime [_self]
    runtime)

  (fn render-targets [_self]
    (local presentation runtime.presentation)
    (if (and presentation (= (type presentation.render-targets) :function))
        (presentation:render-targets)
        []))

  (fn update [_self delta-ms]
    (local scheduler-update (require-function scheduler-service :scheduler :update))
    (scheduler-update scheduler-service delta-ms))

  (fn set-paused [_self paused]
    (local pause-fn (require-function scheduler-service :scheduler :set-paused))
    (pause-fn scheduler-service paused))

  (fn step [_self delta-ms]
    (local step-fn (require-function scheduler-service :scheduler :step))
    (step-fn scheduler-service delta-ms))

  (fn runtime-inspectors [_self]
    inspectors)

  (fn runtime-commands [_self]
    commands)

  (fn drop [_self]
    (when (not dropped?)
      (set dropped? true)
      (local lifecycle runtime.lifecycle)
      (when (and lifecycle (= (type lifecycle.drop) :function))
        (lifecycle:drop))))

  {:runtime controller-runtime
   :render-targets render-targets
   :update update
   :set-paused set-paused
   :step step
   :inspectors runtime-inspectors
   :commands runtime-commands
   :drop drop})

{:create create}
