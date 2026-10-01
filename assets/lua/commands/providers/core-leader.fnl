(local LauncherLaunchable (require :launchables/launcher))

(fn open-launcher [ctx]
  (local hud ((. ctx :hud)))
  (assert hud "LeaderState launcher requires a HUD host")
  (LauncherLaunchable.open-panel {:hud hud})
  true)

(fn run-quit [ctx]
  ((. ctx :set-state) :quit)
  true)

(fn run-camera [ctx]
  ((. ctx :set-state) :camera)
  true)

(fn provider [_opts]
  {:commands {"core.quit" {:id "core.quit"
                            :label "quit-mode"
                            :run run-quit}
              "core.camera" {:id "core.camera"
                              :label "camera-mode"
                              :run run-camera}
              "core.launcher" {:id "core.launcher"
                                :label "launcher"
                                :run open-launcher}}
   :bindings [{:keys ["q"] :command "core.quit" :label "quit-mode" :priority 20}
              {:keys ["c"] :command "core.camera" :label "camera-mode" :priority 30}
              {:keys ["p"] :command "core.launcher" :label "launcher" :priority 40}]})

{:provider provider}
