(local fs (require :fs))

(fn failure [reason message]
  {:ok? false
   :reason reason
   :message message})

(fn starts-with? [value prefix]
  (= (string.sub value 1 (string.len prefix)) prefix))

(fn strip-prefix [value prefix]
  (if (starts-with? value prefix)
      (string.sub value (+ (string.len prefix) 1))
      nil))

(fn filename [path]
  (local name (string.match path "([^/]+)$"))
  (assert name (.. "source resolver could not determine filename for " (tostring path)))
  name)

(fn basename-without-extension [path]
  (local name (filename path))
  (local base (string.match name "^(.*)%.fnl$"))
  (assert base (.. "source resolver expected .fnl basename for " name))
  base)

(fn module-name-from-relative [relative]
  (local module-name (string.match relative "^(.*)%.fnl$"))
  (assert module-name (.. "source resolver expected .fnl module path for " relative))
  module-name)

(fn fnl-file? [path]
  (and (= (type path) :string)
       (not (= (string.match path "%.fnl$") nil))))

(fn stat-path [path]
  (local (ok stat) (pcall fs.stat path))
  (if ok stat nil))

(fn existing-entry [path]
  (local stat (stat-path path))
  (and stat stat.exists stat.is-file))

(fn node-for-key [graph-map key]
  (if (and graph-map graph-map.lookup)
      (graph-map:lookup key)
      (and graph-map graph-map.nodes (. graph-map.nodes key))))

(fn path-for-selection [graph-map key]
  (local node (node-for-key graph-map key))
  (if (and node node.path)
      node.path
      (strip-prefix key "fs:")))

(fn file-module-info [path]
  (local marker "/assets/lua/")
  (local (start-index end-index) (string.find path marker 1 true))
  (if start-index
      (do
        (local lua-root (string.sub path 1 (- end-index 1)))
        (local relative (string.sub path (+ end-index 1)))
        {:lua-root lua-root
         :module-name (module-name-from-relative relative)})
      (do
        (local parent (and fs.parent (fs.parent path)))
        (assert parent (.. "source resolver could not determine parent for " path))
        {:lua-root parent
         :module-name (basename-without-extension path)})))

(fn label-for-path [path]
  (filename path))

(fn success [source-kind selection-key path entry-path lua-root module-name]
  {:ok? true
   :source-kind source-kind
   :selection-key selection-key
   :path path
   :entry-path entry-path
   :lua-root lua-root
   :module-name module-name
   :label (label-for-path path)})

(fn resolve-file [selection-key path]
  (if (not (fnl-file? path))
      (failure :unsupported-file (.. "selected file is not a .fnl source: " path))
      (do
        (local info (file-module-info path))
        (success :file selection-key path path info.lua-root info.module-name))))

(fn directory-candidates [path]
  [{:entry-path (fs.join-path path "assets" "lua" "main.fnl")
    :lua-root (fs.join-path path "assets" "lua")
    :module-name "main"}
   {:entry-path (fs.join-path path "main.fnl")
    :lua-root path
    :module-name "main"}
   {:entry-path (fs.join-path path "init.fnl")
    :lua-root path
    :module-name "init"}])

(fn resolve-directory [selection-key path]
  (local matches [])
  (each [_ candidate (ipairs (directory-candidates path))]
    (when (existing-entry candidate.entry-path)
      (table.insert matches candidate)))
  (if (= (# matches) 0)
      (failure :no-directory-entry (.. "directory has no hosted app entry: " path))
      (> (# matches) 1)
      (failure :ambiguous-directory (.. "directory has multiple hosted app entries: " path))
      (do
        (local entry (. matches 1))
        (success :directory selection-key path entry.entry-path entry.lua-root entry.module-name))))

(fn resolve-path [selection-key path]
  (local stat (stat-path path))
  (if (not stat)
      (failure :missing-path (.. "selected filesystem path does not exist: " (tostring path)))
      (not stat.exists)
      (failure :missing-path (.. "selected filesystem path does not exist: " (tostring path)))
      stat.is-file
      (resolve-file selection-key path)
      stat.is-dir
      (resolve-directory selection-key path)
      (failure :missing-path (.. "selected filesystem path is not a file or directory: " path))))

(fn resolve-selection [graph-map selected-keys]
  (local keys (if selected-keys selected-keys []))
  (if (= (# keys) 0)
      (failure :no-selection "select one filesystem app source")
      (> (# keys) 1)
      (failure :multiple-selection "select only one filesystem app source")
      (do
        (local key (. keys 1))
        (if (not (= (type key) :string))
            (failure :unsupported-selection (.. "selected graph key is not an fs: source: " (tostring key)))
            (not (starts-with? key "fs:"))
            (failure :unsupported-selection (.. "selected graph key is not an fs: source: " (tostring key)))
            (do
              (local path (path-for-selection graph-map key))
              (if (not (= (type path) :string))
                  (failure :missing-path "selected filesystem node has no path")
                  (= path "")
                  (failure :missing-path "selected filesystem node has no path")
                  (resolve-path key path)))))))

{:resolve-selection resolve-selection}
