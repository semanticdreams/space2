;; Fixture-only: loaded before copied main can initialize native reporting.
;; Keep the native enabled? query so tests prove that no backend was started.
(local reporting (require :error-reporting))
(assert (not (reporting.enabled?)) "live fixture must start with reporting disabled")
(fn initialize-offline [_options]
  (local count (if (= _G.__live-dev-offline-inits nil) 0 _G.__live-dev-offline-inits))
  (assert (= (type count) :number) "offline reporting init counter must be numeric")
  (set _G.__live-dev-offline-inits (+ count 1))
  true)
(set reporting.init initialize-offline)
true
