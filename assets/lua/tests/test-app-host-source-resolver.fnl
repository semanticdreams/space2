(local Runner (require :tests/runner))
(local fs (require :fs))
(local SourceResolver (require :app-host.source-resolver))

(local tests [])
(local temp-root (fs.join-path "/tmp/space/tests" "hosted-app-source-resolver"))
(var temp-counter 0)

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn assert-equals [actual expected message]
  (assert (= actual expected)
          (.. (or message "values should match")
              ": expected " (tostring expected)
              ", got " (tostring actual))))

(local path-like-success-fields {:path true :entry-path true :lua-root true})

(fn normalize-test-path [path]
  (if (= (type path) :string)
      (string.gsub path "\\" "/")
      path))

(fn path-like-success-field? [key]
  (. path-like-success-fields key))

(fn assert-failure [result reason]
  (assert-equals result.ok? false "resolver should fail")
  (assert-equals result.reason reason "failure reason should match")
  (assert (= (type result.message) :string) "failure should include message"))

(fn assert-success [result expected]
  (assert-equals result.ok? true "resolver should succeed")
  (each [key value (pairs expected)]
    (if (path-like-success-field? key)
        (assert-equals (normalize-test-path (. result key))
                       (normalize-test-path value)
                       (.. "success field " (tostring key) " should match"))
        (assert-equals (. result key) value (.. "success field " (tostring key) " should match")))))

(fn graph-map [nodes]
  {:nodes (or nodes {})
   :lookup (fn [self key]
             (. self.nodes key))})

(fn write-file [path content]
  (local parent (fs.parent path))
  (when parent
    (fs.create-dirs parent))
  (fs.write-file path (if content content "{:ok true}\n"))
  path)

(fn with-temp-dir [name f]
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. name "-" (os.time) "-" temp-counter)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (if ok
      result
      (error result)))

(fn resolve [selected-keys nodes]
  (SourceResolver.resolve-selection (graph-map nodes) selected-keys))

(fn test-no-selection []
  (assert-failure (resolve [] {}) :no-selection))

(fn test-multiple-selection []
  (assert-failure (resolve ["fs:/tmp/a.fnl" "fs:/tmp/b.fnl"] {}) :multiple-selection))

(fn test-unsupported-selection []
  (assert-failure (resolve ["graph:start"] {}) :unsupported-selection))

(fn test-missing-filesystem-path []
  (assert-failure (resolve ["fs:/tmp/space/tests/hosted-app-source-resolver/missing.fnl"] {})
                  :missing-path))

(fn test-unsupported-file-extension []
  (with-temp-dir "unsupported-file"
    (fn [root]
      (local path (write-file (fs.join-path root "main.lua") "return {}\n"))
      (assert-failure (resolve [(.. "fs:" path)] {}) :unsupported-file))))

(fn test-file-under-assets-lua-main []
  (with-temp-dir "assets-main"
    (fn [root]
      (local lua-root (fs.join-path root "assets" "lua"))
      (local entry (write-file (fs.join-path lua-root "main.fnl")))
      (assert-success (resolve [(.. "fs:" entry)] {})
                      {:source-kind :file
                       :selection-key (.. "fs:" entry)
                       :path entry
                       :entry-path entry
                       :lua-root lua-root
                       :module-name "main"}))))

(fn test-file-under_assets_lua_nested_module []
  (with-temp-dir "assets-nested"
    (fn [root]
      (local lua-root (fs.join-path root "assets" "lua"))
      (local entry (write-file (fs.join-path lua-root "snake" "app.fnl")))
      (assert-success (resolve [(.. "fs:" entry)] {})
                      {:source-kind :file
                       :lua-root lua-root
                       :module-name "snake/app"
                       :entry-path entry}))))

(fn test-windows-file-under-assets-lua-main []
  (with-temp-dir "windows-assets-main"
    (fn [root]
      (local lua-root (.. root "\\assets\\lua"))
      (local entry (write-file (.. lua-root "\\main.fnl")))
      (assert-success (resolve [(.. "fs:" entry)] {})
                      {:source-kind :file
                       :selection-key (.. "fs:" entry)
                       :path entry
                       :entry-path entry
                       :lua-root lua-root
                       :module-name "main"}))))

(fn test-windows-file-under-assets-lua-nested-module []
  (with-temp-dir "windows-assets-nested"
    (fn [root]
      (local lua-root (.. root "\\assets\\lua"))
      (local entry (write-file (.. lua-root "\\snake\\app.fnl")))
      (assert-success (resolve [(.. "fs:" entry)] {})
                      {:source-kind :file
                       :entry-path entry
                       :lua-root lua-root
                       :module-name "snake/app"}))))

(fn test-windows-standalone-file-module-name []
  (with-temp-dir "windows-standalone"
    (fn [root]
      (local entry (write-file (.. root "\\nested\\widget.fnl")))
      (assert-success (resolve [(.. "fs:" entry)] {})
                      {:source-kind :file
                       :entry-path entry
                       :module-name "widget"}))))

(fn test-file-under-nested-assets-lua-uses-nearest-root []
  (with-temp-dir "assets-nested-root"
    (fn [root]
      (local outer-root (fs.join-path root "assets" "lua"))
      (local inner-root (fs.join-path outer-root "vendor" "app" "assets" "lua"))
      (local entry (write-file (fs.join-path inner-root "main.fnl")))
      (assert-success (resolve [(.. "fs:" entry)] {})
                      {:source-kind :file
                       :lua-root inner-root
                       :module-name "main"
                       :entry-path entry}))))

(fn test-standalone-file []
  (with-temp-dir "standalone"
    (fn [root]
      (local entry (write-file (fs.join-path root "widget.fnl")))
      (assert-success (resolve [(.. "fs:" entry)] {})
                      {:source-kind :file
                       :lua-root root
                       :module-name "widget"
                       :entry-path entry}))))

(fn assert-directory-entry [entry-relative expected-lua-root expected-module-name]
  (with-temp-dir (.. "dir-entry-" (string.gsub entry-relative "/" "-"))
    (fn [root]
      (local entry (write-file (fs.join-path root entry-relative)))
      (local result (resolve [(.. "fs:" root)] {}))
      (assert-success result
                      {:source-kind :directory
                       :selection-key (.. "fs:" root)
                       :path root
                       :entry-path entry
                       :lua-root (expected-lua-root root)
                       :module-name expected-module-name}))))

(fn test-directory-assets-lua-main []
  (assert-directory-entry "assets/lua/main.fnl"
                          (fn [root] (fs.join-path root "assets" "lua"))
                          "main"))

(fn test-directory-main []
  (assert-directory-entry "main.fnl" (fn [root] root) "main"))

(fn test-directory-main-with-trailing-slash []
  (with-temp-dir "dir-main-trailing-slash"
    (fn [root]
      (write-file (fs.join-path root "main.fnl"))
      (local selected-path (.. root "/"))
      (local result (resolve [(.. "fs:" selected-path)] {}))
      (assert-success result
                      {:source-kind :directory
                       :selection-key (.. "fs:" selected-path)
                       :path selected-path
                       :module-name "main"}))))

(fn test-directory-init []
  (assert-directory-entry "init.fnl" (fn [root] root) "init"))

(fn test-directory-no-entry []
  (with-temp-dir "dir-none"
    (fn [root]
      (assert-failure (resolve [(.. "fs:" root)] {}) :no-directory-entry))))

(fn test-directory-ambiguous-entry []
  (with-temp-dir "dir-ambiguous"
    (fn [root]
      (write-file (fs.join-path root "assets" "lua" "main.fnl"))
      (write-file (fs.join-path root "main.fnl"))
      (assert-failure (resolve [(.. "fs:" root)] {}) :ambiguous-directory))))

(fn test-visible-node-path-overrides-key-path []
  (with-temp-dir "visible-path"
    (fn [root]
      (local entry (write-file (fs.join-path root "visible.fnl")))
      (local key "fs:/does/not/exist.fnl")
      (assert-success (resolve [key] {key {:key key :path entry}})
                      {:path entry
                       :entry-path entry
                       :module-name "visible"}))))

(add-test "no selection returns no-selection" test-no-selection)
(add-test "multiple selections return multiple-selection" test-multiple-selection)
(add-test "non-fs selection returns unsupported-selection" test-unsupported-selection)
(add-test "missing filesystem path returns missing-path" test-missing-filesystem-path)
(add-test "unsupported file extension returns unsupported-file" test-unsupported-file-extension)
(add-test "file under assets lua main resolves module" test-file-under-assets-lua-main)
(add-test "file under assets lua nested resolves slash module" test-file-under_assets_lua_nested_module)
(add-test "windows file under assets lua main resolves module" test-windows-file-under-assets-lua-main)
(add-test "windows file under assets lua nested resolves slash module" test-windows-file-under-assets-lua-nested-module)
(add-test "windows standalone file resolves basename module" test-windows-standalone-file-module-name)
(add-test "file under nested assets lua uses nearest root" test-file-under-nested-assets-lua-uses-nearest-root)
(add-test "standalone file resolves from parent" test-standalone-file)
(add-test "directory assets lua main resolves" test-directory-assets-lua-main)
(add-test "directory main resolves" test-directory-main)
(add-test "directory main with trailing slash resolves" test-directory-main-with-trailing-slash)
(add-test "directory init resolves" test-directory-init)
(add-test "directory without entry fails" test-directory-no-entry)
(add-test "directory with multiple entries is ambiguous" test-directory-ambiguous-entry)
(add-test "visible node path overrides key path" test-visible-node-path-overrides-key-path)

(fn main []
  (Runner.run-tests {:name "app-host-source-resolver" :tests tests}))

{:name "app-host-source-resolver"
 :tests tests
 :main main}
