(local Runner (require :tests/runner))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false) "expected call to fail")
  (assert (string.find (tostring err) expected 1 true)
          (.. "expected error to contain " expected ", got " (tostring err))))

(fn make-fake-hud []
  (local children [])
  {:children children
   :remove-count 0
   :add-panel-child (fn [self child]
                      (table.insert children child)
                      child)
   :remove-panel-child (fn [self child]
                         (set self.remove-count (+ self.remove-count 1))
                         (for [i (# children) 1 -1]
                           (when (= (. children i) child)
                             (table.remove children i)))
                         true)})

(fn make-fake-mount []
  (local controller {:paused-calls []
                     :step-calls []
                     :set-paused (fn [self paused]
                                   (table.insert self.paused-calls paused)
                                   paused)
                     :step (fn [self delta-ms]
                             (table.insert self.step-calls delta-ms)
                             delta-ms)})
  {:controller controller
   :drop-count 0
   :drop (fn [self]
           (set self.drop-count (+ self.drop-count 1)))})

(fn create-empty-runtime [_host]
  {})

(fn install-panel-module [fake-mount]
  (local previous-panel (. package.loaded "app-host.workspace-panel"))
  (local previous-mount (. package.loaded "app-host.workspace-mount"))
  (local fake-workspace-mount {:mount (fn [opts]
                                      (set fake-mount.opts opts)
                                      fake-mount)})
  (set (. package.loaded "app-host.workspace-panel") nil)
  (set (. package.loaded "app-host.workspace-mount") fake-workspace-mount)
  (local WorkspacePanel (require :app-host.workspace-panel))

  (fn restore [_self]
    (set (. package.loaded "app-host.workspace-panel") previous-panel)
    (set (. package.loaded "app-host.workspace-mount") previous-mount))

  {:WorkspacePanel WorkspacePanel
   :restore restore})

(fn panel-opts [hud]
  {:runtime {} :app {:hud hud} :module {:create create-empty-runtime}})

(fn test-open-adds-one-hud-child []
  (local hud (make-fake-hud))
  (local fake-mount (make-fake-mount))
  (local fixture (install-panel-module fake-mount))
  (local session (fixture.WorkspacePanel.open (panel-opts hud)))
  (assert (= session.mount fake-mount) "session should expose workspace mount")
  (assert (= (# hud.children) 1) "opening should add exactly one HUD panel child")
  (assert (= (. hud.children 1 :mount) fake-mount) "HUD child should describe mounted app")
  (fixture:restore))

(fn test-controls_delegate_to_controller []
  (local hud (make-fake-hud))
  (local fake-mount (make-fake-mount))
  (local fixture (install-panel-module fake-mount))
  (local session (fixture.WorkspacePanel.open (panel-opts hud)))
  (session:pause)
  (session:resume)
  (session:step 33)
  (assert (= (. fake-mount.controller.paused-calls 1) true) "pause should set controller paused true")
  (assert (= (. fake-mount.controller.paused-calls 2) false) "resume should set controller paused false")
  (assert (= (. fake-mount.controller.step-calls 1) 33) "step should delegate delta to controller")
  (fixture:restore))

(fn test-close_removes_child_and_drops_mount_once []
  (local hud (make-fake-hud))
  (local fake-mount (make-fake-mount))
  (local fixture (install-panel-module fake-mount))
  (local session (fixture.WorkspacePanel.open (panel-opts hud)))
  (session:close)
  (session:close)
  (assert (= (# hud.children) 0) "close should remove HUD child")
  (assert (= hud.remove-count 1) "close should remove HUD child exactly once")
  (assert (= fake-mount.drop-count 1) "close should drop mount exactly once")
  (fixture:restore))

(fn open-without-hud [WorkspacePanel]
  (WorkspacePanel.open {:runtime {} :app {} :module {:create create-empty-runtime}}))

(fn test-missing_hud_fails_loudly []
  (local saved-hud (and app app.hud))
  (local fake-mount (make-fake-mount))
  (when app
    (set app.hud nil))
  (local fixture (install-panel-module fake-mount))
  (fn attempt-open-without-hud []
    (open-without-hud fixture.WorkspacePanel))
  (assert-error-contains attempt-open-without-hud "requires :app.hud or app.hud")
  (assert (= fake-mount.opts nil) "missing HUD should fail before mounting")
  (fixture:restore)
  (when app
    (set app.hud saved-hud)))

(add-test "open adds exactly one HUD panel child" test-open-adds-one-hud-child)
(add-test "controls delegate to controller" test-controls_delegate_to_controller)
(add-test "close removes child and drops mount once" test-close_removes_child_and_drops_mount_once)
(add-test "missing HUD fails loudly" test-missing_hud_fails_loudly)

(fn main []
  (Runner.run-tests {:name "hosted-app-workspace-panel" :tests tests}))

{:main main :tests tests}
