(local Runner (require :tests/runner))
(local WorkspaceMount (require :app-host.workspace-mount))
(local ActivityPresentation (require :activity-presentation))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn base-render-targets [_self]
  [{:kind :scene :id :base}])

(fn hosted-render-targets [_self]
  [{:kind :hud :id :hosted}])

(fn drop-runtime [_self]
  nil)

(fn create-hosted-runtime [_host]
  {:presentation {:render-targets hosted-render-targets}
   :lifecycle {:drop drop-runtime}})

(fn scene-presentation-target [self]
  self.target)

(fn canvas-presentation-target [self]
  self.target)

(fn mount-render-targets [self]
  [self.target])

(fn hud-presentation-target [self]
  self.target)

(fn add-panel-child [self child]
  (table.insert self.children child)
  child)

(fn remove-panel-child [self child]
  (for [i (# self.children) 1 -1]
    (when (= (. self.children i) child)
      (table.remove self.children i)))
  true)

(fn create-invalid-runtime-with-hud-child [host]
  (host.hud:add-panel-child {:id :owned-child})
  {:presentation {}})

(var quit-during-create-state nil)

(fn note-quit-during-create-drop [self]
  (set self.state.dropped-count (+ self.state.dropped-count 1)))

(fn create-runtime-that-quits-during-create [host]
  (host.lifecycle:quit)
  {:presentation {:render-targets hosted-render-targets}
   :lifecycle {:state quit-during-create-state
               :drop note-quit-during-create-drop}})

(fn test-embedded-quit-during-create-closes-workspace-mount []
  (local runtime {})
  (local state {:dropped-count 0})
  (set quit-during-create-state state)
  (local module {:create create-runtime-that-quits-during-create})
  (local mount (WorkspaceMount.mount {:runtime runtime :app {} :module module}))
  (assert (= (# runtime.hosted-app-mounts) 0)
          "quit during create should close and unregister the workspace mount")
  (assert (= state.dropped-count 1)
          "quit during create should drop the hosted controller once")
  (assert (= (# (mount:render-targets)) 0)
          "closed mount should not expose render targets"))

(fn test-mount-registers-without-replacing-runtime []
  (local runtime {:presentation {:render-targets base-render-targets}})
  (local module {:create create-hosted-runtime})
  (local app-shell {})
  (local saved-active (and app app.active-world-runtime))
  (local mount (WorkspaceMount.mount {:runtime runtime :app app-shell :module module}))
  (assert (= (. runtime :hosted-app-mounts 1) mount)
          "mount should be registered on runtime.hosted-app-mounts")
  (assert (= app.active-world-runtime saved-active)
          "workspace mount must not replace app.active-world-runtime")
  (assert (= (# (mount:render-targets)) 1)
          "mount should expose controller render targets")
  (mount:drop)
  (assert (= (# runtime.hosted-app-mounts) 0)
          "drop should remove mount from runtime list"))

(fn test-activity-presentation-composes-hosted-targets-before-hud []
  (local saved-hud (and app app.hud))
  (local scene-target {:kind :scene :id :base-scene})
  (local canvas-target {:kind :canvas :id :base-canvas})
  (local hosted-target {:kind :hud :id :hosted})
  (local hud-target {:kind :hud :id :shell-hud})
  (local mount {:target hosted-target :render-targets mount-render-targets})
  (local runtime {:scene {:target scene-target :presentation-target scene-presentation-target}
                  :canvas {:target canvas-target :presentation-target canvas-presentation-target}
                  :hosted-app-mounts [mount]})
  (when app
    (set app.hud {:target hud-target :presentation-target hud-presentation-target}))
  (local provider (ActivityPresentation.for-runtime runtime))
  (local targets (provider:render-targets))
  (assert (= (# targets) 4)
          (.. "presentation should include scene/canvas/hosted/hud targets, got " (# targets)))
  (assert (= (. targets 1) scene-target) "scene target should remain first")
  (assert (= (. targets 2) canvas-target) "canvas target should remain second")
  (assert (= (. targets 3) hosted-target) "hosted target should appear before HUD")
  (assert (= (. targets 4) hud-target) "HUD target should remain last")
  (set runtime.hosted-app-mounts [])
  (local after-drop (provider:render-targets))
  (assert (= (# after-drop) 3)
          "removed hosted mounts should no longer contribute targets")
  (assert (= (. after-drop 1) scene-target))
  (assert (= (. after-drop 2) canvas-target))
  (assert (= (. after-drop 3) hud-target))
  (when app
    (set app.hud saved-hud)))

(fn test-failed-mount-drops-host-owned-children []
  (local runtime {})
  (local hud {:children []
              :add-panel-child add-panel-child
              :remove-panel-child remove-panel-child})
  (local module {:create create-invalid-runtime-with-hud-child})
  (local (ok err) (pcall #(WorkspaceMount.mount {:runtime runtime
                                                 :app {:hud hud}
                                                 :module module})))
  (assert (not ok) "invalid runtime should fail workspace mount")
  (assert (string.find (tostring err) "render-targets" 1 true)
          "failure should preserve original runtime validation error")
  (assert (= (# hud.children) 0)
          "failed workspace mount should drop host-owned HUD children"))

(add-test "mount registers without replacing runtime" test-mount-registers-without-replacing-runtime)
(add-test "activity presentation composes hosted targets before HUD" test-activity-presentation-composes-hosted-targets-before-hud)
(add-test "failed mount drops host-owned children" test-failed-mount-drops-host-owned-children)
(add-test "embedded quit during create closes workspace mount" test-embedded-quit-during-create-closes-workspace-mount)

(fn main []
  (Runner.run-tests {:name "hosted-app-workspace-mount" :tests tests}))

{:main main :tests tests}
