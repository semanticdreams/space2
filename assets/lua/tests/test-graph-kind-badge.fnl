(local Graph (require :graph/init))
(local GraphMapModule (require :graph/map))
(local KindBadge (require :graph/kind-badge))
(local glm (require :glm))

(local GraphMap GraphMapModule.GraphMap)
(local tests [])

(fn approx [a b]
  (< (math.abs (- a b)) 1e-5))

(fn color= [a b]
  (and a b
       (approx a.x b.x)
       (approx a.y b.y)
       (approx a.z b.z)
       (approx a.w b.w)))

(fn normalize-derives-uppercase-scheme []
  (local badge (KindBadge.normalize {:key "fs:/tmp/a.txt"
                                     :color (glm.vec4 0.3 0.6 1 1)}))
  (assert badge "scheme-bearing keys should derive a default badge")
  (assert (= badge.text "FS"))
  (assert (color= badge.background-color (glm.vec4 0.3 0.6 1 1))))

(fn normalize-no-scheme-is-nil []
  (assert (= (KindBadge.normalize {:key "start"}) nil)
          "keys without ':' should not derive badges"))

(fn normalize-explicit-false-opts-out []
  (assert (= (KindBadge.normalize {:key "fs:/tmp/a.txt" :value false}) false)
          "explicit false should suppress derived badges"))

(fn normalize-explicit-text-trims-without-changing-case []
  (local badge (KindBadge.normalize {:key "fs:/tmp/a.txt"
                                     :value {:text " File "
                                             :foreground-color (glm.vec4 1 1 0 1)}}))
  (assert (= badge.text "File"))
  (assert (color= badge.foreground-color (glm.vec4 1 1 0 1))))

(fn malformed-explicit-badge-fails-loudly []
  (each [_ value (ipairs [true {} {:text ""} {:text "  "}])]
    (local (ok err)
      (pcall (fn [] (KindBadge.normalize {:key "fs:/tmp/a.txt" :value value}))))
    (assert (not ok) "malformed explicit badge should fail")
    (assert (string.find (tostring err) "kind-badge" 1 true)
            (.. "expected clear kind-badge error, got " (tostring err)))))

(fn malformed-explicit-colors-fail-loudly []
  (each [_ field (ipairs [:background-color :foreground-color])]
    (each [_ color-value (ipairs [false true "red" 12 (glm.vec3 1 0 0)])]
      (local metadata {:text "FS"})
      (tset metadata field color-value)
      (local (ok err)
        (pcall (fn [] (KindBadge.normalize {:key "fs:/tmp/a.txt" :value metadata}))))
      (assert (not ok) (.. "malformed explicit " field " should fail"))
      (assert (string.find (tostring err) (.. "kind-badge." field) 1 true)
              (.. "expected clear kind-badge color error, got " (tostring err))))))

(fn graph-node-stores-normalized-derived-kind-badge []
  (local node (Graph.GraphNode {:key "fs:/tmp/a.txt"
                                :label "a.txt"
                                :color (glm.vec4 0.25 0.5 0.75 1)}))
  (assert node.kind-badge "GraphNode should store normalized badge metadata")
  (assert (= node.kind-badge.text "FS")))

(fn graph-node-preserves-explicit-kind-badge-opt-out []
  (local node (Graph.GraphNode {:key "fs:/tmp/a.txt" :kind-badge false}))
  (assert (= node.kind-badge false)
          "GraphNode should preserve explicit false opt-out"))

(table.insert tests {:name "KindBadge derives uppercase scheme text"
                     :fn normalize-derives-uppercase-scheme})
(table.insert tests {:name "KindBadge omits badge for keys without scheme"
                     :fn normalize-no-scheme-is-nil})
(table.insert tests {:name "KindBadge explicit false opts out"
                     :fn normalize-explicit-false-opts-out})
(table.insert tests {:name "KindBadge explicit text trims without changing case"
                     :fn normalize-explicit-text-trims-without-changing-case})
(table.insert tests {:name "KindBadge malformed explicit metadata fails loudly"
                     :fn malformed-explicit-badge-fails-loudly})
(table.insert tests {:name "KindBadge malformed explicit colors fail loudly"
                     :fn malformed-explicit-colors-fail-loudly})
(table.insert tests {:name "GraphNode stores normalized derived kind-badge metadata"
                     :fn graph-node-stores-normalized-derived-kind-badge})
(table.insert tests {:name "GraphNode preserves explicit kind-badge opt-out"
                     :fn graph-node-preserves-explicit-kind-badge-opt-out})

(fn main []
  (local runner (require :tests/runner))
  (runner.run-tests {:name "graph-kind-badge" :tests tests}))

{:name "graph-kind-badge" :tests tests :main main}
