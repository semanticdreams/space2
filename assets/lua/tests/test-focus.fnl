(local BuildContext (require :build-context))
(local {: FocusManager} (require :focus))
(local {: Layout} (require :layout))
(local glm (require :glm))
(local Camera (require :camera))

(local tests [])

(fn add-test [name handler]
  (table.insert tests {:name name :fn handler}))

(add-test
  "focus manager tracks focus state"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "hud-scope"}))
    (manager:attach scope root)
    (local node (manager:create-node {:name "button"}))
    (manager:attach node scope)
    (node:request-focus)
    (assert (= (manager:get-focused-node) node)
            "FocusManager should return focused node")
    (assert node.focused? "Node should be marked as focused")
    (assert scope.descendant-has-focus?
            "Scope should know it contains a focused descendant")
    (manager:clear-focus)
    (assert (not scope.descendant-has-focus?)
            "Clearing focus should update ancestor scopes")
    (manager:drop)))

(add-test
  "build context focus helpers attach nodes"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local ctx-scope (manager:create-scope {:name "ctx"}))
    (manager:attach ctx-scope root)
    (local ctx
      (BuildContext {:focus-manager manager
                         :focus-scope ctx-scope}))
    (assert ctx.focus "BuildContext should expose focus helpers when manager exists")
    (local node (ctx.focus:create-node {:name "child"}))
    (assert (= node.parent ctx-scope) "Nodes attach to default scope")
    (local nested-scope (ctx.focus:create-scope {:name "nested"}))
    (assert (= nested-scope.parent ctx-scope) "New scopes attach to default scope")
    (ctx.focus:set-scope nested-scope)
    (local nested-node (ctx.focus:create-node {:name "nested-node"}))
    (assert (= nested-node.parent nested-scope)
            "Changing focus scope should change attach target")
    (ctx.focus:set-scope ctx-scope)
    (ctx.focus:detach nested-node)
    (manager:drop)))

(add-test
  "focus manager cycles focus order"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "scope"}))
    (manager:attach scope root)
    (local nodes [])
    (for [i 1 3]
      (local node (manager:create-node {:name (.. "node" i)}))
      (manager:attach node scope)
      (table.insert nodes node))
    (manager:focus-next {})
    (assert (= (manager:get-focused-node) (. nodes 1)))
    (manager:focus-next {})
    (assert (= (manager:get-focused-node) (. nodes 2)))
    (manager:focus-next {:backwards? true})
    (assert (= (manager:get-focused-node) (. nodes 1)))
    (manager:focus-next {})
    (manager:focus-next {})
    (manager:focus-next {})
    (assert (= (manager:get-focused-node) (. nodes 1)))
    (manager:drop)))

(add-test
  "focus manager respects scope order in traversal"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope-a (manager:create-scope {:name "scope-a"}))
    (local scope-b (manager:create-scope {:name "scope-b"}))
    (manager:attach scope-a root)
    (manager:attach scope-b root)
    (local a1 (manager:create-node {:name "a1"}))
    (local b1 (manager:create-node {:name "b1"}))
    (local a2 (manager:create-node {:name "a2"}))
    (manager:attach a1 scope-a)
    (manager:attach b1 scope-b)
    (manager:attach a2 scope-a)
    (manager:focus-next {})
    (assert (= (manager:get-focused-node) a1))
    (manager:focus-next {})
    (assert (= (manager:get-focused-node) a2))
    (manager:focus-next {})
    (assert (= (manager:get-focused-node) b1))
    (manager:drop)))

(add-test
  "focus manager emits blur before focus"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "scope"}))
    (manager:attach scope root)
    (local a (manager:create-node {:name "a"}))
    (local b (manager:create-node {:name "b"}))
    (manager:attach a scope)
    (manager:attach b scope)
    (local events [])
    (local blur-listener
      (manager.focus-blur:connect
        (fn [event]
          (table.insert events {:type :blur
                                :previous event.previous
                                :current event.current}))))
    (local focus-listener
      (manager.focus-focus:connect
        (fn [event]
          (table.insert events {:type :focus
                                :previous event.previous
                                :current event.current}))))
    (a:request-focus)
    (b:request-focus)
    (var blur-index nil)
    (var focus-index nil)
    (each [idx entry (ipairs events)]
      (when (and (= entry.type :blur)
                 (= entry.previous a)
                 (= entry.current b))
        (set blur-index idx))
      (when (and (= entry.type :focus)
                 (= entry.previous a)
                 (= entry.current b))
        (set focus-index idx)))
    (assert blur-index)
    (assert focus-index)
    (assert (< blur-index focus-index))
    (manager.focus-blur:disconnect blur-listener true)
    (manager.focus-focus:disconnect focus-listener true)
    (manager:drop)))

(add-test
  "focus manager skips detached nodes when cycling"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "scope"}))
    (manager:attach scope root)
    (local a (manager:create-node {:name "a"}))
    (local b (manager:create-node {:name "b"}))
    (local c (manager:create-node {:name "c"}))
    (manager:attach a scope)
    (manager:attach b scope)
    (manager:attach c scope)
    (manager:focus-next {})
    (manager:focus-next {})
    (assert (= (manager:get-focused-node) b))
    (b:detach)
    (manager:focus-next {})
    (assert (= (manager:get-focused-node) c))
    (manager:focus-next {})
    (assert (= (manager:get-focused-node) a))
    (manager:drop)))

(fn attach-bounds-node [manager scope name position size]
  (local node (manager:create-node {:name name}))
  (manager:attach node scope)
  (set node.get-focus-bounds
       (fn [_self]
         {:position position
          :size size}))
  node)

(add-test
  "focus manager selects nearest candidate in direction"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "scope"}))
    (manager:attach scope root)
    (local current (attach-bounds-node manager scope "current"
                                       (glm.vec3 0 0 0)
                                       (glm.vec3 1 1 1)))
    (local left (attach-bounds-node manager scope "left"
                                    (glm.vec3 -10 0 0)
                                    (glm.vec3 1 1 1)))
    (local right-near (attach-bounds-node manager scope "right-near"
                                          (glm.vec3 5 0 0)
                                          (glm.vec3 1 1 1)))
    (local right-far (attach-bounds-node manager scope "right-far"
                                         (glm.vec3 12 0 0)
                                         (glm.vec3 1 1 1)))
    (current:request-focus)
    (manager:focus-direction {:direction (glm.vec3 1 0 0)
                              :frustum-angle (/ math.pi 2)})
    (assert (= (manager:get-focused-node) right-near)
            "Directional focus should pick nearest right candidate")
    (current:request-focus)
    (manager:focus-direction {:direction :left})
    (assert (= (manager:get-focused-node) left)
            "Directional focus should pick left candidate")
    (manager:drop)))

(add-test
  "directional focus ignores culled nodes"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "scope"}))
    (manager:attach scope root)
    (local current (attach-bounds-node manager scope "current"
                                       (glm.vec3 0 0 0)
                                       (glm.vec3 1 1 1)))
    (local culled (attach-bounds-node manager scope "culled"
                                      (glm.vec3 4 0 0)
                                      (glm.vec3 1 1 1)))
    (local visible (attach-bounds-node manager scope "visible"
                                       (glm.vec3 8 0 0)
                                       (glm.vec3 1 1 1)))
    (local culled-layout (Layout {:name "culled-layout"}))
    (set culled-layout.culled? true)
    (set culled.layout culled-layout)
    (local visible-layout (Layout {:name "visible-layout"}))
    (set visible.layout visible-layout)
    (current:request-focus)
    (manager:focus-direction {:direction :right})
    (assert (= (manager:get-focused-node) visible)
            "Directional focus should skip culled nodes")
    (manager:drop)))

(add-test
  "directional focus uses camera orientation when provided"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "scope"}))
    (manager:attach scope root)
    (local current (attach-bounds-node manager scope "current"
                                       (glm.vec3 0 0 0)
                                       (glm.vec3 1 1 1)))
    (local north (attach-bounds-node manager scope "north"
                                     (glm.vec3 0 10 0)
                                     (glm.vec3 1 1 1)))
    (local east (attach-bounds-node manager scope "east"
                                    (glm.vec3 10 0 0)
                                    (glm.vec3 1 1 1)))
    (local camera (Camera {:position (glm.vec3 0 0 0)}))
    (camera:roll (/ math.pi 2))
    (current:request-focus)
    (manager:focus-direction {:direction :right :camera camera})
    (assert (= (manager:get-focused-node) north)
            "Camera basis should rotate directional focus")
    (camera:drop)
    (manager:drop)))

(add-test
  "directional focus uses frustum distance"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "scope"}))
    (manager:attach scope root)
    (local current (attach-bounds-node manager scope "current"
                                       (glm.vec3 0 0 0)
                                       (glm.vec3 2 2 1)))
    (local aligned (attach-bounds-node manager scope "aligned"
                                       (glm.vec3 5 0.1 0)
                                       (glm.vec3 2 2 1)))
    (local offset (attach-bounds-node manager scope "offset"
                                      (glm.vec3 3 4 0)
                                      (glm.vec3 2 2 1)))
    (current:request-focus)
    (manager:focus-direction {:direction :right :frustum-angle (/ math.pi 4)})
    (assert (= (manager:get-focused-node) aligned)
            "Frustum distance should favor near-axis candidate")
    (manager:drop)))

(add-test
  "directional focus scrolls when inside same scroll controller"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "scope"}))
    (manager:attach scope root)
    (local controller {:calls 0})
    (set controller.ensure-visible
         (fn [_self _node]
           (set controller.calls (+ controller.calls 1))))
    (local scroll-layout (Layout {:name "scroll-root"}))
    (set (. scroll-layout :scroll-controller) controller)
    (local clip {:layout scroll-layout})
    (local focused-layout (Layout {:name "focused-layout" :clip-region clip}))
    (set focused-layout.parent scroll-layout)
    (set focused-layout.position (glm.vec3 0 0 0))
    (set focused-layout.size (glm.vec3 1 1 1))
    (set focused-layout.clip-visibility :inside)
    (local target-layout (Layout {:name "target-layout" :clip-region clip}))
    (set target-layout.parent scroll-layout)
    (set target-layout.position (glm.vec3 5 0 0))
    (set target-layout.size (glm.vec3 1 1 1))
    (set target-layout.clip-visibility :outside)
    (local focused (manager:create-node {:name "focused"}))
    (manager:attach focused scope)
    (set focused.layout focused-layout)
    (local target (manager:create-node {:name "target"}))
    (manager:attach target scope)
    (set target.layout target-layout)
    (focused:request-focus)
    (manager:focus-direction {:direction :right})
    (assert (= (manager:get-focused-node) target))
    (assert (= controller.calls 1))
    (manager:drop)))

(add-test
  "directional focus stays within traversal boundary"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope-a (manager:create-scope {:name "a"
                                          :directional-traversal-boundary? true}))
    (local scope-b (manager:create-scope {:name "b"
                                          :directional-traversal-boundary? true}))
    (manager:attach scope-a root)
    (manager:attach scope-b root)
    (local current (attach-bounds-node manager scope-a "current"
                                       (glm.vec3 0 0 0)
                                       (glm.vec3 2 2 1)))
    (local farther (attach-bounds-node manager scope-a "farther"
                                       (glm.vec3 -6 0 0)
                                       (glm.vec3 2 2 1)))
    (local closer-other (attach-bounds-node manager scope-b "closer"
                                            (glm.vec3 -3 0 0)
                                            (glm.vec3 2 2 1)))
    (current:request-focus)
    (manager:focus-direction {:direction :left})
    (assert (= (manager:get-focused-node) farther)
            "Directional traversal should not cross boundary scopes")
    (manager:drop)))

(add-test
  "focus into enters first traversable child"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local owner (manager:create-node {:name "owner"}))
    (local sibling (manager:create-node {:name "sibling"}))
    (local inner (manager:create-scope {:name "inner"}))
    (local child-a (manager:create-node {:name "child-a"}))
    (local child-b (manager:create-node {:name "child-b"}))
    (manager:attach owner root)
    (manager:attach inner root)
    (manager:attach sibling root)
    (manager:attach child-a inner)
    (manager:attach child-b inner)
    (owner:set-entry-scope inner)
    (owner:request-focus)
    (assert (manager:can-focus-into?))
    (assert (= (manager:focus-into {}) child-a))
    (assert (= (manager:get-focused-node) child-a))
    (assert (not (manager:can-focus-into?)))
    (manager:drop)))

(add-test
  "focus into restores remembered descendant"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local owner (manager:create-node {:name "owner"}))
    (local inner (manager:create-scope {:name "inner"}))
    (local child-a (manager:create-node {:name "child-a"}))
    (local child-b (manager:create-node {:name "child-b"}))
    (manager:attach owner root)
    (manager:attach inner root)
    (manager:attach child-a inner)
    (manager:attach child-b inner)
    (owner:set-entry-scope inner)
    (child-b:request-focus)
    (owner:request-focus)
    (assert (= (manager:focus-into {}) child-b)
            "Entry should restore the scope's remembered focused descendant")
    (assert (= (manager:get-focused-node) child-b))
    (manager:drop)))

(add-test
  "focus out returns nearest exit node through nesting"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local outer-owner (manager:create-node {:name "outer-owner"}))
    (local outer-scope (manager:create-scope {:name "outer-scope"}))
    (local inner-owner (manager:create-node {:name "inner-owner"}))
    (local inner-scope (manager:create-scope {:name "inner-scope"}))
    (local inner-child (manager:create-node {:name "inner-child"}))
    (manager:attach outer-owner root)
    (manager:attach outer-scope root)
    (manager:attach inner-owner outer-scope)
    (manager:attach inner-scope outer-scope)
    (manager:attach inner-child inner-scope)
    (outer-owner:set-entry-scope outer-scope)
    (inner-owner:set-entry-scope inner-scope)
    (inner-child:request-focus)
    (assert (manager:can-focus-out?))
    (assert (= (manager:focus-out {}) inner-owner)
            "First exit should return to the nearest owner")
    (assert (= (manager:get-focused-node) inner-owner))
    (assert (manager:can-focus-out?))
    (assert (= (manager:focus-out {}) outer-owner)
            "Second exit should return to the outer owner")
    (assert (= (manager:get-focused-node) outer-owner))
    (assert (not (manager:can-focus-out?)))
    (manager:drop)))

(add-test
  "focus traversal skips unopened entry scopes"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local before (manager:create-node {:name "before"}))
    (local owner (manager:create-node {:name "owner"}))
    (local inner (manager:create-scope {:name "inner"}))
    (local child (manager:create-node {:name "child"}))
    (local after (manager:create-node {:name "after"}))
    (manager:attach before root)
    (manager:attach owner root)
    (manager:attach inner root)
    (manager:attach after root)
    (manager:attach child inner)
    (owner:set-entry-scope inner)
    (before:request-focus)
    (assert (= (manager:focus-next {}) owner))
    (assert (= (manager:focus-next {}) after)
            "Parent traversal should skip unopened entry scope children")
    (assert (= (manager:get-focused-node) after))
    (manager:drop)))

(add-test
  "directional focus honors active entry scope"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local owner (attach-bounds-node manager root "owner"
                                     (glm.vec3 0 0 0)
                                     (glm.vec3 1 1 1)))
    (local outside (attach-bounds-node manager root "outside"
                                       (glm.vec3 2 0 0)
                                       (glm.vec3 1 1 1)))
    (local inner (manager:create-scope {:name "inner"}))
    (manager:attach inner root)
    (local current (attach-bounds-node manager inner "current"
                                       (glm.vec3 0 0 0)
                                       (glm.vec3 1 1 1)))
    (local inside (attach-bounds-node manager inner "inside"
                                      (glm.vec3 5 0 0)
                                      (glm.vec3 1 1 1)))
    (owner:set-entry-scope inner)
    (current:request-focus)
    (manager:focus-direction {:direction :right})
    (assert (= (manager:get-focused-node) inside)
            "Directional focus inside an entry scope should ignore parent-level candidates")
    (assert (= outside.parent root))
    (manager:drop)))

(add-test
  "directional focus allows partial candidates when entering scroll view"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "scope"}))
    (manager:attach scope root)
    (local scroll-layout (Layout {:name "scroll-root"}))
    (set (. scroll-layout :scroll-controller) {:name "scroll-controller"})
    (fn attach-layout-node [name position visibility]
      (local node (manager:create-node {:name name}))
      (manager:attach node scope)
      (local layout (Layout {:name (.. name "-layout")}))
      (set layout.position position)
      (set layout.size (glm.vec3 1 1 1))
      (set layout.clip-visibility visibility)
      (set layout.parent scroll-layout)
      (set node.layout layout)
      node)
    (local current (attach-layout-node "current"
                                       (glm.vec3 0 0 0)
                                       :inside))
    (local partial-x (attach-layout-node "partial-x"
                                         (glm.vec3 2 0 0)
                                         :partial))
    (current:request-focus)
    (manager:focus-direction {:direction (glm.vec3 1 0 0)
                              :frustum-angle (/ math.pi 2)})
    (assert (= (manager:get-focused-node) partial-x)
            "Directional focus should allow partial clipping when entering a scroll view")
    (manager:drop)))

(add-test
  "activate-focused auto-focuses newly created node"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "scope"}))
    (manager:attach scope root)
    (local starter (manager:create-node {:name "starter"}))
    (manager:attach starter scope)
    (set starter.activate
         (fn [_node _opts]
           (local created (manager:create-node {:name "created"}))
           (manager:attach created scope)
           true))
    (starter:request-focus)
    (manager:activate-focused-from-payload {:mod 0})
    (local focused (manager:get-focused-node))
    (assert (and focused (= focused.name "created"))
            "Activation should focus newly created node")
    (manager:drop)))

(add-test
  "activate-focused respects ctrl to skip auto-focus"
  (fn []
    (local manager (FocusManager {:root-name "root"}))
    (local root (manager:get-root-scope))
    (local scope (manager:create-scope {:name "scope"}))
    (manager:attach scope root)
    (local starter (manager:create-node {:name "starter"}))
    (manager:attach starter scope)
    (set starter.activate
         (fn [_node _opts]
           (local created (manager:create-node {:name "created"}))
           (manager:attach created scope)
           true))
    (starter:request-focus)
    (manager:activate-focused-from-payload {:mod 64})
    (local focused (manager:get-focused-node))
    (assert (and focused (= focused.name "starter"))
            "Ctrl should keep focus on original node")
    (manager:drop)))

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "focus"
                       :tests tests})))

{:name "focus"
 :tests tests
 :main main}
