(fn log-line [msg]
  (print msg)
  (io.flush))

(fn protected-call [traceback f]
  (if traceback
      (xpcall f (fn [err]
                  (traceback err 2)))
      (pcall f)))

(fn copy-array [items]
  (local out [])
  (each [_ item (ipairs items)]
    (table.insert out item))
  out)

(fn env-enabled? [name]
  (= (os.getenv name) "1"))

(fn select-test-timeout-seconds [raw case-budget]
  (when (not (= case-budget nil))
    (assert (and (= (type case-budget) :number) (> case-budget 0) (< case-budget math.huge))
            "test timeout-seconds must be a positive finite number"))
  (if (and raw (> (# raw) 0))
      (do
        (local parsed (tonumber raw))
        (assert parsed "SPACE_TEST_CASE_TIMEOUT_SECONDS must be numeric")
        (assert (>= parsed 0) "SPACE_TEST_CASE_TIMEOUT_SECONDS must be non-negative")
        parsed)
      (if (= case-budget nil) 120 case-budget)))

(fn restore-debug-hook! [debug-lib old-hook old-mask old-count]
  (if old-hook
      (debug-lib.sethook old-hook old-mask old-count)
      (debug-lib.sethook nil "" 0)))

(fn make-now-ms []
  (local (ok sysinfo) (pcall (fn []
                               (require :sysinfo))))
  (if (and ok sysinfo sysinfo.now-ms)
      sysinfo.now-ms
      (fn [] (* (os.clock) 1000))))

(fn protected-call-with-timeout [traceback test timeout-seconds clock]
  (local debug-lib _G.debug)
  (if (or (= timeout-seconds 0)
          (not debug-lib)
          (not debug-lib.sethook)
          (not debug-lib.gethook))
      (protected-call traceback test.fn)
      (do
        (local now-ms (if clock clock (make-now-ms)))
        (local started-at (now-ms))
        (local timeout-ms (* timeout-seconds 1000))
        (var timed-out? false)
        (var timeout-message nil)
        (local (old-hook old-mask old-count) (debug-lib.gethook))
        (fn timeout-hook []
          (when (>= (- (now-ms) started-at) timeout-ms)
            (set timed-out? true)
            (set timeout-message (.. "test timed out after " timeout-seconds "s: " test.name))
            (error timeout-message 2)))
        (debug-lib.sethook timeout-hook "" 10000)
        (local (ok err) (protected-call traceback test.fn))
        (restore-debug-hook! debug-lib old-hook old-mask old-count)
        (if timed-out?
             (values false timeout-message)
             (values ok err)))))

(fn verbose-stage [stage outcome]
  (when (os.getenv "TEST_VERBOSE")
    (log-line (.. stage " " outcome))))

(fn run-case [test timeout-seconds traceback now-ms]
  (select-test-timeout-seconds nil test.timeout-seconds)
  (assert (or (= test.teardown nil) (= (type test.teardown) :function))
          "test teardown must be a function")
  (local (ok result) (protected-call-with-timeout traceback test timeout-seconds now-ms))
  (local teardown-errors [])
  (var cleanup-ok true)
  (var cleanup-result nil)
  (when test.teardown
    (local stage (.. "[TEARDOWN] " test.name))
    (verbose-stage stage "attempt")
    (set (cleanup-ok cleanup-result) (protected-call traceback test.teardown))
    (verbose-stage stage (if cleanup-ok "returned" "failed"))
    (when (not cleanup-ok)
      (table.insert teardown-errors cleanup-result)))
  (values (and ok cleanup-ok) (if ok (if cleanup-ok result cleanup-result) result) teardown-errors))

(fn with-owned-engine [owned-engine body traceback]
  (local (ok result) (protected-call traceback body))
  (var shutdown-attempted? false)
  (fn shutdown-owned []
    (assert owned-engine "test runner requires its captured owned engine")
    (if (or shutdown-attempted? (owned-engine:is-shutdown))
        (verbose-stage "[SUITE-ENGINE]" "skip-already-attempted")
        (not (owned-engine:is-started))
        (verbose-stage "[SUITE-ENGINE]" "skip-unstarted")
        (do
          ;; Native is-shutdown is an ATTEMPT flag, not a completion receipt.
          (set shutdown-attempted? true)
          (verbose-stage "[SUITE-ENGINE]" "shutdown attempt")
          (owned-engine:shutdown)
          (verbose-stage "[SUITE-ENGINE]" "shutdown returned"))))
  (local (cleanup-ok cleanup-result) (protected-call traceback shutdown-owned))
  (when (not cleanup-ok)
    (log-line (.. "[SUITE-ENGINE] shutdown failed: " (tostring cleanup-result))))
  (if (not ok) (error result 0)
      (not cleanup-ok) (error cleanup-result 0)
      result))

(local windows-default-skip-modules
  {:tests.test-terminal true
   :tests.test-terminal-widget true
   :tests.test-terminal-renderer true
   :tests.test-terminal-scrollback true
   :tests.test-external-editor true
   :tests.test-ripgrep true
   :tests.test-ripgrep-view true
   :tests.test-flamegraph true
   :tests.test-llm-tools true})

(fn apply-module-overrides [modules]
  (var result (copy-array modules))
  (var platform-os nil)
  (local (sys-ok sysinfo-or-err) (pcall (fn []
                                          (require :sysinfo))))
  (when sys-ok
    (local platform (sysinfo-or-err.platform))
    (when (and platform platform.os)
      (set platform-os platform.os)))

  (when (= platform-os "windows")
    ;; Keep Windows/Wine test filtering explicit and centralized.
    ;; `lua "return true"` per-test skips remain valid for feature-level gates.
    (local excluded {})
    (each [module-name enabled? (pairs windows-default-skip-modules)]
      (when enabled?
        (set (. excluded module-name) true)))
    (local (terminal-ok _terminal) (pcall (fn []
                                            (require :terminal))))
    (when terminal-ok
      (set (. excluded :tests.test-terminal) nil)
      (set (. excluded :tests.test-terminal-widget) nil)
      (set (. excluded :tests.test-terminal-renderer) nil)
      (set (. excluded :tests.test-terminal-scrollback) nil))
    (local filtered [])
    (each [_ module-name (ipairs result)]
      (when (not (. excluded module-name))
        (table.insert filtered module-name)))
    (set result filtered))

  (when (env-enabled? "SPACE_MATRIX_TEST")
    (table.insert result :tests.test-matrix))
  (when (env-enabled? "SPACE_REALTIME_TEST")
    (table.insert result :tests.test-realtime-online))
  (when (env-enabled? "SKIP_KEYRING_TESTS")
    (local filtered [])
    (each [_ module-name (ipairs result)]
      (when (not (= module-name :tests.test-keyring))
        (table.insert filtered module-name)))
    (set result filtered))
  result) (fn ensure-test-interactions [Intersectables Clickables Hoverables] (when (not app.intersectables) (set app.intersectables (Intersectables))) (when (not app.clickables) (set app.clickables (Clickables {:intersectables app.intersectables}))) (when (not app.hoverables) (set app.hoverables (Hoverables {:intersectables app.intersectables}))) (assert app.clickables "test runner requires app.clickables") (assert app.hoverables "test runner requires app.hoverables"))

(fn setup-test-env [test-verbose]
  (global app {})
  (set app.testing true)
  (when test-verbose
    (log-line "[BOOT] loading bindings"))
  (when test-verbose
    (log-line "[BOOT] require :engine"))
  (local EngineModule (require :engine))
  (when test-verbose
    (log-line "[BOOT] require :intersectables"))
  (local Intersectables (require :intersectables))
  (when test-verbose
    (log-line "[BOOT] require :clickables"))
  (local Clickables (require :clickables))
  (when test-verbose
    (log-line "[BOOT] require :hoverables"))
  (local Hoverables (require :hoverables))
  (local Runtime (require :state-runtime))
  (when test-verbose
    (log-line "[BOOT] require :textures"))
  (local textures (require :textures))
  (when test-verbose
    (log-line "[BOOT] test runner"))

  (global reset-engine-events
    (fn []
      (assert (and app.engine app.engine.events) "app.engine.events missing in tests")
      (each [_ signal (pairs app.engine.events)]
        (signal:clear))
      (Runtime.reset)))

  ;; Ensure font textures and loaders are available during tests; do not fall back to stubs.
  (set app.disable_font_textures false)
  (local loaded {})
  (local stub
    (fn [name path]
      (local tex {:id (tonumber (tostring (string.byte name 1) 10))
                  :name name :path path
                  :ready true
                  :width 1
                  :height 1})
      (set tex.allocate
           (fn [_self width height _channels]
             (set tex.width width)
             (set tex.height height)
             (set tex.ready true)))
      (set tex.update-full
           (fn [_self _bytes]
             (set tex.ready true)))
      (tset tex "update-full" tex.update-full)
      (set tex.update-sub-rect
           (fn [_self _x _y _width _height _bytes]
             (set tex.ready true)))
      (tset tex "update-sub-rect" tex.update-sub-rect)
      (set (. loaded name) tex)
      tex))
  (set textures.load-texture stub)
  (set textures.load-texture-async stub)
  (set textures.load-texture-from-bytes
       (fn [name _bytes]
         (stub name "<bytes>")))
  (set textures.load-texture-from-bytes-async textures.load-texture-from-bytes)
  (set textures.load-texture-from-pixels
       (fn [name width height _channels _bytes]
         (local tex (stub name "<pixels>"))
         (set tex.width width)
         (set tex.height height)
         tex))
  (set textures.allocate-texture
       (fn [name width height channels]
         (local tex (stub name "<allocated>"))
         (tex:allocate width height channels)
         tex))
  (tset textures "allocate-texture" textures.allocate-texture)
  (set textures.get-texture
       (fn [name]
         (or (. loaded name)
             (stub name "<lazy>"))))
  (set textures.drop-texture
       (fn [name]
         (if (. loaded name)
             (do
               (set (. loaded name) nil)
               true)
             false)))
  (tset textures "drop-texture" textures.drop-texture)
  (when (not textures.load-cubemap)
    (local cube-stub (fn [_files] {:id 1 :ready true}))
    (set textures.load-cubemap cube-stub)
    (set textures.load-cubemap-async cube-stub))

  (do
    (local MockOpenGL (require :mock-opengl))
    (local global-mock (MockOpenGL))
    (global-mock:install))
  (require :gl)

  (set app.engine (EngineModule.Engine {:headless true}))

  (require :main)

  (app.engine:start)

  (ensure-test-interactions Intersectables Clickables Hoverables)






  ;; Reapply texture stubs in case bindings overwrote them.
  (when textures
    (set textures.load-texture
         (fn [name path]
           (stub name path)))
    (set textures.load-texture-async textures.load-texture)
    (set textures.load-texture-from-bytes
         (fn [name _bytes]
           (textures.load-texture name "<bytes>")))
    (set textures.load-texture-from-bytes-async textures.load-texture-from-bytes)
    (set textures.load-texture-from-pixels
         (fn [name width height _channels _bytes]
           (local tex (stub name "<pixels>"))
           (set tex.width width)
           (set tex.height height)
           tex))
    (set textures.allocate-texture
         (fn [name width height channels]
           (local tex (stub name "<allocated>"))
           (tex:allocate width height channels)
           tex))
    (tset textures "allocate-texture" textures.allocate-texture)
    (set textures.get-texture
         (fn [name]
           (or (. loaded name)
               (stub name "<lazy>"))))
    (set textures.drop-texture
         (fn [name]
           (if (. loaded name)
               (do
                 (set (. loaded name) nil)
                 true)
               false)))
    (tset textures "drop-texture" textures.drop-texture)
    (when (not textures.load-cubemap)
      (set textures.load-cubemap (fn [_files] {:id 1}))
      (set textures.load-cubemap-async textures.load-cubemap)))

  (when (not (and app.themes app.themes.get-active-theme))
    (set app.themes ((require :themes)))
    (app.themes.add-theme :dark (require :dark-theme))
    (app.themes.add-theme :light (require :light-theme))
    (app.themes.set-theme :dark))
  (when (not app.lights)
    (local {:LightSystem LightSystem} (require :light-system))
    (set app.lights (LightSystem {})))
  )

(fn execute-test-list [suite tests test-verbose traceback raw-timeout]
  (local registered-tests [])
  (each [_ test (ipairs tests)]
    (when (not (= (type test.name) "string"))
      (error "suite test missing name"))
    (when (not (= (type test.fn) "function"))
      (error (.. "suite test " test.name " missing fn")))
    (table.insert registered-tests test))

  (var failures 0)
  (each [_ test (ipairs registered-tests)]
    (when test-verbose
      (log-line (.. "[RUN] " test.name)))
    (local timeout-seconds (select-test-timeout-seconds raw-timeout test.timeout-seconds))
    (local (ok err teardown-errors) (run-case test timeout-seconds traceback))
    (each [_ cleanup-error (ipairs teardown-errors)]
      (log-line (.. "[TEARDOWN-ERROR] " test.name ": " (tostring cleanup-error))))
    (if ok
        (when test-verbose
          (log-line (.. "[PASS] " test.name)))
        (do
          (log-line (.. "[FAIL] " test.name))
          (log-line (tostring err))
          (set failures (+ failures 1)))))

  (values failures (# registered-tests)))

(fn execute-tests [suite test-verbose test-filter traceback raw-timeout]
  (local registered-tests [])
  (each [_ test (ipairs suite.tests)]
    (when (or (not test-filter)
              (string.find test.name test-filter 1 true))
      (table.insert registered-tests test)))

  (local (initial-failures initial-executed)
    (execute-test-list suite registered-tests test-verbose traceback raw-timeout))
  (var failures initial-failures)
  (local executed initial-executed)

  (when suite.teardown
    (local (_ok err) (protected-call traceback suite.teardown))
    (when (not _ok)
      (log-line (.. "[FAIL] teardown " (tostring err)))
      (set failures (+ failures 1))))

  (when (> failures 0)
    (error (.. failures " Lua test(s) failed")))

  (log-line (.. "Executed " executed " Lua tests"))

  suite)

(fn run-tests [suite]
  (assert (and suite suite.tests) "tests.runner: suite missing tests")
  (local test-verbose (os.getenv "TEST_VERBOSE"))
  (local test-filter (os.getenv "TEST_FILTER"))
  (local traceback (and _G.debug _G.debug.traceback))
  (local raw-timeout (os.getenv "SPACE_TEST_CASE_TIMEOUT_SECONDS"))
  (select-test-timeout-seconds raw-timeout nil)
  (setup-test-env test-verbose)
  (local owned-engine app.engine)
  (fn body [] (execute-tests suite test-verbose test-filter traceback raw-timeout))
  (with-owned-engine owned-engine body traceback))

(fn execute-modules [suite test-verbose test-filter traceback raw-timeout]
  (local print-timings (or (os.getenv "SPACE_TEST_TIMINGS")
                           (os.getenv "TEST_VERBOSE")))
  (local modules (apply-module-overrides suite.modules))
  (local now-ms (make-now-ms))
  (var failures 0)
  (var executed 0)
  (local suite-start (now-ms))

  (fn run-module-tests [module-name]
    (when test-verbose
      (log-line (.. "[LOAD] " module-name)))
    (local (ok result)
      (protected-call traceback (fn []
                                  (require module-name))))
    (when (not ok)
      (error (.. "Failed to load " module-name ":\n" (tostring result))))
    (do
      (when (not (= (type result) "table"))
        (error (.. module-name " must return a test suite")))
      (local tests (or (. result :tests) result))
      (local registered-tests [])
      (each [_ test (ipairs tests)]
        (when (not (= (type test.name) "string"))
          (error (.. module-name " test missing name")))
        (when (not (= (type test.fn) "function"))
          (error (.. module-name " test " test.name " missing fn")))
        (when (or (not test-filter)
                  (string.find test.name test-filter 1 true))
          (table.insert registered-tests test)))
      (local (module-failures module-executed)
        (execute-test-list {:name module-name} registered-tests test-verbose traceback raw-timeout))
      (set failures (+ failures module-failures))
      (set executed (+ executed module-executed))))

  (each [_ module-name (ipairs modules)]
    (local module-start (now-ms))
    (run-module-tests module-name)
    (when print-timings
      (log-line (.. "[TIME] " module-name " " (string.format "%.3f" (- (now-ms) module-start)) "ms"))))

  (when suite.teardown
    (local (_ok err) (protected-call traceback suite.teardown))
    (when (not _ok)
      (log-line (.. "[FAIL] teardown " (tostring err)))
      (set failures (+ failures 1))))

  (when print-timings
    (log-line (.. "[TIME] total suite " (string.format "%.3f" (- (now-ms) suite-start)) "ms")))

  (when (> failures 0)
    (error (.. failures " Lua test(s) failed")))

  (log-line (.. "Executed " executed " Lua tests"))

  suite)

(fn run-modules [suite]
  (assert (and suite suite.modules) "tests.runner: suite missing modules")
  (local test-verbose (os.getenv "TEST_VERBOSE"))
  (local test-filter (os.getenv "TEST_FILTER"))
  (local traceback (and _G.debug _G.debug.traceback))
  (local raw-timeout (os.getenv "SPACE_TEST_CASE_TIMEOUT_SECONDS"))
  (select-test-timeout-seconds raw-timeout nil)
  (setup-test-env test-verbose)
  (local owned-engine app.engine)
  (fn body [] (execute-modules suite test-verbose test-filter traceback raw-timeout))
  (with-owned-engine owned-engine body traceback))

(fn shutdown-test-env []
  "Shut down the test environment: drop the app and reset it to an empty table."
  (when (and app app.drop)
    (app.drop))
  (set app {}))

{:run-modules run-modules
 :select-test-timeout-seconds select-test-timeout-seconds
 :run-case run-case
 :with-owned-engine with-owned-engine
 :run-tests run-tests
 :setup-test-env setup-test-env
 :shutdown-test-env shutdown-test-env}
