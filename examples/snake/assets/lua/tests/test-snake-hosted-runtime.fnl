(local Runner (require :tests/runner))
(local RuntimeController (require :app-host.runtime-controller))
(local HostedRuntime (require :hosted-app-runtime))
(local StandaloneRuntime (require :standalone-app-runtime))
(local SnakeMain (require :main))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn copy-list [items]
  (local out [])
  (each [_ item (ipairs items)]
    (table.insert out item))
  out)

(fn make-registry [opts]
  (local options (if opts opts {}))
  (local items [])
  {:items items
   :register (fn [_self item]
               (when options.on-register
                 (options.on-register item))
               (table.insert items item)
               item)
   :unregister (fn [_self item]
                 (var removed? false)
                 (for [i (# items) 1 -1]
                   (when (= (. items i) item)
                     (table.remove items i)
                     (set removed? true)))
                 removed?)
   :list (fn [_self]
           (copy-list items))})

(fn make-scheduler []
  (local registrations [])
  (var paused? false)
  {:registrations registrations
   :register (fn [_self facet]
               (table.insert registrations facet)
               facet)
   :unregister (fn [_self facet]
                 (var removed? false)
                 (for [i (# registrations) 1 -1]
                   (when (= (. registrations i) facet)
                     (table.remove registrations i)
                     (set removed? true)))
                 removed?)
   :update (fn [_self delta-ms]
             (when (not paused?)
               (each [_ facet (ipairs registrations)]
                 (when (and facet facet.update)
                   (facet:update delta-ms))))
             true)
   :set-paused (fn [_self next-paused]
                 (set paused? (not (not next-paused)))
                 paused?)
   :step (fn [_self delta-ms]
           (each [_ facet (ipairs registrations)]
             (when (and facet facet.update)
               (facet:update delta-ms)))
           true)})

(fn make-input []
  (local handlers [])
  {:handlers handlers
   :register (fn [_self handler]
               (table.insert handlers handler)
               handler)
   :unregister (fn [_self handler]
                 (var removed? false)
                 (for [i (# handlers) 1 -1]
                   (when (= (. handlers i) handler)
                     (table.remove handlers i)
                     (set removed? true)))
                 removed?)
   :dispatch (fn [_self event-name payload]
               (each [_ handler (ipairs handlers)]
                 (local cb (. handler event-name))
                 (when (= (type cb) :function)
                   (cb handler payload)))
               true)})

(fn fake-host [opts]
  (local options (if opts opts {}))
  {:viewport {:x 0 :y 0 :width 800 :height 600}
   :scheduler (make-scheduler)
   :input (make-input)
   :inspectors (make-registry)
   :commands (make-registry)
   :surfaces (make-registry {:on-register options.on-surface-register})
   :lifecycle {:quit (fn [_self]
                       (set options.quit-count (+ (or options.quit-count 0) 1)))}})

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

(fn make-quit-engine []
  (local state {:quit-count 0})
  (local engine {:events {:key-down (fake-signal)}})
  (set engine.quit (fn [_self]
                     (set state.quit-count (+ state.quit-count 1))))
  (values engine state))

(fn assert-one-target [controller label]
  (local targets (controller:render-targets))
  (assert (= (# targets) 1) (.. label " should expose one presentation target"))
  (assert (. targets 1) (.. label " should expose a concrete presentation target")))

(fn snake-state [inspector]
  (assert (= (type inspector.read) :function) "snake inspector should expose read")
  (inspector:read))

(fn assert-state-shape [state]
  (assert (= (type state.score) :number) "inspector should expose numeric score")
  (assert (= (type state.head) :table) "inspector should expose head")
  (assert (= (type state.snake) :table) "inspector should expose snake body")
  (assert (= (type state.food) :table) "inspector should expose food")
  (assert (not (= state.game-over? nil)) "inspector should expose game-over state"))

(fn test-snake-create-returns-runtime-facets []
  (local host (fake-host))
  (local runtime (SnakeMain.create host))
  (assert (= runtime.metadata.id "examples.snake") "runtime metadata should identify Snake")
  (assert (= (type runtime.presentation.render-targets) :function) "runtime should expose presentation facet")
  (assert (= (type runtime.lifecycle.drop) :function) "runtime should expose lifecycle drop facet")
  (runtime.lifecycle:drop))

(fn test-controller-mounts-snake-runtime []
  (local host (fake-host))
  (local controller (RuntimeController.create {:module SnakeMain :host host}))
  (assert-one-target controller "mounted Snake runtime")
  (assert (= (# host.inspectors.items) 1) "host inspector registry should receive Snake inspector")
  (local state (snake-state (. host.inspectors.items 1)))
  (assert-state-shape state)
  (controller:drop))

(fn test-pause-blocks-simulation-keeps-presentation []
  (local host (fake-host))
  (local controller (RuntimeController.create {:module SnakeMain :host host}))
  (local inspector (. host.inspectors.items 1))
  (local before (snake-state inspector))
  (controller:set-paused true)
  (controller:update 300)
  (local paused (snake-state inspector))
  (assert (= paused.head.x before.head.x) "paused scheduler should block Snake movement")
  (assert (= paused.head.y before.head.y) "paused scheduler should keep Snake head row stable")
  (assert-one-target controller "paused Snake runtime")
  (controller:set-paused false)
  (controller:update 150)
  (local after (snake-state inspector))
  (assert (> after.head.x before.head.x) "unpaused scheduler should advance Snake movement")
  (controller:drop))

(fn test-quit-key-uses-standalone-host-lifecycle []
  (local (engine state) (make-quit-engine))
  (local host (StandaloneRuntime.create-host {:engine engine
                                             :viewport {:x 0 :y 0 :width 800 :height 600}}))
  (local controller (RuntimeController.create {:module SnakeMain :host host}))
  (host.input:dispatch :key-down {:key 113})
  (assert (= state.quit-count 1) "Q key should quit through standalone host lifecycle")
  (host.input:dispatch :key-down {:key 27})
  (assert (= state.quit-count 2) "Escape key should quit through standalone host lifecycle")
  (controller:drop)
  (host.lifecycle:disconnect))

(fn test-invalid-host-leaves-no-partial-registrations []
  (local host {:viewport {:x 0 :y 0 :width 800 :height 600}
               :scheduler (make-scheduler)
               :input {}
               :inspectors (make-registry)
               :surfaces (make-registry)
               :lifecycle {:quit (fn [_self] nil)}})
  (local (ok err) (pcall SnakeMain.create host))
  (assert (not ok) "invalid host should fail composition")
  (assert (string.find (tostring err) "input" 1 true) "invalid host error should name input capability")
  (assert (= (# host.scheduler.registrations) 0) "invalid host should not retain scheduler registration"))

(fn test-missing-viewport-errors-loudly []
  (local host (fake-host))
  (set host.viewport nil)
  (local (ok err) (pcall #(SnakeMain.create host)))
  (assert (not ok) "Snake create must fail when required viewport capability is missing")
  (assert (string.find (tostring err) "viewport" 1 true) "missing viewport error should name viewport capability"))

(fn test-drop-is-idempotent-and-drops-owned-surface-once []
  (var registered-surface nil)
  (local host (fake-host {:on-surface-register (fn [surface]
                                                (set registered-surface surface))}))
  (local controller (RuntimeController.create {:module SnakeMain :host host}))
  (assert-one-target controller "Snake runtime before drop")
  (assert (= (# host.surfaces.items) 1) "Snake surface should register with host surfaces")
  (local screen registered-surface.entity)
  (var surface-drop-count 0)
  (var screen-drop-count 0)
  (local original-surface-drop registered-surface.drop)
  (local original-screen-drop screen.drop)
  (set registered-surface.drop (fn [self]
                                 (set surface-drop-count (+ surface-drop-count 1))
                                 (original-surface-drop self)))
  (set screen.drop (fn [self]
                     (set screen-drop-count (+ screen-drop-count 1))
                     (original-screen-drop self)))
  (controller:drop)
  (controller:drop)
  (assert (= (# (controller:render-targets)) 0) "dropped Snake runtime should not expose stale render targets")
  (assert (= (# host.surfaces.items) 0) "drop should unregister Snake surface from host surfaces")
  (assert (= surface-drop-count 1) "drop should drop Snake-owned surface once")
  (assert (= screen-drop-count 1) "drop should drop Snake-owned screen widget once"))

(fn test-snake-mounts-in-workspace-and-removes-targets-on-drop []
  (local runtime {})
  (local shell {})
  (local mount (HostedRuntime.mount-in-workspace {:runtime runtime
                                                  :app shell
                                                  :module SnakeMain}))
  (assert (= (. runtime :hosted-app-mounts 1) mount)
          "Snake workspace mount should register on runtime")
  (assert-one-target mount "Snake workspace mount")
  (mount:drop)
  (assert (= (# runtime.hosted-app-mounts) 0)
          "Snake workspace mount should be removed after drop"))

(add-test "snake create returns runtime facets" test-snake-create-returns-runtime-facets)
(add-test "controller mounts snake runtime" test-controller-mounts-snake-runtime)
(add-test "pause blocks simulation but keeps presentation" test-pause-blocks-simulation-keeps-presentation)
(add-test "quit key uses standalone host lifecycle" test-quit-key-uses-standalone-host-lifecycle)
(add-test "invalid host leaves no partial registrations" test-invalid-host-leaves-no-partial-registrations)
(add-test "missing viewport errors loudly" test-missing-viewport-errors-loudly)
(add-test "drop is idempotent and drops owned surface once" test-drop-is-idempotent-and-drops-owned-surface-once)
(add-test "snake mounts in workspace and removes targets on drop" test-snake-mounts-in-workspace-and-removes-targets-on-drop)

(fn main []
  (Runner.run-tests {:name "snake-hosted-runtime" :tests tests}))

{:main main :tests tests}
