(local glm (require :glm))
(local {:GraphEdge GraphEdge} (require :graph/edge))
(local {:GraphNode GraphNode} (require :graph/node-base))
(local CodeDirNodeView (require :graph/view/views/code-dir))
(local FnlModuleNode (require :graph/nodes/fnl-module))
(local CppModuleNode (require :graph/nodes/cpp-module))
(local TextModuleNode (require :graph/nodes/text-module))
(local Signal (require :signal))
(local fs (require :fs))
(local logging (require :logging))

(fn normalize-path [path]
    (if (= (type path) :table)
        (or path.path (tostring path))
        path))

(fn default-root []
    (if (and fs fs.cwd)
        (fs.cwd)
        "."))

(fn safe-lower [text]
    (if text
        (string.lower text)
        ""))

(fn fnl-file? [entry]
    (and entry entry.is-file entry.name (string.match entry.name "%.fnl$")))

(fn cpp-file? [entry]
    (and entry entry.is-file entry.name
         (or (string.match entry.name "%.cpp$")
             (string.match entry.name "%.cc$")
             (string.match entry.name "%.cxx$")
             (string.match entry.name "%.h$")
             (string.match entry.name "%.hpp$")
             (string.match entry.name "%.hh$"))))

(fn text-file? [entry]
    (and entry entry.is-file (not (fnl-file? entry)) (not (cpp-file? entry))))

(fn sort-entries [entries]
    (table.sort entries
                (fn [a b]
                    (if (= a.is-dir b.is-dir)
                        (< (safe-lower a.name) (safe-lower b.name))
                        a.is-dir)))
    entries)

(fn CodeDirNode [opts]
    (local options (or opts {}))
    (local root (normalize-path (or options.root (default-root))))
    (local path (normalize-path (or options.path root)))
    (local absolute-path (if (and path fs.absolute)
                             (fs.absolute path)
                             path))
    (local key (or options.key (.. "code-dir:" absolute-path)))
    (local label (or options.label absolute-path))
    (local node (GraphNode {:key key
                            :label label
                            :color (glm.vec4 0.45 0.5 0.75 1)
                            :sub-color (glm.vec4 0.35 0.4 0.65 1)
                            :size 8.0
                            :view CodeDirNodeView}))
    (set node.kind "code-dir")
    (set node.path absolute-path)
    (set node.root root)
    (set node.items-changed (Signal))

    (set node.list-directory
         (fn [self]
             (local (ok entries) (pcall fs.list-dir self.path false))
             (if ok
                 entries
                 (do
                     (logging.warn (.. "CodeDirNode failed to list " self.path ": " entries))
                     []))))

    (set node.normalize-entry
         (fn [_self entry]
             {:name entry.name
              :path entry.path
              :is-dir (and entry.is-dir true)
              :is-file (and entry.is-file true)}))

    (set node.collect-items
         (fn [self]
             (local entries [])
             (each [_ entry (ipairs (self:list-directory))]
                 (when (or entry.is-dir entry.is-file)
                     (table.insert entries (self:normalize-entry entry))))
             (sort-entries entries)
             (icollect [_ entry (ipairs entries)]
                 [entry (if entry.is-dir
                            (.. entry.name "/")
                            entry.name)])))

    (set node.emit-items
         (fn [self]
             (local items (self:collect-items))
             (self.items-changed:emit items)
             items))

    (set node.create-child-node
         (fn [self entry]
             (local child-path (if (and entry entry.path fs.absolute)
                                   (fs.absolute entry.path)
                                   (and entry entry.path)))
             (assert child-path "CodeDirNode requires entry.path")
             (if entry.is-dir
                 (CodeDirNode {:path child-path
                               :root self.root})
                 (if (fnl-file? entry)
                     (FnlModuleNode {:path child-path
                                     :lua-root self.root})
                     (if (cpp-file? entry)
                         (CppModuleNode {:path child-path
                                         :project-root self.root})
                         (if (text-file? entry)
                             (TextModuleNode {:path child-path
                                              :project-root self.root})
                             (error (.. "CodeDirNode unsupported entry: " child-path))))))))

    (set node.open-entry
         (fn [self entry]
             (local graph self.graph)
             (when (and graph entry)
                 (local child (self:create-child-node entry))
                 (graph:add-edge (GraphEdge {:source self
                                             :target child})))))

    (set node.actions
         [{:name "Refresh"
           :icon "refresh"
           :fn (fn [_button _event]
                   (node:emit-items))}])

    (set node.drop
         (fn [self]
             (when self.items-changed
                 (self.items-changed:clear))))

    node)

CodeDirNode
