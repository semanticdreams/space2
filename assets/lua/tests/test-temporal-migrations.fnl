(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local Temporal (require :temporal))

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
(table.insert tests {:name "tree migration aggregates dry run errors and idempotency" :fn tree-migration-aggregates-dry-run-errors-and-idempotency})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "temporal migrations"
                       :tests tests})))

{:name "temporal migrations"
 :tests tests
 :main main}
