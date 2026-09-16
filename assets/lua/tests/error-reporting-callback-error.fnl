(local reporting (require :error-reporting))
(local callbacks (require :callbacks))

(fn main []
  (local dsn (os.getenv :SPACE_TEST_ERROR_REPORTING_DSN))
  (local db (os.getenv :SPACE_TEST_ERROR_REPORTING_DB))
  (when (or (not dsn) (= dsn ""))
    (error "SPACE_TEST_ERROR_REPORTING_DSN is required"))
  (when (or (not db) (= db ""))
    (error "SPACE_TEST_ERROR_REPORTING_DB is required"))
  (reporting.init {:dsn dsn :database-path db :environment "test" :release "space-test"})
  (local id (callbacks.register (fn [_payload] (error "tests.error-reporting callback failure"))))
  (callbacks.enqueue id {})
  (callbacks.dispatch 1)
  (reporting.flush 5000)
  (reporting.shutdown)
  true)

{:main main}
