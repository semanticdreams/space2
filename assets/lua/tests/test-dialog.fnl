(local glm (require :glm))
(local _ (require :main))
(local Dialog (require :dialog))
(local DefaultDialog (require :default-dialog))
(local Scene (require :scene))
(local Hud (require :hud))
(local Camera (require :camera))
(local Canvas (require :canvas))
(local AppProjection (require :app-projection))
(local MathUtils (require :math-utils))
(local {: Layout} (require :layout))
(local Tiles (require :tiles))
(local FloatLayer (require :float-layer))
(local Intersectables (require :intersectables))
(local Resizables (require :resizables))
(local PanelUtils (require :target-panel-utils))

(local tests [])

(local approx (. MathUtils :approx))
(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(fn color= [a b]
  (and (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)
       (approx a.w b.w)))

(fn make-vector-buffer []
  (local buffer {})
  (set buffer.allocate (fn [_self _count] 1))
  (set buffer.delete (fn [_self _handle] nil))
  (set buffer.set-glm-vec3 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec4 (fn [_self _handle _offset _value] nil))
  (set buffer.set-glm-vec2 (fn [_self _handle _offset _value] nil))
  (set buffer.set-float (fn [_self _handle _offset _value] nil))
  buffer)

(fn make-test-ctx [opts]
  (local options (or opts {}))
  (local triangle (make-vector-buffer))
  (local text-buffer (make-vector-buffer))
  (local ctx {:triangle-vector triangle
              :pointer-target {}})
  (set ctx.get-text-vector (fn [_self _font] text-buffer))
  (set ctx.get-text-ssbo-batcher
       (fn [_self]
         {:upsert-text (fn [_batcher _key _opts] nil)
          :update-text-transform (fn [_batcher _key _opts] nil)
          :remove-text (fn [_batcher _key] nil)}))
  (set ctx.icons options.icons)
  (set ctx.clickables (assert options.clickables "dialog test context requires clickables"))
  (set ctx.hoverables (assert options.hoverables "dialog test context requires hoverables"))
  (set ctx.system-cursors options.cursors)
  ctx)

(fn make-icons-stub []
  (local glyph {:advance 1
                :planeBounds {:left 0 :right 1 :top 1 :bottom 0}
                :atlasBounds {:left 0 :right 1 :top 1 :bottom 0}})
  (local font {:metadata {:metrics {:ascender 1 :descender -1}
                          :atlas {:width 1 :height 1}}
               :glyph-map {4242 glyph}
               :advance 1})
  (local stub {:font font
               :codepoints {:refresh 4242
                            :close 4242
                            :cancel 4242
                            :move_item 4242
                            :wallet 4242}})
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

(fn make-clickables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  (set stub.register-right-click (fn [_self _obj] nil))
  (set stub.unregister-right-click (fn [_self _obj] nil))
  (set stub.register-double-click (fn [_self _obj] nil))
  (set stub.unregister-double-click (fn [_self _obj] nil))
  stub)

(fn make-hoverables-stub []
  (local stub {})
  (set stub.register (fn [_self _obj] nil))
  (set stub.unregister (fn [_self _obj] nil))
  stub)

(fn make-stub-movables []
  (local registered [])
  (local movables {:registered registered :unregistered []})
  (set movables.register
       (fn [self widget opts]
         (table.insert self.registered {:widget widget
                                        :opts opts})))
  (set movables.unregister
       (fn [self key]
         (table.insert self.unregistered key)))
  movables)

(fn make-resize-intersector []
  (local stub {:selection-point nil
               :selection-pointer-target nil
               :next-ray nil})
  (set stub.pointer (fn [_ payload]
                      (or payload.pointer payload)))
  (set stub.select-entry
       (fn [self objects pointer _opts]
         (set self.last-select {:objects objects :pointer pointer})
         (if (and self.selection-point (> (# objects) 0))
             (do
               (local obj (. objects 1))
               (when obj
                 {:object obj
                  :point self.selection-point
                  :pointer-target (or self.selection-pointer-target obj.pointer-target)
                  :distance 0.5}))
             nil)))
  (set stub.resolve-ray
       (fn [self pointer target]
         (set self.last-resolve {:pointer pointer :target target})
         self.next-ray))
  stub)

(fn world->screen [world units-per-pixel viewport]
  {:x (+ (/ world.x units-per-pixel) (/ viewport.width 2))
   :y (- (/ viewport.height 2) (/ world.y units-per-pixel))})

(fn make-default-camera []
  (Camera {:position (glm.vec3 0 0 0)}))

(fn make-test-hud-builder []
  (fn [ctx]
    (local tiles ((Tiles {:rows 4
                          :columns 4
                          :xspacing 0.5
                          :yspacing 0.5}) ctx))
    (local float ((FloatLayer {}) ctx))

    (fn measurer [self]
      (tiles.layout:measurer)
      (float.layout:measurer)
      (local width (math.max 1 tiles.layout.measure.x float.layout.measure.x))
      (local height (math.max 1 tiles.layout.measure.y float.layout.measure.y))
      (local depth (math.max tiles.layout.measure.z float.layout.measure.z))
      (set self.measure (glm.vec3 width height depth)))

    (fn layouter [self]
      (set self.size self.measure)
      (set tiles.layout.size self.size)
      (set tiles.layout.position self.position)
      (set tiles.layout.rotation self.rotation)
      (set tiles.layout.depth-offset-index self.depth-offset-index)
      (set tiles.layout.clip-region self.clip-region)
      (tiles.layout:layouter)
      (set float.layout.size self.size)
      (set float.layout.position self.position)
      (set float.layout.rotation self.rotation)
      (set float.layout.depth-offset-index (+ self.depth-offset-index 1))
      (set float.layout.clip-region self.clip-region)
      (float.layout:layouter))

    (local layout
      (Layout {:name "test-hud-root"
               :measurer measurer
               :layouter layouter
               :children [tiles.layout float.layout]}))

    (fn drop [_self]
      (layout:drop)
      (tiles:drop)
      (float:drop))

    {:layout layout
     :drop drop
     :tiles-root tiles
     :float-root float}))

(fn make-system-cursors-stub []
  (local stub {})
  (set stub.set-cursor (fn [_self _name] nil))
  (set stub.reset (fn [_self] nil))
  stub)

(fn with-dialog-stubs [body]
  (local icons (make-icons-stub))
  (local clickables (assert (make-clickables-stub) "dialog test requires clickables"))
  (local hoverables (assert (make-hoverables-stub) "dialog test requires hoverables"))
  (local cursors (make-system-cursors-stub))
  (local ctx (make-test-ctx {:icons icons
                             :clickables clickables
                             :hoverables hoverables
                             :cursors cursors}))
  (let [(ok result) (pcall body {:ctx ctx
                                 :icons icons
                                 :clickables clickables
                                 :hoverables hoverables
                                 :cursors cursors})]
    (if ok result (error result))))

(fn make-probe-widget [name]
  (local state {:drop-called false
                :drop-count 0
                :instance nil})
  (local layout-name (or name "dialog-test-child"))
  (local builder
    (fn [_ctx]
      (local layout
        (Layout {:name layout-name
                 :measurer (fn [self]
                             (set self.measure (glm.vec3 1 1 1)))
                 :layouter (fn [_self] nil)}))
      (local widget {:layout layout})
      (set widget.drop (fn [_self]
                         (set state.drop-called true)
                         (set state.drop-count (+ state.drop-count 1))))
      (set state.instance widget)
      widget))
  {:builder builder :state state})

(fn resolve-dialog-element [dialog]
  (or dialog.__front_widget dialog.front dialog))

(fn unwrap-hud-element [element]
  (or (and element element.__hud_inner) element))

(fn find-action-row [dialog]
  (local target (resolve-dialog-element dialog))
  (local titlebar-meta (. target.children 1))
  (local titlebar titlebar-meta.element)
  (local title-flex (. titlebar.children 2))
  (local action-row-meta (. title-flex.children (length title-flex.children)))
  action-row-meta.element)

(fn make-scene-and-hud [opts]
  (local options (or opts {}))
  (local originals {:scene app.scene
                    :layout-root app.layout-root
                    :hud app.hud
                    :camera app.camera
                    :create-default-projection app.create-default-projection})
  (var scene nil)
  (var hud nil)
  (var camera nil)

  (fn cleanup []
    (when scene
      (scene:drop)
      (set scene nil))
    (when hud
      (hud:drop)
      (set hud nil))
    (when camera
      (camera:drop)
      (set camera nil))
    (set app.scene originals.scene)
    (set app.layout-root originals.layout-root)
    (set app.hud originals.hud)
    (set app.camera originals.camera)
    (set app.create-default-projection originals.create-default-projection))

  (let [(ok result)
        (pcall
          (fn []
            (set camera (make-default-camera))
            (set app.camera camera)
            (set app.create-default-projection AppProjection.create-default-projection)
            (set scene (Scene {:icons options.icons
                               :camera camera}))
            (set hud (Hud {:scene scene
                               :icons options.icons}))
            (set app.scene scene)
            (set app.layout-root scene.layout-root)
            (set app.hud hud)

            (scene:ensure-activity-slot "sandbox")
            (scene:activate-activity-slot "sandbox")
            (scene:build-default)

            (hud:build (make-test-hud-builder))
            {:scene scene :hud hud}))]
    (if ok
        {:cleanup cleanup :scene scene :hud hud}
        (do
          (cleanup)
          (error result)))))

(fn dialog-requires-title []
  (local child (make-probe-widget "child-a"))
  (let [(ok err) (pcall (fn []
                          (Dialog {:child child.builder})))]
    (assert (not ok))
    (assert (string.find err "Dialog requires :title"))))

(fn dialog-requires-child []
  (let [(ok err) (pcall (fn []
                          (Dialog {:title "Invalid"})))]
    (assert (not ok))
    (assert (string.find err "Dialog requires :child"))))

(fn dialog-wraps-titlebar-and-body-in-cards []
  (with-dialog-stubs
    (fn [env]
      (local child (make-probe-widget "dialog-body-child"))
      (local builder (Dialog {:title "Sample"
                              :child child.builder}))
      (local dialog (builder env.ctx))
      (local titlebar-meta (. dialog.children 1))
      (local body-meta (. dialog.children 2))
      (assert titlebar-meta)
      (assert body-meta)
      (local titlebar titlebar-meta.element)
      (local body body-meta.element)
      (assert (= titlebar.layout.name "stack"))
      (assert (= body.layout.name "stack"))
      (local title-rectangle (. titlebar.children 1))
      (local body-rectangle (. body.children 1))
      (assert (= title-rectangle.layout.name "rectangle"))
      (assert (= body-rectangle.layout.name "rectangle"))
      (local title-flex (. titlebar.children 2))
      (assert (= title-flex.layout.name "flex"))
      (local body-content (. body.children 2))
      (assert (= body-content.layout.name "padding"))
      (assert (= body-content.child child.state.instance))
      (dialog:drop)
      (assert child.state.drop-called))))

(fn dialog-actions-create-icon-buttons []
  (with-dialog-stubs
    (fn [env]
      (local child (make-probe-widget "with-actions"))
      (var refresh-count 0)
      (var close-count 0)
      (local builder
        (Dialog
          {:title "Actions"
           :child child.builder
           :actions [["refresh"
                      (fn [_button _event]
                        (set refresh-count (+ refresh-count 1)))]
                     {:name "close"
                      :icon "cancel"
                      :on-click (fn [_button _event]
                                  (set close-count (+ close-count 1)))}]}))
      (local dialog (builder env.ctx))
      (local titlebar-meta (. dialog.children 1))
      (local titlebar titlebar-meta.element)
      (local title-flex (. titlebar.children 2))
      (local action-row-meta (. title-flex.children (length title-flex.children)))
      (local action-row action-row-meta.element)
      (assert (= (length action-row.children) 2))
      (local refresh-meta (. action-row.children 1))
      (local refresh-button refresh-meta.element)
      (local close-meta (. action-row.children 2))
      (local close-button close-meta.element)
      (assert (= refresh-button.icon "refresh"))
      (assert (= close-button.icon "cancel"))
      (refresh-button:on-click {:button 1})
      (close-button:on-click {:button 1})
      (assert (= refresh-count 1))
      (assert (= close-count 1))
      (dialog:drop)
      (assert child.state.drop-called))))

(fn dialog-without-actions-omits-spacer []
  (with-dialog-stubs
    (fn [env]
      (local child (make-probe-widget "no-actions"))
      (local dialog ((Dialog {:title "Solo" :child child.builder}) env.ctx))
      (local titlebar-meta (. dialog.children 1))
      (local titlebar titlebar-meta.element)
      (local title-flex (. titlebar.children 2))
      (assert (= (length title-flex.children) 1))
      (dialog:drop)
      (assert child.state.drop-called))))

(fn dialog-titlebar-uses-action-button-color []
  (with-dialog-stubs
    (fn [env]
      (local theme ((require :light-theme)))
      (local action-color theme.button.variants.tertiary.background)
      (assert action-color "LightTheme must expose tertiary background for default dialog titlebars")
      (set env.ctx.theme theme)
      (local child (make-probe-widget "color-match"))
      (local dialog ((Dialog {:title "Themed"
                              :child child.builder
                              :actions [{:name "close"}]}) env.ctx))
      (local titlebar-meta (. dialog.children 1))
      (local titlebar titlebar-meta.element)
      (local title-rectangle (. titlebar.children 1))
      (local title-color title-rectangle.color)
      (local title-flex (. titlebar.children 2))
      (local action-row-meta (. title-flex.children (length title-flex.children)))
      (local action-row action-row-meta.element)
      (local button-meta (. action-row.children 1))
      (local button button-meta.element)
      (assert (color= title-color action-color))
      (assert (color= button.background-color action-color))
      (assert (not (color= title-color theme.button.variants.secondary.background))
              "Default light dialog titlebar should not fall back to secondary")
      (dialog:drop)
      (assert child.state.drop-called))))

(fn default-dialog-close-button-calls-on-close-once []
  (with-dialog-stubs
    (fn [env]
      (local child (make-probe-widget "default-close-child"))
      (var close-count 0)
      (local dialog ((DefaultDialog {:title "Closable"
                                     :child child.builder
                                     :on-close (fn [instance _button _event]
                                                 (set close-count (+ close-count 1))
                                                 (when instance
                                                   (instance:drop)))})
                     env.ctx))
      (local action-row (find-action-row dialog))
      (assert (= (length action-row.children) 2))
      (local toggle-meta (. action-row.children 1))
      (local close-meta (. action-row.children 2))
      (local toggle-button toggle-meta.element)
      (local close-button close-meta.element)
      (assert (= close-button.icon "close"))
      (assert (= toggle-button.icon "move_item"))
      (close-button:on-click {:button 1})
      (close-button:on-click {:button 1})
      (assert (= close-count 1))
      (assert child.state.drop-called))))

(fn default-dialog-toggle-moves-between-scene-and-hud []
  (with-dialog-stubs
    (fn [_env]
      (local resources (make-scene-and-hud {:icons _env.icons}))
      (local scene resources.scene)
      (local hud resources.hud)

      (let [(ok err)
            (pcall
              (fn []
                (local child (make-probe-widget "toggle-child"))
                (local dialog-builder (DefaultDialog {:title "Toggle"
                                                      :child child.builder}))
                (local element (scene:add-panel-child {:builder dialog-builder}))
                (assert element "Dialog should be created in scene flex root")
                (assert (= (length scene.scene-children) 1)
                        "Scene should contain dialog before toggle")

                (local action-row (find-action-row element))
                (local toggle-meta (. action-row.children 1))
                (local toggle-button toggle-meta.element)
                (toggle-button:on-click {:button 1})

                (assert (= (length scene.scene-children) 0)
                        "Dialog should detach from scene after toggling")
                (assert (= (length hud.tiles.children) 1)
                        "Dialog should appear in HUD tiles after toggling")
                (assert (= child.state.drop-count 1)
                        "Moving dialog should drop the original instance")

                (local hud-element (. hud.tiles.children 1))
                (local hud-inner (unwrap-hud-element hud-element.element))
                (local hud-action-row (find-action-row hud-inner))
                (local hud-toggle-meta (. hud-action-row.children 1))
                (local hud-toggle hud-toggle-meta.element)
                (hud-toggle:on-click {:button 1})

                (assert (= (length hud.tiles.children) 0)
                        "Dialog should detach from HUD tiles after toggling back")
                (assert (= (length scene.scene-children) 1)
                        "Dialog should return to scene after toggling back")
                (assert (= child.state.drop-count 2)
                        "Moving dialog twice should drop each prior instance")))]
        (resources.cleanup)
        (when (not ok)
          (error err))))))

(fn default-dialog-close-after-toggle-clears-both-roots []
  (with-dialog-stubs
    (fn [_env]
      (local resources (make-scene-and-hud {:icons _env.icons}))
      (local scene resources.scene)
      (local hud resources.hud)

      (let [(ok err)
            (pcall
              (fn []
                (local child (make-probe-widget "toggle-close-child"))
                (local dialog-builder (DefaultDialog {:title "Toggle Close"
                                                      :child child.builder}))
                (local element (scene:add-panel-child {:builder dialog-builder}))
                (local action-row (find-action-row element))
                (local toggle-button (. (. action-row.children 1) :element))
                (toggle-button:on-click {:button 1})
                (assert (= (length scene.scene-children) 0))
                (assert (= (length hud.tiles.children) 1))
                (local hud-element (. (. hud.tiles.children 1) :element))
                (local hud-inner (unwrap-hud-element hud-element))
                (local hud-action-row (find-action-row hud-inner))
                (local close-button (. (. hud-action-row.children 2) :element))
                (close-button:on-click {:button 1})
                (assert (= (length scene.scene-children) 0)
                        "Scene should stay empty after closing from HUD")
                (assert (= (length hud.tiles.children) 0)
                        "HUD should lose dialog after close")
                (assert (= child.state.drop-count 2)
                        "Toggle then close should drop both instances")))]
        (resources.cleanup)
        (when (not ok)
          (error err))))))

(fn default-dialog-multi-toggle-does-not-duplicate []
  (with-dialog-stubs
    (fn [_env]
      (local resources (make-scene-and-hud {:icons _env.icons}))
      (local scene resources.scene)
      (local hud resources.hud)

      (let [(ok err)
            (pcall
              (fn []
                (local child (make-probe-widget "multi-toggle-child"))
                (local dialog-builder (DefaultDialog {:title "Multi Toggle"
                                                      :child child.builder}))
                (local element (scene:add-panel-child {:builder dialog-builder}))
                (var current element)

                (fn toggle-and-assert [expected-scene expected-hud]
                  (local action-row (find-action-row current))
                  (local toggle-button (. (. action-row.children 1) :element))
                  (toggle-button:on-click {:button 1})
                  (assert (= (length scene.scene-children) expected-scene)
                          "Scene child count mismatch after toggle")
                  (assert (= (length hud.tiles.children) expected-hud)
                          "HUD child count mismatch after toggle")
                  (set current
                       (if (= expected-hud 1)
                           (unwrap-hud-element (. (. hud.tiles.children 1) :element))
                           (. (. scene.scene-children 1) :element))))

                (toggle-and-assert 0 1)
                (toggle-and-assert 1 0)
                (toggle-and-assert 0 1)
                (assert (= child.state.drop-count 3)
                        "Each toggle should drop the previous instance")))]
        (resources.cleanup)
        (when (not ok)
          (error err))))))

(fn hud-tiles-register-movables []
  (with-dialog-stubs
    (fn [_env]
      (local originals {:scene app.scene
                        :layout-root app.layout-root
                        :hud app.hud
                        :movables app.movables
                        :camera app.camera
                        :create-default-projection app.create-default-projection})
      (var scene nil)
      (var hud nil)
      (local movables (make-stub-movables))
      (var camera nil)

      (fn cleanup []
        (when scene
          (scene:drop)
          (set scene nil))
        (when hud
          (hud:drop)
          (set hud nil))
        (when camera
          (camera:drop)
          (set camera nil))
        (set app.scene originals.scene)
        (set app.layout-root originals.layout-root)
        (set app.hud originals.hud)
        (set app.movables originals.movables)
        (set app.camera originals.camera)
        (set app.create-default-projection originals.create-default-projection))

      (let [(ok err)
            (pcall
              (fn []
                (set camera (make-default-camera))
                (set app.camera camera)
                (set app.create-default-projection AppProjection.create-default-projection)
                (set scene (Scene {:icons _env.icons
                                   :camera camera}))
                (set hud (Hud {:scene scene
                               :icons _env.icons}))
                (set app.scene scene)
                (set app.layout-root scene.layout-root)
                (set app.hud hud)
                (set app.movables movables)

                (scene:ensure-activity-slot "sandbox")
                (scene:activate-activity-slot "sandbox")
                (scene:build-default)

                (hud:build (make-test-hud-builder))

                (local child (make-probe-widget "hud-movable-child"))
                (local dialog-builder (DefaultDialog {:title "HUD Movable"
                                                      :child child.builder}))
                (local element (hud:add-panel-child {:builder dialog-builder}))
                (assert element "Expected dialog to be added to HUD tiles")
                (assert (= (length hud.tiles.children) 1)
                        "HUD tiles should contain the dialog")
                (local registered-count (length movables.registered))
                (assert (>= registered-count 1)
                        (string.format "HUD movables should register the dialog (registered=%s)"
                                       registered-count))
                (assert (= (length hud.entity.__hud_movable_keys) 1)
                        "HUD entity should track its movable key")

                (local action-row (find-action-row element))
                (local close-button (. (. action-row.children 2) :element))
                (close-button:on-click {:button 1})

                (assert (= (length hud.tiles.children) 0)
                        "Closing dialog should remove it from HUD tiles")
                (assert (>= (length movables.unregistered) 1)
                        "Closing dialog should unregister its movable")
                (assert (or (not hud.entity.__hud_movable_keys)
                            (= (length hud.entity.__hud_movable_keys) 0))
                        "Movable keys should clear after closing dialog")))]
        (cleanup)
        (when (not ok)
          (error err))))))

(fn hud-tiles-promote-to-float-on-drag []
  (with-dialog-stubs
    (fn [_env]
      (local originals {:scene app.scene
                        :layout-root app.layout-root
                        :hud app.hud
                        :movables app.movables
                        :camera app.camera
                        :create-default-projection app.create-default-projection})
      (var scene nil)
      (var hud nil)
      (local movables (make-stub-movables))
      (var camera nil)

      (fn cleanup []
        (when scene
          (scene:drop)
          (set scene nil))
        (when hud
          (hud:drop)
          (set hud nil))
        (when camera
          (camera:drop)
          (set camera nil))
        (set app.scene originals.scene)
        (set app.layout-root originals.layout-root)
        (set app.hud originals.hud)
        (set app.movables originals.movables)
        (set app.camera originals.camera)
        (set app.create-default-projection originals.create-default-projection))

      (let [(ok err)
            (pcall
              (fn []
                (set camera (make-default-camera))
                (set app.camera camera)
                (set app.create-default-projection AppProjection.create-default-projection)
                (set scene (Scene {:icons _env.icons
                                   :camera camera}))
                (set hud (Hud {:scene scene
                               :icons _env.icons}))
                (set app.scene scene)
                (set app.layout-root scene.layout-root)
                (set app.hud hud)
                (set app.movables movables)

                (scene:ensure-activity-slot "sandbox")
                (scene:activate-activity-slot "sandbox")
                (scene:build-default)
                (hud:build (make-test-hud-builder))

                (local child (make-probe-widget "hud-drag-child"))
                (local dialog-builder (DefaultDialog {:title "HUD Drag"
                                                      :child child.builder}))
                (local element (hud:add-panel-child {:builder dialog-builder}))
                (assert element "Expected dialog to be added to HUD tiles")
                (assert (= (length hud.tiles.children) 1))
                (assert (= (length hud.float.children) 0))

                (var movable-entry nil)
                (each [_ entry (ipairs movables.registered)]
                  (when (and (not movable-entry)
                             entry.opts
                             (= entry.widget element.__hud_wrapper))
                    (set movable-entry entry)))
                (assert movable-entry "Expected movables entry for HUD tile")
                (assert movable-entry.opts.on-drag-start
                        "Expected HUD tiles to register a drag-start handler")
                (movable-entry.opts.on-drag-start {:target element.__hud_wrapper.layout})

                (assert (= (length hud.tiles.children) 0)
                        "Dragging should remove the dialog from tiles")
                (assert (= (length hud.float.children) 1)
                        "Dragging should move the dialog into float")
                (assert (= (. (. hud.float.children 1) :element) element.__hud_wrapper)
                        "Floating dialog should be the same instance")
                (assert (not child.state.drop-called)
                        "Dragging to float should not drop the dialog")))]
        (cleanup)
        (when (not ok)
          (error err))))))

(fn hud-tiles-promote-to-float-on-resize []
  (with-dialog-stubs
    (fn [_env]
      (local originals {:scene app.scene
                        :layout-root app.layout-root
                        :hud app.hud
                        :movables app.movables
                        :resizables app.resizables
                        :camera app.camera
                        :create-default-projection app.create-default-projection})
      (var scene nil)
      (var hud nil)
      (var resizables nil)
      (var intersector nil)
      (var camera nil)

      (fn cleanup []
        (when scene
          (scene:drop)
          (set scene nil))
        (when hud
          (hud:drop)
          (set hud nil))
        (when camera
          (camera:drop)
          (set camera nil))
        (set app.scene originals.scene)
        (set app.layout-root originals.layout-root)
        (set app.hud originals.hud)
        (set app.movables originals.movables)
        (set app.resizables originals.resizables)
        (set app.camera originals.camera)
        (set app.create-default-projection originals.create-default-projection))
      (fn run-test []
        (set intersector (make-resize-intersector))
        (set resizables (Resizables {:intersectables intersector}))
        (set app.resizables resizables)
        (set camera (make-default-camera))
        (set app.camera camera)
        (set app.create-default-projection AppProjection.create-default-projection)

        (set scene (Scene {:icons _env.icons
                           :camera camera}))
        (set hud (Hud {:scene scene
                       :icons _env.icons}))
        (set app.scene scene)
        (set app.layout-root scene.layout-root)
        (set app.hud hud)

        (scene:ensure-activity-slot "sandbox")
        (scene:activate-activity-slot "sandbox")
        (scene:build-default)
        (hud:build (make-test-hud-builder))

        (local child (make-probe-widget "hud-resize-child"))
        (local dialog-builder (DefaultDialog {:title "HUD Resize"
                                              :child child.builder}))
        (local element (hud:add-panel-child {:builder dialog-builder}))
        (assert element "Expected dialog to be added to HUD tiles")
        (assert (= (length hud.tiles.children) 1))
        (assert (= (length hud.float.children) 0))

        (var resizable-entry nil)
        (each [_ entry (ipairs resizables.entries)]
          (when (and (not resizable-entry)
                     (= entry.key element.__hud_wrapper))
            (set resizable-entry entry)))
        (assert resizable-entry "Expected resizables entry for HUD tile")
        (assert resizable-entry.on-resize-start
                "Expected HUD tiles to register a resize-start handler")
        (resizable-entry.on-resize-start resizable-entry {})

        (assert (= (length hud.tiles.children) 0)
                "Resizing should remove the dialog from tiles")
        (assert (= (length hud.float.children) 1)
                "Resizing should move the dialog into float")
        (assert (= (. (. hud.float.children 1) :element) element.__hud_wrapper)
                "Resized dialog should be the same instance")
        (assert (not child.state.drop-called)
                "Resizing to float should not drop the dialog"))

      (local (ok err) (pcall run-test))
      (cleanup)
      (when (not ok)
        (error err)))))

(fn run-hud-float-resize-test [env]
  (set app.intersectables (Intersectables))
  (set app.resizables (Resizables {:intersectables app.intersectables}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (set app.create-default-projection AppProjection.create-default-projection)
  (local camera (make-default-camera))
  (set app.camera camera)
  (set app.presentation-camera (fn [_opts] camera))
  (local scene (Scene {:icons env.icons
                       :camera camera}))
  (local hud (Hud {:scene scene
                   :icons env.icons}))
  (set app.scene scene)
  (set app.layout-root scene.layout-root)
  (set app.hud hud)

  (scene:ensure-activity-slot "sandbox")
  (scene:activate-activity-slot "sandbox")
  (scene:build-default)
  (hud:build (make-test-hud-builder))
  (hud:update-projection app.viewport)
  (hud:update)

  (local float-layout (and hud.float hud.float.layout))
  (assert float-layout "HUD resize test requires float layout")
  (local float-center
    (+ float-layout.position
       (glm.vec3 (/ float-layout.size.x 2)
                 (/ float-layout.size.y 2)
                 0)))
  (local child (make-probe-widget "hud-float-resize-child"))
  (local dialog-builder (DefaultDialog {:title "HUD Float Resize"
                                        :child child.builder}))
  (local element (hud:add-panel-child {:builder dialog-builder
                                       :location :float
                                       :position float-center
                                       :size (glm.vec3 10 6 0)}))
  (assert element "Expected dialog to be added to HUD float")
  (hud:update)
  (assert (and hud.entity hud.entity.__hud_resizable_keys)
          "HUD resizables should be registered")

  (local wrapper element.__hud_wrapper)
  (local layout (and wrapper wrapper.layout))
  (assert layout "HUD resize test requires wrapper layout")
  (local initial-size (or layout.size layout.measure (glm.vec3 0 0 0)))
  (local offset (glm.vec3 (- initial-size.x 0.2)
                          (- initial-size.y 0.2)
                          0))
  (local world-pos (+ layout.position offset))
  (local pointer (world->screen world-pos hud.world-units-per-pixel app.viewport))
  (app.resizables:on-mouse-button-down {:button 3 :x pointer.x :y pointer.y})
  (app.resizables:on-mouse-motion {:x (+ pointer.x 20) :y (+ pointer.y 10)})
  (app.resizables:on-mouse-button-up {:button 3 :x (+ pointer.x 20) :y (+ pointer.y 10)})
  (hud:update)
  (local final-size (or layout.size layout.measure (glm.vec3 0 0 0)))
  (assert (> final-size.x initial-size.x)
          "HUD float resize should increase width")
  {:scene scene
   :hud hud
   :camera camera})

(fn run-with-cleanup [cleanup f]
  (local (ok err)
    (pcall f))
  (cleanup)
  (when (not ok)
    (error err)))

(fn hud-float-resize-updates-layout []
  (with-dialog-stubs
    (fn [env]
      (local originals {:scene app.scene
                        :layout-root app.layout-root
                        :hud app.hud
                        :intersectables app.intersectables
                        :resizables app.resizables
                        :presentation-camera app.presentation-camera})
      (var scene nil)
      (var hud nil)
      (var camera nil)
      (fn cleanup []
        (when scene
          (scene:drop)
          (set scene nil))
        (when hud
          (hud:drop)
          (set hud nil))
        (when camera
          (camera:drop)
          (set camera nil))
        (set app.scene originals.scene)
        (set app.layout-root originals.layout-root)
        (set app.hud originals.hud)
        (set app.intersectables originals.intersectables)
        (set app.resizables originals.resizables)
        (set app.presentation-camera originals.presentation-camera))
      (run-with-cleanup
        cleanup
        (fn []
          (local result (run-hud-float-resize-test env))
          (set scene result.scene)
          (set hud result.hud)
          (set camera result.camera))))))

(fn run-scene-resize-test [env]
  (set app.intersectables (Intersectables))
  (set app.resizables (Resizables {:intersectables app.intersectables}))
  (set app.viewport {:x 0 :y 0 :width 800 :height 600})
  (set app.create-default-projection AppProjection.create-default-projection)
  (local camera (make-default-camera))
  (set app.camera camera)
  (set app.presentation-camera (fn [_opts] camera))
  (local scene (Scene {:icons env.icons
                       :camera camera}))
  (set app.scene scene)
  (set app.layout-root scene.layout-root)
  (scene:ensure-activity-slot "sandbox" {:camera camera})
  (scene:activate-activity-slot "sandbox")
  (scene:build-default)

  (local half-width 20)
  (local half-height 15)
  (set scene.projection (glm.ortho (- half-width) half-width (- half-height) half-height -100.0 100.0))
  (scene:update)

  (local child (make-probe-widget "scene-resize-child"))
  (local dialog-builder (DefaultDialog {:title "Scene Resize"
                                        :child child.builder}))
  (local element (scene:add-panel-child {:builder dialog-builder
                                         :skip-cuboid true
                                         :position (glm.vec3 0 0 0)
                                         :rotation (glm.quat 1 0 0 0)}))
  (assert element "Expected dialog to be added to scene")
  (scene:update)
  (assert (and scene.entity scene.entity.__scene_resizable_keys)
          "Scene resizables should be registered")

  (local layout (and element element.layout))
  (assert layout "Scene resize test requires layout")
  (local initial-size (or layout.size layout.measure (glm.vec3 0 0 0)))
  (local offset (glm.vec3 (- initial-size.x 0.2)
                          (- initial-size.y 0.2)
                          0))
  (local world-pos (+ layout.position offset))
  (local units-per-pixel (/ (* 2 half-width) app.viewport.width))
  (local pointer (world->screen world-pos units-per-pixel app.viewport))
  (app.resizables:on-mouse-button-down {:button 3 :x pointer.x :y pointer.y})
  (app.resizables:on-mouse-motion {:x (+ pointer.x 20) :y (+ pointer.y 10)})
  (app.resizables:on-mouse-button-up {:button 3 :x (+ pointer.x 20) :y (+ pointer.y 10)})
  (scene:update)
  (local final-size (or layout.size layout.measure (glm.vec3 0 0 0)))
  (assert (> final-size.x initial-size.x)
          "Scene resize should increase width")
  {:scene scene
   :camera camera})

(fn scene-resize-updates-layout []
  (with-dialog-stubs
    (fn [env]
      (local originals {:scene app.scene
                        :layout-root app.layout-root
                        :intersectables app.intersectables
                        :resizables app.resizables
                        :viewport app.viewport
                        :create-default-projection app.create-default-projection
                        :camera app.camera
                        :presentation-camera app.presentation-camera})
      (var scene nil)
      (var camera nil)
      (fn cleanup []
        (when scene
          (scene:drop)
          (set scene nil))
        (when camera
          (camera:drop)
          (set camera nil))
        (set app.scene originals.scene)
        (set app.layout-root originals.layout-root)
        (set app.intersectables originals.intersectables)
        (set app.resizables originals.resizables)
        (set app.viewport originals.viewport)
        (set app.create-default-projection originals.create-default-projection)
        (set app.camera originals.camera)
        (set app.presentation-camera originals.presentation-camera))
      (run-with-cleanup
        cleanup
        (fn []
          (local result (run-scene-resize-test env))
          (set scene result.scene)
          (set camera result.camera))))))

(fn hud-capture-state-requires-panel-persistence []
  (with-dialog-stubs
    (fn [env]
      (local resources (make-scene-and-hud {:icons env.icons}))
      (local cleanup resources.cleanup)
      (local hud resources.hud)
      (local child (make-probe-widget "hud-persistence-required"))
      (local dialog-builder
        (DefaultDialog {:title "No Persistence"
                        :child child.builder}))
      (var state nil)
      (local (ok err)
        (pcall
          (fn []
            (hud:add-panel-child {:builder dialog-builder})
            (set state (hud:capture-state)))))
      (cleanup)
      (assert ok "Hud.capture-state should not throw when a panel has no persistence")
      (assert (= (length state.panels) 0) "Hud.capture-state should skip panels without persistence")
      true)))

(fn hud-capture-and-restore-persistent-panel []
  (with-dialog-stubs
    (fn [env]
      (local resources (make-scene-and-hud {:icons env.icons}))
      (local cleanup resources.cleanup)
      (local hud resources.hud)
      (local child (make-probe-widget "hud-persist-dialog"))
      (local dialog-builder
        (DefaultDialog {:title "Persisted HUD Dialog"
                        :child child.builder}))
      (local kind "dialog-test-probe")
      (hud:register-panel-restorer
        kind
        (fn [panel]
          (local placement (PanelUtils.panel-placement-options hud panel))
          (hud:add-panel-child {:builder dialog-builder
                                :location placement.location
                                :position placement.position
                                :rotation placement.rotation
                                :size placement.size
                                :align-x placement.align-x
                                :align-y placement.align-y
                                :persistence {:kind kind}})))
      (local element
        (hud:add-panel-child {:builder dialog-builder
                              :location :float
                              :position (glm.vec3 2 3 0)
                              :rotation (glm.quat 1 0 0 0)
                              :size (glm.vec3 12 8 0)
                              :persistence {:kind kind}}))
      (local captured (hud:capture-state))
      (assert (= (length (or captured.panels [])) 1)
              "Hud.capture-state should persist one panel")
      (hud:remove-panel-child element)
      (assert (= (length (or hud.float.children [])) 0))
      (hud:restore-state captured)
      (assert (= (length (or hud.float.children [])) 1)
              "Hud.restore-state should recreate persisted float panel")
      (hud:unregister-panel-restorer kind)
      (cleanup)
      true)))

(fn hud-capture-state-requires-restore-strategy []
  (with-dialog-stubs
    (fn [env]
      (local resources (make-scene-and-hud {:icons env.icons}))
      (local cleanup resources.cleanup)
      (local hud resources.hud)
      (local child (make-probe-widget "hud-missing-restore-strategy"))
      (local dialog-builder
        (DefaultDialog {:title "Missing Restore Strategy"
                        :child child.builder}))
      (local (ok err)
        (pcall
          (fn []
            (hud:add-panel-child {:builder dialog-builder
                                  :persistence {:kind "missing-restore-strategy"}})
            (hud:capture-state))))
      (cleanup)
      (assert (not ok) "Hud.capture-state should fail when restore strategy is missing")
      (assert (string.find (tostring err) "no restore strategy")
              "Hud.capture-state should report missing restore strategy")
      true)))

(fn hud-restore-state-uses-restorer-module []
  (with-dialog-stubs
    (fn [env]
      (local resources (make-scene-and-hud {:icons env.icons}))
      (local cleanup resources.cleanup)
      (local hud resources.hud)
      (local module-name "launchables/launcher")
      (local captured {:panels [{:kind "launcher-view-dialog"
                                 :layer "tiles"
                                 :align-x :start
                                 :align-y :start
                                 :restorer-module module-name}]})
      (hud:restore-state captured)
      (assert (= (length (or hud.tiles.children [])) 1)
              "Hud.restore-state should restore panel from module")
      (cleanup)
      true)))

(fn hud-restore-state-builds-roots-before-float-restore []
  (with-dialog-stubs
    (fn [env]
      (local originals {:scene app.scene
                        :layout-root app.layout-root
                        :hud app.hud
                        :camera app.camera
                        :create-default-projection app.create-default-projection})
      (local camera (make-default-camera))
      (local scene (Scene {:icons env.icons
                           :camera camera}))
      (local hud (Hud {:scene scene
                       :icons env.icons}))
      (set app.camera camera)
      (set app.create-default-projection AppProjection.create-default-projection)
      (set app.scene scene)
      (set app.layout-root scene.layout-root)
      (set app.hud hud)
      (local captured {:panels [{:kind "launcher-view-dialog"
                                 :layer "float"
                                 :relative-position [0.1 0.2 0]
                                 :rotation [1 0 0 0]
                                 :relative-size [0.3 0.4 0]
                                 :restorer-module "launchables/launcher"}]})
      (hud:restore-state captured)
      (scene.layout-root:update)
      (assert (= (length (or hud.float.children [])) 1)
              "Hud.restore-state should build roots before restoring float panels")
      (local restored (hud:capture-state))
      (local panel (. (or restored.panels []) 1))
      (assert panel "Hud.restore-state should produce restorable float panel")
      (assert (= panel.layer "float")
              "Hud.restore-state should preserve float panel layer")
      (assert (= (type panel.relative-position) :table)
              "Hud.restore-state should preserve float panel relative position")
      (hud:drop)
      (scene:drop)
      (camera:drop)
      (set app.scene originals.scene)
      (set app.layout-root originals.layout-root)
      (set app.hud originals.hud)
      (set app.camera originals.camera)
      (set app.create-default-projection originals.create-default-projection)
      true)))


(fn canvas-float-panels-use-measured-size-when-size-unspecified []
  (with-dialog-stubs
    (fn [env]
      (local originals {:clickables app.clickables
                        :hoverables app.hoverables
                        :system-cursors app.system-cursors
                        :viewport app.viewport})
      (local camera (make-default-camera))
      (var canvas nil)
      (fn cleanup [] (assert app.clickables "Canvas float panel cleanup requires app.clickables") (assert app.hoverables "Canvas float panel cleanup requires app.hoverables")
        (when canvas
          (canvas:drop)
          (set canvas nil))
        (when camera
          (camera:drop))
        (set app.clickables originals.clickables)
        (set app.hoverables originals.hoverables)
        (set app.system-cursors originals.system-cursors)
        (set app.viewport originals.viewport))
      (local (ok result)
        (pcall
          (fn []
            (set app.clickables env.clickables)
            (set app.hoverables env.hoverables)
            (set app.system-cursors env.cursors)
            (set app.viewport {:x 0 :y 0 :width 100 :height 100})
            (set canvas (Canvas {:camera camera
                                 :icons env.icons}))
            (local child (make-probe-widget "canvas-measured-size-child"))
            (local dialog
              (canvas:add-panel-child {:builder (Dialog {:title "Float Test"
                                                         :child child.builder})}))
            (canvas:update)
            (local size dialog.layout.size)
            (assert (> size.x 0)
                    "Canvas float panels should use measured width when size is unspecified")
            (assert (> size.y 0)
                    "Canvas float panels should use measured height when size is unspecified")
            true)))
      (cleanup)
      (if ok
          result
          (error result)))))

(table.insert tests {:name "Dialog requires a title" :fn dialog-requires-title})
(table.insert tests {:name "Dialog requires a child" :fn dialog-requires-child})
(table.insert tests {:name "Dialog wraps titlebar and body in cards" :fn dialog-wraps-titlebar-and-body-in-cards})
(table.insert tests {:name "Dialog actions create icon buttons" :fn dialog-actions-create-icon-buttons})
(table.insert tests {:name "Dialog without actions omits spacer" :fn dialog-without-actions-omits-spacer})
(table.insert tests {:name "Dialog titlebar uses action button color" :fn dialog-titlebar-uses-action-button-color})
(table.insert tests {:name "DefaultDialog close action fires once and drops" :fn default-dialog-close-button-calls-on-close-once})
(table.insert tests {:name "DefaultDialog toggle moves between scene and HUD" :fn default-dialog-toggle-moves-between-scene-and-hud})
(table.insert tests {:name "HUD tiles register movables" :fn hud-tiles-register-movables})
(table.insert tests {:name "HUD tiles promote to float on drag" :fn hud-tiles-promote-to-float-on-drag})
(table.insert tests {:name "HUD tiles promote to float on resize" :fn hud-tiles-promote-to-float-on-resize})
(table.insert tests {:name "HUD float resize updates layout" :fn hud-float-resize-updates-layout})
(table.insert tests {:name "Scene resize updates layout" :fn scene-resize-updates-layout})
(table.insert tests {:name "Hud capture-state requires panel persistence" :fn hud-capture-state-requires-panel-persistence})
(table.insert tests {:name "Hud capture and restore persistent panel" :fn hud-capture-and-restore-persistent-panel})
(table.insert tests {:name "Hud capture-state requires restore strategy" :fn hud-capture-state-requires-restore-strategy})
(table.insert tests {:name "Hud restore-state uses restorer module" :fn hud-restore-state-uses-restorer-module})
(table.insert tests {:name "Hud restore-state builds roots before float restore" :fn hud-restore-state-builds-roots-before-float-restore})
(table.insert tests {:name "Canvas float panels use measured size when size is unspecified"
                     :fn canvas-float-panels-use-measured-size-when-size-unspecified})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "dialog"
                       :tests tests})))

{:name "dialog"
 :tests tests
 :main main}
