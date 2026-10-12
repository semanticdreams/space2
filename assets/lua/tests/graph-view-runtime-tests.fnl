(local glm (require :glm))
(local Runtime (require :graph/view/runtime))

(fn camera-set-position [self next-position]
    (set self.position next-position))

(fn make-test-camera [position]
    (local camera {:position position})
    (set camera.set-position camera-set-position)
    camera)

(fn persistence-set-mode-camera-state [self mode state]
    (set self.captured.mode mode)
    (set self.captured.state state)
    true)

(fn projection-capture-state [_view _runtime]
    {})

(fn projection-restore-state [_view _runtime _state]
    true)

(fn projection-drop [_view runtime]
    (local state (assert runtime.test-drop-state
                         "runtime drop test requires test-drop-state"))
    (set state.drop-count (+ state.drop-count 1))
    true)

(fn projection-drop-noop [_view _runtime]
    true)

(fn projection-apply-initial-camera-policy [_view _runtime]
    true)

(fn node-views-drop-all [_self]
    true)

(fn runtime-captures-options-camera-without-view-camera []
    (local view {})
    (local captured {})
    (local persistence {:captured captured
                        :set-mode-camera-state persistence-set-mode-camera-state})
    (local camera (make-test-camera (glm.vec3 7 8 9)))
    (local projection {:mode "spatial"
                       :capture-projection-state! projection-capture-state
                       :restore-projection-state! projection-restore-state
                       :drop-projection! projection-drop-noop
                       :apply-initial-camera-policy! projection-apply-initial-camera-policy})
    (local runtime (Runtime.init! view
                                 {:graph-map {:selected_node_keys []}
                                  :ctx {}
                                  :node-views {}
                                  :persistence persistence
                                  :camera camera}
                                 projection))
    (Runtime.install! view runtime projection)
    (view:capture-camera-state!)
    (assert (= captured.mode "spatial")
            "runtime camera capture should persist the projection mode")
    (assert (= (. captured.state.position 1) 7)
            "runtime camera capture should use options.camera x")
    (assert (= (. captured.state.position 2) 8)
            "runtime camera capture should use options.camera y")
    (assert (= (. captured.state.position 3) 9)
            "runtime camera capture should use options.camera z"))

(fn runtime-drop-invokes-projection-and-guards-methods []
    (local view {})
    (local drop-state {:drop-count 0})
    (local projection {:mode "outline"
                       :capture-projection-state! projection-capture-state
                       :restore-projection-state! projection-restore-state
                       :drop-projection! projection-drop
                       :apply-initial-camera-policy! projection-apply-initial-camera-policy})
    (local runtime (Runtime.init! view
                                  {:graph-map {:selected_node_keys []}
                                   :ctx {}
                                  :node-views {:drop-all node-views-drop-all}
                                  :persistence {}}
                                 projection))
    (set runtime.test-drop-state drop-state)
    (Runtime.install! view runtime projection)
    (view:drop)
    (assert (= drop-state.drop-count 1)
            "runtime drop should invoke projection.drop-projection!")
    (assert runtime.dropped?
            "runtime drop should mark the runtime dropped")
    (local (ok message) (pcall view.capture-state view))
    (assert (not ok)
            "runtime-installed methods should fail after drop")
    (assert (string.find (tostring message) "called after drop" 1 true)
            "runtime dropped guard should explain use after drop"))

(fn append-tests [tests]
    (table.insert tests
                  {:name "GraphViewRuntime captures options camera without view camera"
                   :fn runtime-captures-options-camera-without-view-camera})
    (table.insert tests
                  {:name "GraphViewRuntime drop invokes projection and guards methods"
                   :fn runtime-drop-invokes-projection-and-guards-methods})
    tests)

{:append-tests append-tests}
