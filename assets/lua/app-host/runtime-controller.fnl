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

(fn integer? [value]
  (and (= (type value) :number)
       (= value (math.floor value))))

(fn sequential-list? [value]
  (if (not (= (type value) :table))
      false
      (do
        (local count (# value))
        (var valid? true)
        (each [key _item (pairs value)]
          (if (not (integer? key))
              (set valid? false)
              (< key 1)
              (set valid? false)
              (> key count)
              (set valid? false)))
        valid?)))

(fn validate-presentation [runtime]
  (local presentation runtime.presentation)
  (when presentation
    (when (not (= (type presentation) :table))
      (host-error "runtime presentation facet must be a table"))
    (when (not (= (type presentation.render-targets) :function))
      (host-error "runtime presentation facet requires render-targets function"))))

(fn validate-facet-list [runtime name]
  (local facets (facet-list runtime name))
  (when (not (sequential-list? facets))
    (host-error (.. "runtime " (tostring name) " facet must be a sequential list")))
  facets)

(fn validate-scheduler [runtime]
  (local scheduler runtime.scheduler)
  (when scheduler
    (when (not (= (type scheduler) :table))
      (host-error "runtime scheduler facet must be a table"))
    (when (not (= (type scheduler.update) :function))
      (host-error "runtime scheduler facet requires update function")))
  scheduler)

(fn register-facet-list [host capability facets registered]
  (when (> (# facets) 0)
    (local service (Capabilities.require host capability))
    (local register (require-function service capability :register))
    (each [_ facet (ipairs facets)]
      (register service facet)
      (table.insert registered {:capability capability :service service :facet facet}))))

(fn unregister-facet [registration]
  (local service registration.service)
  (local unregister service.unregister)
  (when unregister
    (when (not (= (type unregister) :function))
      (host-error (.. "capability " (tostring registration.capability) " invalid method: unregister")))
    (unregister service registration.facet)))

(fn note-error [state err]
  (when (not state.err)
    (set state.err err)))

(fn teardown-step [state cb]
  (local (ok err) (pcall cb))
  (when (not ok)
    (note-error state err)))

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
  (validate-presentation runtime)
  (local inspectors (validate-facet-list runtime :inspectors))
  (local commands (validate-facet-list runtime :commands))
  (local scheduler (validate-scheduler runtime))
  (local registered [])
  (var dropped? false)

  (when scheduler
    (local register (require-function scheduler-service :scheduler :register))
    (register scheduler-service scheduler)
    (table.insert registered {:capability :scheduler :service scheduler-service :facet scheduler}))
  (register-facet-list host :inspectors inspectors registered)
  (register-facet-list host :commands commands registered)

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
      (local teardown-state {})
      (for [i (# registered) 1 -1]
        (local registration (. registered i))
        (teardown-step teardown-state #(unregister-facet registration))
        (table.remove registered i))
      (local lifecycle runtime.lifecycle)
      (when (and lifecycle (= (type lifecycle.drop) :function))
        (teardown-step teardown-state #(lifecycle:drop)))
      (when teardown-state.err
        (error teardown-state.err))))

  {:runtime controller-runtime
   :render-targets render-targets
   :update update
   :set-paused set-paused
   :step step
   :inspectors runtime-inspectors
   :commands runtime-commands
   :drop drop})

{:create create}
