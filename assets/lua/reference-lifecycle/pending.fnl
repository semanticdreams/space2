(local fs (require :fs))
(local J (require :json-utils))
(local R (require :reference-lifecycle/record-utils))

(fn Pending [base-dir]
  (local directory (fs.join-path (R.comparison-path base-dir) "reference-lifecycle"))
  (fn path [] (R.record-path base-dir directory "pending" ".json"))
  (fn read [_self]
    (local snapshot (R.snapshot (path) "json" R.decode-json))
    (if snapshot.value
        (do (assert (= snapshot.value.version 1) "unsupported pending intent version") snapshot.value)
        nil))
  (fn write! [_self intent]
    (assert (= intent.version 1) "unsupported pending intent version")
    (local target (path))
    (fs.create-dirs directory)
    (J.write-json! target intent)
    true)
  (fn clear! [_self]
    (local target (path))
    (when (fs.exists target) (fs.remove target))
    true)
  {:read read :write! write! :clear! clear!})
Pending
