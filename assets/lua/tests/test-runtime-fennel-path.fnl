(local Runner (require :tests/runner))

(local tests [])

(fn directory-module-require-loads-built-in-graph-extensions []
  (local Builtins (require :graph/extensions/builtins))
  (assert (= (type Builtins) "table") "built-in graph extensions module should return a table")
  (assert (= (type Builtins.descriptors) "function") "built-in graph extensions should expose descriptors")
  (assert (= (type Builtins.register!) "function") "built-in graph extensions should expose register!"))

(fn macro-import-module-loads-with-runtime-macro-path []
  (local FlexModule (require :flex))
  (assert (= (type FlexModule) "table") "flex module should return a table")
  (assert (= (type FlexModule.Flex) "function") "flex module should expose Flex")
  (assert (= (type FlexModule.FlexChild) "function") "flex module should expose FlexChild"))

(table.insert tests {:name "directory-module-require-loads-built-in-graph-extensions"
                     :fn directory-module-require-loads-built-in-graph-extensions})
(table.insert tests {:name "macro-import-module-loads-with-runtime-macro-path"
                     :fn macro-import-module-loads-with-runtime-macro-path})

(fn main []
  (Runner.run-tests {:name "runtime-fennel-path" :tests tests}))

{:main main}
