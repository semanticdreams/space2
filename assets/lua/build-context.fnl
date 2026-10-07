(local Lines (require :lines))
(local Points (require :points))
(local DrawBatcher (require :draw-batcher))
(local TextSsboBatcher (require :text-ssbo-batcher))
(local QuadBatcher (require :next-app/quad-batcher))

(local {:VectorBuffer VectorBuffer} (require :vector-buffer))

(fn ensure-focus-scope-belongs [focus-manager scope]
  (assert scope "Focus context requires a scope")
  (assert (= scope.manager focus-manager)
          "Focus scope belongs to another manager")
  scope)

(fn ensure-focus-node-belongs [focus-manager node]
  (assert node "Focus context requires a node")
  (assert (= node.manager focus-manager)
          "Focus node belongs to another manager")
  node)

(fn resolve-focus-parent [focus-manager focus-ctx parent]
  (if parent
      (ensure-focus-scope-belongs focus-manager parent)
      (ensure-focus-scope-belongs focus-manager focus-ctx.scope)))

(fn call-with-focus-scope [focus-manager focus-ctx scope f]
  (ensure-focus-scope-belongs focus-manager scope)
  (assert f "Focus context with-scope requires a callback")
  (local previous-scope focus-ctx.scope)
  (focus-ctx:set-scope scope)
  (local result (table.pack (pcall f)))
  (focus-ctx:set-scope previous-scope)
  (if (. result 1)
      (table.unpack result 2 result.n)
      (error (. result 2))))

(fn create-focus-context [options]
  (local focus-manager options.focus-manager)
  (local focus-scope options.focus-scope)
  (when (and focus-manager focus-scope)
    (local focus-parent
      (if options.focus-parent
          options.focus-parent
          (focus-manager:get-root-scope)))
    (when (and (not focus-scope.parent) (not focus-scope.is-root?))
      (focus-manager:attach focus-scope focus-parent))
    (local focus-ctx {:manager focus-manager :scope focus-scope})
    (set focus-ctx.get-scope (fn [self] self.scope))
    (set focus-ctx.set-scope
         (fn [self scope]
           (ensure-focus-scope-belongs focus-manager scope)
           (set self.scope scope)
           self))
    (set focus-ctx.with-scope
         (fn [self scope f]
           (call-with-focus-scope focus-manager self scope f)))
    (set focus-ctx.attach
         (fn [self node parent]
           (ensure-focus-node-belongs focus-manager node)
           (focus-manager:attach node (resolve-focus-parent focus-manager self parent))
           node))
    (set focus-ctx.attach-at
         (fn [self node parent index]
           (ensure-focus-node-belongs focus-manager node)
           (focus-manager:attach-at node (resolve-focus-parent focus-manager self parent) index)
           node))
    (set focus-ctx.detach
         (fn [_self node]
           (ensure-focus-node-belongs focus-manager node)
           (focus-manager:detach node)
           node))
    (set focus-ctx.create-node
         (fn [self opts]
           (local node (focus-manager:create-node opts))
           (local parent (and opts opts.parent))
           (self:attach node parent)
           (when self._capture
             (table.insert self._capture node))
           node))
    (set focus-ctx.create-scope
         (fn [self opts]
           (local scope (focus-manager:create-scope opts))
           (local parent (and opts opts.parent))
           (self:attach scope parent)
           (when self._capture
             (table.insert self._capture scope))
           scope))
    (set focus-ctx.capture
         (fn [self f]
           (local nodes [])
           (set self._capture nodes)
           (local result (f))
           (set self._capture nil)
           (values result nodes)))
    (set focus-ctx.attach-bounds
         (fn [_self node opts]
           (ensure-focus-node-belongs focus-manager node)
           (local options
             (if opts
                 opts
                 {}))
           (local layout (and options.layout options.layout))
           (local get-bounds (and options.get-bounds options.get-bounds))
           (local position (and options.position options.position))
           (local size (and options.size options.size))
           (when layout
             (set node.layout layout))
           (if get-bounds
               (set node.get-focus-bounds get-bounds)
               (if layout
                   (set node.get-focus-bounds
                        (fn [_self]
                          {:position layout.position
                           :size layout.size}))
                   (do
                     (set node.get-focus-bounds nil)
                     (when position
                       (set node.position position))
                     (when size
                       (set node.size size)))))
           node))
    focus-ctx))

(fn BuildContext [opts]
  (local options
    (if opts
        opts
        {}))
  (local triangle-vector (VectorBuffer))
  (local line-vector (VectorBuffer))
  (local point-vector (VectorBuffer))
  (local image-batches {})
  (local mesh-batches [])
  (local instanced-color-mesh-batches [])
  (local line-strips [])
  (local triangle-batches (DrawBatcher {:stride 8}))
  (local quad-sources [])
  (local rectangle-quad-batcher (QuadBatcher {}))
  (local text-ssbo-sources [])
  (local text-ssbo-batcher (TextSsboBatcher {}))
  (fn register-line-strip [vector]
    (table.insert line-strips vector)
    vector)
  (fn unregister-line-strip [vector]
    (for [i 1 (length line-strips)]
      (when (= (. line-strips i) vector)
        (table.remove line-strips i)
        (lua "break")))
    nil)
  (local ctx
    {:triangle-vector triangle-vector
     :line-vector line-vector
     :point-vector point-vector
     :image-batches image-batches
     :mesh-batches mesh-batches
     :instanced-color-mesh-batches instanced-color-mesh-batches
     :line-strips line-strips
     :pointer-target options.pointer-target
     :touch-gesture-targets options.touch-gesture-targets
     :clickables options.clickables
     :hoverables options.hoverables
     :system-cursors options.system-cursors
     :icons options.icons
     :states options.states
     :object-selector options.object-selector
     :layout-root options.layout-root
     :movables options.movables
     :theme options.theme})
  (set ctx.set-theme (fn [self theme]
                       (set self.theme theme)))
  (set ctx.register-line-strip (fn [_self vector]
                                 (register-line-strip vector)))
  (set ctx.unregister-line-strip (fn [_self vector]
                                   (unregister-line-strip vector)))
  (set ctx.lines (Lines {:line-vector line-vector
                         :register-line-strip register-line-strip
                         :unregister-line-strip unregister-line-strip}))
  (set ctx.points (Points {:point-vector point-vector}))
  (set ctx.track-triangle-handle
       (fn [_self handle clip-region model]
         (triangle-batches:track-handle handle clip-region model)))
  (set ctx.untrack-triangle-handle
       (fn [_self handle]
         (triangle-batches:untrack-handle handle)))
  (set ctx.get-triangle-batches
       (fn [_self]
         (triangle-batches:get-batches)))
  (set ctx.register-quad-source
       (fn [_self source]
         (when source
           (table.insert quad-sources source))
         source))
  (set ctx.unregister-quad-source
       (fn [_self source]
         (when source
           (for [i 1 (length quad-sources)]
             (when (= (. quad-sources i) source)
               (table.remove quad-sources i)
               (lua "break"))))
         nil))
  (set ctx.get-quad-draw-list
       (fn [_self]
         (local out [])
         (each [_ source (ipairs quad-sources)]
           (when (and source source.get-draw-list)
             (local entries (source:get-draw-list))
             (when entries
               (each [_ entry (ipairs entries)]
                 (table.insert out entry)))))
         out))
  (set ctx.get-rectangle-quad-batcher
       (fn [_self]
         rectangle-quad-batcher))
  (set ctx.register-text-ssbo-source
       (fn [_self source]
         (when source
           (table.insert text-ssbo-sources source))
         source))
  (set ctx.unregister-text-ssbo-source
       (fn [_self source]
         (when source
           (for [i 1 (length text-ssbo-sources)]
             (when (= (. text-ssbo-sources i) source)
               (table.remove text-ssbo-sources i)
               (lua "break"))))
         nil))
  (set ctx.get-text-ssbo-draw-list
       (fn [_self]
         (local out [])
         (each [_ source (ipairs text-ssbo-sources)]
           (when (and source source.get-draw-list)
             (local entries (source:get-draw-list))
             (when entries
               (each [_ entry (ipairs entries)]
                 (table.insert out entry)))))
         out))
  (set ctx.get-text-ssbo-batcher
       (fn [_self]
         text-ssbo-batcher))
  ;; Core widget text rendering always feeds this shared SSBO batcher source.
  (table.insert text-ssbo-sources
                {:get-draw-list (fn []
                                  (text-ssbo-batcher:get-draw-list))})
  (table.insert quad-sources
                {:get-draw-list
                 (fn []
                   (local vector (rectangle-quad-batcher:get-vector))
                   (local batches (rectangle-quad-batcher:get-batches))
                   (if (not vector)
                       []
                       (<= (vector:length) 0)
                       []
                       (not batches)
                       []
                       (<= (# batches) 0)
                        []
                        [{:vector vector
                          :unlit (= options.quad-unlit? true)
                          :clip-vector (rectangle-quad-batcher:get-clip-vector)
                          :clip-group-vector (rectangle-quad-batcher:get-clip-group-vector)
                         :batches batches}]))})
  (set ctx.get-image-batch
       (fn [_self texture]
         (assert (and texture texture.id)
                 "Image batch requires a texture with an id")
        (local id texture.id)
        (when (not (. image-batches id))
          (set (. image-batches id)
               {:texture texture
                :vector (VectorBuffer)
                :id id
                :draw-batcher (DrawBatcher {:stride 10})}))
         (. image-batches id)))
  (set ctx.unregister-image-batch
       (fn [_self texture-id]
         (set (. image-batches texture-id) nil)
         nil))
  (set ctx.register-mesh-batch
       (fn [_self batch]
         (table.insert mesh-batches batch)
         batch))
  (set ctx.unregister-mesh-batch
       (fn [_self batch]
         (for [i 1 (length mesh-batches)]
           (when (= (. mesh-batches i) batch)
             (table.remove mesh-batches i)
             (lua "break")))
         nil))
  (set ctx.get-mesh-batches
       (fn [_self]
         mesh-batches))
  (set ctx.register-instanced-color-mesh-batch
       (fn [_self batch]
         (table.insert instanced-color-mesh-batches batch)
         batch))
  (set ctx.unregister-instanced-color-mesh-batch
       (fn [_self batch]
         (for [i 1 (length instanced-color-mesh-batches)]
           (when (= (. instanced-color-mesh-batches i) batch)
             (table.remove instanced-color-mesh-batches i)
             (lua "break")))
         nil))
  (set ctx.get-instanced-color-mesh-batches
       (fn [_self]
         instanced-color-mesh-batches))
  (set ctx.track-image-handle
       (fn [_self batch handle clip-region model]
         (local batcher (and batch batch.draw-batcher))
         (when batcher
           (batcher:track-handle handle clip-region model))))
  (set ctx.untrack-image-handle
       (fn [_self batch handle]
         (local batcher (and batch batch.draw-batcher))
         (when batcher
           (batcher:untrack-handle handle))))
  (local focus-ctx (create-focus-context options))
  (when focus-ctx
    (set ctx.focus focus-ctx))
  ctx)

BuildContext
