(local reporting (require :error-reporting))

(fn main []
  (local dsn (os.getenv :SPACE_TEST_ERROR_REPORTING_DSN))
  (local db (os.getenv :SPACE_TEST_ERROR_REPORTING_DB))
  (when (or (not dsn) (= dsn ""))
    (error "SPACE_TEST_ERROR_REPORTING_DSN is required"))
  (when (or (not db) (= db ""))
    (error "SPACE_TEST_ERROR_REPORTING_DB is required"))
  (reporting.init {:dsn dsn :database-path db :environment "test" :release "space-test"})
  (error "tests.error-reporting startup failure"))

{:main main}
