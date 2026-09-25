(local Runner (require :tests/runner))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn test-main-exports-hostable-contract []
  (local SnakeMain (require :main))
  (assert (= SnakeMain.metadata.id "examples.snake") "main should export Snake metadata")
  (assert (= SnakeMain.metadata.title "Snake") "main should export Snake title")
  (assert (= SnakeMain.metadata.host-api 1) "main should export host API version")
  (assert (= (type SnakeMain.create) :function) "main should export create(host)")
  (assert (= (type SnakeMain.main) :function) "main should export standalone main"))

(fn test-require-main-does-not-start-engine []
  (global app (or app {}))
  (local previous-engine app.engine)
  (local previous-renderers app.renderers)
  (local sentinel-engine {:id :sentinel-engine})
  (local sentinel-renderers {:id :sentinel-renderers})
  (set app.engine sentinel-engine)
  (set app.renderers sentinel-renderers)
  (local (ok result) (pcall require :main))
  (local engine-after-require app.engine)
  (local renderers-after-require app.renderers)
  (set app.engine previous-engine)
  (set app.renderers previous-renderers)
  (assert ok (.. "requiring main should be safe, got: " (tostring result)))
  (assert (= engine-after-require sentinel-engine) "require main should not replace or start app.engine")
  (assert (= renderers-after-require sentinel-renderers) "require main should not replace app.renderers"))

(add-test "require main does not start engine" test-require-main-does-not-start-engine)
(add-test "main exports hostable contract" test-main-exports-hostable-contract)

(fn main []
  (Runner.run-tests {:name "snake-standalone-entry" :tests tests}))

{:main main :tests tests}
