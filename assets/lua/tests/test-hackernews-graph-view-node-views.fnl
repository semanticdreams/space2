(local glm (require :glm))
(local BuildContext (require :build-context))
(local GraphViewNodeViews (require :graph/view/node-views))
(local PanelTransfer (require :panel-transfer))
(local HackerNewsRootNode (require :graph/nodes/hackernews-root))
(local logging (require :logging))
(local {: Layout} (require :layout))

(fn capture-warnings [body]
    (local original-warn logging.warn)
    (local warnings [])
    (set logging.warn
         (fn [message]
             (table.insert warnings (tostring message))))
    (local (ok result) (pcall body))
    (set logging.warn original-warn)
    (when (not ok)
        (error result))
    warnings)

(fn assert-unresolved-restored-warning [warnings key]
    (local expected (.. "[graph-view] skipping unresolved restored node view: " key))
    (assert (= (length warnings) 1)
            (.. "expected one unresolved restored-node warning for " key))
    (assert (= (. warnings 1) expected)
            (.. "expected unresolved restored-node warning for " key
                ", got " (tostring (. warnings 1)))))

(fn make-icons-stub []
    (local glyph {:advance 1})
    (local font {:metadata {:metrics {:ascender 1 :descender -1}
                            :atlas {:width 1 :height 1}}
                 :glyph-map {65533 glyph
                             4242 glyph}})
    (local stub {:font font
                 :codepoints {:close 4242
                              :table 4242
                              :code 4242}})
    (set stub.get
         (fn [self name]
             (local value (. self.codepoints name))
             (assert value (.. "Missing icon " name))
             value))
    (set stub.resolve
         (fn [self name]
             (local code (self:get name))
             {:type :font
              :codepoint code
              :font self.font}))
    stub)

(fn make-ctx []
    (local ctx
      (BuildContext {:clickables (assert app.clickables "test requires app.clickables")
                     :hoverables (assert app.hoverables "test requires app.hoverables")}))
    (set ctx.icons (make-icons-stub))
    ctx)

(fn make-view-target [ctx]
    (local target {:build-context ctx :children []})
    (set target.add-panel-child
         (fn [self opts]
             (local builder (and opts opts.builder))
             (assert builder "builder required")
             (local element (builder self.build-context {}))
             (set element.__test_panel_opts opts)
             (table.insert self.children element)
             (set self.last-add-panel-opts opts)
             element))
    (set target.remove-panel-child
         (fn [self element]
             (var removed false)
             (local kept [])
             (each [_ existing (ipairs self.children)]
                 (if (and (not removed) (= existing element))
                     (set removed true)
                     (table.insert kept existing)))
             (set self.children kept)
             removed))
    (set target.capture-panel-element-state
         (fn [_self element]
             (and element element.__test_panel_state)))
    (set target.register-panel-restorer
         (fn [self kind restorer owner]
             (set self.restorer {:kind kind :restorer restorer :owner owner})
             true))
    (set target.unregister-panel-restorer
         (fn [self _kind owner]
             (when (or (= owner nil)
                       (and self.restorer (= self.restorer.owner owner)))
                 (set self.restorer nil))
             true))
    target)

(fn make-simple-view []
    (local layout
      (Layout {:name "nested-view"
               :measurer (fn [self]
                             (set self.measure (glm.vec3 0 0 0)))
               :layouter (fn [_self] nil)}))
    {:layout layout
     :drop (fn [_self] (layout:drop))})

(local tests [{:name "graph view node-views build hackernews root dialog"
  :fn (fn []
          (local ctx (make-ctx))
          (local target (make-view-target ctx))
          (local views (GraphViewNodeViews {:ctx ctx
                                            :view-target target}))
          (local node (HackerNewsRootNode))
          ;; should build the hackernews root view without throwing
          (views:open node)
          (assert (= (length target.children) 1)
                  "graph view node-views should attach one dialog for the selected node")
          (local dialog (. target.children 1))
          (assert (and dialog dialog.layout)
                  "dialog should expose a layout for HUD attachment")
          (when dialog.drop
            (dialog:drop)))}
 {:name "graph view node-views unwrap nested builder functions"
  :fn (fn []
          (local ctx (make-ctx))
          (local target (make-view-target ctx))
          ;; node view returns a builder that returns another builder instead of a widget
          (local nested {:key "nested"
                         :label "nested"
                         :view (fn [_node]
                                   (fn [_builder-ctx _opts]
                                       (fn [_inner-ctx _inner-opts]
                                           (make-simple-view))))})
          (local views (GraphViewNodeViews {:ctx ctx
                                            :view-target target}))
          (views:open nested)
          (assert (= (length target.children) 1)
                  "graph view node-views should attach dialog even when view builder is nested")
          (local dialog (. target.children 1))
          (assert (and dialog dialog.layout)
                  "dialog should expose a layout even when unwrapped from nested builders")
          (when dialog.drop
            (dialog:drop)))}
 {:name "graph view node-views persist panel placement and restore"
  :fn (fn []
          (local ctx (make-ctx))
          (local target (make-view-target ctx))
          (local node {:key "persist-node"
                       :label "Persist node"
                       :view (fn [_node]
                                 (fn [_builder-ctx _opts]
                                     (make-simple-view)))})
           (local graph {:id "main" :nodes {}})
          (set (. graph.nodes node.key) node)
          (set graph.lookup (fn [_self key] (. graph.nodes key)))
          (set graph.load-by-key (fn [_self key] (. graph.nodes key)))
          (local views (GraphViewNodeViews {:ctx ctx
                                            :graph-map graph
                                            :view-target target}))
          (views:open node)
          (local dialog (. target.children 1))
          (set dialog.__test_panel_state {:layer "float"
                                          :position [1 2 3]
                                          :rotation [1 0 0 0]
                                          :size [7 8 9]})
          (local state (views:capture-state))
          (assert (= (length (or state.open-views [])) 1)
                  "capture-state should record one open node view")
          (local captured (. state.open-views 1))
          (assert (= captured.node-key node.key))
          (assert (= (and captured.panel captured.panel.layer) "float")
                  "capture-state should include panel placement")
          (views:drop-all)
          (target:remove-panel-child dialog)
           (views:restore-state {:open-views [{:node-key node.key
                                               :graph-map-id "main"
                                               :panel {:layer "tiles"
                                                       :align-x :end
                                                       :align-y :start}}]})
          (assert (= (length target.children) 1)
                  "restore-state should reopen persisted node view")
          (assert (= (and target.last-add-panel-opts target.last-add-panel-opts.location) :tiles))
          (assert (= (and target.last-add-panel-opts target.last-add-panel-opts.align-x) :end))
          (assert (= (and target.last-add-panel-opts target.last-add-panel-opts.align-y) :start))
          (assert (= (and target.last-add-panel-opts
                          target.last-add-panel-opts.persistence
                          target.last-add-panel-opts.persistence.kind)
                     "graph-node-view")))}
  {:name "graph view node-views legacy open-node-keys restore uses map id"
   :fn (fn []
          (local ctx (make-ctx))
          (local target (make-view-target ctx))
          (local node {:key "legacy-open-node"
                       :label "Legacy open node"
                       :view (fn [_node]
                                 (fn [_builder-ctx _opts]
                                     (make-simple-view)))})
          (local graph {:id "legacy-map" :nodes {}})
          (set (. graph.nodes node.key) node)
          (set graph.lookup (fn [_self key] (. graph.nodes key)))
          (local views (GraphViewNodeViews {:ctx ctx
                                            :graph-map graph
                                            :view-target target}))
          (views:restore-state {:open-node-keys [node.key]})
          (assert (= (length target.children) 1)
                  "legacy open-node-keys should restore node view on active map")
          (local state (views:capture-state))
          (local captured (. state.open-views 1))
           (assert (= captured.graph-map-id "legacy-map")
                   "legacy open-node-keys restore should capture active graph-map-id")
           (views:drop-all))}
  {:name "graph view node-views canvas restorer redirects to active slot"
   :fn (fn []
           (local saved-canvas app.canvas)
           (local ctx (make-ctx))
           (local slot-target (make-view-target ctx))
           (local canvas-target (make-view-target ctx))
           (set canvas-target.active-activity-slot slot-target)
           (set slot-target.visible? true)
           (set app.canvas canvas-target)
           (local node {:key "slot-restore-node"
                        :label "Slot Restore Node"
                        :view (fn [_node]
                                  (fn [_builder-ctx _opts]
                                      (make-simple-view)))})
           (local graph {:id "main" :nodes {}})
           (set (. graph.nodes node.key) node)
           (set graph.lookup (fn [_self key] (. graph.nodes key)))
           (local (ok err)
             (pcall
               (fn []
                 (local views (GraphViewNodeViews {:ctx ctx
                                                   :graph-map graph
                                                   :view-target slot-target}))
                 (assert (and canvas-target.restorer canvas-target.restorer.restorer)
                         "graph node views should register legacy canvas restorer")
                 ((. canvas-target.restorer :restorer) {:node-key node.key
                                                        :graph-map-id "main"
                                                        :layer "float"})
                 (assert (= (length slot-target.children) 1)
                         "legacy canvas restorer should restore graph panel into active slot")
                 (assert (= (length canvas-target.children) 0)
                         "legacy canvas restorer should not restore graph panel into base canvas")
                 (views:drop-all))))
           (set app.canvas saved-canvas)
           (when (not ok)
             (error err)))}
  {:name "graph view node-views restore skips unresolved nodes"
   :fn (fn []
          (local ctx (make-ctx))
          (local target (make-view-target ctx))
           (local graph {:id "main"
                         :lookup (fn [_self _key] nil)
                         :load-by-key (fn [_self _key] nil)})
          (local views (GraphViewNodeViews {:ctx ctx
                                            :graph-map graph
                                            :view-target target}))
           (local warnings
             (capture-warnings
               (fn []
                 (views:restore-state {:open-views [{:node-key "terrain-tool:world-1:apply-perlin"
                                                     :graph-map-id "main"}]}))))
           (assert-unresolved-restored-warning warnings "terrain-tool:world-1:apply-perlin")
           (assert (= (length target.children) 0)
                   "restore-state should skip unresolved node views")
          (local state (views:capture-state))
          (assert (= (length (or state.open-views [])) 1)
                  "capture-state should preserve unresolved restored node views")
          (assert (= (and (. state.open-views 1) (. (. state.open-views 1) :node-key))
                     "terrain-tool:world-1:apply-perlin"))
          (views:drop-all))}
 {:name "graph view node-views panel restorer skips unresolved nodes"
  :fn (fn []
          (local ctx (make-ctx))
          (local target (make-view-target ctx))
           (local graph {:id "main"
                         :lookup (fn [_self _key] nil)
                         :load-by-key (fn [_self _key] nil)})
          (local views (GraphViewNodeViews {:ctx ctx
                                            :graph-map graph
                                            :view-target target}))
          (assert (and target.restorer target.restorer.restorer)
                  "expected graph node views to register panel restorer")
           (local warnings
             (capture-warnings
               (fn []
                 ((. target.restorer :restorer) {:node-key "terrain:world-1:node-a"
                                                 :graph-map-id "main"
                                                 :layer "float"}))))
           (assert-unresolved-restored-warning warnings "terrain:world-1:node-a")
           (assert (= (length target.children) 0)
                   "panel restorer should skip unresolved node views")
          (local state (views:capture-state))
          (assert (= (length (or state.open-views [])) 1)
                  "capture-state should preserve unresolved node views from panel restore")
          (assert (= (and (. state.open-views 1) (. (. state.open-views 1) :node-key))
                     "terrain:world-1:node-a"))
          (views:drop-all))}
  {:name "graph view node-views default canvas placement uses camera center"
   :fn (fn []
           (local ctx (make-ctx))
           (local target (make-view-target ctx))
          (set target.interaction-surface :canvas)
          (set target.default-panel-location "float")
          (set target.camera {:position (glm.vec3 12 34 99)})
          (local node {:key "canvas-node"
                       :label "Canvas node"
                       :view (fn [_node]
                                 (fn [_builder-ctx _opts]
                                     (make-simple-view)))})
          (local views (GraphViewNodeViews {:ctx ctx
                                            :view-target target}))
          (views:open node)
          (local position (and target.last-add-panel-opts target.last-add-panel-opts.position))
          (assert position "expected canvas node view placement position")
          (assert (= position.x 12) "canvas placement should use camera x")
           (assert (= position.y 34) "canvas placement should use camera y")
           (assert (= position.z 0) "canvas placement should use graph plane z")
           (views:drop-all))}
   {:name "graph-node-view panel restorer module compiles and exports restore"
    :fn (fn []
            (local restorer (require :graph/view/node-view-panel-restorer))
           (assert (= (type restorer) :table)
                   "node-view-panel-restorer should export a table")
           (assert (= (type restorer.restore) :function)
                   "node-view-panel-restorer should export a restore function")
           true)}
  {:name "graph-node-view panel restorer adds child, preserves persistence, close removes child"
   :fn (fn []
           (local RestorerModule (require :graph/view/node-view-panel-restorer))
           (local ctx (make-ctx))
           (local target (make-view-target ctx))
           (local node {:key "test-node"
                        :label "Test"
                        :view (fn [_node]
                                  (fn [_builder-ctx _builder-opts]
                                      (make-simple-view)))})
           (local saved-graph app.graph)
           (local saved-runtime app.active-world-runtime)
           (local graph
              {:id "main"
               :lookup (fn [_self key]
                         (when (= key "test-node") node))
              :nodes {"test-node" node}})
           (set app.graph graph)
           (set app.active-world-runtime {:graph-map graph})
           (local (ok result)
             (pcall
               (fn []
                  (RestorerModule.restore {:hud target
                                            :panel {:kind "graph-node-view"
                                                    :node-key "test-node"
                                                    :graph-map-id "main"
                                                    :layer "tiles"
                                                    :align-x :start}})
                 (assert (= (length target.children) 1)
                         "module restorer should add one child")
                 (local child (. target.children 1))
                 (assert (and child child.layout)
                         "module restorer child should have a layout")
                 (assert (= (and target.last-add-panel-opts
                                 target.last-add-panel-opts.persistence
                                 target.last-add-panel-opts.persistence.kind)
                            "graph-node-view")
                         "module restorer should set persistence kind")
                 (assert (= (and target.last-add-panel-opts
                                 target.last-add-panel-opts.persistence
                                 target.last-add-panel-opts.persistence.node-key)
                            "test-node")
                         "module restorer should set persistence node-key")
                 (target:remove-panel-child child)
                 (assert (= (length target.children) 0)
                         "module restorer close should remove the panel child")
                 true)))
           (set app.graph saved-graph)
           (set app.active-world-runtime saved-runtime)
            (when (not ok)
              (error result))
            true)}
  {:name "graph-node-view panel restorer resolves canvas graph-map"
   :fn (fn []
           (local RestorerModule (require :graph/view/node-view-panel-restorer))
           (local ctx (make-ctx))
           (local target (make-view-target ctx))
           (local node {:key "canvas-node"
                        :label "Canvas Node"
                        :view (fn [_node]
                                  (fn [_builder-ctx _builder-opts]
                                      (make-simple-view)))})
           (local saved-graph-map app.graph-map)
           (local saved-runtime app.active-world-runtime)
           (local graph {:id "canvas-map"
                         :lookup (fn [_self key] (when (= key "canvas-node") node))
                         :nodes {"canvas-node" node}})
           (set target.graph-map graph)
           (set app.graph-map nil)
           (set app.active-world-runtime nil)
           (local (ok result)
             (pcall
               (fn []
                 (RestorerModule.restore {:canvas target
                                          :panel {:kind "graph-node-view"
                                                  :node-key "canvas-node"
                                                  :graph-map-id "canvas-map"}})
                 (assert (= (length target.children) 1)
                         "canvas restorer should add one child from canvas graph-map"))))
           (set app.graph-map saved-graph-map)
           (set app.active-world-runtime saved-runtime)
           (when (not ok)
             (error result))
           true)}
  {:name "graph-node-view panel restorer unwraps nested builders"
   :fn (fn []
           (local RestorerModule (require :graph/view/node-view-panel-restorer))
           (local ctx (make-ctx))
           (local target (make-view-target ctx))
           (local node {:key "nested"
                        :label "Nested"
                        :view (fn [_node]
                                  (fn [_builder-ctx _builder-opts]
                                      (fn [_inner-ctx _inner-opts]
                                          (make-simple-view))))})
           (local saved-graph app.graph)
           (local saved-runtime app.active-world-runtime)
            (local graph {:id "main"
                          :lookup (fn [_self key] (when (= key "nested") node))
                          :nodes {"nested" node}})
           (set app.graph graph)
           (set app.active-world-runtime {:graph-map graph})
           (local (ok result)
             (pcall
               (fn []
                  (RestorerModule.restore {:hud target
                                            :panel {:kind "graph-node-view"
                                                    :node-key "nested"
                                                    :graph-map-id "main"
                                                    :layer "float"
                                                    :position [1 2 3]
                                                   :size [4 5 6]}})
                 (assert (= (length target.children) 1)
                         "module restorer should unwrap nested builders and add a child")
                 (local child (. target.children 1))
                 (assert (and child child.layout)
                         "module restorer nested child should have a layout")
                 true)))
           (set app.graph saved-graph)
           (set app.active-world-runtime saved-runtime)
            (when (not ok)
              (error result))
            true)}
   {:name "graph view node-views scene target round-trips target-kind"
    :fn (fn []
            (local ctx (make-ctx))
            (local target (make-view-target ctx))
            (local scene-target (make-view-target ctx))
            (local saved-scene app.scene)
            (local saved-hud app.hud)
            (var views nil)
            (local (ok err)
              (pcall
                (fn []
                    (set app.scene scene-target)
                    (set app.hud nil)
                    (local node {:key "scene-node"
                                 :label "Scene"
                                 :view (fn [_node]
                                           (fn [_builder-ctx _opts]
                                               (make-simple-view)))})
                    (local graph {:id "main" :nodes {}})
                    (set (. graph.nodes node.key) node)
                    (set graph.lookup (fn [_self key] (. graph.nodes key)))
                    (set graph.load-by-key (fn [_self key] (. graph.nodes key)))
                    (set views (GraphViewNodeViews {:ctx ctx
                                                    :graph-map graph
                                                    :view-target target}))
                    (views:open node {:target app.scene})
                    (local state (views:capture-state))
                    (local captured (. state.open-views 1))
                    (assert (= captured.target-kind "scene")
                            "capture-state should record scene target-kind")
                    (views:drop-all)
                    (each [_ child (ipairs scene-target.children)]
                        (scene-target:remove-panel-child child))
                    (views:restore-state state)
                    (assert (= (length scene-target.children) 1)
                            "restore-state should reopen node view on scene target")
                    (views:drop-all)
                    (set views nil))))
            (when views (views:drop-all))
            (set app.scene saved-scene)
            (set app.hud saved-hud)
            (when (not ok)
                (error err)))}
   {:name "graph view node-views custom receiver target round-trips"
    :fn (fn []
            (local ctx (make-ctx))
            (local target (make-view-target ctx))
            (local custom-target (make-view-target ctx))
            (local saved-pt app.panel-transfer)
            (var views nil)
            (local (ok err)
              (pcall
                (fn []
                    (local pt (PanelTransfer.PanelTransfer))
                    (pt:register-receiver {:id "custom-view"
                                           :label "Custom View"
                                           :target-fn (fn [] custom-target)})
                    (set app.panel-transfer pt)
                    (local node {:key "custom-node"
                                 :label "Custom"
                                 :view (fn [_node]
                                           (fn [_builder-ctx _opts]
                                               (make-simple-view)))})
                    (local graph {:id "main" :nodes {}})
                    (set (. graph.nodes node.key) node)
                    (set graph.lookup (fn [_self key] (. graph.nodes key)))
                    (set graph.load-by-key (fn [_self key] (. graph.nodes key)))
                    (set views (GraphViewNodeViews {:ctx ctx
                                                    :graph-map graph
                                                    :view-target target}))
                    (views:open node {:target custom-target})
                    (local state (views:capture-state))
                    (local captured (. state.open-views 1))
                    (assert (= captured.target-kind "receiver")
                            "capture-state should record receiver target-kind for custom target")
                    (assert (= captured.target-receiver-id "custom-view")
                            "capture-state should record receiver id")
                    (views:drop-all)
                    (each [_ child (ipairs custom-target.children)]
                        (custom-target:remove-panel-child child))
                    (views:restore-state state)
                    (assert (= (length custom-target.children) 1)
                            "restore-state should reopen node view on custom receiver target")
                    (views:drop-all)
                    (set views nil))))
            (when views (views:drop-all))
            (set app.panel-transfer saved-pt)
    (when (not ok)
                (error err)))}
   {:name "graph view node-views transfer updates captured target"
    :fn (fn []
            (local ctx (make-ctx))
            (local source-target (make-view-target ctx))
            (local dest-target (make-view-target ctx))
            (local saved-pt app.panel-transfer)
            (var views nil)
            (local (ok err)
              (pcall
                (fn []
                    (local pt (PanelTransfer.PanelTransfer))
                    (pt:register-receiver {:id "dest-view"
                                           :label "Dest View"
                                           :target-fn (fn [] dest-target)})
                    (set app.panel-transfer pt)
                    (local node {:key "transfer-node"
                                 :label "Transfer"
                                 :view (fn [_node]
                                           (fn [_builder-ctx _opts]
                                               (make-simple-view)))})
                    (local graph {:id "main" :nodes {}})
                    (set (. graph.nodes node.key) node)
                    (set graph.lookup (fn [_self key] (. graph.nodes key)))
                    (set views (GraphViewNodeViews {:ctx ctx
                                                    :graph-map graph
                                                    :view-target source-target}))
                    (views:open node {:target source-target})
                    (local element (. source-target.children 1))
                    (assert element "source should contain opened node view")
                    (pt:transfer-panel {:id "dest-view"
                                        :label "Dest View"
                                        :target dest-target
                                        :receive (fn [_receiver payload]
                                                   (dest-target:add-panel-child payload))
                                        :rollback (fn [_receiver element]
                                                    (dest-target:remove-panel-child element))}
                                       source-target
                                       element
                                       element.__test_panel_opts)
                    (assert (= (length source-target.children) 0)
                            "transfer should remove source panel")
                    (assert (= (length dest-target.children) 1)
                            "transfer should add destination panel")
                    (local state (views:capture-state))
                    (local captured (. state.open-views 1))
                    (assert (= captured.target-kind "receiver")
                            "capture should use destination receiver after transfer")
                    (assert (= captured.target-receiver-id "dest-view")
                            "capture should store destination receiver id after transfer")
                    (views:drop-all)
                    (set views nil))))
            (when views (views:drop-all))
            (set app.panel-transfer saved-pt)
            (when (not ok)
                (error err)))}
   {:name "graph view node-views capture-state errors for unregistered custom target"
    :fn (fn []
            (local ctx (make-ctx))
            (local target (make-view-target ctx))
            (local custom-target (make-view-target ctx))
            (local saved-pt app.panel-transfer)
            (local pt (PanelTransfer.PanelTransfer))
            (set app.panel-transfer pt)
            (var views nil)
            (var capture-ok true)
            (pcall (fn []
                       (local node {:key "unreg-node"
                                    :label "Unreg"
                                    :view (fn [_node]
                                              (fn [_builder-ctx _opts]
                                                  (make-simple-view)))})
                        (local graph {:id "main" :nodes {}})
                       (set (. graph.nodes node.key) node)
                       (set graph.lookup (fn [_self key] (. graph.nodes key)))
                       (set graph.load-by-key (fn [_self key] (. graph.nodes key)))
                       (set views (GraphViewNodeViews {:ctx ctx
                                                       :graph-map graph
                                                       :view-target target}))
                       (views:open node {:target custom-target})
                       (views:capture-state)
                       (set capture-ok false)))
            (when views (views:drop-all))
            (set app.panel-transfer saved-pt)
             (assert capture-ok
                     "capture-state should error when target is not a registered receiver"))}
  {:name "graph view node-views default canvas placement uses bounded size"
   :fn (fn []
           (local ctx (make-ctx))
           (local target (make-view-target ctx))
           (set target.interaction-surface :canvas)
           (set target.default-panel-location "float")
           (set target.camera {:position (glm.vec3 12 34 99)})
           (local node {:key "canvas-size-node"
                        :label "Canvas Size Node"
                        :view (fn [_node]
                                  (fn [_builder-ctx _opts]
                                      (make-simple-view)))})
           (local views (GraphViewNodeViews {:ctx ctx :view-target target}))
           (views:open node)
           (local size (and target.last-add-panel-opts target.last-add-panel-opts.size))
           (assert size "new canvas node view should pass bounded default size")
           (assert (= size.x 32.0) "default canvas panel width should match inline card default")
           (assert (= size.y 18.0) "default canvas panel height should match inline card default")
           (assert (= size.z 0) "default canvas panel z size should be zero")
           (views:drop-all))}
  {:name "graph view node-views restored canvas placement preserves persisted size"
   :fn (fn []
           (local ctx (make-ctx))
           (local target (make-view-target ctx))
           (set target.interaction-surface :canvas)
           (set target.default-panel-location "float")
           (local node {:key "canvas-restored-size-node"
                        :label "Canvas Restored Size Node"
                        :view (fn [_node]
                                  (fn [_builder-ctx _opts]
                                      (make-simple-view)))})
           (local graph {:id "main" :nodes {}})
           (set (. graph.nodes node.key) node)
           (set graph.lookup (fn [_self key] (. graph.nodes key)))
           (local views (GraphViewNodeViews {:ctx ctx :graph-map graph :view-target target}))
           (views:restore-state {:open-views [{:node-key node.key
                                               :graph-map-id "main"
                                               :panel {:layer "float"
                                                       :size [44 22 0]}}]})
           (local size (and target.last-add-panel-opts target.last-add-panel-opts.size))
           (assert size "restored canvas node view should pass restored size")
           (assert (= size.x 44) "restored canvas panel width should come from persisted size")
           (assert (= size.y 22) "restored canvas panel height should come from persisted size")
           (views:drop-all))}
  {:name "graph view node-views restore does not auto-load nodes into map"
   :fn (fn []
           (local ctx (make-ctx))
           (local target (make-view-target ctx))
           (var load-by-key-called? false)
            (local graph {:id "main"
                          :lookup (fn [_self _key] nil)
                          :load-by-key (fn [_self _key]
                                          (set load-by-key-called? true)
                                          nil)})
           (local views (GraphViewNodeViews {:ctx ctx
                                             :graph-map graph
                                             :view-target target}))
            (local warnings
              (capture-warnings
                (fn []
                  (views:restore-state {:open-views [{:node-key "missing-node"
                                                      :graph-map-id "main"}]}))))
            (assert-unresolved-restored-warning warnings "missing-node")
            (assert (not load-by-key-called?)
                    "restore-state should not call load-by-key for missing nodes")
           (assert (= (length target.children) 0)
                   "restore-state should not add child for missing nodes")
           (views:drop-all))}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hackernews-graph-view-node-views"
                       :tests tests})))

{:name "hackernews-graph-view-node-views"
 :tests tests
 :main main}
