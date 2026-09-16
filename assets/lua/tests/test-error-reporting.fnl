(local reporting (require :error-reporting))

(fn assert-eq [actual expected message]
  (when (not= actual expected)
    (error (.. message " expected=" (tostring expected) " actual=" (tostring actual)))))

(fn assert-error [f message]
  (local (ok err) (pcall f))
  (when ok
    (error message))
  err)

(fn main []
  (assert-eq (type reporting.init) :function "init export")
  (assert-eq (type reporting.enabled?) :function "enabled? export")
  (assert-eq (type reporting.capture-message) :function "capture-message export")
  (assert-eq (type reporting.capture-error) :function "capture-error export")
  (assert-eq (type reporting.flush) :function "flush export")
  (assert-eq (type reporting.shutdown) :function "shutdown export")
  (assert-eq (reporting.enabled?) false "reporting disabled before init")
  (assert-eq (reporting.capture-message :error :test "disabled message") false "message capture disabled before init")
  (assert-eq (reporting.capture-error {:type :Disabled :message "disabled"}) false "error capture disabled before init")
  (assert-error #(reporting.init {}) "empty init options must fail")
  (assert-error #(reporting.init {:dsn 42}) "numeric dsn must fail")
  (assert-error #(reporting.capture-message :verbose :test "bad level") "invalid level must fail")
  true)

{:main main}
