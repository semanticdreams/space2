(local tests [])
(local fs (require :fs))

(fn source-contains? [source needle]
  (not= nil (string.find source needle 1 true)))

(fn builtin-graph-node-declarations-use-uniform-size []
  (assert (and app app.engine app.engine.get-asset-path)
          "built-in graph node size audit requires app.engine.get-asset-path")
  (assert (and fs fs.list-dir fs.read-file fs.join-path)
          "built-in graph node size audit requires fs bindings")
  (local nodes-dir (app.engine.get-asset-path "lua/graph/nodes"))
  (local mismatches [])
  (each [_ entry (ipairs (fs.list-dir nodes-dir false))]
    (when (and entry.is-file (string.match entry.name "%.fnl$"))
      (local path (fs.join-path nodes-dir entry.name))
      (local source (fs.read-file path))
      (when (source-contains? source "GraphNode")
        (each [size-text (string.gmatch source ":size%s+([0-9]+%.?[0-9]*)")]
          (when (not= (tonumber size-text) 8.0)
            (table.insert mismatches (.. entry.name " uses :size " size-text)))))))
  (assert (= (length mismatches) 0)
          (.. "built-in graph node declarations should use uniform :size 8.0; mismatches: "
              (table.concat mismatches ", "))))

(table.insert tests {:name "built-in graph node declarations use uniform size"
                     :fn builtin-graph-node-declarations-use-uniform-size})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "builtin-graph-node-sizes"
                       :tests tests})))

{:name "builtin-graph-node-sizes"
 :tests tests
 :main main}
