(local glm (require :glm))
(local {: Layout : LayoutRoot} (require :layout))
(local BuildContext (require :build-context))
(local HudLayout (require :hud-layout))
(local Snackbar (require :snackbar))
(local viewport-utils (require :viewport-utils))
(local Rectangle (require :rectangle))
(local Padding (require :padding))
(local Stack (require :stack))
(local MathUtils (require :math-utils))
(local LightingViewState (require :lighting-view-state))
(local {: CommandHints} (require :hud-command-hints))

(local identity-view (glm.mat4 1))
(local default-world-scale 0.05)
(local default-size-scale (/ 5 3)) ; 20% larger than prior 1080p HUD baseline
(local default-scale-reference-height 1080)
(local panel-border-size 0.2)
(local vec3->array (. MathUtils :vec3->array))
(local quat->array (. MathUtils :quat->array))
(local array->vec3 (. MathUtils :array->vec3))
(local array->quat (. MathUtils :array->quat))

(fn clone-table [value]
  (if (= (type value) :table)
      (do
        (local out {})
        (each [k v (pairs value)]
          (set (. out k) (clone-table v)))
        out)
      value))

(fn resolve-active-theme []
  (and app.engine app.themes app.themes.get-active-theme
       (app.themes.get-active-theme)))

(fn apply-active-theme [ctx]
  (when (and ctx ctx.set-theme)
    (ctx:set-theme (resolve-active-theme))))

(fn resolve-panel-border-color [ctx]
  (local theme (and ctx ctx.theme))
  (or (and theme theme.panel-border)
      (glm.vec4 0.72 0.75 0.79 0.85)))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn adaptive-scale-ratio-for-viewport [viewport-height]
  (if (and (finite-number? viewport-height)
           (> viewport-height default-scale-reference-height))
      (math.max 1.0
                (/ viewport-height
                   default-scale-reference-height))
      1.0))

(fn make-empty-hud-slot-builder []
  (fn [ctx]
    ((Stack {:children []}) ctx)))

(fn make-snackbar-scope-options [ctx]
  (local snackbar-theme (and ctx.theme ctx.theme.snackbar))
  (local options {:theme {:snackbar snackbar-theme}})
  (when snackbar-theme
    (each [key value (pairs snackbar-theme)]
      (set (. options key) value)))
  options)

(fn Hud [opts]
  (local options (or opts {}))
  (local layout-root (LayoutRoot))
  (local focus-manager options.focus-manager)
  (local focus-root (and focus-manager (focus-manager:get-root-scope)))
  (local focus-scope
    (or options.focus-scope
        (and focus-manager
             (focus-manager:create-scope {:name (or options.focus-scope-name "hud")}))))
  (local ctx
    (BuildContext {:theme (resolve-active-theme)
                       :quad-unlit? true
                       :clickables app.clickables
                       :hoverables app.hoverables
                       :touch-gesture-targets app.touch-gesture-targets
                       :system-cursors app.system-cursors
                       :icons options.icons
                       :states options.states
                       :object-selector options.object-selector
                       :layout-root layout-root
                       :movables options.movables
                       :focus-manager focus-manager
                       :focus-parent focus-root
                       :focus-scope focus-scope}))
  (local self {:layout-root layout-root
               :build-context ctx
               :states options.states
               :world-hud-contrib nil
               :projection nil
               :projection-version 0
               :viewport nil
               :entity nil
               :tiles nil
               :float nil
               :overlay-root nil
               :middle-overlay-root nil
               :panel-restorers {}
               :scene options.scene
               :margin-px (or options.margin-px 0)
               :scale-factor (or options.scale-factor default-size-scale)
               :effective-scale-factor (or options.scale-factor default-size-scale)
               :world-units-per-pixel default-world-scale
               :half-width 1
               :half-height 1
               :focus-manager focus-manager
               :focus-scope focus-scope
               :command-hints nil
               :interaction-surface :hud
               :default-panel-location "tiles"})

  (set ctx.pointer-target self)
  (set ctx.panel-target self)
  (apply-active-theme ctx)
  (local snackbar-scope (Snackbar.create-scope (make-snackbar-scope-options ctx)))
  (set self.snackbar-scope snackbar-scope)
  (set self.snackbar-manager snackbar-scope.manager)

  (fn normalize-movable-entry [_self entry]
    (if (not entry)
        (error "Movable entry must not be nil")
        (do
          (local etype (type entry))
          (when (not (= etype :table))
            (error (.. "Movable entry must be a table, got " etype)))
          (local target entry.target)
          (when (not target)
            (error "Movable entry must include :target"))
          {:target target
           :handle entry.handle
           :pointer-target entry.pointer-target
           :key entry.key
           :on-drag-start entry.on-drag-start
           :on-drag-end entry.on-drag-end})))

  (fn register-movable-entries [self entity entries]
    (when (and entity app.movables)
      (local keys [])
      (each [_ entry (ipairs entries)]
        (local target entry.target)
        (local handle (or entry.handle target))
        (local widget (or handle target))
        (local options {})
        (set options.target target)
        (when handle (set options.handle handle))
        (when entry.pointer-target (set options.pointer-target entry.pointer-target))
        (when entry.on-drag-start (set options.on-drag-start entry.on-drag-start))
        (when entry.on-drag-end (set options.on-drag-end entry.on-drag-end))
        (when (not entry.pointer-target)
          (set options.pointer-target self))
        (local key (or entry.key widget entry))
        (when key
          (set options.key key)
          (app.movables:register widget options)
          (table.insert keys key)))
      (set entity.__hud_movable_keys keys)))

  (fn register-entity-movables [self entity]
    (when (and entity app.movables)
      (local entries (icollect [_ entry (ipairs (or entity.movables []))]
                               (normalize-movable-entry self entry)))
      (var filtered [])
      (each [_ entry (ipairs entries)]
        (when entry
          (table.insert filtered entry)))
      (if (> (length filtered) 0)
          (register-movable-entries self entity filtered)
          (set entity.__hud_movable_keys nil))))

  (fn normalize-resizable-entry [_self entry]
    (if (not entry)
        (error "Resizable entry must not be nil")
        (do
          (local etype (type entry))
          (when (not (= etype :table))
            (error (.. "Resizable entry must be a table, got " etype)))
          (local target entry.target)
          (when (not target)
            (error "Resizable entry must include :target"))
          {:target target
           :handle entry.handle
           :pointer-target entry.pointer-target
           :key entry.key
           :min-size entry.min-size
           :max-size entry.max-size
           :on-resize-start entry.on-resize-start
           :on-resize-end entry.on-resize-end})))

  (fn register-resizable-entries [self entity entries]
    (when (and entity app.resizables)
      (local keys [])
      (each [_ entry (ipairs entries)]
        (local target entry.target)
        (local handle (or entry.handle target))
        (local widget (or handle target))
        (local options {})
        (set options.target target)
        (when handle (set options.handle handle))
        (when entry.pointer-target (set options.pointer-target entry.pointer-target))
        (when entry.min-size (set options.min-size entry.min-size))
        (when entry.max-size (set options.max-size entry.max-size))
        (when entry.on-resize-start (set options.on-resize-start entry.on-resize-start))
        (when entry.on-resize-end (set options.on-resize-end entry.on-resize-end))
        (when (not entry.pointer-target)
          (set options.pointer-target self))
        (local key (or entry.key widget entry))
        (when key
          (set options.key key)
          (app.resizables:register widget options)
          (table.insert keys key)))
      (set entity.__hud_resizable_keys keys)))

  (fn register-entity-resizables [self entity]
    (when (and entity app.resizables)
      (local entries (icollect [_ entry (ipairs (or entity.resizables []))]
                               (normalize-resizable-entry self entry)))
      (var filtered [])
      (each [_ entry (ipairs entries)]
        (when entry
          (table.insert filtered entry)))
      (if (> (length filtered) 0)
          (register-resizable-entries self entity filtered)
          (set entity.__hud_resizable_keys nil))))

  (fn resolve-panel-wrapper [element]
    (if (not element)
        nil
        (if element.__hud_inner
            element
            (or element.__hud_wrapper element))))

  (fn find-panel-metadata [self wrapper]
    (local result {:layer nil :metadata nil})
    (when (and self.tiles wrapper)
      (each [_ metadata (ipairs self.tiles.children)]
        (when (and (not result.metadata)
                   (= (and metadata metadata.element) wrapper))
          (set result.layer "tiles")
          (set result.metadata metadata))))
    (when (and (not result.metadata) self.float wrapper)
      (each [_ metadata (ipairs self.float.children)]
        (when (and (not result.metadata)
                   (= (and metadata metadata.element) wrapper))
          (set result.layer "float")
          (set result.metadata metadata))))
    result)

  (fn capture-panel-layout-state [metadata]
    (local element (and metadata metadata.element))
    (local layout (and element element.layout))
    (if (not layout)
        nil
        (do
          (local size (or layout.size layout.measure))
          {:position (vec3->array layout.position)
           :rotation (quat->array layout.rotation)
           :size (and size (vec3->array size))})))

  (fn resolve-scale-viewport-height [_self viewport]
    (local logical-height (and app.engine app.engine.height))
    (if (and (finite-number? logical-height) (> logical-height 1))
        logical-height
        (math.max (or (and viewport viewport.height) 1) 1)))

  (fn encode-float-relative-position [self position]
    (local layout (and self.float self.float.layout))
    (assert layout "Hud float panel placement requires float layout")
    (local layout-size (or layout.size layout.measure))
    (assert layout-size "Hud float panel placement requires float layout size")
    (local frame-position (or layout.position (glm.vec3 0 0 0)))
    (local frame-size (glm.vec3 (math.max 0.001 layout-size.x)
                                (math.max 0.001 layout-size.y)
                                (math.max 0.001 layout-size.z)))
    (local offset (- position frame-position))
    (vec3->array (glm.vec3 (/ offset.x frame-size.x)
                           (/ offset.y frame-size.y)
                           offset.z)))

  (fn encode-float-relative-size [self size]
    (local layout (and self.float self.float.layout))
    (assert layout "Hud float panel placement requires float layout")
    (local layout-size (or layout.size layout.measure))
    (assert layout-size "Hud float panel placement requires float layout size")
    (local frame-size (glm.vec3 (math.max 0.001 layout-size.x)
                                (math.max 0.001 layout-size.y)
                                (math.max 0.001 layout-size.z)))
    (vec3->array (glm.vec3 (/ size.x frame-size.x)
                           (/ size.y frame-size.y)
                           size.z)))

  (fn decode-float-relative-position [self value]
    (local relative (array->vec3 value))
    (local layout (and self.float self.float.layout))
    (assert layout "Hud float panel placement requires float layout")
    (local layout-size (or layout.size layout.measure))
    (assert layout-size "Hud float panel placement requires float layout size")
    (local frame-position (or layout.position (glm.vec3 0 0 0)))
    (local frame-size (glm.vec3 (math.max 0.001 layout-size.x)
                                (math.max 0.001 layout-size.y)
                                (math.max 0.001 layout-size.z)))
    (+ frame-position
       (glm.vec3 (* relative.x frame-size.x)
                 (* relative.y frame-size.y)
                 relative.z)))

  (fn decode-float-relative-size [self value]
    (local relative (array->vec3 value))
    (local layout (and self.float self.float.layout))
    (assert layout "Hud float panel placement requires float layout")
    (local layout-size (or layout.size layout.measure))
    (assert layout-size "Hud float panel placement requires float layout size")
    (local frame-size (glm.vec3 (math.max 0.001 layout-size.x)
                                (math.max 0.001 layout-size.y)
                                (math.max 0.001 layout-size.z)))
    (glm.vec3 (* relative.x frame-size.x)
              (* relative.y frame-size.y)
              relative.z))

  (fn capture-panel-placement-state [self layer metadata]
    (if (= layer "tiles")
        {:layer "tiles"
         :align-x metadata.align-x
         :align-y metadata.align-y}
        (do
          (local layout-state (capture-panel-layout-state metadata))
          (if (not layout-state)
              nil
              {:layer "float"
               :relative-position (encode-float-relative-position self
                                                                 (array->vec3 layout-state.position))
               :rotation layout-state.rotation
               :relative-size (and layout-state.size
                                   (encode-float-relative-size self
                                                               (array->vec3 layout-state.size)))}))))

  (fn wrap-panel-element [self element]
    (local wrapper (resolve-panel-wrapper element))
    (if (and wrapper wrapper.__hud_inner)
        wrapper
        (let [ctx self.build-context
              border-color (resolve-panel-border-color ctx)
              border ((Rectangle {:color border-color}) ctx)
              padding ((Padding {:edge-insets [panel-border-size panel-border-size]
                                 :child (fn [_ctx] element)}) ctx)
              wrapper ((Stack {:children [(fn [_ctx] border)
                                          (fn [_ctx] padding)]}) ctx)]
          (set wrapper.__hud_inner element)
          (set element.__hud_wrapper wrapper)
          wrapper)))

  (fn promote-tile-element [self element entry source]
    (local wrapper (resolve-panel-wrapper element))
    (when (and wrapper self.tiles self.float)
      ;; Always detach from tiles to ensure no duplicates/fighting
      ;; This handles the case where an element might be in both (ghost in tiles)
      (local tile-metadata (self.tiles:detach-child wrapper))
      
      (var float-meta nil)
      (each [_ meta (ipairs self.float.children)]
        (when (= meta.element wrapper)
          (set float-meta meta)))
      
      (if float-meta
          float-meta
          (when tile-metadata
            (local layout wrapper.layout)
            (local position (and layout layout.position))
            (local rotation (and layout layout.rotation))
            (local size (and layout layout.size))
            (set float-meta (self.float:attach-child wrapper {:position position
                                                              :rotation rotation
                                                              :size size}))
            (when (and tile-metadata tile-metadata.persistence)
              (set float-meta.persistence (clone-table tile-metadata.persistence)))
            (when entry
              (set entry.target (self.float:ensure-movable-target float-meta)))
            
            ;; Cross-Registry Refresh to keep passive registries up to date
            (when (= source :movable)
              (self:refresh-panel-resizables))
            (when (= source :resizable)
              (self:refresh-panel-movables))
              
            float-meta))))

  (fn resolve-min-size [layout]
    (and layout layout.min-size))

  (fn collect-panel-movables [self]
    (var entries [])
    (when self.tiles
      (each [_ metadata (ipairs self.tiles.children)]
        (local element (and metadata metadata.element))
        (local wrapper (resolve-panel-wrapper element))
        (local layout (and wrapper wrapper.layout))
        (when layout
          (table.insert entries {:target layout
                                 :handle wrapper
                                 :key wrapper
                                 :on-drag-start (fn [entry]
                                                 (promote-tile-element self wrapper entry :movable))}))))
    (when self.float
      (each [_ metadata (ipairs self.float.children)]
        (local element (and metadata metadata.element))
        (local wrapper (resolve-panel-wrapper element))
        (local target (self.float:ensure-movable-target metadata))
        (local handle (and wrapper wrapper.layout))
        (when (and handle target)
          (table.insert entries {:target target
                                 :handle handle
                                 :key wrapper}))))
    entries)

  (fn collect-panel-resizables [self]
    (var entries [])
    (when self.tiles
      (each [_ metadata (ipairs self.tiles.children)]
        (local element (and metadata metadata.element))
        (local wrapper (resolve-panel-wrapper element))
        (local layout (and wrapper wrapper.layout))
        (when layout
          (local min-size (resolve-min-size layout))
          (table.insert entries {:target layout
                                 :handle layout
                                 :key wrapper
                                 :min-size min-size
                                 :pointer-target self
                                 :on-resize-start (fn [entry]
                                                    (local float-meta (promote-tile-element self wrapper nil :resizable))
                                                    (when (and float-meta self.float)
                                                      (set entry.target (self.float:ensure-resize-target float-meta)))
                                                    entry)}))))
    (when self.float
      (each [_ metadata (ipairs self.float.children)]
        (local element (and metadata metadata.element))
        (local wrapper (resolve-panel-wrapper element))
        (local layout (and wrapper wrapper.layout))
        (local target (self.float:ensure-resize-target metadata))
        (when (and layout target)
          (local min-size (resolve-min-size layout))
          (table.insert entries {:target target
                                 :handle layout
                                 :key wrapper
                                 :min-size min-size
                                 :pointer-target self}))))
    entries)

  (fn unregister-entity-movables [self entity]
    (when (and entity app.movables)
      (local keys entity.__hud_movable_keys)
      (if (and keys (> (length keys) 0))
          (each [_ key (ipairs keys)]
            (app.movables:unregister key))
          (app.movables:unregister entity))
      (set entity.__hud_movable_keys nil)))

  (fn unregister-entity-resizables [self entity]
    (when (and entity app.resizables)
      (local keys entity.__hud_resizable_keys)
      (if (and keys (> (length keys) 0))
          (each [_ key (ipairs keys)]
            (app.resizables:unregister key))
          (app.resizables:unregister entity))
      (set entity.__hud_resizable_keys nil)))

  (fn refresh-panel-movables [self]
    (when self.entity
      (unregister-entity-movables self self.entity)
      (set self.entity.movables (collect-panel-movables self))
      (register-entity-movables self self.entity)))

  (fn refresh-panel-resizables [self]
    (when self.entity
      (unregister-entity-resizables self self.entity)
      (set self.entity.resizables (collect-panel-resizables self))
      (register-entity-resizables self self.entity)))

  (fn unregister-entity [self entity]
    (unregister-entity-movables self entity)
    (unregister-entity-resizables self entity))

  (fn update-root-transform [self opts]
    (when self.entity
      (local options (or opts {}))
      (local skip-mark? (or options.skip-mark-dirty? false))
      (local mark-dirty? (not skip-mark?))
      (local margin (* self.world-units-per-pixel self.margin-px))
      (local layout self.entity.layout)
      (local measured (and layout layout.measure))
      (local height (if measured (. measured 2) 0))
      (local x (+ (- self.half-width) margin))
      (local top (- self.half-height margin))
      (local y (- top height))
      (layout:set-position (glm.vec3 x y 0))
      (layout:set-rotation (glm.quat 1 0 0 0))
      (when mark-dirty?
        (layout:mark-measure-dirty))))

  (fn attach-entity [self entity]
    (when self.command-hints
      (self.command-hints:reset-overlay))
    (when self.entity
      (self:unregister-entity self.entity)
      (self.entity:drop))
    (set self.entity entity)
    (set self.tiles nil)
    (set self.float nil)
    (set self.overlay-root nil)
    (set self.middle-overlay-root nil)
    (when entity
      (set self.tiles entity.tiles-root)
      (set self.float entity.float-root)
      (set self.overlay-root entity.overlay-root)
      (set self.middle-overlay-root entity.middle-overlay-root)
      (entity.layout:set-root self.layout-root)
      (self:update-root-transform)
      (set entity.movables (collect-panel-movables self))
      (set entity.resizables (collect-panel-resizables self))
      (register-entity-movables self entity)
      (register-entity-resizables self entity)))

  (fn build [self builder]
    (set self.builder builder)
    (if builder
        (do
          (apply-active-theme self.build-context)
          (self:attach-entity (builder self.build-context)))
        (self:attach-entity nil)))

  (fn build-default [self opts]
    (local options {})
    (each [key value (pairs (if opts opts {}))]
      (set (. options key) value))
    (when (not (= options.snackbar-host-builder false))
      (set options.snackbar-host-builder self.snackbar-scope.host-builder))
    (self:build (HudLayout.make-hud-builder options)))

  (fn remove-panel-child [self element]
    (local wrapper (resolve-panel-wrapper element))
    (var removed nil)
    (when (and self.tiles wrapper)
      (set removed (self.tiles:remove-child wrapper)))
    (when (and (not removed) self.float wrapper)
      (set removed (self.float:remove-child wrapper)))
    (when removed
      (self:refresh-panel-movables)
      (self:refresh-panel-resizables))
    (not (= removed nil)))

  (fn find-panel-persistence [self element]
    (local wrapper (resolve-panel-wrapper element))
    (local located (find-panel-metadata self wrapper))
    (and located located.metadata located.metadata.persistence))

  (fn add-panel-child [self opts]
    (local options (or opts {}))
    (local destination (or options.location options.layer :tiles))
    (local builder (and options options.builder))
    (when builder
      (when (and (or (= destination :float) (= destination "float"))
                 (not self.float))
        (error "Hud.add-panel-child requires a float root"))
      (when (and (or (= destination :tiles) (= destination "tiles"))
                 (not self.tiles))
        (error "Hud.add-panel-child requires a tiles root"))
      (local builder-options {})
      (each [key value (pairs (or options.builder-options {}))]
        (set (. builder-options key) value))
      (var element nil)
      (var close-called? false)
      (local user-on-close builder-options.on-close)
      (fn handle-close [dialog button event]
        (when (not close-called?)
          (set close-called? true)
          (when user-on-close
            (user-on-close dialog button event))
          (when element
            (self:remove-panel-child element))))
      (set builder-options.on-close handle-close)
      (set element (builder self.build-context builder-options))
      (local wrapper (wrap-panel-element self element))
      (local persistence (and options.persistence
                             (clone-table options.persistence)))
      (var metadata nil)
      (if (or (= destination :float) (= destination "float"))
          (set metadata
               (self.float:attach-child wrapper {:position options.position
                                                 :rotation options.rotation
                                                 :size options.size
                                                 :depth-offset-index options.depth-offset-index}))
          (set metadata
               (self.tiles:attach-child wrapper {:align-x options.align-x
                                                 :align-y options.align-y})))
      (when metadata
        (set metadata.persistence persistence))
      (self:refresh-panel-movables)
      (self:refresh-panel-resizables)
      element))

  (fn remove-overlay-child-from-root [root element]
    (var removed false)
    (when (and root element)
      (each [idx metadata (ipairs root.children)]
        (when (and (not removed) (= metadata.element element))
          (set removed true)
          (root.layout:remove-child idx)
          (table.remove root.children idx)
          (root.layout:mark-measure-dirty)
          (root.layout:mark-layout-dirty))))
    removed)

  (fn remove-overlay-child [self element]
    (local removed (or (remove-overlay-child-from-root self.middle-overlay-root element)
                       (remove-overlay-child-from-root self.overlay-root element)))
    (when removed
      (when (and element element.drop)
        (element:drop)))
    removed)

  (fn resolve-overlay-root [self opts]
    (local layer (or (and opts opts.layer) :full))
    (if (= layer :full)
        (assert self.overlay-root "Hud.add-overlay-child requires a full overlay root")
        (= layer :middle)
        (assert self.middle-overlay-root "Hud.add-overlay-child requires a middle overlay root")
        (error (.. "Unsupported HUD overlay layer: " (tostring layer)))))

  (fn add-overlay-child [self opts]
    (local options (or opts {}))
    (local builder options.builder)
    (when (not builder)
      (error "Hud.add-overlay-child requires :builder"))
    (local root (resolve-overlay-root self options))
    (local builder-options {})
    (each [key value (pairs (or options.builder-options {}))]
      (set (. builder-options key) value))
    (var element nil)
    (var close-called? false)
    (local user-on-close builder-options.on-close)
    (fn handle-close [dialog button event]
      (when (not close-called?)
        (set close-called? true)
        (when user-on-close
          (user-on-close dialog button event))
        (when element
          (self:remove-overlay-child element))))
    (set builder-options.on-close handle-close)
    (set element (builder self.build-context builder-options))
    (local parent-layout (assert root.layout "Hud.add-overlay-child requires overlay root layout"))
    (local parent-position parent-layout.position)
    (local parent-rotation parent-layout.rotation)
    (local parent-inverse (parent-rotation:inverse))
    (local offset (if options.position
                      (parent-inverse:rotate (- options.position parent-position))
                      (glm.vec3 0 0 0)))
    (local local-rotation (if options.rotation
                              (* parent-inverse options.rotation)
                              (glm.quat 1 0 0 0)))
    (local metadata {:element element
                     :position offset
                     :rotation local-rotation
                     :depth-offset-index options.depth-offset-index})
    (table.insert root.children metadata)
    (root.layout:add-child element.layout)
    (root.layout:mark-measure-dirty)
    (root.layout:mark-layout-dirty)
    element)

  (fn capture-panel-element-state [self element]
    (local wrapper (resolve-panel-wrapper element))
    (local located (find-panel-metadata self wrapper))
    (local layer located.layer)
    (local metadata located.metadata)
    (and metadata (capture-panel-placement-state self layer metadata)))

  (fn panel-placement-options [self panel]
    (local entry (or panel {}))
    (local layer (or entry.layer
                     entry.location
                     self.default-panel-location))
    (if (or (= layer :float) (= layer "float"))
        {:location :float
         :position (if entry.relative-position
                       (decode-float-relative-position self entry.relative-position)
                       (array->vec3 (and entry entry.position)))
         :rotation (array->quat (and entry entry.rotation))
         :size (if entry.relative-size
                   (decode-float-relative-size self entry.relative-size)
                   (array->vec3 (and entry entry.size)))}
        (if (or (= layer :tiles) (= layer "tiles"))
            {:location :tiles
             :align-x (and entry entry.align-x)
             :align-y (and entry entry.align-y)}
            (error (.. "Unsupported panel layer: " (tostring layer))))))

  (fn register-panel-restorer [self kind restorer owner]
    (assert (= (type kind) :string) "Hud.register-panel-restorer requires string kind")
    (assert (= (type restorer) :function) "Hud.register-panel-restorer requires function restorer")
    (set (. self.panel-restorers kind) {:restore restorer
                                        :owner owner})
    true)

  (fn unregister-panel-restorer [self kind owner]
    (assert (= (type kind) :string) "Hud.unregister-panel-restorer requires string kind")
    (local current (. self.panel-restorers kind))
    (when current
      (if (or (= owner nil)
              (= current.owner nil)
              (= current.owner owner))
          (set (. self.panel-restorers kind) nil)))
    true)

  (fn capture-state [self]
    (local panels [])
    (fn collect-record [layer metadata]
      (local persistence (and metadata metadata.persistence))
      (when persistence
        (local record (clone-table persistence))
        (local kind record.kind)
        (assert (= (type kind) :string)
                "Hud.capture-state panel persistence requires string :kind")
        (local module-name record.restorer-module)
        (when (not (= module-name nil))
          (assert (= (type module-name) :string)
                  (.. "Hud.capture-state panel persistence for kind "
                      kind
                      " requires string :restorer-module")))
        (local registered (and (. self.panel-restorers kind)
                               (. (. self.panel-restorers kind) :restore)))
        (assert (or registered (= (type module-name) :string))
                (.. "Hud.capture-state panel kind has no restore strategy: "
                    kind
                    " (register restorer or set :restorer-module)"))
        (local placement (capture-panel-placement-state self layer metadata))
        (assert placement
                (.. "Hud.capture-state missing layout for panel kind: " kind))
        (each [key value (pairs placement)]
          (set (. record key) value))
        (table.insert panels record)))
    (when self.tiles
      (each [_ metadata (ipairs (or self.tiles.children []))]
        (collect-record "tiles" metadata)))
    (when self.float
      (each [_ metadata (ipairs (or self.float.children []))]
        (collect-record "float" metadata)))
    (local state {:panels panels})
    (when (and app.extended-sidebar app.extended-sidebar.capture-state)
      (set state.extended-sidebar (app.extended-sidebar:capture-state)))
    state)

  (fn resolve-panel-restorer [self panel]
    (local kind panel.kind)
    (local registered-record (. self.panel-restorers kind))
    (local registered (and registered-record registered-record.restore))
    (if registered
        registered
        (do
          (local module-name panel.restorer-module)
          (assert (= (type module-name) :string)
                  (.. "Hud.restore-state panel kind "
                      kind
                      " requires string :restorer-module or registered restorer"))
          (local (ok module-or-error)
            (pcall require module-name))
          (assert ok
                  (.. "Hud.restore-state failed requiring panel restorer module "
                      module-name
                      ": "
                      (tostring module-or-error)))
          (local module module-or-error)
          (local restore (and module module.restore))
          (assert (= (type restore) :function)
                  (.. "Hud.restore-state module "
                      module-name
                      " must export function :restore"))
          (fn [payload]
            (restore {:hud self
                      :target self
                      :panel payload})))))

  (fn restore-state [self state]
    (local payload (or state {}))
    (local panels (or payload.panels []))
    (assert (= (type panels) :table) "Hud.restore-state requires :panels table")
    (when (and (> (length panels) 0)
               (or (not self.tiles) (not self.float)))
      (local empty-slot (make-empty-hud-slot-builder))
      (self:build-default {:control-builder empty-slot
                           :status-builder empty-slot}))
    (when (> (length panels) 0)
      (assert (and self.tiles self.float)
              "Hud.restore-state requires HUD roots (tiles and float)"))
    (when (> (length panels) 0)
      (self:update))
    (each [_ panel (ipairs panels)]
      (assert (= (type panel) :table) "Hud.restore-state panel entries must be tables")
      (local kind panel.kind)
      (assert (= (type kind) :string) "Hud.restore-state panel kind must be a string")
      (local restorer (resolve-panel-restorer self panel))
      (restorer panel))
    (when payload.extended-sidebar
      (if (and app.extended-sidebar app.extended-sidebar.restore-state)
          (app.extended-sidebar:restore-state payload.extended-sidebar)
          (set app.pending-extended-sidebar-state payload.extended-sidebar)))
    true)

  (fn drop [self]
    (when self.command-hints
      (self.command-hints:reset-overlay))
    (when self.entity
      (self:unregister-entity self.entity)
      (self.entity:drop)
    (set self.entity nil))
    (set self.tiles nil)
    (set self.float nil)
    (set self.overlay-root nil)
    (set self.middle-overlay-root nil)
    (when self.snackbar-scope
      (self.snackbar-scope:drop)
      (set self.snackbar-scope nil))
    (when (and self.focus-manager self.focus-scope)
      (self.focus-manager:detach self.focus-scope)
      (set self.focus-scope nil)))

  (fn get-view-matrix [_self]
    identity-view)

  (fn get-focus-manager [self]
    (local states self.states)
    (if states
        (do
          (assert states.get-focus-manager
                  "Hud states host must expose :get-focus-manager")
          (states:get-focus-manager))
        self.focus-manager))

  (fn get-lighting-view-state [_self]
    (LightingViewState.orthographic (glm.vec3 0.0 0.0 1.0)))

  (fn get-triangle-vector [self]
    self.build-context.triangle-vector)

  (fn get-triangle-batches [self]
    (and self.build-context
         self.build-context.get-triangle-batches
         (self.build-context:get-triangle-batches)))

  (fn get-line-vector [self]
    self.build-context.line-vector)

  (fn get-point-vector [self]
    self.build-context.point-vector)

  (fn get-line-strips [self]
    self.build-context.line-strips)

  (fn get-image-batches [self]
    self.build-context.image-batches)
  (fn get-instanced-color-mesh-batches [self]
    (and self.build-context
         self.build-context.get-instanced-color-mesh-batches
         (self.build-context:get-instanced-color-mesh-batches)))
  (fn get-quad-draw-list [self]
    (and self.build-context
         self.build-context.get-quad-draw-list
         (self.build-context:get-quad-draw-list)))
  (fn get-text-ssbo-draw-list [self]
    (and self.build-context
         self.build-context.get-text-ssbo-draw-list
         (self.build-context:get-text-ssbo-draw-list)))

  (fn screen-pos-ray [self pos opts]
    (local options (or opts {}))
    (local viewport (viewport-utils.to-table (or options.viewport self.viewport app.viewport)))
    (local projection (or options.projection self.projection))
    (fn finite-number? [value]
      (and (= (type value) :number)
           (= value value)
           (not (= value math.huge))
           (not (= value (- math.huge)))))
    (fn assert-finite-vec3 [vec label]
      (when (or (not vec)
                (not (finite-number? vec.x))
                (not (finite-number? vec.y))
                (not (finite-number? vec.z)))
        (error (.. "Hud.screen-pos-ray produced non-finite " label))))
    (assert projection "Hud.screen-pos-ray requires a projection matrix")
    (local sample-pos
      (or (viewport-utils.input-pos->viewport-pos pos viewport app.engine)
          {:x (+ viewport.x (/ viewport.width 2))
           :y (+ viewport.y (/ viewport.height 2))}))
    (local px (or sample-pos.x viewport.x))
    (local py (or sample-pos.y viewport.y))
    (local inverted-y (- (+ viewport.height viewport.y) py))
    (local viewport-vec (viewport-utils.to-glm-vec4 viewport))
    (local near (glm.unproject (glm.vec3 px inverted-y 0.0) identity-view projection viewport-vec))
    (local far (glm.unproject (glm.vec3 px inverted-y 1.0) identity-view projection viewport-vec))
    (local direction (glm.normalize (- far near)))
    (assert-finite-vec3 near "near")
    (assert-finite-vec3 far "far")
    (assert-finite-vec3 direction "direction")
    {:origin near :direction direction})

  (fn update-projection [self viewport]
    (local vp (viewport-utils.to-table (or viewport self.viewport {:x 0 :y 0 :width 1 :height 1})))
    (set self.viewport vp)
    (local safe-width (math.max vp.width 1))
    (local safe-height (math.max vp.height 1))
    (local adaptive-ratio (adaptive-scale-ratio-for-viewport
                            (resolve-scale-viewport-height self vp)))
    (local effective-scale-factor (/ self.scale-factor adaptive-ratio))
    (set self.effective-scale-factor effective-scale-factor)
    (local adjusted-scale (* default-world-scale effective-scale-factor))
    (set self.world-units-per-pixel adjusted-scale)
    (set self.half-width (math.max 0.001 (* 0.5 safe-width adjusted-scale)))
    (set self.half-height (math.max 0.001 (* 0.5 safe-height adjusted-scale)))
    (if glm.ortho
        (set self.projection (glm.ortho (- self.half-width) self.half-width (- self.half-height) self.half-height -100.0 100.0))
        (set self.projection identity-view))
    (set self.projection-version (+ (or self.projection-version 0) 1))
    (self:update-root-transform))

  (fn reset-projection [self]
    (self:update-projection app.viewport))

  (fn on-viewport-changed [self viewport]
    (self:update-projection viewport))

  (fn update [self]
    (when (and self.entity self.entity.update)
      (self.entity:update))
    (self.layout-root:update)
    (self:update-root-transform {:skip-mark-dirty? true}))

  (set self.unregister-entity unregister-entity)
  (set self.attach-entity attach-entity)
  (set self.build build)
  (set self.build-default build-default)
  (set self.show-snackbar
       (fn [self request]
         (self.snackbar-manager:show request)))
  (set self.dismiss-snackbar
       (fn [self id-or-handle reason]
         (self.snackbar-manager:dismiss id-or-handle reason)))
  (set self.drop drop)
  (set self.update-root-transform update-root-transform)
  (set self.get-view-matrix get-view-matrix)
  (set self.get-focus-manager get-focus-manager)
  (set self.get-lighting-view-state get-lighting-view-state)
  (set self.get-triangle-vector get-triangle-vector)
  (set self.get-triangle-batches get-triangle-batches)
  (set self.get-line-vector get-line-vector)
  (set self.get-point-vector get-point-vector)
  (set self.get-line-strips get-line-strips)
  (set self.get-image-batches get-image-batches)
  (set self.get-instanced-color-mesh-batches get-instanced-color-mesh-batches)
  (set self.get-quad-draw-list get-quad-draw-list)
  (set self.get-text-ssbo-draw-list get-text-ssbo-draw-list)
  (set self.reset-projection reset-projection)
  (set self.on-viewport-changed on-viewport-changed)
  (set self.update update)
  (set self.update-projection update-projection)
  (set self.command-hints (CommandHints self))
  (set self.screen-pos-ray screen-pos-ray)
  (fn presentation-target [self]
    "Return a retained HUD presentation target that the runtime presentation
    provider can include after scene and canvas so renderers draw all three
    surfaces in scene/canvas/hud order.  HUD has no activity slot and no camera:
    it uses its own orthographic projection and identity view matrix."
    (when self.projection
      {:kind :hud
       :surface self
       :slot nil
       :camera nil
       :projection self.projection
       :get-view-matrix (fn [_target] (self:get-view-matrix))
       :get-lighting-view-state (fn [_target] (self:get-lighting-view-state))
       :get-render-contexts (fn [_target] [self])
       :screen-pos-ray (fn [_target pos opts] (self:screen-pos-ray pos opts))}))
  (set self.presentation-target presentation-target)
  (set self.add-panel-child add-panel-child)
  (set self.remove-panel-child remove-panel-child)
  (set self.find-panel-persistence find-panel-persistence)
  (set self.add-overlay-child add-overlay-child)
  (set self.remove-overlay-child remove-overlay-child)
  (set self.capture-panel-element-state capture-panel-element-state)
  (set self.register-panel-restorer register-panel-restorer)
  (set self.unregister-panel-restorer unregister-panel-restorer)
  (set self.capture-state capture-state)
  (set self.restore-state restore-state)
  (set self.panel-placement-options panel-placement-options)
  (set self.refresh-panel-movables refresh-panel-movables)
  (set self.refresh-panel-resizables refresh-panel-resizables)

  (self:reset-projection)
  self)

(local exports {:Hud Hud})

(setmetatable exports
              {:__call (fn [_ ...]
                         (Hud ...))})

exports
