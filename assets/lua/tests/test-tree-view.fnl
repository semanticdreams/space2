(local TreeView (require :tree-view))
(local glm (require :glm))
(local {: Layout : LayoutRoot} (require :layout))

(local tests [])

(fn item-key [item] item.id)

(fn item-children [item]
  (if item.children item.children []))

(fn always-expanded [_row] true)

(fn expand-when-has-children [row] row.has-children?)

(fn noop-drop [_self] nil)

(fn noop-layout [_self] nil)

(fn make-zero-measurer [_row-key]
  (fn measure-zero [self]
    (set self.measure (glm.vec3 0 0 0))))

(fn assert-row [row expected-key expected-depth]
  (assert (= row.key expected-key)
          (.. "expected row key " expected-key ", got " (tostring row.key)))
  (assert (= row.depth expected-depth)
          (.. "expected depth " expected-depth ", got " (tostring row.depth))))

(fn make-row-builder [seen]
  (fn build-row [row _ctx]
    (when seen
      (table.insert seen {:key row.key :depth row.depth :toggle! row.toggle!}))
    {:layout (Layout {:name (.. "tree-row-" row.key)
                      :measurer (make-zero-measurer row.key)
                      :layouter noop-layout})
     :drop noop-drop}))

(fn make-measured-row-builder [heights states]
  (fn build-measured-row [row _ctx]
    (local height (. heights row.key))
    (local state {:key row.key})
    (table.insert states state)
    (fn measure-row [self]
      (set self.measure (glm.vec3 1 height 0)))
    (fn layout-row [self]
      (set state.position self.position)
      (set state.size self.size))
    {:layout (Layout {:name (.. "measured-tree-row-" row.key)
                      :measurer measure-row
                      :layouter layout-row})
     :drop noop-drop}))

(fn make-droppable-row-builder [drops]
  (fn build-droppable-row [row _ctx]
    (tset drops row.key (if (= (. drops row.key) nil) 0 (. drops row.key)))
    (fn measure-droppable-row [self]
      (set self.measure (glm.vec3 1 1 0)))
    (fn drop-row [_self]
      (tset drops row.key (+ (. drops row.key) 1)))
    {:layout (Layout {:name (.. "droppable-tree-row-" row.key)
                      :measurer measure-droppable-row
                      :layouter noop-layout})
     :drop drop-row}))

(fn assert-fails-after-drop [label f]
  (local (ok? err) (pcall f))
  (assert (not ok?) (.. label " should fail after drop"))
  (assert (string.find (tostring err) "TreeView" 1 true) (tostring err))
  (assert (string.find (tostring err) "called after drop" 1 true) (tostring err)))

(fn tree-view-flattens-expanded-tree-depth-first []
  (local roots [{:id "a" :children [{:id "b"} {:id "c"}]}])
  (local seen [])
  (local tree ((TreeView {:roots roots
                          :key item-key
                          :children item-children
                          :default-expanded? always-expanded
                          :row-builder (make-row-builder seen)}) {}))
  (local rows (tree:visible-rows))
  (assert (= (length rows) 3))
  (assert-row (. rows 1) "a" 0)
  (assert-row (. rows 2) "b" 1)
  (assert-row (. rows 3) "c" 1)
  (assert (= (length seen) 3))
  (assert-row (. seen 1) "a" 0)
  (assert-row (. seen 2) "b" 1)
  (assert-row (. seen 3) "c" 1)
  (tree:drop))

(fn tree-view-toggles-internal-expansion-state []
  (local roots [{:id "a" :children [{:id "b"}]}])
  (local tree ((TreeView {:roots roots
                          :key item-key
                          :children item-children
                          :row-builder (make-row-builder nil)}) {}))
  (assert (= (length (tree:visible-rows)) 1))
  (assert (not (tree:expanded? "a")))
  (tree:set-expanded "a" true)
  (local rows (tree:visible-rows))
  (assert (tree:expanded? "a"))
  (assert (= (length rows) 2))
  (assert-row (. rows 1) "a" 0)
  (assert-row (. rows 2) "b" 1)
  ((. (. rows 1) :toggle!))
  (assert (not (tree:expanded? "a")))
  (assert (= (length (tree:visible-rows)) 1))
  (tree:drop))

(fn tree-view-supports-caller-owned-expanded-keys []
  (local roots [{:id "a" :children [{:id "b"}]}])
  (local expanded-keys {:a true})
  (local changes [])
  (local tree ((TreeView {:roots roots
                          :key item-key
                          :children item-children
                          :expanded-keys expanded-keys
                          :on-expanded-change (fn on-expanded-change [key next-expanded?]
                                                (table.insert changes {:key key :expanded? next-expanded?})
                                                (tset expanded-keys key next-expanded?))
                          :row-builder (make-row-builder nil)}) {}))
  (local rows (tree:visible-rows))
  (assert (= (length rows) 2))
  ((. (. rows 1) :toggle!))
  (assert (= (length changes) 1))
  (assert (= (. (. changes 1) :key) "a"))
  (assert (= (. (. changes 1) :expanded?) false))
  (assert (not (tree:expanded? "a")))
  (assert (= (length (tree:visible-rows)) 1))
  (tree:drop))

(fn tree-view-lays-out-variable-height-row-widgets []
  (local roots [{:id "a" :children [{:id "b"} {:id "c"}]}])
  (local states [])
  (local tree ((TreeView {:roots roots
                          :key item-key
                          :children item-children
                          :default-expanded? always-expanded
                          :row-gap 2
                          :row-builder (make-measured-row-builder {:a 6 :b 10 :c 4} states)}) {}))
  (tree.layout:measurer)
  (assert (= tree.layout.measure.y 24))
  (set tree.layout.size (glm.vec3 5 24 0))
  (set tree.layout.position (glm.vec3 0 0 0))
  (tree.layout:layouter)
  (assert (= (. (. (. states 1) :position) :y) 18))
  (assert (= (. (. (. states 2) :position) :y) 6))
  (assert (= (. (. (. states 3) :position) :y) 0))
  (tree:drop))

(fn tree-view-drops-owned-rows-exactly-once []
  (local drops {})
  (local tree ((TreeView {:roots [{:id "a"} {:id "b"}]
                          :key item-key
                          :children item-children
                          :row-builder (make-droppable-row-builder drops)}) {}))
  (tree:set-roots [{:id "c"}])
  (assert (= drops.a 1))
  (assert (= drops.b 1))
  (assert (= drops.c 0))
  (tree:drop)
  (assert (= drops.a 1))
  (assert (= drops.b 1))
  (assert (= drops.c 1)))

(fn tree-view-methods-fail-after-drop []
  (local tree ((TreeView {:roots [{:id "a"}]
                          :key item-key
                          :children item-children
                          :row-builder (make-row-builder nil)}) {}))
  (tree:drop)
  (fn call-visible-rows [] (tree:visible-rows))
  (fn call-refresh [] (tree:refresh))
  (fn call-set-expanded [] (tree:set-expanded "a" true))
  (fn call-expanded? [] (tree:expanded? "a"))
  (fn call-set-roots [] (tree:set-roots []))
  (assert-fails-after-drop "visible-rows" call-visible-rows)
  (assert-fails-after-drop "refresh" call-refresh)
  (assert-fails-after-drop "set-expanded" call-set-expanded)
  (assert-fails-after-drop "expanded?" call-expanded?)
  (assert-fails-after-drop "set-roots" call-set-roots))

(fn tree-view-refresh-schedules-remeasurement []
  (local root (LayoutRoot {:log-dirt? false}))
  (local tree ((TreeView {:roots [{:id "a" :children [{:id "b"}]}]
                          :key item-key
                          :children item-children
                          :row-builder (make-row-builder nil)}) {}))
  (tree.layout:set-root root)
  (root:update)
  (assert (not (. root.measure-dirt.lookup tree.layout)))
  (assert (not (. root.layout-dirt.lookup tree.layout)))
  (tree:set-expanded "a" true)
  (assert (. root.measure-dirt.lookup tree.layout)
          "set-expanded should schedule TreeView remeasurement")
  (assert (. root.layout-dirt.lookup tree.layout)
          "set-expanded should schedule TreeView relayout")
  (root:update)
  (tree:set-roots [{:id "c"}])
  (assert (. root.measure-dirt.lookup tree.layout)
          "set-roots should schedule TreeView remeasurement")
  (assert (. root.layout-dirt.lookup tree.layout)
          "set-roots should schedule TreeView relayout")
  (tree:drop))

(fn tree-view-expanded-matches-row-metadata-default []
  (local tree ((TreeView {:roots [{:id "a" :children [{:id "b"}]}]
                          :key item-key
                          :children item-children
                          :default-expanded? expand-when-has-children
                          :row-builder (make-row-builder nil)}) {}))
  (local rows (tree:visible-rows))
  (assert (= (length rows) 2))
  (assert (. (. rows 1) :expanded?))
  (assert (tree:expanded? "a")
          "expanded? should match row metadata for metadata-dependent defaults")
  (tree:drop))

(table.insert tests {:name "TreeView flattens expanded tree depth first"
                     :fn tree-view-flattens-expanded-tree-depth-first})
(table.insert tests {:name "TreeView toggles internal expansion state"
                     :fn tree-view-toggles-internal-expansion-state})
(table.insert tests {:name "TreeView supports caller-owned expanded keys"
                     :fn tree-view-supports-caller-owned-expanded-keys})
(table.insert tests {:name "TreeView lays out variable height row widgets"
                     :fn tree-view-lays-out-variable-height-row-widgets})
(table.insert tests {:name "TreeView drops owned rows exactly once"
                     :fn tree-view-drops-owned-rows-exactly-once})
(table.insert tests {:name "TreeView methods fail after drop"
                     :fn tree-view-methods-fail-after-drop})
(table.insert tests {:name "TreeView refresh schedules remeasurement"
                     :fn tree-view-refresh-schedules-remeasurement})
(table.insert tests {:name "TreeView expanded? matches row metadata default"
                     :fn tree-view-expanded-matches-row-metadata-default})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "tree-view"
                     :tests tests}))

{:name "tree-view"
 :tests tests
 :main main}
