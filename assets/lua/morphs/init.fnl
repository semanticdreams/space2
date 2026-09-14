(local Signal (require :signal))

(local M {})

(fn key-scheme [key]
  (when (and key (= (type key) "string"))
    (local (start _end) (string.find key ":" 1 true))
    (if start
        (string.sub key 1 (- start 1))
        key)))

(fn is-identity-key? [key]
  (and (= (type key) "string")
       (= (string.sub key 1 9) "identity:")))

(fn normalize-source-node [source-node]
  (if (and source-node source-node.key)
      source-node
      nil))

(fn default-target-label [scheme]
  (if scheme
      (tostring scheme)
      ""))

(fn morph-key [from-scheme to-scheme]
  (.. (tostring from-scheme) " -> " (tostring to-scheme)))

(fn make-morph-handle [morphs registration]
  {:from-scheme registration.from-scheme
   :to-scheme registration.to-scheme
   :owner-id registration.owner-id
   :extension-id registration.extension-id
   :registration-id registration.registration-id
   :active? true
   :unregister (fn [handle-self]
                 (morphs:unregister handle-self))})

(fn options-table [opts]
  (if opts opts {}))

(fn registration-at [registry from-scheme to-scheme]
  (local from-map (. registry from-scheme))
  (if from-map
      (. from-map to-scheme)
      nil))

(fn active-morph-error [from-scheme to-scheme suffix]
  (.. "morph " (morph-key from-scheme to-scheme) " " suffix))

(fn unregister-handle [registry handle]
  (assert handle.from-scheme "Morphs.unregister handle requires from-scheme")
  (assert handle.to-scheme "Morphs.unregister handle requires to-scheme")
  (local from-map (. registry handle.from-scheme))
  (local registration (if from-map (. from-map handle.to-scheme) nil))
  (if registration
      (do
        (when (if (= registration.registration-id handle.registration-id)
                  (not (= registration.handle handle))
                  true)
          (error (active-morph-error handle.from-scheme handle.to-scheme "belongs to another registration")))
        (set registration.active? false)
        (set (. from-map handle.to-scheme) nil)
        (set handle.active? false)
        true)
      (if (not handle.active?)
          true
          (do
            (set handle.active? false)
            true))))

(fn unregister-schemes [registry from-scheme to-scheme opts]
  (assert from-scheme "Morphs.unregister requires from-scheme")
  (assert to-scheme "Morphs.unregister requires to-scheme")
  (local unregister-options (options-table opts))
  (local from-map (. registry from-scheme))
  (local registration (if from-map (. from-map to-scheme) nil))
  (if registration
      (do
        (when (and registration.owner-id
                   (not (= unregister-options.owner-id registration.owner-id)))
          (error (active-morph-error from-scheme to-scheme (.. "belongs to owner " registration.owner-id))))
        (when (and unregister-options.registration-id
                   (not (= unregister-options.registration-id registration.registration-id)))
          (error (active-morph-error from-scheme to-scheme "belongs to another registration")))
        (set registration.active? false)
        (when registration.handle
          (set registration.handle.active? false))
        (set (. from-map to-scheme) nil)
        true)
      true))

(fn make-target-items [from-map]
  (local items [])
  (each [to-scheme spec (pairs from-map)]
    (table.insert items [{:to-scheme to-scheme
                          :label spec.label}
                         spec.label]))
  (table.sort items
              (fn [a b]
                (< (tostring (. a 2)) (tostring (. b 2)))))
  items)

(fn target-scheme [target]
  (if (= (type target) "table")
      (if target.to-scheme
          target.to-scheme
          (if target.scheme
              target.scheme
              target.key))
      target))

(fn Morphs [_opts]
  (local registry {})
  (local morphed (Signal))
  (var registration-seq 0)

  (fn allocate-registration-id []
    (set registration-seq (+ registration-seq 1))
    registration-seq)

  (fn register [self from-scheme to-scheme morph-fn meta opts]
    (assert from-scheme "Morphs.register requires from-scheme")
    (assert to-scheme "Morphs.register requires to-scheme")
    (assert (= (type morph-fn) "function") "Morphs.register requires morph function")
    (var from-map (. registry from-scheme))
    (when (not from-map)
      (set from-map {})
      (set (. registry from-scheme) from-map))
    (assert (not (. from-map to-scheme))
            (.. "duplicate morph: " (morph-key from-scheme to-scheme)))
    (local register-options (options-table opts))
    (local registration {:run morph-fn
                         :label (if (and meta meta.label)
                                    meta.label
                                    (default-target-label to-scheme))
                         :from-scheme from-scheme
                         :to-scheme to-scheme
                         :owner-id register-options.owner-id
                         :extension-id register-options.extension-id
                         :registration-id (allocate-registration-id)
                         :active? true})
    (local handle (make-morph-handle self registration))
    (set registration.handle handle)
    (set (. from-map to-scheme) registration)
    handle)

  (fn unregister [_self handle-or-from to-scheme opts]
    (assert handle-or-from "Morphs.unregister requires a handle or from-scheme")
    (local kind (type handle-or-from))
    (assert (if (= kind "table") true (= kind "string"))
            "Morphs.unregister requires table handle or string from-scheme")
    (if (= kind "table")
        (unregister-handle registry handle-or-from)
        (unregister-schemes registry handle-or-from to-scheme opts)))

  (fn morph-owner [_self from-scheme to-scheme]
    (local registration (registration-at registry from-scheme to-scheme))
    (if registration registration.owner-id nil))

  (fn target-items [_self source-node]
    (local source (normalize-source-node source-node))
    (if (not source)
        []
        (if (is-identity-key? source.key)
            []
            (do
              (local from-scheme (key-scheme source.key))
              (local from-map (. registry from-scheme))
              (if (not from-map)
                  []
                  (make-target-items from-map))))))

  (fn apply [self source-node target opts]
    (local source (normalize-source-node source-node))
    (assert source "Morphs.apply requires a source node")
    (assert source.key "Morphs.apply requires source node key")
    (assert (not (is-identity-key? source.key)) "Identity nodes are not morphable")
    (local to-scheme (target-scheme target))
    (assert to-scheme "Morphs.apply requires target scheme")
    (local from-scheme (key-scheme source.key))
    (local from-map (. registry from-scheme))
    (assert from-map (.. "No morphs registered for source scheme: " (tostring from-scheme)))
    (local spec (. from-map to-scheme))
    (assert spec (.. "No morph registered: " (tostring from-scheme) " -> " (tostring to-scheme)))
    (local result (spec.run {:source-node source
                             :options (options-table opts)}))
    (morphed:emit {:source-node source
                   :source-key source.key
                   :from-scheme from-scheme
                   :to-scheme to-scheme
                   :result result})
    result)

  {:register register
   :unregister unregister
   :morph-owner morph-owner
   :target-items target-items
   :apply apply
   :morphed morphed
   :registry registry})

(var default-morphs nil)

(fn get-default [opts]
  (if default-morphs
      default-morphs
      (do
        (set default-morphs (Morphs (options-table opts)))
        (local register-defaults (require :morphs/string-entity-to-code-entity))
        (register-defaults default-morphs)
        default-morphs)))

(set M.Morphs Morphs)
(set M.get-default get-default)
(set M.key-scheme key-scheme)
(set M.is-identity-key? is-identity-key?)

M
