(local glm (require :glm))
(local {:TableNode TableNode} (require :graph/nodes/table))

(local tests [])

(var userdata-tostring-calls 0)
(var table-tostring-calls 0)

(fn fail-userdata-tostring [_value]
  (set userdata-tostring-calls (+ userdata-tostring-calls 1))
  (error "userdata __tostring must not be called"))

(fn fail-table-tostring [_value]
  (set table-tostring-calls (+ table-tostring-calls 1))
  (error "table __tostring must not be called"))

(fn table-node-describes-userdata-without-tostring []
  (assert (and debug debug.getmetatable debug.setmetatable)
          "Table userdata regression requires debug metatable helpers")
  (local fixture (glm.vec3 1 2 3))
  (local original-mt (debug.getmetatable fixture))
  (set userdata-tostring-calls 0)
  (local replacement-mt {:__name "CrashyUserdata"
                         :__tostring fail-userdata-tostring})
  (debug.setmetatable fixture replacement-mt)
  (local node (TableNode {:table {:danger fixture}
                          :label "root"
                          :key "table:root"}))
  (local items (node:build-items))
  (assert (= userdata-tostring-calls 0)
          "TableNode must not call tostring on userdata")
  (local entry (. (. items 1) 1))
  (assert (= entry.value-text "<userdata:CrashyUserdata>")
          (.. "TableNode should use userdata metadata label, got "
              (tostring entry.value-text)))
  (debug.setmetatable fixture original-mt)
  nil)

(fn table-node-describes-metatable-tables-without-tostring []
  (set table-tostring-calls 0)
  (local fixture (setmetatable {:name "wrapped"}
                               {:__tostring fail-table-tostring}))
  (local node (TableNode {:table {:danger fixture}
                          :label "root"
                          :key "table:root"}))
  (local items (node:build-items))
  (assert (= table-tostring-calls 0)
          "TableNode must not call tostring on metatable tables")
  (local entry (. (. items 1) 1))
  (assert (= entry.value-text "wrapped")
          (.. "TableNode should prefer table labels, got "
              (tostring entry.value-text))))

(table.insert tests {:name "Table node describes userdata without tostring"
                     :fn table-node-describes-userdata-without-tostring})

(table.insert tests {:name "Table node describes metatable tables without tostring"
                     :fn table-node-describes-metatable-tables-without-tostring})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "table-node" :tests tests})))

{:name "table-node" :tests tests :main main}
