(local Runner (require :tests/runner))
(local fs (require :fs))
(local fennel (require :fennel))
(local HostedSourceLauncher (require :app-host.hosted-source-launcher))

(local tests [])
(local temp-root (fs.join-path "/tmp/space/tests" "hosted-source-launcher"))
(var temp-counter 0)

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn assert-equals [actual expected message]
  (assert (= actual expected)
          (.. (or message "values should match")
              ": expected " (tostring expected)
              ", got " (tostring actual))))

(fn assert-contains [value needle message]
  (assert (and (= (type value) :string)
               (string.find value needle 1 true))
          (.. (or message "string should contain needle")
              ": expected " (tostring value)
              " to contain " (tostring needle))))

(fn write-file [path content]
  (local parent (fs.parent path))
  (when parent
    (fs.create-dirs parent))
  (fs.write-file path content)
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

(fn source-for [root module-name]
  {:lua-root root
   :module-name module-name
   :label "Snake App"})

(fn clear-module [module-name]
  (set (. package.loaded module-name) nil))

(fn with-package-loaded [module-name value f]
  (local previous (. package.loaded module-name))
  (set (. package.loaded module-name) value)
  (local (ok result) (pcall f))
  (set (. package.loaded module-name) previous)
  (if ok
      result
      (error result)))

(fn test-make-module-loads-source-and-restores-state []
  (with-temp-dir "success"
    (fn [root]
      (local module-name "snake-app")
      (write-file (fs.join-path root "snake-app.fnl")
                  "(local fennel (require :fennel))\n{:create (fn [host]\n  {:host host\n   :path-during-create fennel.path\n   :suppress-during-create app.__suppress-main-run?})}\n")
      (clear-module module-name)
      (local previous-path fennel.path)
      (local previous-require _G.require)
      (local previous-suppress app.__suppress-main-run?)
      (set app.__suppress-main-run? :before)
      (local wrapper (HostedSourceLauncher.make-module (source-for root module-name)))
      (local host {:id :host})
      (local result (wrapper:create host))
      (assert-equals result.host host "create should receive host")
      (assert-contains result.path-during-create (.. root "/?.fnl") "source root should be prepended")
      (assert-equals result.suppress-during-create true "main run should be suppressed while loading hosted source")
      (assert-equals fennel.path previous-path "fennel.path should be restored after success")
      (assert-equals _G.require previous-require "require should be restored after success")
      (assert-equals app.__suppress-main-run? :before "suppression state should be restored after success")
      (set app.__suppress-main-run? previous-suppress)
      (clear-module module-name))))

(fn test-make-module-rejects-missing-create-and-restores-state []
  (with-temp-dir "missing-create"
    (fn [root]
      (local module-name "missing-create")
      (write-file (fs.join-path root "missing-create.fnl") "{:not-create true}\n")
      (clear-module module-name)
      (local previous-path fennel.path)
      (local previous-require _G.require)
      (local previous-suppress app.__suppress-main-run?)
      (set app.__suppress-main-run? :before-error)
      (local wrapper (HostedSourceLauncher.make-module (source-for root module-name)))
      (local (ok err) (pcall #(wrapper:create {:id :host})))
      (assert (not ok) "missing create should fail")
      (assert-contains (tostring err) "create" "error should mention missing create")
      (assert-equals fennel.path previous-path "fennel.path should be restored after error")
      (assert-equals _G.require previous-require "require should be restored after error")
      (assert-equals app.__suppress-main-run? :before-error "suppression state should be restored after error")
      (set app.__suppress-main-run? previous-suppress)
      (clear-module module-name))))

(fn test-make-module-restores_state_when_create_errors []
  (with-temp-dir "create-error"
    (fn [root]
      (local module-name "create-error")
      (write-file (fs.join-path root "create-error.fnl")
                  "{:create (fn [_host]\n  (set _G.require (fn [_name] (error :mutated-require)))\n  (error :boom))}\n")
      (clear-module module-name)
      (local previous-path fennel.path)
      (local previous-require _G.require)
      (local previous-suppress app.__suppress-main-run?)
      (set app.__suppress-main-run? :before-boom)
      (local wrapper (HostedSourceLauncher.make-module (source-for root module-name)))
      (local (ok err) (pcall #(wrapper:create {:id :host})))
      (assert (not ok) "create error should propagate")
      (assert-contains (tostring err) "boom" "error should preserve create failure")
      (assert-equals fennel.path previous-path "fennel.path should be restored after create error")
      (assert-equals _G.require previous-require "require should be restored after create error")
      (assert-equals app.__suppress-main-run? :before-boom "suppression state should be restored after create error")
      (set app.__suppress-main-run? previous-suppress)
      (clear-module module-name))))

(fn create-cached-main [_host]
  {:source :cached})

(fn assert-selected-main-loaded [root]
  (write-file (fs.join-path root "main.fnl")
              "{:create (fn [host]\n  {:source :selected :host host})}\n")
  (local cached-main {:create create-cached-main})
  (fn assert-loads-selected-main []
    (local wrapper (HostedSourceLauncher.make-module (source-for root "main")))
    (local host {:id :host})
    (local result (wrapper:create host))
    (assert-equals result.source :selected "selected source module should bypass cached main")
    (assert-equals result.host host "selected source create should receive host")
    (assert-equals (. package.loaded "main") cached-main "cached main should be restored after launch"))
  (with-package-loaded "main" cached-main assert-loads-selected-main))

(fn test-make-module-loads-selected-main-when-main-cached []
  (with-temp-dir "cached-main" assert-selected-main-loaded))

(fn test-open-source-opens_workspace_panel_with_wrapper_and_label []
  (local calls [])
  (local fake-panel {:open (fn [opts]
                             (table.insert calls opts)
                             {:session true :opts opts})})
  (local shell {:id :app})
  (local runtime {:id :runtime})
  (local source {:lua-root "/tmp/example"
                 :module-name "main"
                 :label "Example App"})
  (local session (HostedSourceLauncher.open-source source {:app shell
                                                           :runtime runtime
                                                           :workspace-panel fake-panel}))
  (assert-equals session.session true "open-source should return workspace session")
  (assert-equals (# calls) 1 "workspace panel should be opened once")
  (local opened (. calls 1))
  (assert-equals opened.app shell "app should come from opts")
  (assert-equals opened.runtime runtime "runtime should come from opts")
  (assert-equals (type opened.module.create) :function "module wrapper should be passed to workspace panel")
  (assert-equals opened.label "Example App" "label should derive from source label")
  (assert-equals opened.title "Example App" "title should derive from source label"))

(add-test "make-module loads source create and restores state" test-make-module-loads-source-and-restores-state)
(add-test "make-module rejects missing create and restores state" test-make-module-rejects-missing-create-and-restores-state)
(add-test "make-module restores state when create errors" test-make-module-restores_state_when_create_errors)
(add-test "make-module loads selected main when main is cached" test-make-module-loads-selected-main-when-main-cached)
(add-test "open-source opens workspace panel with wrapper and label" test-open-source-opens_workspace_panel_with_wrapper_and_label)

(fn main []
  (Runner.run-tests {:name "app-host-hosted-source-launcher" :tests tests}))

{:name "app-host-hosted-source-launcher"
 :tests tests
 :main main}
