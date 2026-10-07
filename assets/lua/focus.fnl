(local Signal (require :signal))
(local glm (require :glm))
(local Modifiers (require :input-modifiers))

(fn remove-child [parent child]
  (when (and parent child)
    (var removed false)
    (local remaining [])
    (each [_ entry (ipairs parent.children)]
      (if (and (not removed) (= entry child))
          (set removed true)
          (table.insert remaining entry)))
    (set parent.children remaining)
    (when (and removed parent.is-scope? (= parent.focused-child child))
      (set parent.focused-child nil))))

(fn insert-child-at [parent child index]
  (local children parent.children)
  (local count (length children))
  (local target-index
    (if (and index (> index 0) (<= index (+ count 1)))
        index
        (+ count 1)))
  (table.insert children target-index child))

(fn mark-descendants-off [node]
  (var current node)
  (var child node)
  (while current
    (if (= current node)
        (do
          (set current.focused? false)
          (set current.descendant-has-focus? false))
        (set current.descendant-has-focus? false))
    (local parent current.parent)
    (when (and parent parent.is-scope? (= parent.focused-child child))
      (set parent.focused-child nil))
    (set child current)
    (set current parent)))

(fn mark-descendants-on [node]
  (local current node)
  (set current.focused? true)
  (set current.descendant-has-focus? false)
  (var child node)
  (var parent current.parent)
  (while parent
    (set parent.descendant-has-focus? true)
    (when parent.is-scope?
      (set parent.focused-child child)
      (when (not node.is-scope?)
        (set parent.last-focused-descendant node)))
    (set child parent)
    (set parent child.parent)))

(fn collect-focusables [node out]
  (when node
    (if node.is-scope?
        (each [_ child (ipairs node.children)]
          (collect-focusables child out))
        (when (and node.can-request-focus? (not node.skip-traversal?))
          (table.insert out node))))
  out)

(fn collect-focusables-pruned [node out active-scope]
  (when node
    (if node.is-scope?
        (if (= node active-scope)
            (each [_ child (ipairs node.children)]
              (collect-focusables-pruned child out active-scope))
            (when (not node.exit-node)
              (each [_ child (ipairs node.children)]
                (collect-focusables-pruned child out active-scope))))
        (when (and node.can-request-focus? (not node.skip-traversal?))
          (table.insert out node))))
  out)

(fn ordered-focusables [manager]
  (local list [])
  (collect-focusables-pruned manager.root list manager.root)
  list)

(fn ordered-focusables-in-scope [manager scope]
  (local list [])
  (local root (if scope scope manager.root))
  (collect-focusables-pruned root list root)
  list)

(fn node-descendant-of-scope? [node scope]
  (var current node)
  (var found false)
  (while (and current (not found))
    (when (= current scope)
      (set found true))
    (set current current.parent))
  found)

(fn node-reachable-from-root? [manager node]
  (var current node)
  (var found false)
  (while (and current (not found))
    (when (= current manager.root)
      (set found true))
    (set current current.parent))
  found)

(fn find-node-index-in-list [nodes node]
  (if (not node)
      nil
      (do
        (var i 1)
        (var found nil)
        (local count (length nodes))
        (while (and (<= i count) (not found))
          (when (= (. nodes i) node)
            (set found i))
          (set i (+ i 1)))
        found)))

(fn ensure-vec3 [value fallback]
  (if value
      (if (= (type value) :userdata)
          value
          (if (= (type value) :table)
              (glm.vec3 (or value.x (rawget value 1) (and fallback fallback.x) 0)
                        (or value.y (rawget value 2) (and fallback fallback.y) 0)
                        (or value.z (rawget value 3) (and fallback fallback.z) 0))
              (if (= (type value) :number)
                  (glm.vec3 value value value)
                  (or fallback (glm.vec3 0 0 0)))))
      (or fallback (glm.vec3 0 0 0))))

(fn resolve-node-bounds [node]
  (when node
    (if node.get-focus-bounds
        (node:get-focus-bounds)
        (if node.layout
            {:position (ensure-vec3 node.layout.position)
             :size (ensure-vec3 node.layout.size)}
            (if (and node.position node.size)
                {:position (ensure-vec3 node.position)
                 :size (ensure-vec3 node.size)}
                nil)))))

(fn bounds-center [bounds]
  (if bounds
      (+ (ensure-vec3 bounds.position)
         (* (ensure-vec3 bounds.size) (glm.vec3 0.5 0.5 0.5)))
      (glm.vec3 0 0 0)))

(fn node-visible? [node]
  (if (not node)
      false
      (do
        (local layout (and node node.layout))
        (if (not layout)
            true
            (if (and layout.effective-culled? (layout:effective-culled?))
                false
                (if (or (= layout.clip-visibility :outside)
                        (= layout.clip-visibility :culled))
                    false
                    true))))))

(fn resolve-scroll-controller [node]
  (local layout (and node node.layout))
  (and layout layout.find-ancestor-field
       (layout:find-ancestor-field :scroll-controller)))

(fn layout-direction-visible? [layout node scroll-controller allow-partial?]
  (local candidate-scroll (resolve-scroll-controller node))
  (local same-scroll?
    (and scroll-controller candidate-scroll (= candidate-scroll scroll-controller)))
  (local outside?
    (or (= layout.clip-visibility :outside)
        (= layout.clip-visibility :culled)))
  (local partial? (= layout.clip-visibility :partial))
  (local effective?
    (and layout.effective-culled? (layout:effective-culled?)))
  (if effective?
      (and outside? same-scroll?)
      (if outside?
          same-scroll?
          (if partial?
              (if (and candidate-scroll (not same-scroll?))
                  (not (not allow-partial?))
                  true)
              true))))

(fn node-direction-visible? [node scroll-controller allow-partial?]
  (if (not node)
      false
      (do
        (local layout (and node node.layout))
        (if (not layout)
            true
            (layout-direction-visible? layout node scroll-controller allow-partial?)))))

(fn normalize-direction [direction]
  (if (not direction)
      nil
      (do
        (local len (glm.length direction))
        (if (> len 1e-6)
            (/ direction len)
            nil))))

(fn resolve-direction-symbol [direction right up]
  (if (= direction :left)
      (* right (glm.vec3 -1 -1 -1))
      (if (= direction :right)
          right
          (if (= direction :up)
              up
              (if (= direction :down)
                  (* up (glm.vec3 -1 -1 -1))
                  nil)))))

(fn resolve-direction-from-camera [direction camera]
  (local right (if (and camera camera.get-right)
                   (camera:get-right)
                   (glm.vec3 1 0 0)))
  (local up (if (and camera camera.get-up)
                (camera:get-up)
                (glm.vec3 0 1 0)))
  (normalize-direction (resolve-direction-symbol direction right up)))

(fn resolve-direction [opts]
  (local direction (and opts opts.direction))
  (when direction
    (if (or (= (type direction) :userdata)
            (= (type direction) :table)
            (= (type direction) :number))
        (normalize-direction (ensure-vec3 direction))
        (resolve-direction-from-camera direction (and opts opts.camera)))))

(fn resolve-direction-axes [opts]
  (local direction (and opts opts.direction))
  (when direction
    (if (or (= (type direction) :userdata)
            (= (type direction) :table)
            (= (type direction) :number))
        (do
          (local axis (normalize-direction (ensure-vec3 direction)))
          (local camera (and opts opts.camera))
          (local up (if (and camera camera.get-up)
                        (camera:get-up)
                        (glm.vec3 0 1 0)))
          (local forward (if (and camera camera.get-forward)
                             (camera:get-forward)
                             (glm.vec3 0 0 -1)))
          (local perp (and axis (normalize-direction (glm.cross forward axis))))
          (local resolved (or perp (and axis (normalize-direction (glm.cross up axis)))))
          (when axis
            {:axis axis :perp (or resolved up)}))
        (do
          (local camera (and opts opts.camera))
          (local right (if (and camera camera.get-right)
                           (camera:get-right)
                           (glm.vec3 1 0 0)))
          (local up (if (and camera camera.get-up)
                        (camera:get-up)
                        (glm.vec3 0 1 0)))
          (local base-right (normalize-direction right))
          (local base-up (normalize-direction up))
          (if (= direction :left)
              {:axis (* base-right (glm.vec3 -1 -1 -1)) :perp base-up}
              (if (= direction :right)
                  {:axis base-right :perp base-up}
                  (if (= direction :up)
                      {:axis base-up :perp base-right}
                      (if (= direction :down)
                          {:axis (* base-up (glm.vec3 -1 -1 -1)) :perp base-right}
                          nil))))))))

(fn bounds-corners [bounds]
  (when bounds
    (local pos (ensure-vec3 bounds.position))
    (local size (ensure-vec3 bounds.size))
    (local xs [0 size.x])
    (local ys [0 size.y])
    (local zs [0 size.z])
    (local corners [])
    (each [_ x (ipairs xs)]
      (each [_ y (ipairs ys)]
        (each [_ z (ipairs zs)]
          (table.insert corners (glm.vec3 (+ pos.x x) (+ pos.y y) (+ pos.z z))))))
    corners))

(fn projection-interval [bounds axis]
  (when (and bounds axis)
    (local corners (bounds-corners bounds))
    (when corners
      (var min-proj nil)
      (var max-proj nil)
      (each [_ corner (ipairs corners)]
        (local value (glm.dot corner axis))
        (if (not min-proj)
            (do (set min-proj value) (set max-proj value))
            (do
              (when (< value min-proj)
                (set min-proj value))
              (when (> value max-proj)
                (set max-proj value)))))
      {:min min-proj :max max-proj})))

(fn compute-perp-gap [source candidate]
  (if (and source candidate)
      (math.max 0 (math.max (- source.min candidate.max)
                            (- candidate.min source.max)))
      math.huge))

(fn frustum-intersection-score [source-bounds candidate-bounds axes angle]
  (local axis (and axes axes.axis))
  (local perp-a (and axes axes.perp))
  (if (not (and axis perp-a))
      nil
      (do
        (local perp-b (normalize-direction (glm.cross axis perp-a)))
        (local current-axis (projection-interval source-bounds axis))
        (local candidate-axis (projection-interval candidate-bounds axis))
        (local current-perp-a (projection-interval source-bounds perp-a))
        (local candidate-perp-a (projection-interval candidate-bounds perp-a))
        (local current-perp-b (and perp-b (projection-interval source-bounds perp-b)))
        (local candidate-perp-b (and perp-b (projection-interval candidate-bounds perp-b)))
        (if (not (and current-axis candidate-axis current-perp-a candidate-perp-a))
            nil
            (do
              (local axis-max current-axis.max)
              (local axis-start (- candidate-axis.min axis-max))
              (local axis-end (- candidate-axis.max axis-max))
              (if (<= axis-end 0)
                  nil
                  (do
                    (local tan-angle (math.tan angle))
                    (local gap-a (compute-perp-gap current-perp-a candidate-perp-a))
                    (local gap-b (if (and current-perp-b candidate-perp-b)
                                     (compute-perp-gap current-perp-b candidate-perp-b)
                                     0))
                    (local required-t (/ (math.max gap-a gap-b) (math.max tan-angle 1e-6)))
                    (local forward (math.max 0 axis-start))
                    (local min-t (math.max forward required-t))
                    (if (<= min-t axis-end)
                        {:score (+ forward required-t)
                         :required required-t
                         :forward forward}
                        nil))))))))

(fn consider-direction-candidate [manager focused axes current-bounds best-state candidate angle scroll-controller
                                  allow-partial?]
  (when (and candidate
             (not (= candidate focused))
             (manager:_can-traverse candidate)
             (node-direction-visible? candidate scroll-controller allow-partial?))
    (local bounds (resolve-node-bounds candidate))
    (when bounds
      (local score (frustum-intersection-score current-bounds bounds axes angle))
      (when score
        (local better?
          (or (not best-state.best)
              (< score.score best-state.score)
              (and (= score.score best-state.score)
                   (< score.required best-state.required))))
        (when better?
          (set best-state.best candidate)
          (set best-state.score score.score)
          (set best-state.required score.required))))))

(fn pick-directional-candidate [manager focused axes angle scope scroll-controller allow-partial?]
  (local current-bounds (resolve-node-bounds focused))
  (when (and current-bounds axes)
    (local nodes (if scope
                     (manager:_get-focusables-in-scope scope)
                     (manager:_get-focusables)))
    (local best-state {:best nil :score math.huge :required math.huge})
    (for [i 1 (length nodes)]
      (consider-direction-candidate manager focused axes current-bounds best-state (. nodes i) angle
                                    scroll-controller allow-partial?))
    best-state.best))

(fn find-directional-target [manager opts]
  (local focused manager.focused-node)
  (when focused
    (local axes (resolve-direction-axes opts))
    (when axes
      (local scope (manager:_find-active-directional-scope focused))
      (local angle (or (and opts opts.frustum-angle) (/ math.pi 4)))
      (local scroll-controller (resolve-scroll-controller focused))
      (var result nil)
      (if scroll-controller
          (set result (pick-directional-candidate manager focused axes angle scope scroll-controller true))
          (do
            (set result (pick-directional-candidate manager focused axes angle scope nil false))
            (when (not result)
              (set result (pick-directional-candidate manager focused axes angle scope nil true)))))
      result)))

(fn assert-same-manager [manager linked message]
  (assert linked message)
  (assert (= linked.manager manager) "Focus hierarchy link belongs to another manager"))

(fn set-node-entry-scope [node scope]
  (when scope
    (assert-same-manager node.manager scope "FocusNode:set-entry-scope expected a scope")
    (assert scope.is-scope? "FocusNode:set-entry-scope expected a FocusScope"))
  (local previous node.entry-scope)
  (when (and previous (not (= previous scope)) (= previous.exit-node node))
    (set previous.exit-node nil))
  (when (and scope scope.exit-node (not (= scope.exit-node node))
             (= scope.exit-node.entry-scope scope))
    (set scope.exit-node.entry-scope nil))
  (set node.entry-scope scope)
  (when scope
    (set scope.exit-node node))
  node)

(fn set-scope-exit-node [scope node]
  (when node
    (assert-same-manager scope.manager node "FocusScope:set-exit-node expected a node")
    (assert (not node.is-scope?) "FocusScope:set-exit-node expected a FocusNode"))
  (local previous scope.exit-node)
  (when (and previous (not (= previous node)) (= previous.entry-scope scope))
    (set previous.entry-scope nil))
  (when (and node node.entry-scope (not (= node.entry-scope scope))
             (= node.entry-scope.exit-node node))
    (set node.entry-scope.exit-node nil))
  (set scope.exit-node node)
  (when node
    (set node.entry-scope scope))
  scope)

(fn new-focus-node [manager opts]
  (assert manager "FocusNode requires a manager")
  (local options (or opts {}))
  (local node
    {:manager manager
     :name (or options.name "focus-node")
     :parent nil
     :children []
     :is-scope? (and (= options.is-scope? true))
     :is-root? false
      :focused? false
      :descendant-has-focus? false
      :entry-scope nil
      :can-request-focus? (not (= options.can-request-focus? false))
      :skip-traversal? (and (= options.skip-traversal? true))})

  (set node.set-entry-scope
       (fn [self scope]
         (assert self.manager "FocusNode missing manager")
         (set-node-entry-scope self scope)))

  (set node.request-focus
       (fn [self opts]
         (assert self.manager "FocusNode missing manager")
         (self.manager:request-focus self opts)))

  (set node.attach
       (fn [self parent]
         (assert self.manager "FocusNode missing manager")
         (self.manager:attach self parent)
         self))

  (set node.detach
       (fn [self]
         (when (and self.manager (or self.parent self.is-root?))
           (self.manager:detach self))
         self))

  (set node.drop
       (fn [self]
         (self:detach)
         (when (and self.manager self.manager._unregister-node)
           (self.manager:_unregister-node self))))
  (when (and manager manager._register-node (not node.is-scope?) node.can-request-focus?)
    (manager:_register-node node))
  node)

(fn new-focus-scope [manager opts]
  (local options (or opts {}))
  (set options.is-scope? true)
  (local scope (new-focus-node manager options))
  (set scope.is-scope? true)
  (set scope.children [])
  (set scope.focused-child nil)
  (set scope.exit-node nil)
  (set scope.last-focused-descendant nil)
  (set scope.directional-traversal-boundary?
        (and (= options.directional-traversal-boundary? true)))
  (set scope.set-exit-node
       (fn [self node]
         (assert self.manager "FocusScope missing manager")
         (set-scope-exit-node self node)))
  scope)

(fn ensure-node [manager node]
  (assert node "FocusManager expected a node")
  (assert (= node.manager manager) "Focus node belongs to another manager"))

(fn ensure-scope [manager scope]
  (ensure-node manager scope)
  (assert scope.is-scope? "Focus parent must be a FocusScope"))

(fn branch-has-focus? [node]
  (and node (or node.focused? node.descendant-has-focus?)))

(fn clear-hierarchy-links-in-branch [node]
  (when node
    (when node.entry-scope
      (node:set-entry-scope nil))
    (when (and node.is-scope? node.exit-node)
      (node:set-exit-node nil))
    (when node.is-scope?
      (set node.last-focused-descendant nil)
      (each [_ child (ipairs node.children)]
        (clear-hierarchy-links-in-branch child)))))

(fn nearest-entry-scope [manager node]
  (var current (and node node.parent))
  (var found nil)
  (while (and current (not found))
    (when (and current.is-scope? current.exit-node)
      (set found current))
    (set current current.parent))
  (if found found manager.root))

(fn active-directional-scope [manager node]
  (local active (nearest-entry-scope manager node))
  (local boundary (manager:_find-directional-boundary node))
  (if (and boundary (not (= boundary manager.root))
           (node-descendant-of-scope? boundary active))
      boundary
      active))

(fn first-traversable-in-scope [manager scope]
  (local nodes (manager:_get-focusables-in-scope scope))
  (var found nil)
  (var i 1)
  (while (and (<= i (length nodes)) (not found))
    (local node (. nodes i))
    (when (manager:_can-traverse node)
      (set found node))
    (set i (+ i 1)))
  found)

(fn focusable-descendant-in-scope? [manager node scope]
  (and node
       (node-descendant-of-scope? node scope)
       (manager:_can-traverse node)))

(fn find-exit-node [manager focused]
  (var current (and focused focused.parent))
  (var found nil)
  (while (and current (not found))
    (when (and current.is-scope? current.exit-node
               (manager:_can-traverse current.exit-node))
      (set found current.exit-node))
    (set current current.parent))
  found)

(fn focus-reason [opts default-reason]
  (if (and opts opts.reason)
      opts.reason
      default-reason))

(fn manager-can-focus-into? [manager]
  (local focused manager.focused-node)
  (local scope (and focused focused.entry-scope))
  (if (not scope)
      false
      (if (focusable-descendant-in-scope? manager scope.last-focused-descendant scope)
          true
          (not (not (first-traversable-in-scope manager scope))))))

(fn manager-focus-into [manager opts]
  (local focused manager.focused-node)
  (local scope (and focused focused.entry-scope))
  (when scope
    (local remembered scope.last-focused-descendant)
    (local target (if (focusable-descendant-in-scope? manager remembered scope)
                      remembered
                      (first-traversable-in-scope manager scope)))
    (when target
      (target:request-focus {:reason (focus-reason opts :focus-into)})
      target)))

(fn manager-can-focus-out? [manager]
  (not (not (find-exit-node manager manager.focused-node))))

(fn manager-focus-out [manager opts]
  (local target (find-exit-node manager manager.focused-node))
  (when target
    (target:request-focus {:reason (focus-reason opts :focus-out)})
    target))

(fn positive-mod [value modulus]
  (if (= modulus 0)
      0
      (do
        (local result (math.fmod value modulus))
        (if (< result 0)
            (+ result modulus)
            result))))

(fn manager-focus-next [manager opts]
  (local active-scope (manager:_find-active-traversal-scope manager.focused-node))
  (local nodes (manager:_get-focusables-in-scope active-scope))
  (local count (length nodes))
  (if (<= count 0)
      nil
      (do
        (local backwards? (and opts opts.backwards?))
        (local direction (if backwards? -1 1))
        (local current-index (find-node-index-in-list nodes manager.focused-node))
        (local baseline (if current-index current-index manager.last-focus-index))
        (local detached-last?
          (and manager.last-focused-node
               (not (if manager.last-focused-node.parent
                        true
                        manager.last-focused-node.is-root?))))
        (local start (if baseline
                         (if (and (not current-index) detached-last?)
                             baseline
                             (- baseline 1))
                         -1))
        (var step 1)
        (var chosen nil)
        (while (and (<= step count) (not chosen))
          (local idx (positive-mod (+ start (* direction step)) count))
          (local candidate (. nodes (+ idx 1)))
          (when (manager:_can-traverse candidate)
            (candidate:request-focus {:reason :tab})
            (set chosen candidate))
          (set step (+ step 1)))
        chosen)))

(fn attach-node-at [manager node parent index]
  (ensure-node manager node)
  (local target (or parent manager.root))
  (ensure-scope manager target)
  (if (= node.parent target)
      (do
        (when (and index (> (length target.children) 0))
          (remove-child target node)
          (insert-child-at target node index))
        node)
      (do
        (when node.parent
          (when (branch-has-focus? node)
            (manager:_set-focused-node nil))
          (remove-child node.parent node)
          (set node.parent nil))
        (insert-child-at target node index)
        (set node.parent target)
        (when (and manager._auto-focus-armed (manager:_can-traverse node))
          (set manager._auto-focus-armed false)
          (node:request-focus))
        node)))

(fn attach-node [manager node parent]
  (attach-node-at manager node parent nil))

(fn detach-node [manager node]
  (ensure-node manager node)
  (local parent node.parent)
  (when (branch-has-focus? node)
    (manager:_set-focused-node nil))
  (clear-hierarchy-links-in-branch node)
  (when parent
    (remove-child parent node)
    (set node.parent nil))
  node)

(fn request-focus [manager node opts]
  (ensure-node manager node)
  (when (not (node-reachable-from-root? manager node))
    (error "FocusNode must be attached before requesting focus"))
  (when (not node.can-request-focus?)
    (error "FocusNode cannot request focus"))
  (manager:_set-focused-node node opts)
  node)

(fn set-focused-node [manager next opts]
  (local previous manager.focused-node)
  (when (not (= previous next))
    (set manager.last-focused-node previous)
    (when previous
      (mark-descendants-off previous))
    (set manager.focused-node next)
    (if next
        (set manager.last-focus-index (and manager (manager:_find-node-index next)))
        (set manager.last-focus-index
             (and previous manager (manager:_find-node-index previous))))
    (when next
      (mark-descendants-on next))
    (when previous
      (manager.focus-blur:emit {:previous previous :current next :reason (and opts opts.reason)}))
    (when next
      (manager.focus-focus:emit {:previous previous :current next :reason (and opts opts.reason)}))))

(fn new-focus-manager [opts]
  (local options (or opts {}))
  (local focus-blur (Signal))
  (local focus-focus (Signal))
  (local manager {:focus-blur focus-blur
                  :focus-focus focus-focus
                  :focused-node nil
                  :focusables []
                  :last-focus-index nil
                  :_auto-focus-armed false})
  (set manager._register-node
       (fn [self node]
         (when (and node (not node.is-scope?) node.can-request-focus?)
           (var exists false)
           (each [_ entry (ipairs self.focusables)]
             (when (= entry node)
               (set exists true)))
           (when (not exists)
             (table.insert self.focusables node)))))
  (set manager._unregister-node
       (fn [self node]
         (when node
           (var removed false)
           (local remaining [])
           (each [_ entry (ipairs self.focusables)]
             (if (and (not removed) (= entry node))
                 (set removed true)
                 (table.insert remaining entry)))
           (set self.focusables remaining))))
  (set manager._find-node-index
       (fn [self node]
         (if (not node)
             nil
             (let [nodes (ordered-focusables self)
                   count (length nodes)]
               (var i 1)
               (var found nil)
               (while (and (<= i count) (not found))
                 (when (= (. nodes i) node)
                   (set found i))
                 (set i (+ i 1)))
               found))))
  (set manager._can-traverse
       (fn [self node]
          (and node
               node.can-request-focus?
               (not node.skip-traversal?)
               (node-reachable-from-root? self node))))
  (set manager._set-focused-node (fn [self node opts] (set-focused-node self node opts)))
  (set manager._get-focusables (fn [self] (ordered-focusables self)))
  (set manager._get-focusables-in-scope
       (fn [self scope]
         (ordered-focusables-in-scope self scope)))
  (set manager._find-directional-boundary
        (fn [self node]
          (var current (and node node.parent))
          (var boundary nil)
         (while (and current (not boundary))
           (when (and current.is-scope? current.directional-traversal-boundary?)
             (set boundary current))
            (set current current.parent))
          (or boundary self.root)))
  (set manager._find-active-traversal-scope
       (fn [self node]
         (nearest-entry-scope self node)))
  (set manager._find-active-directional-scope
       (fn [self node]
         (active-directional-scope self node)))
  (set manager.arm-auto-focus
       (fn [self opts]
         (local event (and opts opts.event))
         (if (and event (Modifiers.ctrl-held? event.mod))
             false
             (do
               (set self._auto-focus-armed true)
               true))))
  (set manager.clear-auto-focus
       (fn [self]
         (set self._auto-focus-armed false)
         true))
  (set manager.make-activation-event
       (fn [_self payload]
         {:source :keyboard
          :mod (and payload payload.mod)
          :payload payload}))
  (set manager.activate-focused-from-payload
       (fn [self payload]
         (self:activate-focused {:event (self:make-activation-event payload)})))
  (fn get-root-name [] (or options.root-name "focus-root"))
  (local root (new-focus-scope manager {:name (get-root-name)
                                        :can-request-focus? false}))
  (set root.is-root? true)
  (set manager.root root)

  (set manager.get-root-scope
       (fn [self]
         self.root))

  (set manager.get-focused-node
       (fn [self] self.focused-node))

  (set manager.attach
       (fn [self node parent]
         (attach-node self node (or parent self.root))))

  (set manager.attach-at
       (fn [self node parent index]
         (attach-node-at self node (or parent self.root) index)))

  (set manager.detach
       (fn [self node]
         (detach-node self node)))

  (set manager.create-node
       (fn [self opts]
         (new-focus-node self opts)))

  (set manager.create-scope
       (fn [self opts]
         (new-focus-scope self opts)))

  (set manager.request-focus
        (fn [self node opts]
          (request-focus self node opts)))

  (set manager.can-focus-into?
       (fn [self]
         (manager-can-focus-into? self)))

  (set manager.focus-into
       (fn [self opts]
         (manager-focus-into self opts)))

  (set manager.can-focus-out?
       (fn [self]
         (manager-can-focus-out? self)))

  (set manager.focus-out
       (fn [self opts]
         (manager-focus-out self opts)))

  (set manager.focus-next
       (fn [self opts]
         (manager-focus-next self opts)))

  (set manager.activate-focused
       (fn [self opts]
         (local node self.focused-node)
         (local activate (and node node.activate))
         (if activate
             (do
               (self:arm-auto-focus opts)
               (local ok (not (= (activate node opts) false)))
               (self:clear-auto-focus)
               ok)
             false)))

  (set manager.focus-direction
       (fn [self opts]
         (if (not self.focused-node)
             (self:focus-next {})
             (let [target (find-directional-target self opts)]
               (when target
                 (local scroll-controller (resolve-scroll-controller self.focused-node))
                 (when (and scroll-controller
                            (= (resolve-scroll-controller target) scroll-controller)
                            scroll-controller.ensure-visible)
                   (scroll-controller:ensure-visible target))
                 (target:request-focus {:reason :direction}))
               target))))

  (set manager.clear-focus
       (fn [self]
         (self:_set-focused-node nil)))

  (set manager.drop
       (fn [self]
         (self:clear-focus)
         (local root-scope self.root)
         (when root-scope
           (while (> (length root-scope.children) 0)
             (self:detach (. root-scope.children 1))))
         (self.focus-blur:clear)
         (self.focus-focus:clear)
         (set self.focused-node nil)
         (set self.last-focused-node nil)
         (set self.focusables [])
         (set self.last-focus-index nil)
         (set self._auto-focus-armed false)
         (set self.root nil)))

  (setmetatable manager
                {:__index (fn [_self key]
                            (if (= key "focus-changed")
                                (error "focus-changed removed; use focus-blur/focus-focus")
                                nil))})

  manager)

{:FocusNode new-focus-node
 :FocusScope new-focus-scope
 :FocusManager new-focus-manager}
