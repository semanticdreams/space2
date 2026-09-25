(local tests [])
(local SpaceHost (require :app-host.space-host))

(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false))
  (assert (string.find (tostring err) expected 1 true)))

(fn fake-target []
  (local children [])
  {:children children
   :add-panel-child (fn [_self child]
                      (table.insert children child)
                      child)
   :remove-panel-child (fn [_self child]
                         (var removed? false)
                         (for [i (# children) 1 -1]
                           (when (= (. children i) child)
                             (table.remove children i)
                             (set removed? true)))
                         removed?)})

(fn test-space_host_exposes_required_services []
  (local runtime {})
  (local host (SpaceHost.create {:runtime runtime :app {}}))
  (each [_ name (ipairs [:viewport :surfaces :scheduler :input :inspectors :commands :assets :logging :lifecycle])]
    (assert (. host name)))
  (host:drop))

(fn test-embedded_quit_uses_close_callback []
  (var closed? false)
  (fn close-host [_host]
    (set closed? true))
  (local host (SpaceHost.create {:runtime {} :app {} :on-quit close-host}))
  (host.lifecycle:quit)
  (assert (= closed? true))
  (host:drop))

(fn test-embedded_quit_without_callback_fails_loudly []
  (local host (SpaceHost.create {:runtime {} :app {}}))
  (assert-error-contains #(host.lifecycle:quit)
                         "[space-host] lifecycle:quit requires on-quit callback")
  (host:drop))

(fn test-create_requires_runtime []
  (assert-error-contains #(SpaceHost.create {:app {}})
                         "[space-host] create requires :runtime"))

(fn test-hud_adapter_adds_and_drops_owned_panel []
  (local hud (fake-target))
  (local host (SpaceHost.create {:runtime {} :app {:hud hud}}))
  (local child {:id :panel})
  (assert (= (host.hud:add-panel-child child) child))
  (assert (= (# hud.children) 1))
  (host:drop)
  (assert (= (# hud.children) 0))
  (host:drop)
  (assert (= (# hud.children) 0)))

(fn test-canvas_adapter_adds_and_drops_owned_panel []
  (local canvas (fake-target))
  (local host (SpaceHost.create {:runtime {} :app {:canvas canvas}}))
  (local child {:id :canvas-panel})
  (assert (= (host.canvas:add-panel-child child) child))
  (assert (= (# canvas.children) 1))
  (host:drop)
  (assert (= (# canvas.children) 0)))

(fn test-scene_adapter_adds_and_drops_owned_panel []
  (local scene (fake-target))
  (local host (SpaceHost.create {:runtime {} :app {:scene scene}}))
  (local child {:id :scene-panel})
  (assert (= (host.scene:add-panel-child child) child))
  (assert (= (# scene.children) 1))
  (host:drop)
  (assert (= (# scene.children) 0)))

(fn test-host_exposes_only_present_space_adapters []
  (local hud (fake-target))
  (local host (SpaceHost.create {:runtime {} :app {:hud hud}}))
  (assert host.hud)
  (assert (= host.canvas nil))
  (assert (= host.scene nil))
  (host:drop))

(table.insert tests {:name "space host exposes required services"
                     :fn test-space_host_exposes_required_services})
(table.insert tests {:name "embedded quit uses close callback"
                     :fn test-embedded_quit_uses_close_callback})
(table.insert tests {:name "embedded quit without callback fails loudly"
                     :fn test-embedded_quit_without_callback_fails_loudly})
(table.insert tests {:name "create requires runtime"
                     :fn test-create_requires_runtime})
(table.insert tests {:name "hud adapter adds and drops owned panel"
                     :fn test-hud_adapter_adds_and_drops_owned_panel})
(table.insert tests {:name "canvas adapter adds and drops owned panel"
                     :fn test-canvas_adapter_adds_and_drops_owned_panel})
(table.insert tests {:name "scene adapter adds and drops owned panel"
                     :fn test-scene_adapter_adds_and_drops_owned_panel})
(table.insert tests {:name "host exposes only present space adapters"
                     :fn test-host_exposes_only_present_space_adapters})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "app-host-space-host"
                       :tests tests})))

{:name "app-host-space-host"
 :tests tests
 :main main}
