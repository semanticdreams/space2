(local fs (require :fs))

(fn non-empty-string? [value]
  (and (= (type value) "string") (> (string.len value) 0)))

(fn starts-with? [text prefix]
  (and text prefix
       (= (type text) "string")
       (= (type prefix) "string")
       (= (string.sub text 1 (string.len prefix)) prefix)))

(fn strip-prefix [text prefix]
  (if (starts-with? text prefix)
      (string.sub text (+ 1 (string.len prefix)))
      nil))

(fn split-key-parts [text]
  (assert text "split-key-parts requires text")
  (local parts [])
  (each [part (string.gmatch text "[^:]+")]
    (table.insert parts part))
  parts)

(fn exact-key-loader [expected make-node]
  (assert (non-empty-string? expected) "exact-key-loader requires expected string key")
  (assert (= (type make-node) "function") "exact-key-loader requires make-node function")
  (fn [key]
    (if (= key expected)
        (make-node)
        nil)))

(fn prefix-loader [prefix make-node]
  (assert (non-empty-string? prefix) "prefix-loader requires string prefix")
  (assert (= (type make-node) "function") "prefix-loader requires make-node function")
  (fn [key]
    (local suffix (strip-prefix key prefix))
    (when (non-empty-string? suffix)
      (make-node suffix key))))

(fn existing-path-loader [prefix kind make-node]
  (assert (non-empty-string? prefix) "existing-path-loader requires string prefix")
  (assert (= (type make-node) "function") "existing-path-loader requires make-node function")
  (fn [key]
    (local path (strip-prefix key prefix))
    (when (non-empty-string? path)
      (local stat (and fs.stat (fs.stat path)))
      (when (and stat stat.exists
                 (if (= kind :dir) stat.is-dir stat.is-file))
        (make-node path key)))))

(fn existing-any-path-loader [prefix make-node]
  (assert (non-empty-string? prefix) "existing-any-path-loader requires string prefix")
  (assert (= (type make-node) "function") "existing-any-path-loader requires make-node function")
  (fn [key]
    (local path (strip-prefix key prefix))
    (when (non-empty-string? path)
      (local stat (and fs.stat (fs.stat path)))
      (when (and stat stat.exists)
        (make-node path key)))))

(fn collect-handles [...]
  (local handles [])
  (each [_ handle (ipairs [...])]
    (assert (= (type handle) "table") "collect-handles requires handle table")
    (assert (= (type handle.unregister) "function") "collect-handles requires handle.unregister")
    (table.insert handles handle))
  handles)

(fn sequential-non-empty-strings? [items]
  (and (= (type items) "table")
       (> (length items) 0)
       (do
         (var ok? true)
         (for [i 1 (length items)]
           (when (not (non-empty-string? (. items i)))
             (set ok? false)))
         ok?)))

(fn descriptor [opts]
  (local desc (assert opts "descriptor requires opts"))
  (assert (non-empty-string? desc.id) "descriptor requires non-empty id")
  (assert (non-empty-string? desc.unit-id) "descriptor requires non-empty unit-id")
  (assert (sequential-non-empty-strings? desc.schemes)
          "descriptor requires non-empty sequential schemes")
  (assert (= (type desc.install-loaders) "function")
          "descriptor requires install-loaders function")
  desc)

{:exact-key-loader exact-key-loader
 :prefix-loader prefix-loader
 :existing-path-loader existing-path-loader
 :existing-any-path-loader existing-any-path-loader
 :split-key-parts split-key-parts
 :collect-handles collect-handles
 :descriptor descriptor}
