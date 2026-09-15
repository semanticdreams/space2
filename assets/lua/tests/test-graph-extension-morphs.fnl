(local Morphs (require :morphs/init))

(local tests [])

(fn demo-morph [_ctx]
  {:key "demo-target:a"})

(fn alternate-morph [_ctx]
  {:key "demo-target:b"})

(fn owner-safe-morph-handle-unregisters-current-registration []
  (local morphs (Morphs.Morphs {}))
  (local handle
    (morphs:register "demo-node" "demo-target" demo-morph {:label "Demo Target"} {:owner-id "unit-a"}))
  (assert handle "register should return a handle")
  (assert (= handle.from-scheme "demo-node") "handle should include from-scheme")
  (assert (= handle.to-scheme "demo-target") "handle should include to-scheme")
  (assert (= handle.owner-id "unit-a") "handle should include owner-id")
  (assert (= (type handle.unregister) "function") "handle should include unregister function")
  (assert (= (morphs:morph-owner "demo-node" "demo-target") "unit-a")
          "Morphs should report the active morph owner")
  (local before (morphs:target-items {:key "demo-node:a"}))
  (assert (= (length before) 1) "registered morph should expose one target")
  (assert (morphs:unregister handle) "unregistering active handle should succeed")
  (assert (= (morphs:morph-owner "demo-node" "demo-target") nil)
          "unregistering handle should remove owner")
  (local after (morphs:target-items {:key "demo-node:a"}))
  (assert (= (length after) 0) "unregistering handle should remove target")
  (assert (morphs:unregister handle)
          "unregistering the same inactive handle should be idempotent"))

(fn duplicate-active-morph-registration-fails-loudly []
  (local morphs (Morphs.Morphs {}))
  (morphs:register "demo-node" "demo-target" demo-morph {:label "Demo Target"} {:owner-id "unit-a"})
  (local (ok err)
    (pcall #(morphs:register "demo-node" "demo-target" alternate-morph {:label "Demo Target 2"} {:owner-id "unit-b"})))
  (assert (not ok) "duplicate active morph registration should fail")
  (assert (string.find (tostring err) "duplicate morph: demo-node -> demo-target" 1 true)
          "duplicate active morph error should name the schemes"))

(fn stale-morph-handle-cannot-remove-new-owner []
  (local morphs (Morphs.Morphs {}))
  (local handle-a
    (morphs:register "demo-node" "demo-target" demo-morph {:label "Demo Target"} {:owner-id "unit-a"}))
  (morphs:unregister handle-a)
  (morphs:register "demo-node" "demo-target" alternate-morph {:label "Demo Target 2"} {:owner-id "unit-b"})
  (local (ok err) (pcall #(morphs:unregister handle-a)))
  (assert (not ok) "stale handle should not remove another owner registration")
  (assert (string.find (tostring err) "belongs to another registration" 1 true)
          "stale handle error should use registration diagnostic")
  (assert (= (morphs:morph-owner "demo-node" "demo-target") "unit-b")
          "stale unregister must not remove the newer owner")
  (local items (morphs:target-items {:key "demo-node:a"}))
  (assert (= (length items) 1) "stale unregister must leave target active"))

(table.insert tests {:name "owner-safe morph handle unregisters current registration"
                     :fn owner-safe-morph-handle-unregisters-current-registration})
(table.insert tests {:name "duplicate active morph registration fails loudly"
                     :fn duplicate-active-morph-registration-fails-loudly})
(table.insert tests {:name "stale morph handle cannot remove a new owner"
                     :fn stale-morph-handle-cannot-remove-new-owner})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "graph-extension-morphs"
                       :tests tests})))

{:name "graph-extension-morphs"
 :tests tests
 :main main}
