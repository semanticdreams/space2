(local Runner (require :tests/runner))
(local RuntimeController (require :app-host.runtime-controller))
(local SnakeMain (require :main))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn copy-list [items]
  (local out [])
  (each [_ item (ipairs items)]
    (table.insert out item))
  out)

(fn make-registry []
  (local items [])
  {:items items
   :register (fn [_self item]
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

(fn fake-host []
  {:viewport {:x 0 :y 0 :width 800 :height 600}
   :scheduler (make-scheduler)
   :input (make-input)
   :inspectors (make-registry)
   :commands (make-registry)
   :surfaces (make-registry)})

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

(fn test-drop-is-idempotent-and-removes-targets []
  (local host (fake-host))
  (local controller (RuntimeController.create {:module SnakeMain :host host}))
  (assert-one-target controller "Snake runtime before drop")
  (controller:drop)
  (controller:drop)
  (assert (= (# (controller:render-targets)) 0) "dropped Snake runtime should not expose stale render targets"))

(add-test "snake create returns runtime facets" test-snake-create-returns-runtime-facets)
(add-test "controller mounts snake runtime" test-controller-mounts-snake-runtime)
(add-test "pause blocks simulation but keeps presentation" test-pause-blocks-simulation-keeps-presentation)
(add-test "drop is idempotent and removes targets" test-drop-is-idempotent-and-removes-targets)

(fn main []
  (Runner.run-tests {:name "snake-hosted-runtime" :tests tests}))

{:main main :tests tests}
