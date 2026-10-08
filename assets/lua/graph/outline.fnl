(fn node-key [node-or-key]
    (if (= (type node-or-key) :string)
        node-or-key
        (and node-or-key node-or-key.key)))

(fn normalize-root-keys [graph-map root-keys]
    (assert (= (type root-keys) :table) "GraphOutline.normalize-root-keys requires root keys table")
    (local result [])
    (local seen {})
    (each [_ key (ipairs root-keys)]
        (when (and (= (type key) :string)
                   (not (. seen key))
                   (graph-map:lookup key))
            (set (. seen key) true)
            (table.insert result key)))
    result)

(fn build-child-index [graph-map]
    (local index {})
    (local seen-by-source {})
    (each [_ edge (ipairs graph-map.edges)]
        (local source-key (node-key edge.source))
        (local target-key (node-key edge.target))
        (when (and source-key target-key (graph-map:lookup source-key) (graph-map:lookup target-key))
            (when (not (. index source-key))
                (set (. index source-key) [])
                (set (. seen-by-source source-key) {}))
            (local source-seen (. seen-by-source source-key))
            (when (not (. source-seen target-key))
                (set (. source-seen target-key) true)
                (table.insert (. index source-key) target-key))))
    index)

(fn build-rows [graph-map root-keys]
    (assert (= (type root-keys) :table) "GraphOutline.build-rows requires root keys table")
    (local rows [])
    (local visited {})
    (local child-index (build-child-index graph-map))
    (fn visit [key depth parent-key]
        (when (and (graph-map:lookup key) (not (. visited key)))
            (set (. visited key) true)
            (table.insert rows {:key key
                                :node (graph-map:lookup key)
                                :depth depth
                                :parent-key parent-key})
            (local child-keys (if (. child-index key) (. child-index key) []))
            (each [_ child-key (ipairs child-keys)]
                (visit child-key (+ depth 1) key))))
    (each [_ key (ipairs (normalize-root-keys graph-map root-keys))]
        (visit key 0 nil))
    rows)

{:build-rows build-rows
 :normalize-root-keys normalize-root-keys}
