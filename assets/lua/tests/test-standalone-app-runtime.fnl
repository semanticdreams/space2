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

(fn index-of [items needle]
  (var found nil)
  (each [i item (ipairs items) &until found]
    (when (= item needle)
      (set found i)))
  found)

(fn make-run-deps [events opts]
  (local options (if opts opts {}))
  (local engine {})
  (set engine.events {})
  (fn engine-start [_self]
    (table.insert events :engine-start)
    (not (= options.start-result false)))
  (fn engine-run [_self]
    (table.insert events :engine-run)
    (when options.on-run
      (options.on-run engine))
    (when options.run-error
      (error options.run-error)))
  (fn engine-shutdown [_self]
    (table.insert events :engine-shutdown)
    (when options.shutdown-error
      (error options.shutdown-error)))
  (set engine.start engine-start)
  (set engine.run engine-run)
  (set engine.shutdown engine-shutdown)
  (local renderer {})
  (fn renderer-update [_self]
    (table.insert events :renderer-update))
  (fn renderer-drop [_self]
    (table.insert events :renderer-drop)
    (when options.renderer-drop-error
      (error options.renderer-drop-error)))
  (set renderer.update renderer-update)
  (set renderer.drop renderer-drop)
  (fn engine-factory [_engine-options]
    (table.insert events :engine-create)
    engine)
  (fn init-renderers [_render-options]
    (table.insert events :renderer-init)
    renderer)
  {:engine engine
   :renderer renderer
   :engine-module {:Engine engine-factory}
   :bootstrap-module {:init-renderers init-renderers}})

(fn runtime-module []
  (fn create-runtime [_host]
    {:presentation {:render-targets fake-render-targets}})
  {:create create-runtime})

(fn run-with-deps [StandaloneRuntime deps module]
  (StandaloneRuntime.run {:module module
                          :engine-module deps.engine-module
                          :bootstrap-module deps.bootstrap-module}))

(fn run-with-invalid-module [StandaloneRuntime deps]
  (run-with-deps StandaloneRuntime deps {}))

(fn run-and-observe-renderers [StandaloneRuntime deps]
  (local (ok err) (pcall run-with-deps StandaloneRuntime deps (runtime-module)))
  {:ok ok :err err :restored-renderers app.renderers})

(fn run-with-viewport [StandaloneRuntime deps viewport]
  (StandaloneRuntime.run {:module (runtime-module)
                          :engine-module deps.engine-module
                          :bootstrap-module deps.bootstrap-module
                          :viewport viewport}))

(fn run-and-observe-viewport [StandaloneRuntime deps viewport]
  (local previous-viewport {:id :previous-viewport})
  (local original-viewport app.viewport)
  (set app.viewport previous-viewport)
  (local (ok err) (pcall run-with-viewport StandaloneRuntime deps viewport))
  (local result {:ok ok :err err :restored-viewport app.viewport})
  (set app.viewport original-viewport)
  result)

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

(fn test-run-starts-engine-before-renderer-init []
  (local StandaloneRuntime (load-module :standalone-app-runtime))
  (local events [])
  (local deps (make-run-deps events))
  (run-with-deps StandaloneRuntime deps (runtime-module))
  (local start-index (index-of events :engine-start))
  (local renderer-index (index-of events :renderer-init))
  (assert start-index "run must start engine")
  (assert renderer-index "run must initialize renderers")
  (assert (< start-index renderer-index)
          "run must start engine before initializing GL-backed renderers"))

(fn test-run-cleans-up-after_controller_mount_failure []
  (local StandaloneRuntime (load-module :standalone-app-runtime))
  (local events [])
  (local deps (make-run-deps events))
  (local (ok err)
    (pcall run-with-invalid-module StandaloneRuntime deps))
  (assert (not ok) "run must surface setup failure")
  (assert (string.find (tostring err) "hostable module must export create" 1 true)
          "run setup failure must include original controller error")
  (assert (index-of events :renderer-drop)
          "run must drop renderers after setup failure")
  (assert (index-of events :engine-shutdown)
          "run must shut down engine after setup failure"))

(fn test-run_reports_cleanup_failure_explicitly []
  (local StandaloneRuntime (load-module :standalone-app-runtime))
  (local events [])
  (local deps (make-run-deps events {:renderer-drop-error "renderer cleanup failed"}))
  (local (ok err)
    (pcall run-with-invalid-module StandaloneRuntime deps))
  (assert (not ok) "run must fail when setup and cleanup fail")
  (assert (string.find (tostring err) "renderer cleanup failed" 1 true)
          "run must explicitly surface cleanup failure")
  (assert (string.find (tostring err) "hostable module must export create" 1 true)
          "run cleanup failure report must retain original setup failure"))

(fn test-run-drops-partial-renderer-after_init_failure []
  (local StandaloneRuntime (load-module :standalone-app-runtime))
  (local events [])
  (local deps (make-run-deps events))
  (local original-renderers app.renderers)
  (local previous-renderers {:id :previous-renderers})
  (local renderer-field :renderers)
  (fn init-renderers [_render-options]
    (table.insert events :renderer-init)
    (tset app renderer-field deps.renderer)
    (error "renderer init failed"))
  (set deps.bootstrap-module {:init-renderers init-renderers})
  (set app.renderers previous-renderers)
  (local (protected-ok result)
    (pcall run-and-observe-renderers StandaloneRuntime deps))
  (set app.renderers original-renderers)
  (when (not protected-ok)
    (error result))
  (local ok result.ok)
  (local err result.err)
  (assert (not ok) "run must surface renderer setup failure")
  (assert (string.find (tostring err) "renderer init failed" 1 true)
          "run setup failure must include renderer init error")
  (assert (index-of events :renderer-drop)
          "run must drop renderer assigned to app.renderers before init failure")
  (assert (= result.restored-renderers previous-renderers)
          "run must restore previous app.renderers after partial renderer init failure"))

(fn test-run-sets-resizes-and-restores-app-viewport []
  (local StandaloneRuntime (load-module :standalone-app-runtime))
  (local events [])
  (local resized-signal (fake-signal))
  (local seen {:during nil :resized nil})
  (local viewport {:x 1 :y 2 :width 300 :height 200})
  (fn observe-viewport-during-run [_engine]
    (set seen.during app.viewport)
    (resized-signal:emit {:x 3 :y 4 :width 640 :height 480})
    (set seen.resized {:x app.viewport.x
                       :y app.viewport.y
                       :width app.viewport.width
                       :height app.viewport.height}))
  (local deps (make-run-deps events {:on-run observe-viewport-during-run}))
  (set deps.engine.events {:window-resized resized-signal})
  (local result (run-and-observe-viewport StandaloneRuntime deps viewport))
  (assert result.ok "standalone run should succeed with fake runtime")
  (assert (= seen.during viewport) "run must publish standalone viewport on app.viewport before event loop")
  (assert (= seen.resized.width 640) "resize must update canonical app.viewport width")
  (assert (= seen.resized.height 480) "resize must update canonical app.viewport height")
  (assert (= seen.resized.x 3) "resize must update canonical app.viewport x")
  (assert (= seen.resized.y 4) "resize must update canonical app.viewport y")
  (assert (= result.restored-viewport.id :previous-viewport) "cleanup must restore previous app.viewport"))

(fn test-renderer-drop-failure-restores-app-renderers []
  (local StandaloneRuntime (load-module :standalone-app-runtime))
  (local events [])
  (local deps (make-run-deps events {:renderer-drop-error "renderer cleanup failed"}))
  (local original-renderers app.renderers)
  (local previous-renderers {:id :previous-renderers})
  (set app.renderers previous-renderers)
  (local (protected-ok result)
    (pcall run-and-observe-renderers StandaloneRuntime deps))
  (set app.renderers original-renderers)
  (when (not protected-ok)
    (error result))
  (assert (not result.ok) "renderer drop failure must be reported")
  (assert (string.find (tostring result.err) "renderer cleanup failed" 1 true)
          "renderer drop failure must surface explicitly")
  (assert (= result.restored-renderers previous-renderers)
          "app.renderers must be restored even when renderers:drop fails"))

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
(table.insert tests {:name "standalone run starts engine before renderer init"
                     :fn test-run-starts-engine-before-renderer-init})
(table.insert tests {:name "standalone run cleans up after controller mount failure"
                     :fn test-run-cleans-up-after_controller_mount_failure})
(table.insert tests {:name "standalone run reports cleanup failure explicitly"
                     :fn test-run_reports_cleanup_failure_explicitly})
(table.insert tests {:name "standalone run drops partial renderer after init failure"
                      :fn test-run-drops-partial-renderer-after_init_failure})
(table.insert tests {:name "standalone run sets resizes and restores app viewport"
                      :fn test-run-sets-resizes-and-restores-app-viewport})
(table.insert tests {:name "standalone renderer drop failure restores app renderers"
                      :fn test-renderer-drop-failure-restores-app-renderers})

;; StandaloneRuntime.run real window/GL behavior remains covered by standalone
;; launch commands; this suite uses fakes for startup ordering and cleanup
;; boundary behavior that can be verified headlessly.

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "standalone-app-runtime"
                       :tests tests})))

{:name "standalone-app-runtime"
 :tests tests
 :main main}
