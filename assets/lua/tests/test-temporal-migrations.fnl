(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local Temporal (require :temporal))
(local {: WorkflowStore} (require :workflows/store))

(local tests [])
(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "temporal-migrations"))

(fn assert-error [f message]
  (local (ok err) (pcall f))
  (assert (not ok) message)
  (tostring err))

(fn assert-contains [value needle message]
  (assert (string.find (tostring value) needle 1 true) message))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (local dir (fs.join-path temp-root (.. "case-" (os.time) "-" temp-counter)))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  dir)

(fn read-json [path]
  (json.loads (fs.read-file path)))

(fn write-json! [path data]
  (JsonUtils.write-json! path data))

(fn assert-z-string [value message]
  (assert (= (type value) :string) message)
  (assert (string.match value "Z$") message))

(fn migrations []
  (assert Temporal.migrations "Temporal.migrations should be exported"))

(fn numeric-zero-converts-to-instant-string []
  (local M (migrations))
  (local instant (M.timestamp->instant 0 {:schema-id :unit :field-path "created-at"}))
  (assert (= (instant:to-string) "1970-01-01T00:00:00Z") "epoch zero should format as canonical UTC instant string"))

(fn canonical-string-round-trips-through-epoch-seconds []
  (local M (migrations))
  (local timestamp "1970-01-01T00:00:01Z")
  (local epoch (M.timestamp->epoch-seconds timestamp {:schema-id :unit :field-path "created-at"}))
  (assert (= epoch 1) "canonical string should parse to epoch seconds")
  (local canonical (M.instant->timestamp (M.timestamp->instant timestamp {:schema-id :unit :field-path "created-at"})
                                         {:schema-id :unit :field-path "created-at"}))
  (assert (= canonical timestamp) "canonical string should remain unchanged after round trip"))

(fn optional-nil-returns-nil []
  (local M (migrations))
  (assert (= (M.timestamp->instant nil {:schema-id :unit :field-path "finished-at" :optional? true}) nil)
          "optional nil should remain nil")
  (assert (= (M.timestamp->epoch-seconds nil {:schema-id :unit :field-path "finished-at" :optional? true}) nil)
          "optional nil epoch conversion should remain nil")
  (assert (= (M.instant->timestamp nil {:schema-id :unit :field-path "finished-at" :optional? true}) nil)
          "optional nil timestamp conversion should remain nil"))

(fn required-nil-throws-temporal-migration-error []
  (local M (migrations))
  (local err (assert-error #(M.timestamp->instant nil {:schema-id :workflow-run :field-path "created-at"})
                           "required nil should fail"))
  (assert-contains err "temporal migration" "error should identify temporal migration")
  (assert-contains err "workflow-run" "error should include schema id")
  (assert-contains err "created-at" "error should include field path"))

(fn fractional-numeric-timestamp-throws []
  (local M (migrations))
  (local err (assert-error #(M.timestamp->instant 1.5 {:schema-id :workflow-run :field-path "created-at"})
                           "fractional timestamp should fail"))
  (assert-contains err "integer" "fractional timestamp error should mention integer seconds"))

(fn malformed-string-throws-with-context []
  (local M (migrations))
  (local err (assert-error #(M.timestamp->instant "not-a-timestamp"
                                                  {:schema-id :workflow-run
                                                   :field-path "events[1].created-at"
                                                   :file-path "/tmp/workflow-run.json"})
                           "malformed string should fail"))
  (assert-contains err "temporal migration" "error should identify temporal migration")
  (assert-contains err "workflow-run" "error should include schema id")
  (assert-contains err "events[1].created-at" "error should include field path")
  (assert-contains err "/tmp/workflow-run.json" "error should include file path"))

(fn unknown-option-key-throws []
  (local M (migrations))
  (local err (assert-error #(M.timestamp->instant 0 {:schema-id :unit :field-path "created-at" :legacy true})
                           "unknown option should fail"))
  (assert-contains err "unknown option" "error should mention unknown option")
  (assert-contains err "legacy" "error should name unknown key"))

(fn dry-run-reports-changes-without-writing []
  (local M (migrations))
  (local dir (make-temp-dir))
  (local path (fs.join-path dir "definition.json"))
  (write-json! path {:id "wf" :created-at 0 :updated-at "1970-01-01T00:00:01Z"})
  (local before (fs.read-file path))
  (local result (M.migrate-json-file! path M.schemas.workflow-definition {:dry-run? true}))
  (assert result.changed? "dry run should report a change")
  (assert (= result.conversions 1) "dry run should count converted integer fields")
  (assert (= (fs.read-file path) before) "dry run should not rewrite the file"))

(fn file-migration-rewrites-integer-seconds []
  (local M (migrations))
  (local dir (make-temp-dir))
  (local path (fs.join-path dir "definition.json"))
  (write-json! path {:id "wf" :created-at 0 :updated-at 1})
  (local result (M.migrate-json-file! path M.schemas.workflow-definition))
  (local migrated (read-json path))
  (assert result.changed? "migration should report a changed file")
  (assert (= result.conversions 2) "migration should count both converted fields")
  (assert (= migrated.created-at "1970-01-01T00:00:00Z") "created-at should be canonical")
  (assert (= migrated.updated-at "1970-01-01T00:00:01Z") "updated-at should be canonical"))

(fn rerunning-file-migration-reports-no-changes []
  (local M (migrations))
  (local dir (make-temp-dir))
  (local path (fs.join-path dir "definition.json"))
  (write-json! path {:id "wf" :created-at 0 :updated-at 1})
  (M.migrate-json-file! path M.schemas.workflow-definition)
  (local before (fs.read-file path))
  (local result (M.migrate-json-file! path M.schemas.workflow-definition))
  (assert (not result.changed?) "canonical file should not report changes")
  (assert (= result.conversions 0) "canonical file should not count conversions")
  (assert (= (fs.read-file path) before) "canonical file should not be rewritten"))

(fn malformed-file-data-fails-without-rewriting []
  (local M (migrations))
  (local dir (make-temp-dir))
  (local path (fs.join-path dir "definition.json"))
  (write-json! path {:id "wf" :created-at 0 :updated-at 1.25})
  (local before (fs.read-file path))
  (local err (assert-error #(M.migrate-json-file! path M.schemas.workflow-definition)
                           "malformed field should fail"))
  (assert-contains err "workflow-definition" "error should include schema id")
  (assert-contains err "updated-at" "error should include field path")
  (assert-contains err path "error should include file path")
  (assert (= (fs.read-file path) before) "malformed file should not be rewritten"))

(fn malformed-json-file-fails-with-root-context []
  (local M (migrations))
  (local dir (make-temp-dir))
  (local path (fs.join-path dir "definition.json"))
  (fs.write-file path "{")
  (local before (fs.read-file path))
  (local err (assert-error #(M.migrate-json-file! path M.schemas.workflow-definition)
                           "malformed JSON should fail"))
  (assert-contains err "temporal migration" "error should identify temporal migration")
  (assert-contains err "workflow-definition" "error should include schema id")
  (assert-contains err "field=$" "error should include root field path")
  (assert-contains err path "error should include file path")
  (assert (= (fs.read-file path) before) "malformed JSON file should not be rewritten"))

(fn workflow-run-nested-schema-converts-events-and-steps []
  (local M (migrations))
  (local dir (make-temp-dir))
  (local path (fs.join-path dir "run.json"))
  (write-json! path {:id "run-1"
                     :created-at 0
                     :started-at 1
                     :finished-at nil
                     :steps {:alpha {:started-at 2 :finished-at 3}
                             :beta {:started-at nil :finished-at 4}}
                     :events [{:id "evt-1" :created-at 5}
                              {:id "evt-2" :created-at "1970-01-01T00:00:06Z"}]})
  (local result (M.migrate-json-file! path M.schemas.workflow-run))
  (local migrated (read-json path))
  (assert result.changed? "workflow run should report changed nested timestamps")
  (assert (= result.conversions 6) "workflow run should count top-level and nested integer conversions")
  (assert (= migrated.created-at "1970-01-01T00:00:00Z") "top-level created-at should be canonical")
  (assert (= migrated.started-at "1970-01-01T00:00:01Z") "top-level started-at should be canonical")
  (assert (= migrated.steps.alpha.started-at "1970-01-01T00:00:02Z") "step started-at should be canonical")
  (assert (= migrated.steps.alpha.finished-at "1970-01-01T00:00:03Z") "step finished-at should be canonical")
  (assert (= migrated.steps.beta.finished-at "1970-01-01T00:00:04Z") "mapped step finished-at should be canonical")
  (assert (= (. migrated.events 1 :created-at) "1970-01-01T00:00:05Z") "event created-at should be canonical")
  (assert (= (. migrated.events 2 :created-at) "1970-01-01T00:00:06Z") "canonical event timestamp should remain canonical"))

(fn workflow-run-migration-rejects-object-shaped-events []
  (local M (migrations))
  (local dir (make-temp-dir))
  (local path (fs.join-path dir "run.json"))
  (write-json! path {:id "run-1"
                     :created-at 0
                     :events {:bad {:created-at 1}}})
  (local before (fs.read-file path))
  (local err (assert-error #(M.migrate-json-file! path M.schemas.workflow-run)
                           "object-shaped events should fail loudly"))
  (assert-contains err "workflow-run" "events container error should include schema id")
  (assert-contains err "events" "events container error should include field path")
  (assert-contains err path "events container error should include file path")
  (assert (= (fs.read-file path) before) "malformed events container should not be rewritten"))

(fn tree-migration-aggregates-dry-run-errors-and-idempotency []
  (local M (migrations))
  (local dir (make-temp-dir))
  (local nested-dir (fs.join-path dir "nested"))
  (fs.create-dirs nested-dir)
  (local change-path (fs.join-path dir "change.json"))
  (local noop-path (fs.join-path dir "noop.json"))
  (local malformed-path (fs.join-path dir "malformed.json"))
  (local nested-path (fs.join-path nested-dir "ignored.json"))
  (write-json! change-path {:id "change" :created-at 0 :updated-at 1})
  (write-json! noop-path {:id "noop" :created-at "1970-01-01T00:00:02Z" :updated-at "1970-01-01T00:00:03Z"})
  (fs.write-file malformed-path "{")
  (write-json! nested-path {:id "nested" :created-at 4 :updated-at 5})
  (local change-before (fs.read-file change-path))
  (local malformed-before (fs.read-file malformed-path))
  (local nested-before (fs.read-file nested-path))

  (local dry-run (M.migrate-json-tree! dir M.schemas.workflow-definition {:dry-run? true}))
  (assert (= dry-run.files 3) "tree migration should scan only non-recursive root JSON files")
  (assert (= dry-run.changed-files 1) "dry run should count changed files")
  (assert (= dry-run.conversions 2) "dry run should count conversions")
  (assert (= dry-run.errors 1) "dry run should count malformed files as errors")
  (assert (= (fs.read-file change-path) change-before) "dry run should not rewrite changed files")
  (assert (= (fs.read-file malformed-path) malformed-before) "dry run should not rewrite malformed files")

  (local migrated (M.migrate-json-tree! dir M.schemas.workflow-definition))
  (assert (= migrated.files 3) "tree migration should report root JSON files")
  (assert (= migrated.changed-files 1) "tree migration should count rewritten files")
  (assert (= migrated.conversions 2) "tree migration should aggregate conversions")
  (assert (= migrated.errors 1) "tree migration should report malformed file errors")
  (assert (= (. (read-json change-path) :created-at) "1970-01-01T00:00:00Z") "tree migration should rewrite changed files")
  (assert (= (fs.read-file malformed-path) malformed-before) "tree migration should not rewrite malformed files")

  (local rerun (M.migrate-json-tree! dir M.schemas.workflow-definition))
  (assert (= rerun.files 3) "tree rerun should scan the same root JSON files")
  (assert (= rerun.changed-files 0) "tree rerun should be idempotent for migrated files")
  (assert (= rerun.conversions 0) "tree rerun should have no conversions")
  (assert (= rerun.errors 1) "tree rerun should still report malformed files")
  (assert (= (fs.read-file nested-path) nested-before)
          "tree migration should not rewrite nested JSON files"))

(fn workflow-store-persists-canonical-timestamp-strings []
  (local dir (make-temp-dir))
  (local store (WorkflowStore {:base-dir dir}))
  (local definition (store:create-definition {:id "canonical"
                                              :name "Canonical"
                                              :steps [{:id "step-a" :code-entity-id "code-a"}]
                                              :edges []
                                              :created-at 0
                                              :updated-at 1}))
  (store:update-definition definition.id {:description "updated"})
  (assert (= (type definition.created-at) :number) "definition cache should keep numeric created-at")
  (assert (= (type definition.updated-at) :number) "definition cache should keep numeric updated-at")
  (local definition-json (read-json (fs.join-path dir "workflows" "definitions" "canonical.json")))
  (assert-z-string definition-json.created-at "definition created-at should persist as canonical string")
  (assert-z-string definition-json.updated-at "definition updated-at should persist as canonical string")

  (local run (store:create-run definition.id {} {}))
  (store:update-run run.id {:started-at 2 :finished-at 3})
  (store:upsert-run-step run.id "step-a" {:started-at 4 :finished-at 5 :status :succeeded})
  (local event (store:append-event run.id {:id "event-a" :kind :step-finished :step-id "step-a" :created-at 6}))
  (assert (= (type (. (store:get-run run.id) :created-at)) :number) "run cache should keep numeric created-at")
  (assert (= (type (. (store:get-run run.id) :started-at)) :number) "run cache should keep numeric started-at")
  (assert (= (type (. (store:get-run-step run.id "step-a") :started-at)) :number) "run step cache should keep numeric started-at")
  (assert (= (type event.created-at) :number) "event cache should keep numeric created-at")
  (local run-json (read-json (fs.join-path dir "workflows" "runs" (.. run.id ".json"))))
  (assert-z-string run-json.created-at "run created-at should persist as canonical string")
  (assert-z-string run-json.started-at "run started-at should persist as canonical string")
  (assert-z-string run-json.finished-at "run finished-at should persist as canonical string")
  (assert-z-string run-json.steps.step-a.started-at "run step started-at should persist as canonical string")
  (assert-z-string run-json.steps.step-a.finished-at "run step finished-at should persist as canonical string")
  (assert-z-string (. run-json.events 1 :created-at) "run event created-at should persist as canonical string"))

(fn workflow-store-loads-legacy-numeric-timestamps-in-memory []
  (local dir (make-temp-dir))
  (local definitions-dir (fs.join-path dir "workflows" "definitions"))
  (local runs-dir (fs.join-path dir "workflows" "runs"))
  (fs.create-dirs definitions-dir)
  (fs.create-dirs runs-dir)
  (write-json! (fs.join-path definitions-dir "legacy.json")
               {:id "legacy"
                :name "Legacy"
                :description ""
                :version 1
                :status :draft
                :parameters {}
                :steps [{:id "step-a" :name "Step A" :code-entity-id "code-a"}]
                :edges []
                :created-at 10
                :updated-at 11})
  (write-json! (fs.join-path runs-dir "run-legacy.json")
               {:id "run-legacy"
                :definition-id "legacy"
                :definition-version 1
                :status :succeeded
                :input {}
                :output {}
                :context {}
                :current-step-ids []
                :created-at 12
                :started-at 13
                :finished-at 14
                :steps {:step-a {:run-id "run-legacy"
                                 :step-id "step-a"
                                 :status :succeeded
                                 :started-at 15
                                 :finished-at 16}}
                :events [{:id "event-legacy" :run-id "run-legacy" :kind :done :created-at 17}]})
  (local store (WorkflowStore {:base-dir dir}))
  (local definition (store:get-definition "legacy"))
  (local run (store:get-run "run-legacy"))
  (assert (= definition.created-at 10) "legacy definition created-at should load as numeric seconds")
  (assert (= definition.updated-at 11) "legacy definition updated-at should load as numeric seconds")
  (assert (= run.created-at 12) "legacy run created-at should load as numeric seconds")
  (assert (= run.started-at 13) "legacy run started-at should load as numeric seconds")
  (assert (= run.finished-at 14) "legacy run finished-at should load as numeric seconds")
  (assert (= run.steps.step-a.started-at 15) "legacy run step started-at should load as numeric seconds")
  (assert (= run.steps.step-a.finished-at 16) "legacy run step finished-at should load as numeric seconds")
  (assert (= (. run.events 1 :created-at) 17) "legacy run event created-at should load as numeric seconds"))

(fn workflow-store-update-normalizes-timestamps-before-cache-mutation []
  (local dir (make-temp-dir))
  (local store (WorkflowStore {:base-dir dir}))
  (local definition (store:create-definition {:id "updates"
                                              :name "Updates"
                                              :steps [{:id "step-a" :code-entity-id "code-a"}]
                                              :edges []
                                              :created-at 0
                                              :updated-at 1}))
  (store:update-definition definition.id {:created-at "1970-01-01T00:00:02Z"})
  (assert (= definition.created-at 2) "definition update should normalize canonical created-at to numeric cache value")
  (local bad-definition-err (assert-error #(store:update-definition definition.id {:created-at 2.5})
                                          "malformed definition timestamp update should fail"))
  (assert-contains bad-definition-err "workflow-definition" "definition update error should include schema id")
  (assert (= definition.created-at 2) "failed definition update should not corrupt cached timestamp")

  (local run (store:create-run definition.id {} {}))
  (store:update-run run.id {:started-at "1970-01-01T00:00:03Z"
                            :finished-at "1970-01-01T00:00:04Z"
                            :steps {:step-a {:run-id run.id
                                             :step-id "step-a"
                                             :status :succeeded
                                             :started-at "1970-01-01T00:00:05Z"
                                             :finished-at "1970-01-01T00:00:06Z"}}
                            :events [{:id "event-a" :run-id run.id :kind :done :created-at "1970-01-01T00:00:07Z"}]})
  (assert (= run.started-at 3) "run started-at update should remain numeric in cache")
  (assert (= run.finished-at 4) "run finished-at update should remain numeric in cache")
  (assert (= run.steps.step-a.started-at 5) "run step update should remain numeric in cache")
  (assert (= (. run.events 1 :created-at) 7) "run event update should remain numeric in cache")
  (local bad-run-err (assert-error #(store:update-run run.id {:started-at 3.5})
                                   "malformed run timestamp update should fail"))
  (assert-contains bad-run-err "workflow-run" "run update error should include schema id")
  (assert (= run.started-at 3) "failed run update should not corrupt cached started-at")

  (store:upsert-run-step run.id "step-a" {:started-at "1970-01-01T00:00:08Z"})
  (assert (= run.steps.step-a.started-at 8) "upserted run step timestamp should remain numeric in cache")
  (local bad-step-err (assert-error #(store:upsert-run-step run.id "step-a" {:started-at 8.5})
                                    "malformed run step timestamp update should fail"))
  (assert-contains bad-step-err "steps.step-a.started-at" "run step update error should include field path")
  (assert (= run.steps.step-a.started-at 8) "failed run step update should not corrupt cached started-at")

  (local appended (store:append-event run.id {:id "event-b" :kind :done :created-at "1970-01-01T00:00:09Z"}))
  (assert (= appended.created-at 9) "appended event timestamp should remain numeric in cache")
  (local event-count (length run.events))
  (local bad-event-err (assert-error #(store:append-event run.id {:id "event-bad" :kind :done :created-at 9.5})
                                     "malformed event timestamp update should fail"))
  (assert-contains bad-event-err "events" "event append error should include field path")
  (assert (= (length run.events) event-count) "failed event append should not mutate cached event list"))

(fn workflow-store-load-rejects-object-shaped-events []
  (local dir (make-temp-dir))
  (local definitions-dir (fs.join-path dir "workflows" "definitions"))
  (local runs-dir (fs.join-path dir "workflows" "runs"))
  (fs.create-dirs definitions-dir)
  (fs.create-dirs runs-dir)
  (write-json! (fs.join-path definitions-dir "events-object.json")
               {:id "events-object"
                :name "Events Object"
                :description ""
                :version 1
                :status :draft
                :parameters {}
                :steps []
                :edges []
                :created-at 0
                :updated-at 1})
  (local run-path (fs.join-path runs-dir "run-events-object.json"))
  (write-json! run-path {:id "run-events-object"
                         :definition-id "events-object"
                         :definition-version 1
                         :status :succeeded
                         :input {}
                         :output {}
                         :context {}
                         :current-step-ids []
                         :created-at 2
                         :steps {}
                         :events {:bad {:created-at 3}}})
  (local err (assert-error #(WorkflowStore {:base-dir dir})
                           "workflow store should reject object-shaped events"))
  (assert-contains err "workflow-run" "store load event container error should include schema id")
  (assert-contains err "events" "store load event container error should include field path")
  (assert-contains err "run-events-object.json" "store load event container error should include file path"))

(table.insert tests {:name "numeric zero converts to instant string" :fn numeric-zero-converts-to-instant-string})
(table.insert tests {:name "canonical string round trips through epoch seconds" :fn canonical-string-round-trips-through-epoch-seconds})
(table.insert tests {:name "optional nil returns nil" :fn optional-nil-returns-nil})
(table.insert tests {:name "required nil throws temporal migration error" :fn required-nil-throws-temporal-migration-error})
(table.insert tests {:name "fractional numeric timestamp throws" :fn fractional-numeric-timestamp-throws})
(table.insert tests {:name "malformed string throws with context" :fn malformed-string-throws-with-context})
(table.insert tests {:name "unknown option key throws" :fn unknown-option-key-throws})
(table.insert tests {:name "dry run reports changes without writing" :fn dry-run-reports-changes-without-writing})
(table.insert tests {:name "file migration rewrites integer seconds" :fn file-migration-rewrites-integer-seconds})
(table.insert tests {:name "rerunning file migration reports no changes" :fn rerunning-file-migration-reports-no-changes})
(table.insert tests {:name "malformed file data fails without rewriting" :fn malformed-file-data-fails-without-rewriting})
(table.insert tests {:name "malformed JSON file fails with root context" :fn malformed-json-file-fails-with-root-context})
(table.insert tests {:name "workflow run nested schema converts events and steps" :fn workflow-run-nested-schema-converts-events-and-steps})
(table.insert tests {:name "workflow run migration rejects object shaped events" :fn workflow-run-migration-rejects-object-shaped-events})
(table.insert tests {:name "tree migration aggregates dry run errors and idempotency" :fn tree-migration-aggregates-dry-run-errors-and-idempotency})
(table.insert tests {:name "workflow store persists canonical timestamp strings" :fn workflow-store-persists-canonical-timestamp-strings})
(table.insert tests {:name "workflow store loads legacy numeric timestamps in memory" :fn workflow-store-loads-legacy-numeric-timestamps-in-memory})
(table.insert tests {:name "workflow store update normalizes timestamps before cache mutation" :fn workflow-store-update-normalizes-timestamps-before-cache-mutation})
(table.insert tests {:name "workflow store load rejects object shaped events" :fn workflow-store-load-rejects-object-shaped-events})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal migrations"
                       :tests tests})))

{:name "temporal migrations"
 :tests tests
 :main main}
