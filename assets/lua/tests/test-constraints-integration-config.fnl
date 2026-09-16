;; Integration configuration checks for the constraints gate.

(local tests [])
(local fs (require :fs))

(fn repo-root-or-nil []
  (local has-cmake (fs.exists "CMakeLists.txt"))
  (local has-cmake-parent (fs.exists "../CMakeLists.txt"))
  (if has-cmake
      "."
      (if has-cmake-parent
          ".."
          nil)))

(fn read-repo-file [path]
  (local root (repo-root-or-nil))
  (when (not root)
    (error "read-repo-file called without repository checkout"))
  (fs.read-file (.. root "/" path)))

(fn assert-contains [contents needle message]
  (assert (string.find contents needle 1 true)
          (.. message " (missing: " needle ")")))

(fn make-target-recipe [makefile target]
  (local header (.. target ":"))
  (local header-length (string.len header))
  (local (start) (string.find makefile (.. "\n" header) 1 true))
  (local target-start (if start (+ start 1) 1))
  (assert (= (string.sub makefile target-start (+ target-start header-length -1)) header)
          (.. "Makefile should contain a " target " target"))
  (local (next-target) (string.find makefile "\n%S[^\n]-:" (+ target-start header-length)))
  (if next-target
      (string.sub makefile target-start (- next-target 1))
      (string.sub makefile target-start)))

(fn constraints-target-recipe [makefile]
  (make-target-recipe makefile "constraints"))

(fn test-constraints-target-recipe-is-isolated []
  (local makefile (table.concat [".PHONY: constraints test"
                                 "constraints: fennel-check"
                                 "\t./build/space -m constraints.runner:main -- --target repo"
                                 ""
                                 "test: constraints"
                                 "\tSPACE_DISABLE_AUDIO=1 FENNEL_PATH=assets/lua/?.fnl ./build/space -m tests.fast:main"]
                                "\n"))
  (local recipe (constraints-target-recipe makefile))
  (assert (not (string.find recipe "FENNEL_PATH" 1 true))
          "constraints recipe slice should not include later make targets"))

(fn test-makefile-wires-constraints-target []
  (local root (repo-root-or-nil))
  (when (not root)
    (print "Skipping constraints integration config test: repository checkout not available")
    (lua "return true"))
  (local makefile (read-repo-file "Makefile"))
  (local fennel-recipe (make-target-recipe makefile "fennel-check"))
  (local recipe (constraints-target-recipe makefile))
  (assert (string.find makefile "^.PHONY:.*constraints")
          "Makefile .PHONY declaration should include constraints")
  (assert-contains makefile "SPACE_TEST_ENV = SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(CURDIR)/assets"
                   "Makefile should declare shared test environment variables")
  (assert-contains makefile "SPACE_FENNEL_ENV = FENNEL_PATH=$(CURDIR)/assets/lua/?.fnl\\;$(CURDIR)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(CURDIR)/assets/lua/?.fnl\\;$(CURDIR)/assets/lua/?/init.fnl"
                   "Makefile should declare shared Fennel environment variables")
  (assert-contains makefile "SPACE_RUNTIME_ENV = $(SPACE_TEST_ENV) $(SPACE_FENNEL_ENV)"
                   "Makefile should compose shared runtime environment variables")
  (assert-contains makefile "VALIDATION_OUTPUT = $(if $(VERBOSE),json,summary)"
                   "Makefile should select concise validation output by default and JSON for verbose runs")
  (assert-contains fennel-recipe "fennel-check: build"
                   "fennel-check should depend on build")
  (assert-contains fennel-recipe "$(SPACE_RUNTIME_ENV) ./build/space -m tools.fennel-check:main -- --output $(VALIDATION_OUTPUT) --target repo"
                    "fennel-check target should run the repo Fennel compile gate with the selected validation output mode")
  (assert-contains makefile "test: constraints"
                   "make test should depend on constraints")
  (assert-contains recipe "constraints: fennel-check"
                   "constraints should depend on the Fennel compile gate")
  (assert-contains recipe "$(SPACE_RUNTIME_ENV) ./build/space -m constraints.runner:main -- --output $(VALIDATION_OUTPUT) --target repo"
                    "constraints target should run the repo constraints command with the selected validation output mode"))

(fn ctest-block-has-fixture? [cmake test-name]
  (local (start) (string.find cmake test-name 1 true))
  (assert start (.. "CMake should configure " test-name))
  (local (fixture-pos) (string.find cmake "FIXTURES_REQUIRED space_constraints" start true))
  (local (next-test-pos) (string.find cmake "add_test(NAME" (+ start 1) true))
  (if next-test-pos
      (and fixture-pos (< fixture-pos next-test-pos))
      fixture-pos))

(fn ctest-test-block [cmake test-name]
  (local (start) (string.find cmake test-name 1 true))
  (assert start (.. "CMake should configure " test-name))
  (local (next-test-pos) (string.find cmake "add_test(NAME" (+ start 1) true))
  (if next-test-pos
      (string.sub cmake start (- next-test-pos 1))
      (string.sub cmake start)))

(fn test-cmake-wires-constraints-fixture []
  (local root (repo-root-or-nil))
  (when (not root)
    (print "Skipping constraints integration config test: repository checkout not available")
    (lua "return true"))
  (local cmake (read-repo-file "CMakeLists.txt"))
  (assert-contains cmake "add_test(NAME ${PROJECT_NAME}_constraints"
                    "CMake should declare the constraints test")
  (assert-contains cmake "set(SPACE_TEST_COMMAND_TARGET ${PROJECT_NAME})"
                    "CMake should default Fennel CTest commands to the main executable target")
  (assert-contains cmake "set(SPACE_TEST_COMMAND_TARGET space-cli)"
                    "CMake should route Windows Fennel CTest commands through the console executable target")
  (assert-contains cmake "COMMAND $<TARGET_FILE:${SPACE_TEST_COMMAND_TARGET}> -m constraints.runner:main -- --output summary --target repo"
                    "constraints CTest should run the repo constraints command in concise summary mode through the selected executable target")
  (assert-contains cmake "FIXTURES_SETUP space_constraints"
                   "constraints CTest should set up its fixture")
  (assert (ctest-block-has-fixture? cmake "${PROJECT_NAME}_fnl_tests")
          "space_fnl_tests should require the constraints fixture")
  (assert (ctest-block-has-fixture? cmake "${PROJECT_NAME}_fnl_tests_integration")
          "space_fnl_tests_integration should require the constraints fixture"))

(fn test-cmake-preserves-fennel-test-display-backend []
  (local root (repo-root-or-nil))
  (when (not root)
    (print "Skipping constraints integration config test: repository checkout not available")
    (lua "return true"))
  (local cmake (read-repo-file "CMakeLists.txt"))
  (local fast-block (ctest-test-block cmake "${PROJECT_NAME}_fnl_tests"))
  (local integration-block (ctest-test-block cmake "${PROJECT_NAME}_fnl_tests_integration"))
  (assert (not (string.find fast-block "SDL_VIDEODRIVER=dummy" 1 true))
          "space_fnl_tests should not force SDL_VIDEODRIVER=dummy")
  (assert (not (string.find integration-block "SDL_VIDEODRIVER=dummy" 1 true))
          "space_fnl_tests_integration should not force SDL_VIDEODRIVER=dummy"))

(fn test-repo-root-detection-uses-cmake-not-makefile []
  ;; repo-root-or-nil must base detection on CMakeLists.txt only,
  ;; not on a generated ../Makefile that may exist in artifact-only layouts.
  (local root (repo-root-or-nil))
  (when root
    (assert (fs.exists (.. root "/CMakeLists.txt"))
            (.. "repo-root-or-nil returned " root " but " root "/CMakeLists.txt does not exist"))))

(table.insert tests {:name "repo-root detection uses CMakeLists.txt not Makefile"
                     :fn test-repo-root-detection-uses-cmake-not-makefile})
(table.insert tests {:name "Makefile wires blocking constraints target"
                     :fn test-makefile-wires-constraints-target})
(table.insert tests {:name "Makefile constraints target recipe is isolated"
                     :fn test-constraints-target-recipe-is-isolated})
(table.insert tests {:name "CMake wires constraints fixture"
                     :fn test-cmake-wires-constraints-fixture})
(table.insert tests {:name "CMake preserves Fennel test display backend"
                     :fn test-cmake-preserves-fennel-test-display-backend})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-integration-config"
                       :tests tests})))

{:name "constraints-integration-config"
 :tests tests
 :main main}
