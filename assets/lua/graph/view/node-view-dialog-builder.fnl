(local fs (require :fs))
(local Dialog (require :dialog))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:FsNode FsNode} (require :graph/nodes/fs))
(local {:TableNode TableNode} (require :graph/nodes/table))
(local ViewKindBadge (require :graph/view/kind-badge))

(fn resolve-view-module-name [node]
  (local view-fn (and node node.view))
  (assert (= (type view-fn) :function)
          "Node view code action requires a node view function")
  (var module-name nil)
  (each [name value (pairs package.loaded)]
    (when (= value view-fn)
      (set module-name name)))
  (assert module-name "Node view code action requires a loaded view module")
  module-name)

(fn resolve-view-module-path [module-name]
  (assert app "Node view code action requires global app")
  (assert (and app.engine app.engine.get-asset-path)
          "Node view code action requires app.engine.get-asset-path")
  (assert module-name "Node view code action requires module name")
  (app.engine.get-asset-path (.. "lua/" module-name ".fnl")))

(fn resolve-built-view [builder ctx builder-opts]
  (var view (builder ctx builder-opts))
  (when (= (type view) :function)
    (set view (view ctx builder-opts)))
  (assert (and view view.layout)
          "Node view builder must return a widget with a layout")
  view)

(fn ensure-mounted-graph [node action-name]
  (local graph (and node node.graph))
  (assert graph (.. "Node view " action-name " action requires a mounted graph"))
  graph)

(fn make-table-node [node graph dialog-instance]
  (local key (.. "table:node-view-dialog:" (tostring dialog-instance)))
  (local existing (if graph.lookup (graph:lookup key) nil))
  (if existing
      existing
      (TableNode {:table dialog-instance
                  :key key
                  :label (.. "node view: " (if node.label node.label node.key))})))

(fn add-table-edge [node graph dialog-instance]
  (local table-node (make-table-node node graph dialog-instance))
  (graph:add-edge (GraphEdge {:source node
                              :target table-node})))

(fn make-table-action [node get-dialog-instance]
  (fn on-table-click [_button _event]
    (local graph (ensure-mounted-graph node "table"))
    (local dialog-instance (get-dialog-instance))
    (assert dialog-instance
            "Node view table action requires a built dialog")
    (add-table-edge node graph dialog-instance))
  {:name "table"
   :icon "table"
   :handler on-table-click})

(fn make-fs-node [module-path key graph]
  (local existing (if graph.lookup (graph:lookup key) nil))
  (if existing
      existing
      (FsNode {:path (fs.absolute module-path)
               :key key})))

(fn add-code-edge [node graph]
  (local module-name (resolve-view-module-name node))
  (local module-path (resolve-view-module-path module-name))
  (local key (.. "fs:" module-path))
  (local fs-node (make-fs-node module-path key graph))
  (graph:add-edge (GraphEdge {:source node
                              :target fs-node})))

(fn make-code-action [node]
  (fn on-code-click [_button _event]
    (local graph (ensure-mounted-graph node "code"))
    (add-code-edge node graph))
  {:name "code"
   :icon "code"
   :handler on-code-click})

(fn make-close-action [node get-dialog-instance on-close]
  (fn on-close-click [_button _event]
    (when on-close
      (on-close node (get-dialog-instance))))
  {:name "close"
   :icon "close"
   :handler on-close-click})

(fn make-actions [node get-dialog-instance on-close]
  [(make-table-action node get-dialog-instance)
   (make-code-action node)
   (make-close-action node get-dialog-instance on-close)])

(fn expose-title-kind-badge! [dialog-instance node title-prefix]
  (when title-prefix
    (set dialog-instance.title-kind-badge-text node.kind-badge.text)
    (set dialog-instance.title-kind-badge
         (. dialog-instance.children 1 :element :children 2 :children 1 :element))))

(fn make-dialog-builder [node builder opts]
  (local options (if opts opts {}))
  (local on-close options.on-close)
  (fn [ctx builder-opts]
    (local view (resolve-built-view builder ctx builder-opts))
    (local title-prefix
      (ViewKindBadge.titlebar-builder node.kind-badge {:scale 0.95
                                                       :padding [0.22 0.08]}))
    (var dialog-instance nil)
    (fn get-dialog-instance [] dialog-instance)
    (fn dialog-child [_dialog-ctx] view)
    (local dialog-builder
      (Dialog {:title (if node.label node.label node.key)
               :title-prefix title-prefix
               :actions (make-actions node get-dialog-instance on-close)
               :child dialog-child}))
    (set dialog-instance (dialog-builder ctx))
    (expose-title-kind-badge! dialog-instance node title-prefix)
    dialog-instance))

{:make-dialog-builder make-dialog-builder}
