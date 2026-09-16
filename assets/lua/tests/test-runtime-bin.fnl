(local tests [])
(local RuntimeBin (require :tests.runtime-bin))

(fn string-contains? [haystack needle]
  (not= nil (string.find (tostring haystack) needle 1 true)))

(fn contains? [items needle]
  (var found false)
  (each [_ item (ipairs items)]
    (when (= item needle)
      (set found true)))
  found)

(fn fake-fs [existing]
  {:cwd (fn [] ".")
   :join-path (fn [left right] (.. left "/" right))
   :exists (fn [path]
             (contains? existing path))})

(fn fake-getenv [env]
  (fn [name]
    (. env name)))

(fn assert-error-contains [needle f]
  (local (ok err) (pcall f))
  (assert (not ok) "expected operation to fail")
  (assert (string-contains? err needle)
          (.. "expected error to contain " needle ", got " (tostring err))))

(fn explicit-space-bin-wins []
  (local resolved
    (RuntimeBin.resolve {:fs (fake-fs ["/custom/space" "build/space"])
                         :getenv (fake-getenv {:SPACE_BIN "/custom/space"})}))
  (assert (= resolved "/custom/space") "SPACE_BIN should resolve before local candidates"))

(fn explicit-missing-space-bin-errors []
  (assert-error-contains
    "SPACE_BIN points to missing space binary"
    (fn []
      (RuntimeBin.resolve {:fs (fake-fs [])
                           :getenv (fake-getenv {:SPACE_BIN "/missing/space"})}))))

(fn explicit-empty-space-bin-errors []
  (assert-error-contains
    "SPACE_BIN points to missing space binary"
    (fn []
      (RuntimeBin.resolve {:fs (fake-fs ["build/space"])
                           :getenv (fake-getenv {:SPACE_BIN ""})}))))

(fn packaged-windows-candidate-resolves []
  (local resolved
    (RuntimeBin.resolve {:fs (fake-fs ["build/dist/windows/space-cli.exe"])
                         :getenv (fake-getenv {})}))
  (assert (= resolved "build/dist/windows/space-cli.exe") "packaged Windows CLI candidate should resolve"))

(fn no-candidates-errors []
  (assert-error-contains
    "could not locate space binary"
    (fn []
      (RuntimeBin.resolve {:fs (fake-fs [])
                           :getenv (fake-getenv {})}))))

(table.insert tests {:name "explicit SPACE_BIN wins" :fn explicit-space-bin-wins})
(table.insert tests {:name "explicit missing SPACE_BIN errors" :fn explicit-missing-space-bin-errors})
(table.insert tests {:name "explicit empty SPACE_BIN errors" :fn explicit-empty-space-bin-errors})
(table.insert tests {:name "packaged Windows candidate resolves" :fn packaged-windows-candidate-resolves})
(table.insert tests {:name "no candidates errors" :fn no-candidates-errors})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "runtime-bin"
                       :tests tests})))

{:name "runtime-bin"
 :tests tests
 :main main}
