(local glm (require :glm))
(local {: Layout} (require :layout))

(fn empty-list [] [])

(fn option-or [value fallback]
  (if (= value nil) fallback value))

(fn flatten-visible-rows [roots key-fn children-fn expanded-fn toggle-fn]
  (local rows [])
  (fn visit [item depth parent-key]
    (local row-key (key-fn item))
    (local children (option-or (children-fn item) (empty-list)))
    (local has-children? (> (length children) 0))
    (local expanded-row? (expanded-fn row-key item depth parent-key has-children?))
    (fn toggle-row []
      (toggle-fn row-key (not expanded-row?)))
    (local row {:key row-key
                :item item
                :depth depth
                :index (+ (length rows) 1)
                :parent-key parent-key
                :expanded? expanded-row?
                :has-children? has-children?
                :toggle! toggle-row})
    (table.insert rows row)
    (when (and row.expanded? has-children?)
      (each [_ child (ipairs children)]
        (visit child (+ depth 1) row-key))))
  (each [_ root (ipairs roots)]
    (visit root 0 nil))
  rows)

(fn assert-tree-view-options [opts]
  (assert opts.roots "TreeView requires :roots")
  (assert opts.key "TreeView requires :key")
  (assert opts.children "TreeView requires :children")
  (assert opts.row-builder "TreeView requires :row-builder"))

(fn find-row-context [roots key-fn children-fn target-key]
  (var found nil)
  (fn visit [item depth parent-key]
    (when (not found)
      (local row-key (key-fn item))
      (local children (option-or (children-fn item) (empty-list)))
      (local has-children? (> (length children) 0))
      (if (= row-key target-key)
          (set found {:key row-key
                      :item item
                      :depth depth
                      :parent-key parent-key
                      :has-children? has-children?})
          (each [_ child (ipairs children)]
            (visit child (+ depth 1) row-key)))))
  (each [_ root (ipairs roots)]
    (visit root 0 nil))
  found)

(fn make-tree-layout [name row-widgets-fn row-gap]
  (fn measure-tree [self]
    (local row-widgets (row-widgets-fn))
    (var width 0)
    (var height 0)
    (each [i child (ipairs row-widgets)]
      (child.layout:measurer)
      (set width (math.max width child.layout.measure.x))
      (set height (+ height child.layout.measure.y))
      (when (< i (length row-widgets))
        (set height (+ height row-gap))))
    (set self.measure (glm.vec3 width height 0)))
  (fn layout-tree [self]
    (local row-widgets (row-widgets-fn))
    (var cursor-y (+ self.position.y self.size.y))
    (each [_ child (ipairs row-widgets)]
      (child.layout:measurer)
      (local height child.layout.measure.y)
      (set cursor-y (- cursor-y height))
      (set child.layout.size (glm.vec3 self.size.x height self.size.z))
      (set child.layout.position (glm.vec3 self.position.x cursor-y self.position.z))
      (set child.layout.rotation self.rotation)
      (child.layout:layouter)
      (set cursor-y (- cursor-y row-gap))))
  (Layout {:name name
           :measurer measure-tree
           :layouter layout-tree}))

(fn TreeView [opts]
  (assert-tree-view-options opts)
  (fn build [ctx]
    (var roots opts.roots)
    (local internal-expanded {})
    (var row-widgets [])
    (local row-gap (option-or opts.row-gap 0))
    (var dropped? false)
    (fn assert-not-dropped []
      (when dropped?
        (error "TreeView method called after drop")))

    (fn default-expanded? [key item depth parent-key has-children?]
      (if opts.default-expanded?
          (opts.default-expanded? {:key key
                                   :item item
                                   :depth depth
                                   :parent-key parent-key
                                   :has-children? has-children?})
          false))

    (fn expanded? [key item depth parent-key has-children?]
      (local lookup (option-or opts.expanded-keys internal-expanded))
      (local stored (. lookup key))
      (if (not (= stored nil))
          stored
          (default-expanded? key item depth parent-key has-children?)))

    (fn set-expanded-state [key expanded]
      (if opts.expanded-keys
          (do
            (assert opts.on-expanded-change "TreeView requires :on-expanded-change with caller-owned :expanded-keys")
            (opts.on-expanded-change key expanded))
          (tset internal-expanded key expanded)))

    (fn current-rows [after-change]
      (fn toggle-expanded [key expanded]
        (assert-not-dropped)
        (set-expanded-state key expanded)
        (when after-change
          (after-change)))
      (flatten-visible-rows roots opts.key opts.children expanded? toggle-expanded))

    (fn drop-rows []
      (each [_ child (ipairs row-widgets)]
        (child:drop))
      (set row-widgets []))

    (fn current-row-widgets [] row-widgets)

    (fn expanded-query [_self key]
      (assert-not-dropped)
      (local context (find-row-context roots opts.key opts.children key))
      (if context
          (expanded? key context.item context.depth context.parent-key context.has-children?)
          (expanded? key nil 0 nil false)))

    (local layout
      (make-tree-layout (option-or opts.name "tree-view") current-row-widgets row-gap))

    (fn mark-dirty []
      (layout:mark-measure-dirty)
      (layout:mark-layout-dirty))

    (fn refresh [self]
      (assert-not-dropped)
      (drop-rows)
      (fn refresh-after-toggle []
        (self:refresh))
      (local rows (current-rows refresh-after-toggle))
      (each [_ row (ipairs rows)]
        (local child (opts.row-builder row ctx))
        (table.insert row-widgets child))
      (layout:set-children (icollect [_ child (ipairs row-widgets)] child.layout))
      (mark-dirty)
      self)

    (fn visible-rows [_self]
      (assert-not-dropped)
      (current-rows nil))

    (fn set-roots [self next-roots]
      (assert-not-dropped)
      (set roots next-roots)
      (self:refresh))

    (fn set-expanded [self key expanded]
      (assert-not-dropped)
      (set-expanded-state key expanded)
      (self:refresh))

    (fn drop [_self]
      (when (not dropped?)
        (set dropped? true)
        (drop-rows)
        (layout:drop)))

    (local self {:layout layout
                 :refresh refresh
                 :set-roots set-roots
                 :set-expanded set-expanded
                 :expanded? expanded-query
                 :visible-rows visible-rows
                 :drop drop})
    (self:refresh)
    self))

TreeView
