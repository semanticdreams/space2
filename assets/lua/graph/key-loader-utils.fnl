(fn key-prefix [scheme]
  (assert scheme "key-prefix requires scheme")
  (assert (= (type scheme) "string") "key-prefix requires string scheme")
  (assert (> (string.len scheme) 0) "key-prefix requires non-empty scheme")
  (.. scheme ":"))

(fn extract-id [scheme key]
  (assert scheme "extract-id requires scheme")
  (assert (= (type scheme) "string") "extract-id requires string scheme")
  (assert key "extract-id requires key")
  (assert (= (type key) "string") "extract-id requires string key")
  (local prefix (key-prefix scheme))
  (if (not (= (string.sub key 1 (string.len prefix)) prefix))
      nil
      (do
        (local id (string.sub key (+ 1 (string.len prefix))))
        (if (> (string.len id) 0)
            id
            nil))))

(fn key-scheme [key]
  (when (and key (= (type key) "string"))
    (local (start _end) (string.find key ":" 1 true))
    (if start
        (string.sub key 1 (- start 1))
        key)))

(fn make-register-loader [scheme get-default-store make-node]
  (assert scheme "make-register-loader requires scheme")
  (assert (= (type scheme) "string") "make-register-loader requires string scheme")
  (assert (> (string.len scheme) 0) "make-register-loader requires non-empty scheme")
  (assert get-default-store "make-register-loader requires get-default-store")
  (assert (= (type get-default-store) "function") "make-register-loader requires function get-default-store")
  (assert make-node "make-register-loader requires make-node")
  (assert (= (type make-node) "function") "make-register-loader requires function make-node")
  (fn [graph opts]
    (local options (or opts {}))
    (local store (or options.store (get-default-store)))
    (graph:register-key-loader scheme
      (fn [key]
        (local entity-id (extract-id scheme key))
        (when entity-id
          (local entity (store:get-entity entity-id))
          (when entity
            (make-node entity-id store)))))))

{:key-prefix key-prefix
 :key-scheme key-scheme
 :extract-id extract-id
 :make-register-loader make-register-loader}
