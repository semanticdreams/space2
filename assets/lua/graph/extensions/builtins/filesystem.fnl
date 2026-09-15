(local Common (require :graph/extensions/builtins/common))
(local FileTypes (require :graph/file-types))
(local {:TableNode TableNode} (require :graph/nodes/table))
(local CodeDirNode (require :graph/nodes/code-dir))
(local CppModuleNode (require :graph/nodes/cpp-module))
(local FnlModuleNode (require :graph/nodes/fnl-module))
(local {:FsNode FsNode} (require :graph/nodes/fs))
(local {:FsFileViewerNode FsFileViewerNode} (require :graph/nodes/fs-file-viewer))
(local TextModuleNode (require :graph/nodes/text-module))

(local schemes ["fs" "fs-file-viewer" "code-dir" "fnl-module" "cpp-module" "text-module" "table"])

(fn loader-opts [ctx]
  {:owner-id ctx.owner-id :extension-id ctx.extension-id})

(fn path-module-kind? [path expected-kind]
  (local classification (FileTypes.classify path))
  (= classification.module-kind expected-kind))

(fn require-table-global [name]
  (when (and name (not (string.find name ":" 1 true)))
    (if (= name "_G")
        _G
        (. _G name))))

(fn install-loaders [_options graph ctx]
  (local handles [])
  (fn add! [handle] (table.insert handles handle))
  (fn make-fs-node [path key] (FsNode {:path path :key key}))
  (fn make-file-viewer-node [path key] (FsFileViewerNode {:path path :key key}))
  (fn make-code-dir-node [path key] (CodeDirNode {:path path :root path :key key}))
  (fn make-fnl-module-node [path key]
    (when (path-module-kind? path :fnl)
      (FnlModuleNode {:path path :key key})))
  (fn make-cpp-module-node [path key]
    (when (path-module-kind? path :cpp)
      (CppModuleNode {:path path :key key})))
  (fn make-text-module-node [path key] (TextModuleNode {:path path :key key}))
  (fn make-table-node [name key]
    (local tbl (require-table-global name))
    (when (= (type tbl) :table)
      (TableNode {:table tbl :label name :key key})))
  (add! (graph:register-key-loader "fs"
      (Common.existing-any-path-loader "fs:" make-fs-node)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "fs-file-viewer"
      (Common.existing-path-loader "fs-file-viewer:" :file make-file-viewer-node)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "code-dir"
      (Common.existing-path-loader "code-dir:" :dir make-code-dir-node)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "fnl-module"
      (Common.existing-path-loader "fnl-module:" :file make-fnl-module-node)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "cpp-module"
      (Common.existing-path-loader "cpp-module:" :file make-cpp-module-node)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "text-module"
      (Common.existing-path-loader "text-module:" :file make-text-module-node)
      (loader-opts ctx)))
  (add! (graph:register-key-loader "table"
      (Common.prefix-loader "table:" make-table-node)
      (loader-opts ctx)))
  handles)

(fn descriptors [opts]
  (local options (if opts opts {}))
  (fn install [graph ctx]
    (install-loaders options graph ctx))
  [(Common.descriptor
     {:id "builtin-graph-filesystem"
      :unit-id "builtin-graph-filesystem"
      :schemes schemes
      :install-loaders install})])

{:descriptors descriptors}
