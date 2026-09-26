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

(fn fake-scene-target []
  (local panels [])
  {:panels panels
   :add-panel-child (fn [_self spec]
                      (local child {:spec spec})
                      (table.insert panels child)
                      child)
   :remove-panel-child (fn [_self child]
                         (for [i (# panels) 1 -1]
                           (when (= (. panels i) child)
                             (table.remove panels i))))
    :height-at (fn [_self point _opts]
                 (+ (. point 1) (. point 3)))})

(fn fake-nil-panel-scene-target []
  {:add-panel-child (fn [_self _spec]
                        nil)
   :remove-panel-child (fn [_self _child]
                           (error "remove-panel-child should not be called"))})

(fn fake-partial-inserting-nil-panel-scene-target []
  (local entity {})
  {:entity entity
   :add-panel-child (fn [self _spec]
                      (when (not entity.children)
                        (set entity.children []))
                      (when (not entity.scene-children)
                        (set entity.scene-children []))
                      (when (not self.scene-children)
                        (set self.scene-children entity.scene-children))
                      (local metadata {:id :partial-child})
                      (table.insert entity.children metadata)
                      (table.insert self.scene-children metadata)
                      nil)
   :remove-panel-child (fn [_self _child]
                         (error "remove-panel-child should not be called"))})

(fn fake-vector-validating-scene-target []
  (local panels [])
  {:panels panels
   :add-panel-child (fn [_self spec]
                      (local child {:spec spec})
                      (table.insert panels child)
                      (when (not (and spec.position spec.position.x))
                        (error "position must be native vec3"))
                      child)
   :remove-panel-child (fn [_self child]
                         (for [i (# panels) 1 -1]
                           (when (= (. panels i) child)
                             (table.remove panels i))))})

(fn fake-object-scene-target []
  (local objects [])
  {:objects objects
   :add-object (fn [_self object opts]
                 (local child {:object object :opts opts})
                 (table.insert objects child)
                 child)
   :remove-panel-child (fn [_self child]
                         (for [i (# objects) 1 -1]
                           (when (= (. objects i) child)
                             (table.remove objects i))))})

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

(fn test-scene_capability_spawns_queries_and_drops_owned_panel []
  (local scene (fake-scene-target))
  (local host (SpaceHost.create {:runtime {} :app {:scene scene}}))
  (local handle (host.scene:spawn {:kind :panel
                                   :id :scene-panel
                                   :position [1 2 3]
                                   :size [4 5 6]}))
  (assert (= handle.id :scene-panel))
  (assert (= handle.kind :panel))
  (assert (= handle._space-host-scene-child nil))
  (assert (= (# scene.panels) 1))
  (local child (. scene.panels 1))
  (assert (= child.spec.kind :panel))
  (set handle._space-host-scene-child {:not child})
  (assert (= (host.scene:height-at [2 0 5]) 7))
  (host:drop)
  (assert (= (# scene.panels) 0)))

(fn test-scene_capability_panel_spawn_nil_child_fails_and_rolls_back []
  (local scene (fake-nil-panel-scene-target))
  (local host (SpaceHost.create {:runtime {} :app {:scene scene}}))
  (assert-error-contains #(host.scene:spawn {:kind :panel :id :missing-builder})
                          "[space-host] scene:add-panel-child returned nil for panel spawn")
  (assert (= (# (host.scene:list-owned)) 0))
  (host:drop))

(fn test-scene_capability_nil_panel_spawn_rolls_back_raw_partial_insertions []
  (local scene (fake-partial-inserting-nil-panel-scene-target))
  (local host (SpaceHost.create {:runtime {} :app {:scene scene}}))
  (assert-error-contains #(host.scene:spawn {:kind :panel :id :partial-builder})
                         "[space-host] scene:add-panel-child returned nil for panel spawn")
  (assert (= scene.entity.children nil))
  (assert (= scene.entity.scene-children nil))
  (assert (= scene.scene-children nil))
  (assert (= (# (host.scene:list-owned)) 0))
  (host:drop))

(fn test-scene_capability_panel_spawn_converts_position_before_raw_scene []
  (local scene (fake-vector-validating-scene-target))
  (local host (SpaceHost.create {:runtime {} :app {:scene scene}}))
  (local handle (host.scene:spawn {:kind :panel
                                   :id :positioned-panel
                                   :position [1 2 3]}))
  (assert (= handle.id :positioned-panel))
  (assert (= (# scene.panels) 1))
  (local child (. scene.panels 1))
  (assert (= child.spec.position.x 1))
  (host:drop)
  (assert (= (# scene.panels) 0)))

(fn test-scene_capability_rejects_unbacked_embedded_spawn_kinds []
  (local scene (fake-scene-target))
  (local host (SpaceHost.create {:runtime {} :app {:scene scene}}))
  (assert-error-contains #(host.scene:spawn {:kind :cube :id :cube})
                         "unsupported embedded scene spawn kind")
  (assert (= (# (host.scene:list-owned)) 0))
  (host:drop))

(fn test-scene_capability_custom_spawn_uses_scene_add_object_when_available []
  (local scene (fake-object-scene-target))
  (local host (SpaceHost.create {:runtime {} :app {:scene scene}}))
  (local object {:name :thing})
  (local handle (host.scene:spawn {:kind :custom
                                   :id :object
                                   :object object
                                   :position [4 5 6]}))
  (assert (= handle.id :object))
  (assert (= (# scene.objects) 1))
  (local child (. scene.objects 1))
  (assert (= child.object object))
  (assert (= child.opts.position.x 4))
  (host.scene:despawn handle)
  (assert (= (# scene.objects) 0))
  (host:drop))

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
(table.insert tests {:name "scene capability spawns queries and drops owned panel"
                      :fn test-scene_capability_spawns_queries_and_drops_owned_panel})
(table.insert tests {:name "scene capability panel spawn nil child fails and rolls back"
                       :fn test-scene_capability_panel_spawn_nil_child_fails_and_rolls_back})
(table.insert tests {:name "scene capability nil panel spawn rolls back raw partial insertions"
                      :fn test-scene_capability_nil_panel_spawn_rolls_back_raw_partial_insertions})
(table.insert tests {:name "scene capability panel spawn converts position before raw scene"
                     :fn test-scene_capability_panel_spawn_converts_position_before_raw_scene})
(table.insert tests {:name "scene capability rejects unbacked embedded spawn kinds"
                     :fn test-scene_capability_rejects_unbacked_embedded_spawn_kinds})
(table.insert tests {:name "scene capability custom spawn uses scene add-object when available"
                     :fn test-scene_capability_custom_spawn_uses_scene_add_object_when_available})
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
