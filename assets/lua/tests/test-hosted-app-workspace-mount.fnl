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

(add-test "mount registers without replacing runtime" test-mount-registers-without-replacing-runtime)
(add-test "activity presentation composes hosted targets before HUD" test-activity-presentation-composes-hosted-targets-before-hud)

(fn main []
  (Runner.run-tests {:name "hosted-app-workspace-mount" :tests tests}))

{:main main :tests tests}
