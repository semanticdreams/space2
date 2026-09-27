(local Runner (require :tests/runner))
(local History (require :app-host.command-run-history))
(local tests [])

(fn add-test [name test-fn]
  (table.insert tests {:name name :fn test-fn}))

(fn make-clock []
  (local state {:now 100})
  (fn next-now []
    (set state.now (+ state.now 1))
    state.now)
  {:state state
   :now next-now})

(fn fixed-now-1 []
  1)

(fn fixed-now-10 []
  10)

(fn test-empty-history-text []
  (local history (History.create {:now fixed-now-1}))
  (assert (= (History.list-text history) "Recent runs\nNo command runs yet"))
  (assert (= (# (History.entries history)) 0)))

(fn test-start-run-ids-and-timestamps []
  (local clock (make-clock))
  (local history (History.create {:now clock.now}))
  (local first (History.start-run! history {:id :save :title "Save"}))
  (local second (History.start-run! history {:id :reset :title "Reset"}))
  (assert (= first.run-id 1))
  (assert (= first.started-at 101))
  (assert (= first.updated-at 101))
  (assert (= second.run-id 2))
  (assert (= (. (History.entries history) 1 :command-id) :reset))
  (assert (= (. (History.entries history) 2 :command-id) :save)))

(fn test-limit-trims_oldest []
  (local clock (make-clock))
  (local history (History.create {:limit 2 :now clock.now}))
  (History.start-run! history {:id :one :title "One"})
  (History.start-run! history {:id :two :title "Two"})
  (History.start-run! history {:id :three :title "Three"})
  (local entries (History.entries history))
  (assert (= (# entries) 2))
  (assert (= (. entries 1 :command-id) :three))
  (assert (= (. entries 2 :command-id) :two))
  (assert (= (History.finish! history 1 {:id :one :title "One"} {:id :one :status :ok :value true}) nil)))

(fn test-progress-updates_existing_entry []
  (local clock (make-clock))
  (local history (History.create {:now clock.now}))
  (local entry (History.start-run! history {:id :export :title "Export"}))
  (History.progress! history entry.run-id {:id :export :title "Export"} {:message "halfway" :value 0.5})
  (local entries (History.entries history))
  (assert (= (# entries) 1))
  (assert (= (. entries 1 :status) :running))
  (assert (= (. entries 1 :progress-text) "halfway"))
  (assert (= (. entries 1 :progress-value) 0.5)))

(fn test-progress-rejects_raw_value_objects []
  (local clock (make-clock))
  (local history (History.create {:now clock.now}))
  (local entry (History.start-run! history {:id :export :title "Export"}))
  (local progress {:message "object progress" :value {:raw true}})
  (History.progress! history entry.run-id {:id :export :title "Export"} progress)
  (local stored (. (History.entries history) 1))
  (assert (= stored.progress-text "object progress"))
  (assert (= stored.progress-value nil))
  (assert (= stored.progress nil)))

(fn test-finish-statuses_and_text []
  (local clock (make-clock))
  (local history (History.create {:now clock.now}))
  (local ok (History.start-run! history {:id :ok :title "OK"}))
  (History.set-payload! history ok.run-id {:slot 1})
  (History.finish! history ok.run-id {:id :ok :title "OK"} {:id :ok :status :ok :value {:saved true}})
  (local err (History.start-run! history {:id :err :title "Err"}))
  (History.finish! history err.run-id {:id :err :title "Err"} {:id :err :status :error :error "boom"})
  (local cancelled (History.start-run! history {:id :cancel :title "Cancel"}))
  (History.finish! history cancelled.run-id {:id :cancel :title "Cancel"} {:id :cancel :status :cancelled :error "user cancelled"})
  (local unknown (History.start-run! history {:id :wait :title "Wait"}))
  (History.finish! history unknown.run-id {:id :wait :title "Wait"} {:id :wait :status :queued})
  (local text (History.list-text history))
  (assert (string.find text "OK" 1 true))
  (assert (string.find text "saved" 1 true))
  (assert (string.find text "boom" 1 true))
  (assert (string.find text "cancelled" 1 true))
  (assert (string.find text "queued" 1 true)))

(fn test-fail-and-no-raw-objects []
  (local history (History.create {:now fixed-now-10}))
  (local entry (History.start-run! history {:id :bad :title "Bad"}))
  (History.set-payload! history entry.run-id {:large (string.rep "x" 700)})
  (History.fail! history entry.run-id {:id :bad :title "Bad"} "number field count is required")
  (local stored (. (History.entries history) 1))
  (assert (= stored.status :error))
  (assert (string.find stored.error-text "number field" 1 true))
  (assert (= stored.payload nil))
  (assert (= stored.result nil))
  (assert (= stored.command nil))
  (assert (<= (# stored.payload-text) 500)))

(add-test "empty history text" test-empty-history-text)
(add-test "start run ids and timestamps" test-start-run-ids-and-timestamps)
(add-test "limit trims oldest" test-limit-trims_oldest)
(add-test "progress updates existing entry" test-progress-updates_existing_entry)
(add-test "progress rejects raw value objects" test-progress-rejects_raw_value_objects)
(add-test "finish statuses and text" test-finish-statuses_and_text)
(add-test "fail and no raw objects" test-fail-and-no-raw-objects)

(fn main []
  (Runner.run-tests {:name "app-host-command-run-history" :tests tests}))

{:main main :tests tests}
