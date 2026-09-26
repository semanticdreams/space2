(local Runner (require :tests/runner))
(local Snapshot (require :app-host.workspace-inspector-snapshot))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn assert-error-contains [f expected]
  (local (ok err) (pcall f))
  (assert (= ok false) "expected call to fail")
  (assert (string.find (tostring err) expected 1 true)
          (.. "expected error to contain " expected ", got " (tostring err))))

(fn registry [items]
  {:list (fn [_self]
           (local out [])
           (each [_ item (ipairs items)]
             (table.insert out item))
           out)})

(fn host-with [inspectors commands]
  {:inspectors (registry inspectors)
   :commands (registry commands)})

(fn read-snake-state [_self]
  {:score 3 :game-over? false})

(fn mark-command-run [self]
  (set self.state.ran? true))

(fn read-broken-inspector [_self]
  (error "inspector failed"))

(fn test-readable-inspector-and-command-metadata []
  (local command-state {:ran? false})
  (local host
    (host-with [{:id :snake-state
                 :title "Snake State"
                 :read read-snake-state}]
               [{:id :restart
                 :title "Restart"
                 :description "Restart the app"
                 :state command-state
                 :run mark-command-run}]))
  (local snapshot (Snapshot.read-host host))
  (assert (= (# snapshot.inspectors) 1) "snapshot should include inspector")
  (assert (= (. snapshot.inspectors 1 :id) :snake-state))
  (assert (= (. snapshot.inspectors 1 :title) "Snake State"))
  (assert (= (. snapshot.inspectors 1 :status) :ok))
  (assert (= (. snapshot.inspectors 1 :data :score) 3))
  (assert (= (# snapshot.commands) 1) "snapshot should include command metadata")
  (assert (= (. snapshot.commands 1 :id) :restart))
  (assert (= (. snapshot.commands 1 :status) :metadata))
  (assert (= command-state.ran? false) "snapshot must not execute commands"))

(fn test-unsupported-and-error-inspectors-are-explicit []
  (local host
    (host-with [{:id :metadata-only :title "Metadata Only"}
                {:id :broken
                 :title "Broken"
                 :read read-broken-inspector}]
               []))
  (local snapshot (Snapshot.read-host host))
  (assert (= (# snapshot.inspectors) 2))
  (assert (= (. snapshot.inspectors 1 :status) :unsupported))
  (assert (= (. snapshot.inspectors 2 :status) :error))
  (assert (string.find (. snapshot.inspectors 2 :error) "inspector failed" 1 true)))

(fn test-missing-registries-fail-loudly []
  (assert-error-contains #(Snapshot.read-host {}) "inspectors")
  (assert-error-contains #(Snapshot.read-host {:inspectors (registry [])}) "commands"))

(add-test "readable inspector and command metadata" test-readable-inspector-and-command-metadata)
(add-test "unsupported and error inspectors are explicit" test-unsupported-and-error-inspectors-are-explicit)
(add-test "missing registries fail loudly" test-missing-registries-fail-loudly)

(fn main []
  (Runner.run-tests {:name "app-host-workspace-inspector-snapshot" :tests tests}))

{:main main :tests tests}
