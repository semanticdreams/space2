(local fennel (require :fennel))

(fn launcher-error [message]
  (error (.. "[app-host.hosted-source-launcher] " message)))

(fn require-string-field [source field-name]
  (local value (. source field-name))
  (when (not (= (type value) :string))
    (launcher-error (.. "source requires string " (tostring field-name))))
  (when (= value "")
    (launcher-error (.. "source requires non-empty " (tostring field-name))))
  value)

(fn assert-source [source]
  (when (not (= (type source) :table))
    (launcher-error "source must be a table"))
  {:lua-root (require-string-field source :lua-root)
   :module-name (require-string-field source :module-name)
   :label (if (= (type source.label) :string)
              source.label
              source.module-name)})

(fn module-paths [lua-root]
  (.. lua-root "/?.fnl;" lua-root "/?/init.fnl"))

(fn path-under? [path root]
  (and (= (type path) :string)
       (= (type root) :string)
       (do
         (local path-len (# path))
         (local root-len (# root))
         (and (>= path-len root-len)
              (= (string.sub path 1 root-len) root)
              (if (= path-len root-len)
                  true
                  (= (string.sub path (+ root-len 1) (+ root-len 1)) "/"))))))

(fn source-owned-module? [source module-name]
  (local (ok path) (pcall fennel.search-module module-name))
  (and ok (path-under? path source.lua-root)))

(fn save-and-clear-loaded! [saved-loaded name]
  (when (= (. saved-loaded name) nil)
    (local existing (. package.loaded name))
    (tset saved-loaded name {:present? (not (= existing nil))
                             :value existing})
    (tset package.loaded name nil)))

(fn restore-loaded! [saved-loaded]
  (each [name saved (pairs saved-loaded)]
    (if saved.present?
        (tset package.loaded name saved.value)
        (tset package.loaded name nil))))

(fn with-source-loader-state [source f]
  (local previous-fennel-path fennel.path)
  (local previous-require _G.require)
  (local previous-suppress (and app app.__suppress-main-run?))
  (local saved-loaded {})
  (set fennel.path (.. (module-paths source.lua-root) ";" fennel.path))
  (set _G.require
       (fn [name]
         (when (source-owned-module? source name)
           (save-and-clear-loaded! saved-loaded name))
         (previous-require name)))
  (when app
    (set app.__suppress-main-run? true))
  (local (ok result) (pcall f))
  (restore-loaded! saved-loaded)
  (set _G.require previous-require)
  (set fennel.path previous-fennel-path)
  (when app
    (set app.__suppress-main-run? previous-suppress))
  (if ok
      result
      (error result)))

(fn load-source-module [source host]
  (local module (require source.module-name))
  (when (not (= (type module) :table))
    (launcher-error (.. "hosted source module " source.module-name " must return a table")))
  (when (not (= (type module.create) :function))
    (launcher-error (.. "hosted source module " source.module-name " requires create(host)")))
  (module.create host))

(fn make-module [source]
  (local checked-source (assert-source source))
  {:create (fn [_self host]
             (with-source-loader-state checked-source
               #(load-source-module checked-source host)))})

(fn resolve-workspace-panel [options]
  (local panel (if options.workspace-panel
                   options.workspace-panel
                   (require :app-host.workspace-panel)))
  (when (not (= (type panel.open) :function))
    (launcher-error "open-source requires workspace-panel.open"))
  panel)

(fn resolve-app [options]
  (local shell (if options.app options.app app))
  (when (not shell)
    (launcher-error "open-source requires :app or global app"))
  shell)

(fn resolve-runtime [options]
  (local runtime (if options.runtime
                     options.runtime
                     (and app app.active-world-runtime)))
  (when (not runtime)
    (launcher-error "open-source requires :runtime or app.active-world-runtime"))
  runtime)

(fn open-source [source opts]
  (local options (if opts opts {}))
  (local checked-source (assert-source source))
  (local shell (resolve-app options))
  (local runtime (resolve-runtime options))
  (local panel (resolve-workspace-panel options))
  (local label checked-source.label)
  (panel.open {:app shell
               :runtime runtime
               :module (make-module checked-source)
               :label label
               :title label}))

{:make-module make-module
 :open-source open-source}
