(local tests [])

(fn load-module [name]
  (local (ok module-or-error) (pcall require name))
  (assert ok (.. "expected module " (tostring name) " to load, got: " (tostring module-or-error)))
  module-or-error)

(fn fake-scheduler-register [self facet]
  (table.insert self.registered facet))

(fn fake-noop [_self _value]
  nil)

(fn fake-render-targets [_self]
  [:target])

(fn scheduled-update [_self delta-ms state]
  (set state.updated-delta delta-ms))

(fn fake-signal []
  (local signal {:handlers []})
  (set signal.connect
       (fn [self handler]
         (table.insert self.handlers handler)
         handler))
  (set signal.disconnect
       (fn [self handler _quiet]
         (for [i (# self.handlers) 1 -1]
           (when (= (. self.handlers i) handler)
             (table.remove self.handlers i)))
         true))
  (set signal.emit
       (fn [self payload]
         (each [_ handler (ipairs self.handlers)]
           (handler payload))))
  signal)

(fn test-hosted-mount-returns-runtime-controller []
  (local HostedRuntime (load-module :hosted-app-runtime))
  (var create-host nil)
  (local module
    {:create (fn [host]
               (set create-host host)
               {:presentation {:render-targets fake-render-targets}})})
  (local host
    {:scheduler {:registered []
                 :register fake-scheduler-register
                 :update fake-noop
                 :set-paused fake-noop
                 :step fake-noop}
     :inspectors {:register fake-noop}
     :commands {:register fake-noop}})
  (local controller (HostedRuntime.mount {:module module :host host}))
  (assert controller "mount must return a runtime controller")
  (assert (= create-host host) "mount must pass the supplied host to module.create via RuntimeController")
  (local targets (controller:render-targets))
  (assert (= (. targets 1) :target) "controller returned by mount must delegate runtime presentation"))

(fn test-create-host-exposes-required-capabilities []
  (local StandaloneRuntime (load-module :standalone-app-runtime))
  (local host (StandaloneRuntime.create-host {:viewport {:x 0 :y 0 :width 100 :height 100}}))
  (each [_ name (ipairs [:viewport :surfaces :presentation :scheduler :input :inspectors :commands :assets :logging :lifecycle])]
    (assert (. host name) (.. "missing host capability " (tostring name)))))

(fn test-create-host-registries-store-inspectors-and-commands []
  (local StandaloneRuntime (load-module :standalone-app-runtime))
  (local host (StandaloneRuntime.create-host {:viewport {:x 0 :y 0 :width 100 :height 100}}))
  (local inspector {:id :inspector})
  (local command {:id :command})
  (host.inspectors:register inspector)
  (host.commands:register command)
  (assert (= (. (host.inspectors:list) 1) inspector) "inspectors registry must store registered facets")
  (assert (= (. (host.commands:list) 1) command) "commands registry must store registered facets"))

(fn test-create-host-scheduler-runs-registered-updates []
  (local StandaloneRuntime (load-module :standalone-app-runtime))
  (local host (StandaloneRuntime.create-host {:viewport {:x 0 :y 0 :width 100 :height 100}}))
  (local state {:updated-delta nil})
  (host.scheduler:register {:update (fn [self delta-ms]
                                      (scheduled-update self delta-ms state))})
  (host.scheduler:update 16)
  (assert (= state.updated-delta 16) "scheduler must update registered runtime facets"))

(fn test-create-host-engine-update-drives-scheduler-and-renderers []
  (local StandaloneRuntime (load-module :standalone-app-runtime))
  (local updated-signal (fake-signal))
  (local engine {:events {:updated updated-signal}})
  (local render-state {:updated? false})
  (local renderers {:update (fn [_self]
                              (set render-state.updated? true))})
  (local host (StandaloneRuntime.create-host {:viewport {:x 0 :y 0 :width 100 :height 100}
                                             :engine engine
                                             :renderers renderers}))
  (local scheduler-state {:updated-delta nil})
  (host.scheduler:register {:update (fn [self delta-ms]
                                      (scheduled-update self delta-ms scheduler-state))})
  (updated-signal:emit 33)
  (assert (= scheduler-state.updated-delta 33)
          "engine updated signal must drive host scheduler")
  (assert render-state.updated?
          "engine updated signal must drive standalone-owned renderers"))

(table.insert tests {:name "hosted mount returns runtime controller"
                     :fn test-hosted-mount-returns-runtime-controller})
(table.insert tests {:name "standalone create-host exposes required capabilities"
                     :fn test-create-host-exposes-required-capabilities})
(table.insert tests {:name "standalone registries store inspectors and commands"
                     :fn test-create-host-registries-store-inspectors-and-commands})
(table.insert tests {:name "standalone scheduler runs registered updates"
                     :fn test-create-host-scheduler-runs-registered-updates})
(table.insert tests {:name "standalone engine update drives scheduler and renderers"
                     :fn test-create-host-engine-update-drives-scheduler-and-renderers})

;; StandaloneRuntime.run owns real Engine construction, window start, event loop,
;; renderer drop, and engine shutdown. Those boundaries require a real engine and
;; remain covered by standalone launch commands rather than this headless host
;; construction suite.

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "standalone-app-runtime"
                       :tests tests})))

{:name "standalone-app-runtime"
 :tests tests
 :main main}
