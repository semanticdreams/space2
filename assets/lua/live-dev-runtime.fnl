(local callbacks (require :callbacks))
(local fennel (require :fennel))
(local fs (require :fs))
(local HotReload (require :hot-reload))
(local RemoteControl (require :remote-control))
(local JsonUtils (require :json-utils))
(local CliArgs (require :cli-args))

;; This is the single restart boundary, including retained Fennel dependencies.
;; Native modules are process-owned already and have no reloadable source here.
(local preserved-modules
  ["live-dev-runtime" "remote-control" "fennel-evaluator" "hot-reload"
   "units" "fennel-cache" "path-utils" "json-utils" "fennel" "cli-args"])
(var active nil)
(var active-recipe nil)

(fn copy [value]
  (if (not= (type value) :table) value
      (do
        (local out {})
        (each [k v (pairs value)] (tset out k (copy v)))
        out)))

(fn status [s]
  (local result (copy s.identity))
  (each [k v (pairs {:schema-version 1 :ready s.ready :mode s.mode
                     :generation s.generation :next-request-id (+ s.high-water 1)
                     :endpoint (if (= s.endpoint nil) false s.endpoint) :faulted s.faulted
                     :error s.error :capabilities ["manual" "reload" "quit" "launch-recipe"]})]
    (tset result k v))
  result)

(fn publish! [s]
  (s.opts.publisher (status s)))

(fn fault! [s err]
  (set s.faulted true)
  (set s.ready false)
  (set s.error (tostring err)))

(fn retain! [s op]
  (set op.generation s.generation)
  (table.insert s.terminal op.request-id)
  (when (> (# s.terminal) 64)
    (tset s.operations (table.remove s.terminal 1) nil))
  (set s.pending nil))

(fn fail! [s op err recovery?]
  (set op.status "failed")
  (set op.error (tostring err))
  (set op.recovery-required (= recovery? true))
  (when recovery? (fault! s err)))

(fn check-health! [s]
  (assert (= (s.opts.health-check) true) "runtime health check failed"))

(fn reload! [s op]
  (set op.phase "reload")
  (local result (if (= op.action "watch-reload") (s.controller:reload-pending!)
                   (s.controller:reload-root!)))
  (assert (= (type result) :table) "controller did not return ReloadResult")
  (set op.phase result.phase)
  (set op.rollback result.rollback)
  (set op.rollback-error (if (= result.rollback-error nil) false result.rollback-error))
  (if (not result.ok)
      (do
        (fail! s op result.error (= result.rollback "failed"))
        (when (not s.faulted)
          (local (ok err) (pcall check-health! s))
          (when (not ok)
            (set op.phase "health")
            (fail! s op err true))))
      (do
        (set op.phase "health")
        (check-health! s)
        (when (= result.target-unit-id "app-root")
          (set s.generation (+ s.generation 1)))
        (set s.ready true))))

(fn execute-action! [s op]
  (when (not= op.action "quit")
    (set op.phase "restart-required")
    (assert (s.opts.boundary-check) "restart-required: preserved infrastructure changed")
    (set op.phase "publish")
    (publish! s))
  (if (or (= op.action "reload") (= op.action "watch-reload")) (reload! s op)
      (= op.action "manual")
      (do
        (set op.phase "manual")
        (s.controller:use-manual!)
        (set s.mode "manual"))
      (= op.action "quit")
      (do (set op.phase "quit") (s.opts.quit)))
  (when (not= op.status "failed")
    (set op.status "succeeded")
    (set op.phase "complete"))
  (set op.phase (if (= op.status "failed") op.phase "publish"))
  (publish! s)
  (when (= op.status "succeeded") (set op.phase "complete")))

(fn execute-pending! [s]
  (when (and (not s.dropped) s.pending)
    (local op s.pending)
    (if (and s.faulted (not= op.action "quit"))
        (do
          (set op.phase "faulted")
          (fail! s op s.error true))
        (do
          (set op.status "running")
          (local (ok err) (pcall execute-action! s op))
          (when (not ok)
            (fail! s op err (not= op.phase "restart-required")))))
    (retain! s op)))

(fn poll! [s]
  (when (not s.dropped)
    (when s.transport (s.transport:tick 1))
    (when (and (not s.dropped) (not s.faulted) (not s.pending)) (s.controller:update 0))))

(fn request! [s id action]
  (assert (and s.started (not s.dropped)) "live-dev runtime is not running")
  (assert (and (= (type id) :number) (= id (math.floor id)) (> id 0)
               (< id 9007199254740991)) "request-id must be a positive safe integer")
  (local retained (. s.operations id))
  (if retained (copy retained)
      (do
        (assert (> id s.high-water) "request-id expired")
        (assert (not s.pending) "operation already pending or running")
        (assert (or (= action "manual") (= action "reload") (= action "watch-reload") (= action "quit")) "unknown action")
        (assert (or (= action "quit") (and s.ready (not s.faulted))) "runtime not healthy; restart required")
        (local op {:request-id id :action action :instance-id s.identity.instance-id
                   :generation s.generation :status "pending" :phase "queued"
                   :error false :rollback "not-needed" :rollback-error false :recovery-required false})
        (set s.high-water id)
        (tset s.operations id op)
        (set s.pending op)
        (callbacks.enqueue s.operation-id true)
        (copy op))))

(fn drop! [s]
  (when (not s.dropped)
    (set s.dropped true)
    (set s.ready false)
    (when s.pending
      (fail! s s.pending "runtime dropped before operation completed" false)
      (retain! s s.pending))
    (when s.poll-id (callbacks.unregister s.poll-id))
    (when s.operation-id (callbacks.unregister s.operation-id))
    (local errors [])
    (fn cleanup [f owner]
      (local (ok err) (pcall f owner))
      (when (not ok) (table.insert errors (tostring err))))
    (when s.transport (cleanup s.transport.drop s.transport))
    (cleanup s.controller.drop s.controller)
    (cleanup s.opts.unpublish)
    (assert (= (# errors) 0) (table.concat errors "\n")))
  true)

(fn LiveDevRuntime [opts]
  (assert opts.identity.instance-id "live-dev runtime requires instance identity")
  (each [_ key (ipairs [:publisher :unpublish :health-check :boundary-check :quit :launch-recipe])]
    (assert (= (type (. opts key)) :function) (.. "live-dev runtime requires " key)))
  (local s {:opts opts :identity (copy opts.identity) :controller (assert opts.controller)
            :transport opts.transport :endpoint opts.endpoint :ready false :faulted false
            :mode (or opts.mode "manual") :generation 0 :high-water 0
            :operations {} :terminal [] :started false :dropped false})
  (fn operation-callback [_payload] (execute-pending! s))
  (fn poll-callback [_payload]
    (local (ok err) (pcall poll! s))
    (when (not ok) (fault! s err))
    (when (not s.dropped) (callbacks.enqueue s.poll-id true)))
  (fn start [_self]
    (assert (not s.dropped) "cannot start dropped live-dev runtime")
    (when (not s.started)
      (set s.started true)
      (set s.operation-id (callbacks.register operation-callback))
      (set s.poll-id (callbacks.register poll-callback))
      (publish! s)
      (callbacks.enqueue s.poll-id true))
    true)
  (fn mark-ready! [_self]
    (assert (and s.started (not s.dropped) (not s.ready)) "invalid ready transition")
    (local (ok err) (pcall check-health! s))
    (when (not ok) (fault! s err) (error err))
    (set s.generation (+ s.generation 1))
    (set s.ready true)
    (publish! s)
    true)
  (fn operation [_self id]
    (copy (assert (. s.operations id) "unknown or expired request-id")))
  (fn describe [_self] (status s))
  (fn request [_self id action]
    (assert (not= action "watch-reload") "watch scheduling is internal")
    (request! s id action))
  (fn request-watched! [_self] (request! s (+ s.high-water 1) "watch-reload"))
  (fn faulted? [_self] s.faulted)
  (fn drop [_self] (drop! s))
  {:start start :mark-ready! mark-ready! :status describe :request request
   :request-watched! request-watched! :operation operation :faulted? faulted? :drop drop})

(fn current [] active)
(fn stop! []
  (local previous active)
  (set active nil)
  (set active-recipe nil)
  (when previous
    (set app.hot-reload-controller nil)
    (set app.remote-control nil)
    (set app.remote-control-endpoint nil)
    (previous:drop))
  true)

;; Startup adapters are deliberately bounded: fixed source files, no watching or
;; dependency graph, and self-only executable identity from the native bootstrap.
(fn capture-boundary [bootstrap identity]
  (local files {})
  (each [_ name (ipairs preserved-modules)]
    (local path (assert (or (fennel.search-module name) (package.searchpath name package.path))
                        (.. "cannot resolve retained infrastructure source: " name)))
    (tset files name {:path (fs.absolute path) :bytes (fs.read-file path)}))
  (local macros-path (assert (fennel.search-module "macros") "cannot resolve macros.fnl"))
  (tset files "macros" {:path (fs.absolute macros-path) :bytes (fs.read-file macros-path)})
  (fn unchanged? []
    (each [name entry (pairs files)]
      (local path (or (fennel.search-module name) (package.searchpath name package.path)))
      (assert (and path (= (fs.absolute path) entry.path)
                   (= (fs.read-file path) entry.bytes))
              (.. "restart-required: changed " name)))
    (when (and bootstrap identity.executable-identity)
      (local now (bootstrap.describe-source identity.main-source))
      (assert (= now.executable-identity identity.executable-identity)
              "restart-required: executable changed"))
    true)
  unchanged?)

(fn startup-endpoint [options]
  (local result
    (CliArgs.parse {:name "space" :allow-unknown? true :add-help? false
                    :options [{:key "remote-control" :long "remote-control" :takes-value? true}]}
                   (or options.args _G.arg [])))
  (assert result.ok (or result.error "invalid remote control arguments"))
  (or options.endpoint (. result.values "remote-control")))

(fn start! [bootstrap opts]
  (assert (not active) "live-dev runtime already started")
  (local options (or opts {}))
  (local main-source (assert (fennel.search-module "main") "cannot resolve main source"))
  (local identity (if bootstrap (bootstrap.describe-source main-source)
                      {:instance-id ((. (require :uuid) :v4)) :main-source main-source
                       :source-root (fs.parent main-source)}))
  (local paths (and bootstrap identity.checkout-root
                   (bootstrap.private-paths identity.checkout-root identity.instance-id)))
  (local requested-endpoint (startup-endpoint options))
  (local endpoint
    (if (= requested-endpoint "auto")
        (assert (and paths paths.endpoint) "auto remote control requires private checkout paths")
        requested-endpoint requested-endpoint
        (and paths paths.endpoint)))
  (local boundary-check (capture-boundary bootstrap identity))
  (local config (or options.reload-config {}))
  (local preserve (copy preserved-modules))
  (each [_ name (ipairs (or config.preserve-modules []))] (table.insert preserve name))
  (fn requested [_controller]
    (when active (active:request-watched!)))
  (fn live-children [_root]
    (if app.unit-manager (app.unit-manager:list) []))
  (local controller
    (HotReload.AppRootController {:watch-paths (or config.watch-paths [identity.source-root])
                                 :watch? (= config.enabled true) :debounce-ms config.debounce-ms
                                  :generic? config.generic? :preserve-modules preserve
                                  :narrow-reload-unit-ids config.narrow-reload-unit-ids
                                  :units-fn live-children :on-reload-requested requested}))
  (fn health-check [] (assert app.check-runtime-health "missing current runtime health check") (app.check-runtime-health))
  (fn publish [record]
    (when paths
      (bootstrap.protect-file (.. paths.record ".tmp"))
      (JsonUtils.write-json! paths.record record)
      (bootstrap.protect-file paths.record)))
  (fn unpublish []
    (when paths
      (when (fs.exists paths.record) (fs.remove paths.record))
      (when (fs.exists (.. paths.record ".tmp")) (fs.remove (.. paths.record ".tmp")))))
  (fn recipe []
    (assert bootstrap "native launch recipe unavailable")
    (bootstrap.launch-recipe))
  (fn quit [] (assert app.engine.quit "engine quit unavailable") (app.engine.quit))
  (var transport nil)
  (fn install []
    (when endpoint (set transport (RemoteControl {:endpoint endpoint})))
    (set active (LiveDevRuntime {:identity identity :controller controller :transport transport
                                :endpoint endpoint :mode (if config.enabled "watch" "manual")
                                :health-check health-check :publisher publish :unpublish unpublish
                                :launch-recipe recipe :boundary-check boundary-check :quit quit}))
    (set active-recipe recipe)
    (active:start))
  (local (ok err) (pcall install))
  (when (not ok)
    (if active (stop!)
        (do (when transport (transport:drop)) (controller:drop)))
    (error err))
  ;; Borrowed inspection references. Root init/drop never own these objects.
  (set app.hot-reload-controller controller)
  (set app.remote-control transport)
  (set app.remote-control-endpoint endpoint)
  active)

(fn rpc [request]
  (assert active "live-dev runtime unavailable")
  (assert (= request.expected-instance-id (. (active:status) :instance-id)) "instance identity mismatch")
  (if (= request.action "status") (active:status)
      (= request.action "operation") (active:operation request.request-id)
      (= request.action "launch-recipe")
      ((assert active-recipe "private launch recipe unavailable"))
      (active:request request.request-id request.action)))

{:LiveDevRuntime LiveDevRuntime :start! start! :current current :stop! stop!
 :rpc rpc :preserved-modules preserved-modules}
